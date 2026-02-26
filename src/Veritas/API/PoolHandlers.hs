-- | Servant request handlers for the Pool computing API.
module Veritas.API.PoolHandlers
  ( poolServer
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as Aeson
import Data.ByteArray.Encoding (Base(..), convertFromBase)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID.V4 as UUID4
import Servant

import Veritas.API.Handlers (AppEnv(..))
import Veritas.API.PoolTypes
import Veritas.Crypto.Hash (hexEncode)
import Veritas.DB.Pool (withConnection)
import qualified Veritas.DB.PoolQueries as PQ
import Veritas.Pool.Comparison (compareResults)
import Veritas.Pool.Seal (computeFingerprint, verifySealSignature)
import Veritas.Pool.Types

-- | Wire up all pool handlers to the PoolAPI type
poolServer :: AppEnv -> Server PoolAPI
poolServer env =
       createPoolH env
  :<|> getPoolH env
  :<|> joinPoolH env
  :<|> listMembersH env
  :<|> queryCacheH env
  :<|> listCacheEntriesH env
  :<|> submitComputeH env
  :<|> listRoundsH env
  :<|> getRoundStatusH env
  :<|> roundDetailH env
  :<|> listSealsH env
  :<|> submitSealH env
  :<|> submitRevealH env

-- === Pool Management ===

createPoolH :: AppEnv -> CreatePoolRequest -> Handler PoolResponse
createPoolH AppEnv{..} req = do
  now <- liftIO getCurrentTime
  pid <- liftIO UUID4.nextRandom
  let config = PoolConfig
        { pcComparisonMethod = cprComparisonMethod req
        , pcComputeDeadlineSeconds = cprComputeDeadlineSeconds req
        , pcMinPrincipals = cprMinPrincipals req
        }
  liftIO $ withConnection envPool $ \conn ->
    PQ.insertPool conn pid (cprName req) (Aeson.toJSON config) now
  pure PoolResponse
    { prspId = pid
    , prspName = cprName req
    , prspComparisonMethod = cprComparisonMethod req
    , prspComputeDeadlineSeconds = cprComputeDeadlineSeconds req
    , prspMinPrincipals = cprMinPrincipals req
    , prspCreatedAt = now
    }

getPoolH :: AppEnv -> UUID -> Handler PoolResponse
getPoolH AppEnv{..} pid = do
  mrow <- liftIO $ withConnection envPool $ \conn -> PQ.getPool conn pid
  case mrow of
    Nothing -> throwError err404
    Just row -> case Aeson.fromJSON (PQ.prConfig row) of
      Aeson.Success config -> pure PoolResponse
        { prspId = PQ.prId row
        , prspName = PQ.prName row
        , prspComparisonMethod = pcComparisonMethod config
        , prspComputeDeadlineSeconds = pcComputeDeadlineSeconds config
        , prspMinPrincipals = pcMinPrincipals config
        , prspCreatedAt = PQ.prCreatedAt row
        }
      _ -> throwError err500 { errBody = "Invalid pool config in database" }

joinPoolH :: AppEnv -> UUID -> JoinPoolRequest -> Handler PoolMemberResponse
joinPoolH AppEnv{..} pid req = do
  now <- liftIO getCurrentTime
  case hexDecode (jprPublicKey req) of
    Nothing -> throwError err400 { errBody = "invalid hex in public_key" }
    Just pkBytes
      | BS.length pkBytes /= 32 ->
          throwError err400 { errBody = "public_key must be 32 bytes (Ed25519)" }
      | otherwise -> do
          -- Verify pool exists
          mpool <- liftIO $ withConnection envPool $ \conn -> PQ.getPool conn pid
          case mpool of
            Nothing -> throwError err404
            Just _ -> do
              liftIO $ withConnection envPool $ \conn ->
                PQ.insertPoolMember conn pid (jprAgentId req) pkBytes (jprPrincipalId req) now
              pure PoolMemberResponse
                { pmrspAgentId = jprAgentId req
                , pmrspPublicKey = jprPublicKey req
                , pmrspPrincipalId = jprPrincipalId req
                , pmrspJoinedAt = now
                }

listMembersH :: AppEnv -> UUID -> Handler [PoolMemberResponse]
listMembersH AppEnv{..} pid = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolMembers conn pid
  pure $ map memberRowToResponse rows

-- === Cache ===

queryCacheH :: AppEnv -> UUID -> Text -> Handler CacheEntryResponse
queryCacheH AppEnv{..} pid fpHex = do
  case hexDecode fpHex of
    Nothing -> throwError err400 { errBody = "invalid hex fingerprint" }
    Just fpBytes -> do
      mentry <- liftIO $ withConnection envPool $ \conn -> PQ.getCacheEntry conn pid fpBytes
      case mentry of
        Nothing -> throwError err404
        Just row -> cacheRowToResponse row

listCacheEntriesH :: AppEnv -> UUID -> Handler [CacheEntryResponse]
listCacheEntriesH AppEnv{..} pid = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolCacheEntries conn pid
  mapM cacheRowToResponse rows

-- === Validation Rounds ===

listRoundsH :: AppEnv -> UUID -> Handler [ValidationRoundResponse]
listRoundsH AppEnv{..} pid = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolRounds conn pid
  pure [ ValidationRoundResponse
           { vrrspRoundId = PQ.vrrId row
           , vrrspFingerprint = hexEncode (PQ.vrrFingerprint row)
           , vrrspPhase = phase
           , vrrspCreatedAt = PQ.vrrCreatedAt row
           }
       | row <- rows
       , Just phase <- [parseValidationPhase (PQ.vrrPhase row)]
       ]

roundDetailH :: AppEnv -> UUID -> UUID -> Handler RoundDetailResponse
roundDetailH AppEnv{..} _pid roundId = do
  mround <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationRound conn roundId
  case mround of
    Nothing -> throwError err404
    Just row -> case (parseValidationPhase (PQ.vrrPhase row), Aeson.fromJSON (PQ.vrrComputationSpec row)) of
      (Just phase, Aeson.Success spec) -> do
        seals <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationSeals conn roundId
        pure RoundDetailResponse
          { rdrRoundId = PQ.vrrId row
          , rdrFingerprint = hexEncode (PQ.vrrFingerprint row)
          , rdrPhase = phase
          , rdrComputationSpec = spec
          , rdrRequesterId = PQ.vrrRequesterId row
          , rdrBeaconRound = PQ.vrrBeaconRound row
          , rdrCreatedAt = PQ.vrrCreatedAt row
          , rdrSeals = map sealRowToResponse seals
          }
      _ -> throwError err500 { errBody = "Invalid phase or computation_spec in database" }

listSealsH :: AppEnv -> UUID -> UUID -> Handler [SealDetailResponse]
listSealsH AppEnv{..} _pid roundId = do
  seals <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationSeals conn roundId
  pure $ map sealRowToResponse seals

submitComputeH :: AppEnv -> UUID -> SubmitComputeRequest -> Handler ValidationRoundResponse
submitComputeH AppEnv{..} pid req = do
  now <- liftIO getCurrentTime
  -- Verify agent is pool member
  mMember <- liftIO $ withConnection envPool $ \conn ->
    PQ.getPoolMember conn pid (scrAgentId req)
  case mMember of
    Nothing -> throwError err400 { errBody = "agent is not a member of this pool" }
    Just member -> do
      -- Check cache first
      let fp = computeFingerprint (scrComputationSpec req)
      mCache <- liftIO $ withConnection envPool $ \conn ->
        PQ.getCacheEntry conn pid (unFingerprint fp)
      case mCache of
        Just _ -> throwError err409 { errBody = "result already cached for this computation" }
        Nothing -> do
          -- Decode seal
          case (hexDecode (scrSealHash req), hexDecode (scrSealSig req)) of
            (Just sealHash, Just sealSig) -> do
              -- Verify Ed25519 signature on the seal
              let publicKey = PQ.pmrPublicKey member
              if not (verifySealSignature publicKey sealHash sealSig)
                then throwError err400 { errBody = "invalid seal signature" }
                else do
                  roundId <- liftIO UUID4.nextRandom
                  liftIO $ withConnection envPool $ \conn -> do
                    PQ.insertValidationRound conn roundId pid
                      (unFingerprint fp)
                      (Aeson.toJSON (scrComputationSpec req))
                      "exact"  -- POC: use exact comparison
                      "selecting"  -- Requester seal verified, go to Selecting for validator assignment
                      (scrAgentId req)
                      now
                      Nothing
                    PQ.insertValidationSeal conn roundId (scrAgentId req) "requester" sealHash sealSig
                  pure ValidationRoundResponse
                    { vrrspRoundId = roundId
                    , vrrspFingerprint = hexEncode (unFingerprint fp)
                    , vrrspPhase = Selecting
                    , vrrspCreatedAt = now
                    }
            _ -> throwError err400 { errBody = "invalid hex in seal_hash or seal_sig" }

getRoundStatusH :: AppEnv -> UUID -> UUID -> Handler RoundStatusResponse
getRoundStatusH AppEnv{..} _pid roundId = do
  mround <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationRound conn roundId
  case mround of
    Nothing -> throwError err404
    Just row -> case parseValidationPhase (PQ.vrrPhase row) of
      Just phase -> pure RoundStatusResponse
        { rsrspRoundId = PQ.vrrId row
        , rsrspPhase = phase
        , rsrspMessage = "Round is in " <> PQ.vrrPhase row <> " phase"
        }
      Nothing -> throwError err500 { errBody = "Invalid phase in database" }

submitSealH :: AppEnv -> UUID -> UUID -> SubmitSealRequest -> Handler RoundStatusResponse
submitSealH AppEnv{..} pid roundId req = do
  -- Verify agent is pool member
  mMember <- liftIO $ withConnection envPool $ \conn ->
    PQ.getPoolMember conn pid (ssrAgentId req)
  case mMember of
    Nothing -> throwError err400 { errBody = "agent is not a member of this pool" }
    Just member -> do
      case (hexDecode (ssrSealHash req), hexDecode (ssrSealSig req)) of
        (Just sealHash, Just sealSig) -> do
          -- Verify Ed25519 signature on the seal
          let publicKey = PQ.pmrPublicKey member
          if not (verifySealSignature publicKey sealHash sealSig)
            then throwError err400 { errBody = "invalid seal signature" }
            else do
              liftIO $ withConnection envPool $ \conn ->
                PQ.insertValidationSeal conn roundId (ssrAgentId req) "validator" sealHash sealSig
              -- Check if all seals are in
              seals <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationSeals conn roundId
              let newPhase = if length seals >= 3 then Revealing else Sealing
              liftIO $ withConnection envPool $ \conn -> PQ.updateRoundPhase conn roundId newPhase
              pure RoundStatusResponse
                { rsrspRoundId = roundId
                , rsrspPhase = newPhase
                , rsrspMessage = "Seal accepted"
                }
        _ -> throwError err400 { errBody = "invalid hex in seal_hash or seal_sig" }

submitRevealH :: AppEnv -> UUID -> UUID -> SubmitRevealRequest -> Handler RoundStatusResponse
submitRevealH AppEnv{..} pid roundId req = do
  -- Verify agent is pool member
  mMember <- liftIO $ withConnection envPool $ \conn ->
    PQ.getPoolMember conn pid (srrAgentId req)
  case mMember of
    Nothing -> throwError err400 { errBody = "agent is not a member of this pool" }
    Just _ ->
      case (hexDecode (srrResult req), hexDecode (srrNonce req)) of
        (Just result, Just nonce) -> do
          liftIO $ withConnection envPool $ \conn ->
            PQ.updateSealReveal conn roundId (srrAgentId req) result (srrEvidence req) nonce
          -- Check if all revealed
          seals <- liftIO $ withConnection envPool $ \conn -> PQ.getValidationSeals conn roundId
          let allRevealed = all (\s -> PQ.vsrPhase s == "revealed") seals
          if allRevealed && length seals >= 3
            then do
              -- Run comparison
              let results = [(AgentId (PQ.vsrAgentId s), r) | s <- seals, Just r <- [PQ.vsrRevealedResult s]]
                  outcome = compareResults Exact results
              case outcome of
                CompUnanimous -> do
                  let (_, majorityResult) = head results
                  now <- liftIO getCurrentTime
                  liftIO $ withConnection envPool $ \conn -> do
                    mround <- PQ.getValidationRound conn roundId
                    case mround of
                      Just row -> do
                        let provenance = Aeson.toJSON $ ResultProvenance
                              Unanimous
                              (length results)
                              (fmap fromIntegral (PQ.vrrBeaconRound row))
                              (PQ.vrrSelectionProof row)
                              now
                        PQ.insertCacheEntry conn pid (PQ.vrrFingerprint row) majorityResult
                          provenance (PQ.vrrComputationSpec row) now Nothing
                      Nothing -> pure ()
                    PQ.updateRoundPhase conn roundId Validated
                  pure RoundStatusResponse
                    { rsrspRoundId = roundId, rsrspPhase = Validated, rsrspMessage = "Unanimous agreement, result cached" }
                CompMajority dissenter -> do
                  now <- liftIO getCurrentTime
                  let majorityResult = case filter (\(a, _) -> a /= dissenter) results of
                        ((_, r):_) -> r
                        _          -> BS.empty
                  liftIO $ withConnection envPool $ \conn -> do
                    mround <- PQ.getValidationRound conn roundId
                    case mround of
                      Just row -> do
                        let provenance = Aeson.toJSON $ ResultProvenance
                              (Majority dissenter)
                              (length results - 1)
                              (fmap fromIntegral (PQ.vrrBeaconRound row))
                              (PQ.vrrSelectionProof row)
                              now
                        PQ.insertCacheEntry conn pid (PQ.vrrFingerprint row) majorityResult
                          provenance (PQ.vrrComputationSpec row) now Nothing
                      Nothing -> pure ()
                    PQ.updateRoundPhase conn roundId Validated
                  pure RoundStatusResponse
                    { rsrspRoundId = roundId, rsrspPhase = Validated, rsrspMessage = "Majority agreement, result cached" }
                CompInconclusive -> do
                  liftIO $ withConnection envPool $ \conn ->
                    PQ.updateRoundPhase conn roundId Failed
                  pure RoundStatusResponse
                    { rsrspRoundId = roundId, rsrspPhase = Failed, rsrspMessage = "No agreement, round failed" }
            else pure RoundStatusResponse
              { rsrspRoundId = roundId, rsrspPhase = Revealing, rsrspMessage = "Reveal accepted, waiting for others" }
        _ -> throwError err400 { errBody = "invalid hex in result or nonce" }

-- === Helpers ===

memberRowToResponse :: PQ.PoolMemberRow -> PoolMemberResponse
memberRowToResponse row = PoolMemberResponse
  { pmrspAgentId = PQ.pmrAgentId row
  , pmrspPublicKey = hexEncode (PQ.pmrPublicKey row)
  , pmrspPrincipalId = PQ.pmrPrincipalId row
  , pmrspJoinedAt = PQ.pmrJoinedAt row
  }

cacheRowToResponse :: PQ.CacheEntryRow -> Handler CacheEntryResponse
cacheRowToResponse row = case Aeson.fromJSON (PQ.cerProvenance row) of
  Aeson.Success prov -> pure CacheEntryResponse
    { cerspFingerprint = hexEncode (PQ.cerFingerprint row)
    , cerspResult = hexEncode (PQ.cerResult row)
    , cerspProvenance = prov
    , cerspComputationSpec = case Aeson.fromJSON (PQ.cerComputationSpec row) of
        Aeson.Success spec -> Just spec
        _                  -> Nothing
    , cerspCreatedAt = PQ.cerCreatedAt row
    , cerspExpiresAt = PQ.cerExpiresAt row
    }
  _ -> throwError err500 { errBody = "Invalid provenance in database" }

sealRowToResponse :: PQ.ValidationSealRow -> SealDetailResponse
sealRowToResponse s = SealDetailResponse
  { sdAgentId  = PQ.vsrAgentId s
  , sdRole     = PQ.vsrRole s
  , sdSealHash = hexEncode (PQ.vsrSealHash s)
  , sdSealSig  = hexEncode (PQ.vsrSealSig s)
  , sdPhase    = PQ.vsrPhase s
  , sdResult   = hexEncode <$> PQ.vsrRevealedResult s
  , sdNonce    = hexEncode <$> PQ.vsrRevealedNonce s
  , sdEvidence = PQ.vsrRevealedEvidence s
  }

hexDecode :: Text -> Maybe ByteString
hexDecode t = case convertFromBase Base16 (TE.encodeUtf8 t) of
  Left _  -> Nothing
  Right bs -> Just bs

