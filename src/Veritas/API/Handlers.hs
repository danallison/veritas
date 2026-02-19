-- | Servant request handlers for the Veritas API.
module Veritas.API.Handlers
  ( server
  , AppEnv(..)
  , validateTwoPartySafety
  , validateMethodParams
  ) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID4
import GHC.Natural (Natural)
import Servant

import Veritas.Core.Types
import Veritas.Core.StateMachine (Action(..), TransitionResult(..), transition)
import Veritas.Core.Resolution (resolve, deriveIntRange)
import Veritas.Core.Entropy (verifySealForReveal)
import Veritas.Crypto.Hash (sha256, genesisHash, deriveUniform)
import Veritas.Crypto.VRF (generateVRF)
import Veritas.Crypto.Signatures (KeyPair(..), publicKeyBytes)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q
import Veritas.API.Types

-- | Application environment passed to all handlers
data AppEnv = AppEnv
  { envPool      :: DBPool
  , envKeyPair   :: KeyPair
  }

-- | Wire up all handlers to the API type
server :: AppEnv -> Server VeritasAPI
server env =
       createCeremony env
  :<|> getCeremonyH env
  :<|> listCeremoniesH env
  :<|> commitToCeremony env
  :<|> revealEntropy env
  :<|> getOutcomeH env
  :<|> getAuditLogH env
  :<|> verifyCeremony env
  :<|> randomCoin
  :<|> randomInteger
  :<|> randomUUID
  :<|> serverPubKey env
  :<|> healthCheck

-- === Ceremony Lifecycle ===

createCeremony :: AppEnv -> CreateCeremonyRequest -> Handler CeremonyResponse
createCeremony AppEnv{..} req = do
  -- Method-specific parameter validation (protocol Section 3)
  case validateMethodParams (crqEntropyMethod req) (crqRevealDeadline req) (crqNonParticipationPolicy req) of
    Left msg -> throwError err400 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
    Right () -> pure ()

  -- Two-party safety check
  case validateTwoPartySafety (crqRequiredParties req) (crqNonParticipationPolicy req) of
    Left msg -> throwError err400 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
    Right () -> pure ()

  now <- liftIO getCurrentTime
  cid <- liftIO UUID4.nextRandom
  let ceremony = Ceremony
        { ceremonyId = CeremonyId cid
        , question = crqQuestion req
        , ceremonyType = crqCeremonyType req
        , entropyMethod = crqEntropyMethod req
        , requiredParties = crqRequiredParties req
        , commitmentMode = crqCommitmentMode req
        , commitDeadline = crqCommitDeadline req
        , revealDeadline = crqRevealDeadline req
        , nonParticipationPolicy = crqNonParticipationPolicy req
        , beaconSpec = crqBeaconSpec req
        , phase = Pending
        , createdBy = ParticipantId UUID.nil  -- placeholder for Phase 1
        , createdAt = now
        }
  liftIO $ withConnection envPool $ \conn -> do
    Q.insertCeremony conn ceremony
    Q.appendAuditLog conn (CeremonyId cid) (CeremonyCreated ceremony)
  pure $ ceremonyToResponse ceremony 0

-- | Reject DefaultSubstitution for 2-party ceremonies.
-- With only 2 parties, if one doesn't reveal, the remaining party knows both
-- their own entropy and the deterministic default, giving them full control.
validateTwoPartySafety :: Natural -> Maybe NonParticipationPolicy -> Either Text ()
validateTwoPartySafety requiredParties (Just DefaultSubstitution)
  | requiredParties == 2 = Left "DefaultSubstitution is not allowed for 2-party ceremonies: one party would control the outcome"
validateTwoPartySafety _ _ = Right ()

