-- | Servant request handlers for the verification pivot API.
module Veritas.API.VerificationHandlers
  ( verificationServer
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.ByteArray.Encoding (Base(..), convertFromBase)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Data.UUID (UUID)
import qualified Data.UUID.V4 as UUID4
import Servant

import Veritas.API.Handlers (AppEnv(..))
import Veritas.API.VerificationTypes
import Veritas.Crypto.Hash (hexEncode)
import Veritas.DB.Pool (withConnection)
import qualified Veritas.DB.PoolQueries as PQ

-- | Wire up all verification pivot handlers
verificationServer :: AppEnv -> Server VerificationPivotAPI
verificationServer env =
       listPoolsH env
  :<|> createPoolH env
  :<|> getPoolH env
  :<|> joinPoolH env
  :<|> listMembersH env
  :<|> submitVerificationH env
  :<|> getVerificationH env
  :<|> listVerificationsH env
  :<|> recordSubmissionH env
  :<|> listCacheH env
  :<|> cacheStatsH env
  :<|> lookupCacheH env

-- === Pool Handlers ===

listPoolsH :: AppEnv -> Handler [VolunteerPoolResponse]
listPoolsH AppEnv{..} = do
  pools <- liftIO $ withConnection envPool $ \conn -> PQ.listPoolsV2 conn
  -- Get member counts for each pool
  mapM (\p -> do
    members <- liftIO $ withConnection envPool $ \conn ->
      PQ.getPoolMembersV2 conn (PQ.pv2Id p)
    let total = length members
        active = length (filter (\m -> PQ.pmv2Status m == "active") members)
    pure VolunteerPoolResponse
      { vprId = PQ.pv2Id p
      , vprName = PQ.pv2Name p
      , vprDescription = PQ.pv2Description p
      , vprTaskType = PQ.pv2TaskType p
      , vprSelectionSize = PQ.pv2SelectionSize p
      , vprMemberCount = total
      , vprActiveMemberCount = active
      , vprCreatedAt = PQ.pv2CreatedAt p
      }
    ) pools

createPoolH :: AppEnv -> CreatePoolV2Request -> Handler VolunteerPoolResponse
createPoolH AppEnv{..} req = do
  now <- liftIO getCurrentTime
  pid <- liftIO UUID4.nextRandom
  liftIO $ withConnection envPool $ \conn ->
    PQ.insertPoolV2 conn pid
      (cpv2Name req)
      (cpv2Description req)
      (cpv2TaskType req)
      (cpv2SelectionSize req)
      now
  pure VolunteerPoolResponse
    { vprId = pid
    , vprName = cpv2Name req
    , vprDescription = cpv2Description req
    , vprTaskType = cpv2TaskType req
    , vprSelectionSize = cpv2SelectionSize req
    , vprMemberCount = 0
    , vprActiveMemberCount = 0
    , vprCreatedAt = now
    }

getPoolH :: AppEnv -> UUID -> Handler VolunteerPoolResponse
getPoolH AppEnv{..} pid = do
  mpool <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolV2 conn pid
  case mpool of
    Nothing -> throwError err404
    Just p -> do
      members <- liftIO $ withConnection envPool $ \conn ->
        PQ.getPoolMembersV2 conn pid
      let total = length members
          active = length (filter (\m -> PQ.pmv2Status m == "active") members)
      pure VolunteerPoolResponse
        { vprId = PQ.pv2Id p
        , vprName = PQ.pv2Name p
        , vprDescription = PQ.pv2Description p
        , vprTaskType = PQ.pv2TaskType p
        , vprSelectionSize = PQ.pv2SelectionSize p
        , vprMemberCount = total
        , vprActiveMemberCount = active
        , vprCreatedAt = PQ.pv2CreatedAt p
        }

joinPoolH :: AppEnv -> UUID -> JoinPoolV2Request -> Handler PoolMemberV2Response
joinPoolH AppEnv{..} pid req = do
  now <- liftIO getCurrentTime
  case hexDecode (jpv2PublicKey req) of
    Nothing -> throwError err400 { errBody = "invalid hex in public_key" }
    Just pkBytes
      | BS.length pkBytes /= 32 ->
          throwError err400 { errBody = "public_key must be 32 bytes (Ed25519)" }
      | otherwise -> do
          mpool <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolV2 conn pid
          case mpool of
            Nothing -> throwError err404
            Just _ -> do
              let caps = Aeson.toJSON (jpv2Capabilities req)
              liftIO $ withConnection envPool $ \conn ->
                PQ.insertPoolMemberV2 conn pid (jpv2AgentId req) pkBytes
                  (jpv2DisplayName req) (jpv2DisplayName req) caps now
              pure PoolMemberV2Response
                { pmv2rAgentId = jpv2AgentId req
                , pmv2rPublicKey = jpv2PublicKey req
                , pmv2rDisplayName = jpv2DisplayName req
                , pmv2rCapabilities = jpv2Capabilities req
                , pmv2rStatus = "active"
                , pmv2rJoinedAt = now
                }

listMembersH :: AppEnv -> UUID -> Handler [PoolMemberV2Response]
listMembersH AppEnv{..} pid = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.getPoolMembersV2 conn pid
  pure $ map memberToResponse rows

-- === Verification Handlers ===

submitVerificationH :: AppEnv -> SubmitVerificationRequest -> Handler VerificationResponse
submitVerificationH AppEnv{..} req = do
  now <- liftIO getCurrentTime
  vid <- liftIO UUID4.nextRandom
  submitterId <- liftIO UUID4.nextRandom  -- placeholder: in real flow, extracted from auth
  let expectedSubmissions = svrValidatorCount req + 1  -- validators + submitter
      validators = Aeson.toJSON ([] :: [UUID])  -- populated when selection happens
  liftIO $ withConnection envPool $ \conn ->
    PQ.insertVerification conn vid
      (svrPoolId req)
      (svrDescription req)
      (svrComputationFingerprint req)
      (svrSubmittedResult req)
      (svrComparisonMethod req)
      (svrValidatorCount req)
      submitterId
      validators
      expectedSubmissions
      now
  pure VerificationResponse
    { verifyId = vid
    , verifyPoolId = svrPoolId req
    , verifySpec = VerificationSpecResponse
        { vsrDescription = svrDescription req
        , vsrComputationFingerprint = svrComputationFingerprint req
        , vsrSubmittedResult = svrSubmittedResult req
        , vsrComparisonMethod = svrComparisonMethod req
        , vsrValidatorCount = svrValidatorCount req
        }
    , verifySubmitter = submitterId
    , verifyValidators = []
    , verifySubmissionCount = 0
    , verifyExpectedSubmissions = expectedSubmissions
    , verifyPhase = "collecting"
    , verifyVerdict = Nothing
    , verifyCreatedAt = now
    }

getVerificationH :: AppEnv -> UUID -> Handler VerificationResponse
getVerificationH AppEnv{..} vid = do
  mrow <- liftIO $ withConnection envPool $ \conn -> PQ.getVerification conn vid
  case mrow of
    Nothing -> throwError err404
    Just row -> pure (rowToVerificationResponse row)

listVerificationsH :: AppEnv -> Handler [VerificationResponse]
listVerificationsH AppEnv{..} = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.listVerifications conn
  pure $ map rowToVerificationResponse rows

recordSubmissionH :: AppEnv -> UUID -> RecordSubmissionRequest -> Handler VerificationResponse
recordSubmissionH AppEnv{..} vid _req = do
  mrow <- liftIO $ withConnection envPool $ \conn -> PQ.getVerification conn vid
  case mrow of
    Nothing -> throwError err404
    Just row -> do
      let newCount = PQ.vrSubmissionCount row + 1
          newPhase = if newCount >= PQ.vrExpectedSubmissions row then "deciding" else "collecting"
      liftIO $ withConnection envPool $ \conn -> do
        PQ.updateVerificationSubmissionCount conn vid newCount
        when (newPhase /= PQ.vrPhase row) $
          PQ.updateVerificationVerdict conn vid newPhase (Aeson.toJSON (Nothing :: Maybe ()))
      mrow' <- liftIO $ withConnection envPool $ \conn -> PQ.getVerification conn vid
      case mrow' of
        Nothing -> throwError err500
        Just row' -> pure (rowToVerificationResponse row')

