-- | Servant request handlers for the Veritas API.
module Veritas.API.Handlers
  ( server
  , fullServer
  , AppEnv(..)
  , validateTwoPartySafety
  , validateMethodParams
  , validateBeaconSpec
  , validateTemporalConstraints
  ) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.ByteArray.Encoding (Base(..), convertFromBase)
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
import qualified Crypto.Random
import qualified Data.Aeson as Aeson
import Veritas.Core.AuditLog (computeEntryHash)
import Veritas.Crypto.Hash (genesisHash, deriveUniform, hexEncode)
import Veritas.Crypto.VRF (generateVRF)
import Veritas.Crypto.Signatures (KeyPair(..), publicKeyBytes)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q
import Data.OpenApi (OpenApi)
import Katip (LogEnv, logMsg, Severity(..), runKatipT, ls)
import Servant.OpenApi (toOpenApi)
import Veritas.API.Types
import Veritas.Config (DrandConfig(..))

-- | Application environment passed to all handlers
data AppEnv = AppEnv
  { envPool        :: DBPool
  , envKeyPair     :: KeyPair
  , envLogEnv      :: LogEnv
  , envDrandConfig :: DrandConfig
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
  :<|> beaconVerificationGuide env

-- | Wire up all handlers including docs endpoint
fullServer :: AppEnv -> Server FullAPI
fullServer env = server env :<|> docsHandler

-- | Serve the OpenAPI 3.0 JSON spec
docsHandler :: Handler OpenApi
docsHandler = pure $ toOpenApi api

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

  -- Beacon spec validation
  case validateBeaconSpec (crqEntropyMethod req) (crqBeaconSpec req) of
    Left msg -> throwError err400 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
    Right () -> pure ()

  now <- liftIO getCurrentTime

  -- Temporal constraint validation
  case validateTemporalConstraints now (crqCommitDeadline req) (crqRevealDeadline req) of
    Left msg -> throwError err400 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
    Right () -> pure ()

  cid <- liftIO UUID4.nextRandom
  creator <- case crqCreatedBy req of
    Just pid -> pure pid
    Nothing  -> liftIO UUID4.nextRandom
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
        , createdBy = ParticipantId creator
        , createdAt = now
        }
  liftIO $ do
    withConnection envPool $ \conn -> do
      Q.insertCeremony conn ceremony
      Q.appendAuditLog conn (CeremonyId cid) (CeremonyCreated ceremony)
    runKatipT envLogEnv $
      logMsg "api.ceremony" InfoS (ls ("Ceremony created: " <> UUID.toText cid))
  pure $ ceremonyToResponse ceremony 0 []

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

-- | Validate that beacon_spec is provided for beacon methods (B, D) and absent for others (A, C).
validateBeaconSpec :: EntropyMethod -> Maybe BeaconSpec -> Either Text ()
validateBeaconSpec method mSpec = case method of
  ExternalBeacon -> case mSpec of
    Nothing -> Left "beacon_spec is required for ExternalBeacon method"
    Just _  -> Right ()
  Combined -> case mSpec of
    Nothing -> Left "beacon_spec is required for Combined method"
    Just _  -> Right ()
  ParticipantReveal -> case mSpec of
    Just _  -> Left "beacon_spec is only for ExternalBeacon and Combined methods"
    Nothing -> Right ()
  OfficiantVRF -> case mSpec of
    Just _  -> Left "beacon_spec is only for ExternalBeacon and Combined methods"
    Nothing -> Right ()

