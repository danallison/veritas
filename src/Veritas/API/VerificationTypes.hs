-- | Request/response types for the verification pivot API endpoints.
-- These serve the new frontend (/pools, /verify, /cache top-level routes).
module Veritas.API.VerificationTypes
  ( VerificationPivotAPI

    -- * Request types
  , CreatePoolV2Request(..)
  , JoinPoolV2Request(..)
  , SubmitVerificationRequest(..)
  , RecordSubmissionRequest(..)

    -- * Response types
  , VolunteerPoolResponse(..)
  , PoolMemberV2Response(..)
  , VerificationResponse(..)
  , VerificationSpecResponse(..)
  , VerdictResponse(..)
  , CacheEntryV2Response(..)
  , CacheProvenanceResponse(..)
  , CacheStatsResponse(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withObject, (.:), (.:?), object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Servant.API

-- | Verification pivot API endpoints
type VerificationPivotAPI =
       -- Pool management (new shapes)
       "pools" :> Get '[JSON] [VolunteerPoolResponse]
  :<|> "pools" :> ReqBody '[JSON] CreatePoolV2Request :> Post '[JSON] VolunteerPoolResponse
  :<|> "pools" :> Capture "id" UUID :> Get '[JSON] VolunteerPoolResponse
  :<|> "pools" :> Capture "id" UUID :> "join" :> ReqBody '[JSON] JoinPoolV2Request :> Post '[JSON] PoolMemberV2Response
  :<|> "pools" :> Capture "id" UUID :> "members" :> Get '[JSON] [PoolMemberV2Response]

       -- Verification
  :<|> "verify" :> ReqBody '[JSON] SubmitVerificationRequest :> Post '[JSON] VerificationResponse
  :<|> "verify" :> Capture "id" UUID :> Get '[JSON] VerificationResponse
  :<|> "verify" :> Get '[JSON] [VerificationResponse]
  :<|> "verify" :> Capture "id" UUID :> "submit" :> ReqBody '[JSON] RecordSubmissionRequest :> Post '[JSON] VerificationResponse

       -- Cache (top-level)
  :<|> "cache" :> Get '[JSON] [CacheEntryV2Response]
  :<|> "cache" :> "stats" :> Get '[JSON] CacheStatsResponse
  :<|> "cache" :> Capture "fingerprint" Text :> Get '[JSON] CacheEntryV2Response

-- === Request Types ===

data CreatePoolV2Request = CreatePoolV2Request
  { cpv2Name          :: Text
  , cpv2Description   :: Text
  , cpv2TaskType      :: Text
  , cpv2SelectionSize :: Int
  } deriving stock (Eq, Show, Generic)

instance FromJSON CreatePoolV2Request where
  parseJSON = withObject "CreatePoolV2Request" $ \o -> CreatePoolV2Request
    <$> o .: "name"
    <*> o .: "description"
    <*> o .: "task_type"
    <*> o .: "selection_size"

instance ToJSON CreatePoolV2Request where
  toJSON r = object
    [ "name"           .= cpv2Name r
    , "description"    .= cpv2Description r
    , "task_type"      .= cpv2TaskType r
    , "selection_size" .= cpv2SelectionSize r
    ]

data JoinPoolV2Request = JoinPoolV2Request
  { jpv2AgentId      :: UUID
  , jpv2PublicKey     :: Text    -- hex-encoded Ed25519
  , jpv2DisplayName   :: Text
  , jpv2Capabilities :: [Text]
  } deriving stock (Eq, Show, Generic)

instance FromJSON JoinPoolV2Request where
  parseJSON = withObject "JoinPoolV2Request" $ \o -> JoinPoolV2Request
    <$> o .: "agent_id"
    <*> o .: "public_key"
    <*> o .: "display_name"
    <*> o .: "capabilities"

instance ToJSON JoinPoolV2Request where
  toJSON r = object
    [ "agent_id"     .= jpv2AgentId r
    , "public_key"   .= jpv2PublicKey r
    , "display_name" .= jpv2DisplayName r
    , "capabilities" .= jpv2Capabilities r
    ]

data SubmitVerificationRequest = SubmitVerificationRequest
  { svrPoolId                  :: UUID
  , svrDescription             :: Text
  , svrComputationFingerprint  :: Text
  , svrSubmittedResult         :: Maybe Text
  , svrComparisonMethod        :: Text
  , svrValidatorCount          :: Int
  } deriving stock (Eq, Show, Generic)

instance FromJSON SubmitVerificationRequest where
  parseJSON = withObject "SubmitVerificationRequest" $ \o -> SubmitVerificationRequest
    <$> o .: "pool_id"
    <*> o .: "description"
    <*> o .: "computation_fingerprint"
    <*> o .:? "submitted_result"
    <*> o .: "comparison_method"
    <*> o .: "validator_count"

instance ToJSON SubmitVerificationRequest where
  toJSON r = object
    [ "pool_id"                  .= svrPoolId r
    , "description"              .= svrDescription r
    , "computation_fingerprint"  .= svrComputationFingerprint r
    , "submitted_result"         .= svrSubmittedResult r
    , "comparison_method"        .= svrComparisonMethod r
    , "validator_count"          .= svrValidatorCount r
    ]

data RecordSubmissionRequest = RecordSubmissionRequest
  { rsrAgentId :: UUID
  , rsrResult  :: Text    -- hex-encoded
  } deriving stock (Eq, Show, Generic)

instance FromJSON RecordSubmissionRequest where
  parseJSON = withObject "RecordSubmissionRequest" $ \o -> RecordSubmissionRequest
    <$> o .: "agent_id"
    <*> o .: "result"

instance ToJSON RecordSubmissionRequest where
  toJSON r = object
    [ "agent_id" .= rsrAgentId r
    , "result"   .= rsrResult r
    ]

-- === Response Types ===

data VolunteerPoolResponse = VolunteerPoolResponse
  { vprId                :: UUID
  , vprName              :: Text
  , vprDescription       :: Text
  , vprTaskType          :: Text
  , vprSelectionSize     :: Int
  , vprMemberCount       :: Int
  , vprActiveMemberCount :: Int
  , vprCreatedAt         :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON VolunteerPoolResponse where
  toJSON r = object
    [ "id"                  .= vprId r
    , "name"                .= vprName r
    , "description"         .= vprDescription r
    , "task_type"           .= vprTaskType r
    , "selection_size"      .= vprSelectionSize r
    , "member_count"        .= vprMemberCount r
    , "active_member_count" .= vprActiveMemberCount r
    , "created_at"          .= vprCreatedAt r
    ]

instance FromJSON VolunteerPoolResponse where
  parseJSON = withObject "VolunteerPoolResponse" $ \o -> VolunteerPoolResponse
    <$> o .: "id"
    <*> o .: "name"
    <*> o .: "description"
    <*> o .: "task_type"
    <*> o .: "selection_size"
    <*> o .: "member_count"
    <*> o .: "active_member_count"
    <*> o .: "created_at"

data PoolMemberV2Response = PoolMemberV2Response
  { pmv2rAgentId      :: UUID
  , pmv2rPublicKey    :: Text       -- hex-encoded
  , pmv2rDisplayName  :: Text
  , pmv2rCapabilities :: [Text]
  , pmv2rStatus       :: Text
  , pmv2rJoinedAt     :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON PoolMemberV2Response where
  toJSON r = object
    [ "agent_id"     .= pmv2rAgentId r
    , "public_key"   .= pmv2rPublicKey r
    , "display_name" .= pmv2rDisplayName r
    , "capabilities" .= pmv2rCapabilities r
    , "status"       .= pmv2rStatus r
    , "joined_at"    .= pmv2rJoinedAt r
    ]

instance FromJSON PoolMemberV2Response where
  parseJSON = withObject "PoolMemberV2Response" $ \o -> PoolMemberV2Response
    <$> o .: "agent_id"
    <*> o .: "public_key"
    <*> o .: "display_name"
    <*> o .: "capabilities"
    <*> o .: "status"
    <*> o .: "joined_at"

data VerificationSpecResponse = VerificationSpecResponse
  { vsrDescription             :: Text
  , vsrComputationFingerprint  :: Text
  , vsrSubmittedResult         :: Maybe Text
  , vsrComparisonMethod        :: Text
  , vsrValidatorCount          :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON VerificationSpecResponse where
  toJSON r = object
    [ "description"              .= vsrDescription r
    , "computation_fingerprint"  .= vsrComputationFingerprint r
    , "submitted_result"         .= vsrSubmittedResult r
    , "comparison_method"        .= vsrComparisonMethod r
    , "validator_count"          .= vsrValidatorCount r
    ]

instance FromJSON VerificationSpecResponse where
  parseJSON = withObject "VerificationSpecResponse" $ \o -> VerificationSpecResponse
    <$> o .: "description"
    <*> o .: "computation_fingerprint"
    <*> o .:? "submitted_result"
    <*> o .: "comparison_method"
    <*> o .: "validator_count"

data VerdictResponse = VerdictResponse
  { vrdOutcome        :: Value     -- {tag, dissenters?}
  , vrdAgreementCount :: Int
  , vrdMajorityResult :: Maybe Text
  , vrdDecidedAt      :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON VerdictResponse where
  toJSON r = object
    [ "outcome"          .= vrdOutcome r
    , "agreement_count"  .= vrdAgreementCount r
    , "majority_result"  .= vrdMajorityResult r
    , "decided_at"       .= vrdDecidedAt r
    ]

instance FromJSON VerdictResponse where
  parseJSON = withObject "VerdictResponse" $ \o -> VerdictResponse
    <$> o .: "outcome"
    <*> o .: "agreement_count"
    <*> o .:? "majority_result"
    <*> o .: "decided_at"

data VerificationResponse = VerificationResponse
  { verifyId                 :: UUID
  , verifyPoolId             :: UUID
  , verifySpec               :: VerificationSpecResponse
  , verifySubmitter          :: UUID
  , verifyValidators         :: [UUID]
  , verifySubmissionCount    :: Int
  , verifyExpectedSubmissions :: Int
  , verifyPhase              :: Text
  , verifyVerdict            :: Maybe VerdictResponse
  , verifyCreatedAt          :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON VerificationResponse where
  toJSON r = object
    [ "id"                   .= verifyId r
    , "pool_id"              .= verifyPoolId r
    , "spec"                 .= verifySpec r
    , "submitter"            .= verifySubmitter r
    , "validators"           .= verifyValidators r
    , "submission_count"     .= verifySubmissionCount r
    , "expected_submissions" .= verifyExpectedSubmissions r
    , "phase"                .= verifyPhase r
    , "verdict"              .= verifyVerdict r
    , "created_at"           .= verifyCreatedAt r
    ]

instance FromJSON VerificationResponse where
  parseJSON = withObject "VerificationResponse" $ \o -> VerificationResponse
    <$> o .: "id"
    <*> o .: "pool_id"
    <*> o .: "spec"
    <*> o .: "submitter"
    <*> o .: "validators"
    <*> o .: "submission_count"
    <*> o .: "expected_submissions"
    <*> o .: "phase"
    <*> o .:? "verdict"
    <*> o .: "created_at"

data CacheProvenanceResponse = CacheProvenanceResponse
  { cprVerdictOutcome  :: Value
  , cprAgreementCount  :: Int
  , cprCachedAt        :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON CacheProvenanceResponse where
  toJSON r = object
    [ "verdict_outcome" .= cprVerdictOutcome r
    , "agreement_count" .= cprAgreementCount r
    , "cached_at"       .= cprCachedAt r
    ]

instance FromJSON CacheProvenanceResponse where
  parseJSON = withObject "CacheProvenanceResponse" $ \o -> CacheProvenanceResponse
    <$> o .: "verdict_outcome"
    <*> o .: "agreement_count"
    <*> o .: "cached_at"

data CacheEntryV2Response = CacheEntryV2Response
  { cev2Fingerprint  :: Text
  , cev2Result       :: Text       -- hex-encoded
  , cev2Provenance   :: CacheProvenanceResponse
  , cev2TtlSeconds   :: Maybe Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON CacheEntryV2Response where
  toJSON r = object
    [ "fingerprint"  .= cev2Fingerprint r
    , "result"       .= cev2Result r
    , "provenance"   .= cev2Provenance r
    , "ttl_seconds"  .= cev2TtlSeconds r
    ]

instance FromJSON CacheEntryV2Response where
  parseJSON = withObject "CacheEntryV2Response" $ \o -> CacheEntryV2Response
    <$> o .: "fingerprint"
    <*> o .: "result"
    <*> o .: "provenance"
    <*> o .:? "ttl_seconds"

data CacheStatsResponse = CacheStatsResponse
  { csTotal     :: Int
  , csUnanimous :: Int
  , csMajority  :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON CacheStatsResponse where
  toJSON r = object
    [ "total_entries"    .= csTotal r
    , "unanimous_count"  .= csUnanimous r
    , "majority_count"   .= csMajority r
    ]

instance FromJSON CacheStatsResponse where
  parseJSON = withObject "CacheStatsResponse" $ \o -> CacheStatsResponse
    <$> o .: "total_entries"
    <*> o .: "unanimous_count"
    <*> o .: "majority_count"
