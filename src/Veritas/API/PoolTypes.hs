-- | Request/response types for the Pool computing API endpoints.
module Veritas.API.PoolTypes
  ( PoolAPI

    -- * Request types
  , CreatePoolRequest(..)
  , JoinPoolRequest(..)
  , SubmitComputeRequest(..)
  , SubmitSealRequest(..)
  , SubmitRevealRequest(..)

    -- * Response types
  , PoolResponse(..)
  , PoolMemberResponse(..)
  , CacheEntryResponse(..)
  , ValidationRoundResponse(..)
  , RoundStatusResponse(..)
  , RoundDetailResponse(..)
  , SealDetailResponse(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withObject, (.:), (.:?), object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Servant.API

import Veritas.Pool.Types (ComparisonMethod, ValidationPhase, ComputationSpec, ResultProvenance)

-- | Pool computing API endpoints
type PoolAPI =
       -- Pool management
       "pools" :> ReqBody '[JSON] CreatePoolRequest :> Post '[JSON] PoolResponse
  :<|> "pools" :> Capture "id" UUID :> Get '[JSON] PoolResponse
  :<|> "pools" :> Capture "id" UUID :> "join" :> ReqBody '[JSON] JoinPoolRequest :> Post '[JSON] PoolMemberResponse
  :<|> "pools" :> Capture "id" UUID :> "members" :> Get '[JSON] [PoolMemberResponse]

       -- Cache
  :<|> "pools" :> Capture "id" UUID :> "cache" :> Capture "fingerprint" Text :> Get '[JSON] CacheEntryResponse
  :<|> "pools" :> Capture "id" UUID :> "cache" :> Get '[JSON] [CacheEntryResponse]

       -- Validation rounds
  :<|> "pools" :> Capture "id" UUID :> "compute" :> ReqBody '[JSON] SubmitComputeRequest :> Post '[JSON] ValidationRoundResponse
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Get '[JSON] [ValidationRoundResponse]
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Capture "roundId" UUID :> Get '[JSON] RoundStatusResponse
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Capture "roundId" UUID :> "detail" :> Get '[JSON] RoundDetailResponse
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Capture "roundId" UUID :> "seals" :> Get '[JSON] [SealDetailResponse]
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Capture "roundId" UUID :> "seal" :> ReqBody '[JSON] SubmitSealRequest :> Post '[JSON] RoundStatusResponse
  :<|> "pools" :> Capture "id" UUID :> "rounds" :> Capture "roundId" UUID :> "reveal" :> ReqBody '[JSON] SubmitRevealRequest :> Post '[JSON] RoundStatusResponse

-- === Request Types ===

data CreatePoolRequest = CreatePoolRequest
  { cprName                   :: Text
  , cprComparisonMethod       :: ComparisonMethod
  , cprComputeDeadlineSeconds :: Int
  , cprMinPrincipals          :: Int
  } deriving stock (Eq, Show, Generic)

instance FromJSON CreatePoolRequest where
  parseJSON = withObject "CreatePoolRequest" $ \o -> CreatePoolRequest
    <$> o .: "name"
    <*> o .: "comparison_method"
    <*> o .: "compute_deadline_seconds"
    <*> o .: "min_principals"

instance ToJSON CreatePoolRequest where
  toJSON r = object
    [ "name"                     .= cprName r
    , "comparison_method"        .= cprComparisonMethod r
    , "compute_deadline_seconds" .= cprComputeDeadlineSeconds r
    , "min_principals"           .= cprMinPrincipals r
    ]

data JoinPoolRequest = JoinPoolRequest
  { jprAgentId     :: UUID
  , jprPublicKey   :: Text     -- hex-encoded
  , jprPrincipalId :: Text
  } deriving stock (Eq, Show, Generic)

instance FromJSON JoinPoolRequest where
  parseJSON = withObject "JoinPoolRequest" $ \o -> JoinPoolRequest
    <$> o .: "agent_id"
    <*> o .: "public_key"
    <*> o .: "principal_id"

instance ToJSON JoinPoolRequest where
  toJSON r = object
    [ "agent_id"     .= jprAgentId r
    , "public_key"   .= jprPublicKey r
    , "principal_id" .= jprPrincipalId r
    ]

data SubmitComputeRequest = SubmitComputeRequest
  { scrAgentId         :: UUID
  , scrComputationSpec :: ComputationSpec
  , scrSealHash        :: Text   -- hex-encoded
  , scrSealSig         :: Text   -- hex-encoded
  } deriving stock (Eq, Show, Generic)

instance FromJSON SubmitComputeRequest where
  parseJSON = withObject "SubmitComputeRequest" $ \o -> SubmitComputeRequest
    <$> o .: "agent_id"
    <*> o .: "computation_spec"
    <*> o .: "seal_hash"
    <*> o .: "seal_sig"

instance ToJSON SubmitComputeRequest where
  toJSON r = object
    [ "agent_id"          .= scrAgentId r
    , "computation_spec"  .= scrComputationSpec r
    , "seal_hash"         .= scrSealHash r
    , "seal_sig"          .= scrSealSig r
    ]

data SubmitSealRequest = SubmitSealRequest
  { ssrAgentId  :: UUID
  , ssrSealHash :: Text   -- hex-encoded
  , ssrSealSig  :: Text   -- hex-encoded
  } deriving stock (Eq, Show, Generic)

instance FromJSON SubmitSealRequest where
  parseJSON = withObject "SubmitSealRequest" $ \o -> SubmitSealRequest
    <$> o .: "agent_id"
    <*> o .: "seal_hash"
    <*> o .: "seal_sig"

instance ToJSON SubmitSealRequest where
  toJSON r = object
    [ "agent_id"  .= ssrAgentId r
    , "seal_hash" .= ssrSealHash r
    , "seal_sig"  .= ssrSealSig r
    ]

data SubmitRevealRequest = SubmitRevealRequest
  { srrAgentId  :: UUID
  , srrResult   :: Text     -- hex-encoded
  , srrEvidence :: Value    -- execution evidence JSON
  , srrNonce    :: Text     -- hex-encoded
  } deriving stock (Eq, Show, Generic)

instance FromJSON SubmitRevealRequest where
  parseJSON = withObject "SubmitRevealRequest" $ \o -> SubmitRevealRequest
    <$> o .: "agent_id"
    <*> o .: "result"
    <*> o .: "evidence"
    <*> o .: "nonce"

instance ToJSON SubmitRevealRequest where
  toJSON r = object
    [ "agent_id" .= srrAgentId r
    , "result"   .= srrResult r
    , "evidence" .= srrEvidence r
    , "nonce"    .= srrNonce r
    ]

-- === Response Types ===

data PoolResponse = PoolResponse
  { prspId                     :: UUID
  , prspName                   :: Text
  , prspComparisonMethod       :: ComparisonMethod
  , prspComputeDeadlineSeconds :: Int
  , prspMinPrincipals          :: Int
  , prspCreatedAt              :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON PoolResponse where
  toJSON r = object
    [ "id"                       .= prspId r
    , "name"                     .= prspName r
    , "comparison_method"        .= prspComparisonMethod r
    , "compute_deadline_seconds" .= prspComputeDeadlineSeconds r
    , "min_principals"           .= prspMinPrincipals r
    , "created_at"               .= prspCreatedAt r
    ]

instance FromJSON PoolResponse where
  parseJSON = withObject "PoolResponse" $ \o -> PoolResponse
    <$> o .: "id"
    <*> o .: "name"
    <*> o .: "comparison_method"
    <*> o .: "compute_deadline_seconds"
    <*> o .: "min_principals"
    <*> o .: "created_at"

data PoolMemberResponse = PoolMemberResponse
  { pmrspAgentId     :: UUID
  , pmrspPublicKey   :: Text
  , pmrspPrincipalId :: Text
  , pmrspJoinedAt    :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON PoolMemberResponse where
  toJSON r = object
    [ "agent_id"     .= pmrspAgentId r
    , "public_key"   .= pmrspPublicKey r
    , "principal_id" .= pmrspPrincipalId r
    , "joined_at"    .= pmrspJoinedAt r
    ]

instance FromJSON PoolMemberResponse where
  parseJSON = withObject "PoolMemberResponse" $ \o -> PoolMemberResponse
    <$> o .: "agent_id"
    <*> o .: "public_key"
    <*> o .: "principal_id"
    <*> o .: "joined_at"

data CacheEntryResponse = CacheEntryResponse
  { cerspFingerprint     :: Text
  , cerspResult          :: Text     -- hex-encoded
  , cerspProvenance      :: ResultProvenance
  , cerspComputationSpec :: Maybe ComputationSpec
  , cerspCreatedAt       :: UTCTime
  , cerspExpiresAt       :: Maybe UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON CacheEntryResponse where
  toJSON r = object
    [ "fingerprint"      .= cerspFingerprint r
    , "result"           .= cerspResult r
    , "provenance"       .= cerspProvenance r
    , "computation_spec" .= cerspComputationSpec r
    , "created_at"       .= cerspCreatedAt r
    , "expires_at"       .= cerspExpiresAt r
    ]

instance FromJSON CacheEntryResponse where
  parseJSON = withObject "CacheEntryResponse" $ \o -> CacheEntryResponse
    <$> o .: "fingerprint"
    <*> o .: "result"
    <*> o .: "provenance"
    <*> o .:? "computation_spec"
    <*> o .: "created_at"
    <*> o .:? "expires_at"

data ValidationRoundResponse = ValidationRoundResponse
  { vrrspRoundId     :: UUID
  , vrrspFingerprint :: Text
  , vrrspPhase       :: ValidationPhase
  , vrrspCreatedAt   :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON ValidationRoundResponse where
  toJSON r = object
    [ "round_id"    .= vrrspRoundId r
    , "fingerprint" .= vrrspFingerprint r
    , "phase"       .= vrrspPhase r
    , "created_at"  .= vrrspCreatedAt r
    ]

instance FromJSON ValidationRoundResponse where
  parseJSON = withObject "ValidationRoundResponse" $ \o -> ValidationRoundResponse
    <$> o .: "round_id"
    <*> o .: "fingerprint"
    <*> o .: "phase"
    <*> o .: "created_at"

data RoundStatusResponse = RoundStatusResponse
  { rsrspRoundId :: UUID
  , rsrspPhase   :: ValidationPhase
  , rsrspMessage :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON RoundStatusResponse where
  toJSON r = object
    [ "round_id" .= rsrspRoundId r
    , "phase"    .= rsrspPhase r
    , "message"  .= rsrspMessage r
    ]

instance FromJSON RoundStatusResponse where
  parseJSON = withObject "RoundStatusResponse" $ \o -> RoundStatusResponse
    <$> o .: "round_id"
    <*> o .: "phase"
    <*> o .: "message"

-- | Detailed round information including seals
data RoundDetailResponse = RoundDetailResponse
  { rdrRoundId         :: UUID
  , rdrFingerprint     :: Text
  , rdrPhase           :: ValidationPhase
  , rdrComputationSpec :: ComputationSpec
  , rdrRequesterId     :: UUID
  , rdrBeaconRound     :: Maybe Int
  , rdrCreatedAt       :: UTCTime
  , rdrSeals           :: [SealDetailResponse]
  } deriving stock (Eq, Show, Generic)

instance ToJSON RoundDetailResponse where
  toJSON r = object
    [ "round_id"         .= rdrRoundId r
    , "fingerprint"      .= rdrFingerprint r
    , "phase"            .= rdrPhase r
    , "computation_spec" .= rdrComputationSpec r
    , "requester_id"     .= rdrRequesterId r
    , "beacon_round"     .= rdrBeaconRound r
    , "created_at"       .= rdrCreatedAt r
    , "seals"            .= rdrSeals r
    ]

instance FromJSON RoundDetailResponse where
  parseJSON = withObject "RoundDetailResponse" $ \o -> RoundDetailResponse
    <$> o .: "round_id"
    <*> o .: "fingerprint"
    <*> o .: "phase"
    <*> o .: "computation_spec"
    <*> o .: "requester_id"
    <*> o .:? "beacon_round"
    <*> o .: "created_at"
    <*> o .: "seals"

-- | Per-agent seal details
data SealDetailResponse = SealDetailResponse
  { sdAgentId  :: UUID
  , sdRole     :: Text
  , sdSealHash :: Text   -- hex-encoded
  , sdSealSig  :: Text   -- hex-encoded
  , sdPhase    :: Text
  , sdResult   :: Maybe Text   -- hex-encoded, revealed
  , sdNonce    :: Maybe Text   -- hex-encoded, revealed
  , sdEvidence :: Maybe Value  -- revealed
  } deriving stock (Eq, Show, Generic)

instance ToJSON SealDetailResponse where
  toJSON r = object
    [ "agent_id"  .= sdAgentId r
    , "role"      .= sdRole r
    , "seal_hash" .= sdSealHash r
    , "seal_sig"  .= sdSealSig r
    , "phase"     .= sdPhase r
    , "result"    .= sdResult r
    , "nonce"     .= sdNonce r
    , "evidence"  .= sdEvidence r
    ]

instance FromJSON SealDetailResponse where
  parseJSON = withObject "SealDetailResponse" $ \o -> SealDetailResponse
    <$> o .: "agent_id"
    <*> o .: "role"
    <*> o .: "seal_hash"
    <*> o .: "seal_sig"
    <*> o .: "phase"
    <*> o .:? "result"
    <*> o .:? "nonce"
    <*> o .:? "evidence"