-- | Validate that deadlines are in the future and properly ordered.
validateTemporalConstraints :: UTCTime -> UTCTime -> Maybe UTCTime -> Either Text ()
validateTemporalConstraints now commitDeadline' mRevealDeadline = do
  when (commitDeadline' <= now) $
    Left "commit_deadline must be in the future"
  case mRevealDeadline of
    Just revealDeadline' -> do
      when (revealDeadline' <= now) $
        Left "reveal_deadline must be in the future"
      when (revealDeadline' <= commitDeadline') $
        Left "reveal_deadline must be after commit_deadline"
    Nothing -> Right ()

getCeremonyH :: AppEnv -> UUID -> Handler CeremonyResponse
getCeremonyH AppEnv{..} cid = do
  mrow <- liftIO $ withConnection envPool $ \conn -> Q.getCeremony conn (CeremonyId cid)
  case mrow of
    Nothing -> throwError err404
    Just row -> do
      (count, participants) <- liftIO $ withConnection envPool $ \conn -> do
        c <- Q.getCommitmentCount conn (CeremonyId cid)
        ps <- Q.getCommittedParticipants conn (CeremonyId cid)
        pure (c, ps)
      pure $ ceremonyRowToResponse row count participants

listCeremoniesH :: AppEnv -> Maybe Text -> Handler [CeremonyResponse]
listCeremoniesH AppEnv{..} phaseFilter = do
  liftIO $ withConnection envPool $ \conn -> do
    rows <- Q.listCeremonies conn phaseFilter
    let cids = map (CeremonyId . Q.crId) rows
    countRows <- Q.getCommitmentCountsBatch conn cids
    partRows <- Q.getCommittedParticipantsBatch conn cids
    let countMap = Map.fromList countRows
        partMap = Map.fromListWith (flip (++)) [(cid', [Q.CommittedParticipant pid dn]) | (cid', pid, dn) <- partRows]
    pure $ map (\row ->
      let uid = Q.crId row
          count = Map.findWithDefault 0 uid countMap
          participants = Map.findWithDefault [] uid partMap
      in ceremonyRowToResponse row count participants
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
                , entropySealHash = cmrqEntropySeal req >>= hexDecode
                , committedAt = now
                }

          case transition ceremony commitments [] (AddCommitment commit) of
            Left err -> pure (Left $ err400 { errBody = LBS.fromStrict (BS8.pack (show err)) })
            Right TransitionResult{..} -> do
              Q.insertCommitment conn' commit (cmrqDisplayName req)
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
    Right resp -> do
      liftIO $ runKatipT envLogEnv $
        logMsg "api.commit" InfoS (ls ("Commitment received for ceremony " <> show cid))
      pure resp

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

          case hexDecode (rvrqEntropyValue req) of
            Nothing -> pure (Left $ err400 { errBody = "Invalid hex in entropy_value" })
            Just val ->
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
    Right resp -> do
      liftIO $ runKatipT envLogEnv $
        logMsg "api.reveal" InfoS (ls ("Entropy revealed for ceremony " <> show cid))
      pure resp

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
  let errs = verifyHashChain rows
  pure VerifyResponse { vrValid = null errs, vrErrors = errs }

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

-- === Verification Guides ===

beaconVerificationGuide :: AppEnv -> Handler BeaconVerificationGuideResponse
beaconVerificationGuide AppEnv{..} = do
  let cfg = envDrandConfig
      infoUrl = drandRelayUrl cfg <> "/" <> drandChainHash cfg <> "/info"
      pubKeyHex = fmap hexEncode (drandPublicKey cfg)
  pure BeaconVerificationGuideResponse
    { bvgScheme      = "bls-unchained-g1-rfc9380"
    , bvgPublicKey   = pubKeyHex
    , bvgChainHash   = drandChainHash cfg
    , bvgDrandInfoUrl = infoUrl
    , bvgDST         = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"
    , bvgSteps       =
        [ "1. Fetch the ceremony audit log (GET /ceremonies/{id}/log) and locate the BeaconAnchored event."
        , "2. Extract the beacon data from event_data.anchor: baRound, baSignature (hex), and baValue (hex randomness)."
        , "3. Verify that baValue == SHA-256(baSignature) to confirm the randomness is derived from the signature."
        , "4. Construct the message: message = SHA-256(big_endian_uint64(baRound))."
        , "5. Obtain the drand public key from this endpoint's public_key field, or directly from the drand network (drand_info_url)."
        , "6. Verify the BLS12-381 signature (baSignature) over the message using the public key and DST."
        ]
    }

-- === Helpers ===

ceremonyToResponse :: Ceremony -> Int -> [Q.CommittedParticipant] -> CeremonyResponse
ceremonyToResponse c count participants = CeremonyResponse
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
  , crspCommittedParticipants = map toParticipantResponse participants
  }

ceremonyRowToResponse :: Q.CeremonyRow -> Int -> [Q.CommittedParticipant] -> CeremonyResponse
ceremonyRowToResponse row count participants =
  ceremonyToResponse (Q.ceremonyRowToDomain row) count participants

toParticipantResponse :: Q.CommittedParticipant -> CommittedParticipantResponse
toParticipantResponse Q.CommittedParticipant{..} = CommittedParticipantResponse
  { cprParticipantId = cpParticipantId
  , cprDisplayName = cpDisplayName
  }

auditLogRowToResponse :: Q.AuditLogRow -> AuditLogEntryResponse
auditLogRowToResponse Q.AuditLogRow{..} = AuditLogEntryResponse
  { alerSequenceNum = alrSequenceNum
  , alerEventType = alrEventType
  , alerEventData = alrEventData
  , alerPrevHash = hexEncode alrPrevHash
  , alerEntryHash = hexEncode alrEntryHash
  , alerCreatedAt = alrCreatedAt
  }

verifyHashChain :: [Q.AuditLogRow] -> [Text]
verifyHashChain [] = []
verifyHashChain rows = go genesisHash rows
  where
    go _ [] = []
    go expectedPrev (r:rs)
      | Q.alrPrevHash r /= expectedPrev =
          ("Entry " <> showT (Q.alrSequenceNum r) <> ": prev_hash mismatch") : go (Q.alrEntryHash r) rs
      | otherwise = case verifyEntryHash r of
          Nothing  -> go (Q.alrEntryHash r) rs
          Just err -> err : go (Q.alrEntryHash r) rs

    verifyEntryHash r =
      case Aeson.fromJSON (Q.alrEventData r) of
        Aeson.Error msg ->
          Just ("Entry " <> showT (Q.alrSequenceNum r) <> ": failed to parse event_data: " <> showT msg)
        Aeson.Success event ->
          let computed = computeEntryHash
                (LogSequence (fromIntegral (Q.alrSequenceNum r)))
                (CeremonyId (Q.alrCeremonyId r))
                event
                (Q.alrCreatedAt r)
                (Q.alrPrevHash r)
          in if computed == Q.alrEntryHash r
             then Nothing
             else Just ("Entry " <> showT (Q.alrSequenceNum r) <> ": entry_hash mismatch (recomputed hash differs)")

    showT :: Show a => a -> Text
    showT = T.pack . show

-- | Generate 32 cryptographically secure random bytes
generateRandomBytes :: IO ByteString
generateRandomBytes = Crypto.Random.getRandomBytes 32

-- | Hex-decode a Text to ByteString, returning Nothing on invalid hex
hexDecode :: Text -> Maybe ByteString
hexDecode t = case convertFromBase Base16 (TE.encodeUtf8 t) of
  Left _  -> Nothing
  Right bs -> Just bs