-- | Validate that reveal_deadline and non_participation_policy are consistent
-- with the entropy method. Per protocol Section 3, these are "Methods A and D only."
validateMethodParams :: EntropyMethod -> Maybe UTCTime -> Maybe NonParticipationPolicy -> Either Text ()
validateMethodParams method mRevealDeadline mPolicy = case method of
  ParticipantReveal -> requireRevealParams
  Combined          -> requireRevealParams
  ExternalBeacon    -> rejectRevealParams
  OfficiantVRF      -> rejectRevealParams
  where
    requireRevealParams = do
      case mRevealDeadline of
        Nothing -> Left "reveal_deadline is required for ParticipantReveal and Combined methods"
        Just _  -> Right ()
      case mPolicy of
        Nothing -> Left "non_participation_policy is required for ParticipantReveal and Combined methods"
        Just _  -> Right ()
    rejectRevealParams = do
      case mRevealDeadline of
        Just _  -> Left "reveal_deadline is only for ParticipantReveal and Combined methods"
        Nothing -> Right ()
      case mPolicy of
        Just _  -> Left "non_participation_policy is only for ParticipantReveal and Combined methods"
        Nothing -> Right ()

getCeremonyH :: AppEnv -> UUID -> Handler CeremonyResponse
getCeremonyH AppEnv{..} cid = do
  mrow <- liftIO $ withConnection envPool $ \conn -> Q.getCeremony conn (CeremonyId cid)
  case mrow of
    Nothing -> throwError err404
    Just row -> do
      count <- liftIO $ withConnection envPool $ \conn -> Q.getCommitmentCount conn (CeremonyId cid)
      pure $ ceremonyRowToResponse row count

listCeremoniesH :: AppEnv -> Maybe Text -> Handler [CeremonyResponse]
listCeremoniesH AppEnv{..} phaseFilter = do
  rows <- liftIO $ withConnection envPool $ \conn -> Q.listCeremonies conn phaseFilter
  liftIO $ withConnection envPool $ \conn ->
    mapM (\row -> do
      count <- Q.getCommitmentCount conn (CeremonyId (Q.crId row))
      pure $ ceremonyRowToResponse row count
    ) rows

commitToCeremony :: AppEnv -> UUID -> CommitRequest -> Handler CommitResponse
commitToCeremony AppEnv{..} cid req = do
  now <- liftIO getCurrentTime
  result <- liftIO $ withConnection envPool $ \conn ->
    withSerializableTransaction conn $ \conn' -> do
      mrow <- Q.getCeremony conn' (CeremonyId cid)
      case mrow of
        Nothing -> pure (Left err404)
        Just row -> do
          let ceremony = Q.ceremonyRowToDomain row
              pid = ParticipantId (cmrqParticipantId req)
          commitments <- map Q.commitmentRowToDomain <$> Q.getCommitments conn' (CeremonyId cid)

          let commit = Commitment
                { commitCeremony = CeremonyId cid
                , commitParty = pid
                , commitSignature = TE.encodeUtf8 (cmrqSignature req)
                , entropySealHash = fmap TE.encodeUtf8 (cmrqEntropySeal req)
                , committedAt = now
                }

          case transition ceremony commitments [] (AddCommitment commit) of
            Left err -> pure (Left $ err400 { errBody = LBS.fromStrict (BS8.pack (show err)) })
            Right TransitionResult{..} -> do
              Q.insertCommitment conn' commit
              Q.updateCeremonyPhase conn' (CeremonyId cid) trNewPhase
              Q.appendAuditLog conn' (CeremonyId cid) (ParticipantCommitted commit)

              -- For Method C (VRF), if we've entered Resolving, generate VRF and resolve
              when (trNewPhase == Resolving && entropyMethod ceremony == OfficiantVRF) $ do
                let vrfOut = generateVRF envKeyPair (CeremonyId cid)
                    contribution = EntropyContribution
                      { ecCeremony = CeremonyId cid
                      , ecSource = VRFEntropy vrfOut
                      , ecValue = vrfValue vrfOut
                      }
                    outcome = resolve (ceremonyType ceremony) [contribution]
                Q.appendAuditLog conn' (CeremonyId cid) (VRFGenerated vrfOut)
                Q.insertOutcome conn' (CeremonyId cid) outcome
                Q.updateCeremonyPhase conn' (CeremonyId cid) Finalized
                Q.appendAuditLog conn' (CeremonyId cid) (CeremonyResolved outcome)
                Q.appendAuditLog conn' (CeremonyId cid) CeremonyFinalized

              pure (Right $ CommitResponse
                { cmrStatus = "committed"
                , cmrPhase = trNewPhase
                })

  case result of
    Left err -> throwError err
    Right resp -> pure resp