-- === Cache Handlers ===

listCacheH :: AppEnv -> Handler [CacheEntryV2Response]
listCacheH AppEnv{..} = do
  rows <- liftIO $ withConnection envPool $ \conn -> PQ.getAllCacheEntries conn
  mapM cacheRowToV2Response rows

cacheStatsH :: AppEnv -> Handler CacheStatsResponse
cacheStatsH AppEnv{..} = do
  (total, unan, maj) <- liftIO $ withConnection envPool $ \conn -> PQ.countCacheEntries conn
  pure CacheStatsResponse
    { csTotal = total
    , csUnanimous = unan
    , csMajority = maj
    }

lookupCacheH :: AppEnv -> Text -> Handler CacheEntryV2Response
lookupCacheH AppEnv{..} fpText = do
  -- Try all pools for this fingerprint
  case hexDecode fpText of
    Nothing -> throwError err404 { errBody = "invalid fingerprint" }
    Just fpBytes -> do
      rows <- liftIO $ withConnection envPool $ \conn -> PQ.getAllCacheEntries conn
      let matching = filter (\r -> PQ.cerFingerprint r == fpBytes) rows
      case matching of
        [] -> throwError err404
        (row:_) -> cacheRowToV2Response row

-- === Helpers ===

memberToResponse :: PQ.PoolMemberV2Row -> PoolMemberV2Response
memberToResponse row =
  let caps = case Aeson.fromJSON (PQ.pmv2Capabilities row) of
        Aeson.Success cs -> cs
        _                -> []
  in PoolMemberV2Response
    { pmv2rAgentId = PQ.pmv2AgentId row
    , pmv2rPublicKey = hexEncode (PQ.pmv2PublicKey row)
    , pmv2rDisplayName = PQ.pmv2DisplayName row
    , pmv2rCapabilities = caps
    , pmv2rStatus = PQ.pmv2Status row
    , pmv2rJoinedAt = PQ.pmv2JoinedAt row
    }