revealEntropy :: AppEnv -> UUID -> RevealRequest -> Handler RevealResponse
revealEntropy AppEnv{..} cid req = do
  result <- liftIO $ withConnection envPool $ \conn ->
    withSerializableTransaction conn $ \conn' -> do
      mrow <- Q.getCeremony conn' (CeremonyId cid)
      case mrow of
        Nothing -> pure (Left err404)
        Just row -> do
          let ceremony = Q.ceremonyRowToDomain row
              pid = ParticipantId (rvrqParticipantId req)
              val = TE.encodeUtf8 (rvrqEntropyValue req)

          if phase ceremony /= AwaitingReveals
            then pure (Left $ err400 { errBody = "Ceremony not in AwaitingReveals phase" })
            else do
              commitments <- map Q.commitmentRowToDomain <$> Q.getCommitments conn' (CeremonyId cid)

              -- Seal verification: look up this participant's commitment
              case find (\c -> commitParty c == pid) commitments of
                Nothing ->
                  pure (Left $ err400 { errBody = LBS.fromStrict (BS8.pack (show (NotCommitted pid))) })
                Just commit -> case entropySealHash commit of
                  Just seal
                    | not (verifySealForReveal (CeremonyId cid) pid val seal) ->
                        pure (Left $ err400 { errBody = LBS.fromStrict (BS8.pack (show (SealMismatch pid))) })
                  _ -> do
                    revealedPids <- Q.getRevealedParticipants conn' (CeremonyId cid)

                    case transition ceremony commitments revealedPids (SubmitReveal pid val) of
                      Left err -> pure (Left $ err400 { errBody = LBS.fromStrict (BS8.pack (show err)) })
                      Right TransitionResult{..} -> do
                        Q.insertEntropyReveal conn' (CeremonyId cid) pid val False
                        Q.updateCeremonyPhase conn' (CeremonyId cid) trNewPhase

                        -- Reveal batching: only log when phase transitions away from AwaitingReveals
                        when (trNewPhase /= AwaitingReveals) $ do
                          Q.markRevealsPublished conn' (CeremonyId cid)
                          reveals <- Q.getEntropyReveals conn' (CeremonyId cid)
                          let contributions = Q.revealsToContributions (CeremonyId cid) reveals
                          Q.appendAuditLog conn' (CeremonyId cid) (RevealsPublished contributions)

                        pure (Right $ RevealResponse { rvrsStatus = "accepted" })

  case result of
    Left err -> throwError err
    Right resp -> pure resp

getOutcomeH :: AppEnv -> UUID -> Handler OutcomeResponse
getOutcomeH AppEnv{..} cid = do
  mrow <- liftIO $ withConnection envPool $ \conn -> Q.getCeremony conn (CeremonyId cid)
  case mrow of
    Nothing -> throwError err404
    Just row
      | Q.crPhase row /= "finalized" -> throwError err400 { errBody = "Ceremony not finalized" }
      | otherwise -> do
          moutcome <- liftIO $ withConnection envPool $ \conn -> Q.getOutcome conn (CeremonyId cid)
          case moutcome of
            Nothing -> throwError err404
            Just orow -> pure OutcomeResponse
              { orOutcome = Q.orOutcomeValue orow
              , orCombinedEntropy = hexEncode (Q.orCombinedEntropy orow)
              , orResolvedAt = Q.orResolvedAt orow
              }

getAuditLogH :: AppEnv -> UUID -> Handler AuditLogResponse
getAuditLogH AppEnv{..} cid = do
  rows <- liftIO $ withConnection envPool $ \conn -> Q.getAuditLog conn (CeremonyId cid)
  pure AuditLogResponse
    { alrEntries = map auditLogRowToResponse rows
    }