rowToVerificationResponse :: PQ.VerificationRow -> VerificationResponse
rowToVerificationResponse row =
  let validators = case Aeson.fromJSON (PQ.vrValidators row) of
        Aeson.Success vs -> vs
        _                -> []
      verdict = case PQ.vrVerdict row of
        Just v -> case Aeson.fromJSON v of
          Aeson.Success vr -> Just vr
          _                -> Nothing
        Nothing -> Nothing
  in VerificationResponse
    { verifyId = PQ.vrId row
    , verifyPoolId = PQ.vrPoolId row
    , verifySpec = VerificationSpecResponse
        { vsrDescription = PQ.vrDescription row
        , vsrComputationFingerprint = PQ.vrFingerprint row
        , vsrSubmittedResult = PQ.vrSubmittedResult row
        , vsrComparisonMethod = PQ.vrComparisonMethod row
        , vsrValidatorCount = PQ.vrValidatorCount row
        }
    , verifySubmitter = PQ.vrSubmitter row
    , verifyValidators = validators
    , verifySubmissionCount = PQ.vrSubmissionCount row
    , verifyExpectedSubmissions = PQ.vrExpectedSubmissions row
    , verifyPhase = PQ.vrPhase row
    , verifyVerdict = verdict
    , verifyCreatedAt = PQ.vrCreatedAt row
    }

cacheRowToV2Response :: PQ.CacheEntryRow -> Handler CacheEntryV2Response
cacheRowToV2Response row = do
  let provJson = PQ.cerProvenance row
      mProv = case provJson of
        Aeson.Object obj ->
          -- Handle both old format (outcome/validated_at) and new format (verdict_outcome/cached_at)
          let outcome = firstJust [KM.lookup (Key.fromText "verdict_outcome") obj
                                  ,KM.lookup (Key.fromText "outcome") obj]
              agreementCount = case KM.lookup (Key.fromText "agreement_count") obj of
                Just (Aeson.Number n) -> Just (round n :: Int)
                _                     -> Nothing
              cachedAt = case firstJust [KM.lookup (Key.fromText "cached_at") obj
                                        ,KM.lookup (Key.fromText "validated_at") obj] of
                Just v -> case Aeson.fromJSON v of
                  Aeson.Success (t :: UTCTime) -> Just t
                  _                            -> Nothing
                Nothing -> Nothing
          in case (outcome, agreementCount, cachedAt) of
            (Just o, Just ac, Just ca) -> Just CacheProvenanceResponse
              { cprVerdictOutcome = o
              , cprAgreementCount = ac
              , cprCachedAt = ca
              }
            _ -> Nothing
        _ -> Nothing
      ttl = case PQ.cerExpiresAt row of
        Just expiry -> Just (round (diffUTCTime expiry (PQ.cerCreatedAt row)) :: Int)
        Nothing     -> Nothing
  case mProv of
    Just prov -> pure CacheEntryV2Response
      { cev2Fingerprint = hexEncode (PQ.cerFingerprint row)
      , cev2Result = hexEncode (PQ.cerResult row)
      , cev2Provenance = prov
      , cev2TtlSeconds = ttl
      }
    Nothing -> throwError err500 { errBody = "Invalid provenance in database" }

firstJust :: [Maybe a] -> Maybe a
firstJust []             = Nothing
firstJust (Just x : _)  = Just x
firstJust (Nothing : xs) = firstJust xs

hexDecode :: Text -> Maybe BS.ByteString
hexDecode t = case convertFromBase Base16 (TE.encodeUtf8 t) of
  Left _  -> Nothing
  Right bs -> Just bs

when :: Bool -> IO () -> IO ()
when True  act = act
when False _   = pure ()