verifyCeremony :: AppEnv -> UUID -> Handler VerifyResponse
verifyCeremony AppEnv{..} cid = do
  rows <- liftIO $ withConnection envPool $ \conn -> Q.getAuditLog conn (CeremonyId cid)
  let isValid = verifyHashChain rows
      errs = if isValid then [] else ["Hash chain integrity check failed"]
  pure VerifyResponse { vrValid = isValid, vrErrors = errs }

-- === Standalone Random ===

randomCoin :: Handler RandomCoinResponse
randomCoin = do
  entropy <- liftIO generateRandomBytes
  let r = deriveUniform entropy
  pure RandomCoinResponse { rcrResult = r >= 0.5 }

randomInteger :: Maybe Int -> Maybe Int -> Handler RandomIntResponse
randomInteger mmin mmax = do
  let lo = maybe 0 id mmin
      hi = maybe 100 id mmax
  entropy <- liftIO generateRandomBytes
  let val = deriveIntRange entropy lo hi
  pure RandomIntResponse { rirResult = val, rirMin = lo, rirMax = hi }

randomUUID :: Handler RandomUUIDResponse
randomUUID = do
  uuid <- liftIO UUID4.nextRandom
  pure RandomUUIDResponse { rurResult = uuid }

-- === Server Info ===

serverPubKey :: AppEnv -> Handler ServerPubKeyResponse
serverPubKey AppEnv{..} = do
  let pkBytes = publicKeyBytes (kpPublic envKeyPair)
  pure ServerPubKeyResponse
    { spkPublicKey = hexEncode pkBytes
    }

healthCheck :: Handler HealthResponse
healthCheck = pure HealthResponse
  { hrStatus = "ok"
  , hrVersion = "0.1.0"
  }

-- === Helpers ===

ceremonyToResponse :: Ceremony -> Int -> CeremonyResponse
ceremonyToResponse c count = CeremonyResponse
  { crspId = unCeremonyId (ceremonyId c)
  , crspQuestion = question c
  , crspCeremonyType = ceremonyType c
  , crspEntropyMethod = entropyMethod c
  , crspRequiredParties = requiredParties c
  , crspCommitmentMode = commitmentMode c
  , crspCommitDeadline = commitDeadline c
  , crspRevealDeadline = revealDeadline c
  , crspNonParticipationPolicy = nonParticipationPolicy c
  , crspBeaconSpec = beaconSpec c
  , crspPhase = phase c
  , crspCreatedBy = unParticipantId (createdBy c)
  , crspCreatedAt = createdAt c
  , crspCommitmentCount = count
  }

ceremonyRowToResponse :: Q.CeremonyRow -> Int -> CeremonyResponse
ceremonyRowToResponse row count =
  ceremonyToResponse (Q.ceremonyRowToDomain row) count

auditLogRowToResponse :: Q.AuditLogRow -> AuditLogEntryResponse
auditLogRowToResponse Q.AuditLogRow{..} = AuditLogEntryResponse
  { alerSequenceNum = alrSequenceNum
  , alerEventType = alrEventType
  , alerEventData = alrEventData
  , alerPrevHash = hexEncode alrPrevHash
  , alerEntryHash = hexEncode alrEntryHash
  , alerCreatedAt = alrCreatedAt
  }

verifyHashChain :: [Q.AuditLogRow] -> Bool
verifyHashChain [] = True
verifyHashChain rows = go genesisHash rows
  where
    go _ [] = True
    go expectedPrev (r:rs)
      | Q.alrPrevHash r /= expectedPrev = False
      | otherwise = go (Q.alrEntryHash r) rs

-- | Generate 32 random bytes using UUID as entropy source
generateRandomBytes :: IO ByteString
generateRandomBytes = do
  u1 <- UUID4.nextRandom
  u2 <- UUID4.nextRandom
  pure $ sha256 (UUID.toASCIIBytes u1 <> UUID.toASCIIBytes u2)

-- | Hex-encode a ByteString to Text
hexEncode :: ByteString -> Text
hexEncode = TE.decodeUtf8 . BS.concatMap (\w ->
  let (hi, lo) = w `divMod` 16
  in BS.pack [hexDigit hi, hexDigit lo])
  where
    hexDigit n
      | n < 10    = n + 48  -- '0'
      | otherwise = n + 87  -- 'a'
