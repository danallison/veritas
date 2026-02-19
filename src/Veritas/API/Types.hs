-- | Servant API type definition and request/response types.
module Veritas.API.Types
  ( VeritasAPI
  , api

    -- * Request types
  , CreateCeremonyRequest(..)
  , CommitRequest(..)
  , RevealRequest(..)

    -- * Response types
  , CeremonyResponse(..)
  , CommitResponse(..)
  , RevealResponse(..)
  , OutcomeResponse(..)
  , AuditLogResponse(..)
  , AuditLogEntryResponse(..)
  , VerifyResponse(..)
  , HealthResponse(..)
  , RandomCoinResponse(..)
  , RandomIntResponse(..)
  , RandomUUIDResponse(..)
  , ServerPubKeyResponse(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withObject, (.:), (.:?), object, (.=))
import Data.Proxy (Proxy(..))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import GHC.Natural (Natural)
import Servant.API

import Veritas.Core.Types (Phase, CeremonyType, EntropyMethod, CommitmentMode, NonParticipationPolicy, BeaconSpec)

-- | The full Veritas API
type VeritasAPI =
       -- Ceremony lifecycle
       "ceremonies" :> ReqBody '[JSON] CreateCeremonyRequest :> Post '[JSON] CeremonyResponse
  :<|> "ceremonies" :> Capture "id" UUID :> Get '[JSON] CeremonyResponse
  :<|> "ceremonies" :> QueryParam "phase" Text :> Get '[JSON] [CeremonyResponse]
  :<|> "ceremonies" :> Capture "id" UUID :> "commit" :> ReqBody '[JSON] CommitRequest :> Post '[JSON] CommitResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "reveal" :> ReqBody '[JSON] RevealRequest :> Post '[JSON] RevealResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "outcome" :> Get '[JSON] OutcomeResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "log" :> Get '[JSON] AuditLogResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "verify" :> Get '[JSON] VerifyResponse

       -- Standalone random
  :<|> "random" :> "coin" :> Get '[JSON] RandomCoinResponse
  :<|> "random" :> "integer" :> QueryParam "min" Int :> QueryParam "max" Int :> Get '[JSON] RandomIntResponse
  :<|> "random" :> "uuid" :> Get '[JSON] RandomUUIDResponse

       -- Server info
  :<|> "server" :> "pubkey" :> Get '[JSON] ServerPubKeyResponse
  :<|> "health" :> Get '[JSON] HealthResponse

api :: Proxy VeritasAPI
api = Proxy

-- === Request types ===

data CreateCeremonyRequest = CreateCeremonyRequest
  { crqQuestion               :: Text
  , crqCeremonyType           :: CeremonyType
  , crqEntropyMethod          :: EntropyMethod
  , crqRequiredParties        :: Natural
  , crqCommitmentMode         :: CommitmentMode
  , crqCommitDeadline         :: UTCTime
  , crqRevealDeadline         :: Maybe UTCTime
  , crqNonParticipationPolicy :: Maybe NonParticipationPolicy
  , crqBeaconSpec             :: Maybe BeaconSpec
  } deriving stock (Eq, Show, Generic)

instance FromJSON CreateCeremonyRequest where
  parseJSON = withObject "CreateCeremonyRequest" $ \o -> CreateCeremonyRequest
    <$> o .: "question"
    <*> o .: "ceremony_type"
    <*> o .: "entropy_method"
    <*> o .: "required_parties"
    <*> o .: "commitment_mode"
    <*> o .: "commit_deadline"
    <*> o .:? "reveal_deadline"
    <*> o .:? "non_participation_policy"
    <*> o .:? "beacon_spec"

instance ToJSON CreateCeremonyRequest where
  toJSON r = object
    [ "question"                 .= crqQuestion r
    , "ceremony_type"            .= crqCeremonyType r
    , "entropy_method"           .= crqEntropyMethod r
    , "required_parties"         .= crqRequiredParties r
    , "commitment_mode"          .= crqCommitmentMode r
    , "commit_deadline"          .= crqCommitDeadline r
    , "reveal_deadline"          .= crqRevealDeadline r
    , "non_participation_policy" .= crqNonParticipationPolicy r
    , "beacon_spec"              .= crqBeaconSpec r
    ]

data CommitRequest = CommitRequest
  { cmrqParticipantId :: UUID
  , cmrqSignature     :: Text
  , cmrqEntropySeal   :: Maybe Text
  } deriving stock (Eq, Show, Generic)

instance FromJSON CommitRequest where
  parseJSON = withObject "CommitRequest" $ \o -> CommitRequest
    <$> o .: "participant_id"
    <*> o .: "signature"
    <*> o .:? "entropy_seal"

instance ToJSON CommitRequest where
  toJSON r = object
    [ "participant_id" .= cmrqParticipantId r
    , "signature"      .= cmrqSignature r
    , "entropy_seal"   .= cmrqEntropySeal r
    ]

data RevealRequest = RevealRequest
  { rvrqParticipantId :: UUID
  , rvrqEntropyValue  :: Text
  } deriving stock (Eq, Show, Generic)

instance FromJSON RevealRequest where
  parseJSON = withObject "RevealRequest" $ \o -> RevealRequest
    <$> o .: "participant_id"
    <*> o .: "entropy_value"

instance ToJSON RevealRequest where
  toJSON r = object
    [ "participant_id" .= rvrqParticipantId r
    , "entropy_value"  .= rvrqEntropyValue r
    ]

-- === Response types ===

data CeremonyResponse = CeremonyResponse
  { crspId                      :: UUID
  , crspQuestion                :: Text
  , crspCeremonyType            :: CeremonyType
  , crspEntropyMethod           :: EntropyMethod
  , crspRequiredParties         :: Natural
  , crspCommitmentMode          :: CommitmentMode
  , crspCommitDeadline          :: UTCTime
  , crspRevealDeadline          :: Maybe UTCTime
  , crspNonParticipationPolicy  :: Maybe NonParticipationPolicy
  , crspBeaconSpec              :: Maybe BeaconSpec
  , crspPhase                   :: Phase
  , crspCreatedBy               :: UUID
  , crspCreatedAt               :: UTCTime
  , crspCommitmentCount         :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON CeremonyResponse where
  toJSON r = object
    [ "id"                       .= crspId r
    , "question"                 .= crspQuestion r
    , "ceremony_type"            .= crspCeremonyType r
    , "entropy_method"           .= crspEntropyMethod r
    , "required_parties"         .= crspRequiredParties r
    , "commitment_mode"          .= crspCommitmentMode r
    , "commit_deadline"          .= crspCommitDeadline r
    , "reveal_deadline"          .= crspRevealDeadline r
    , "non_participation_policy" .= crspNonParticipationPolicy r
    , "beacon_spec"              .= crspBeaconSpec r
    , "phase"                    .= crspPhase r
    , "created_by"               .= crspCreatedBy r
    , "created_at"               .= crspCreatedAt r
    , "commitment_count"         .= crspCommitmentCount r
    ]

instance FromJSON CeremonyResponse where
  parseJSON = withObject "CeremonyResponse" $ \o -> CeremonyResponse
    <$> o .: "id"
    <*> o .: "question"
    <*> o .: "ceremony_type"
    <*> o .: "entropy_method"
    <*> o .: "required_parties"
    <*> o .: "commitment_mode"
    <*> o .: "commit_deadline"
    <*> o .:? "reveal_deadline"
    <*> o .:? "non_participation_policy"
    <*> o .:? "beacon_spec"
    <*> o .: "phase"
    <*> o .: "created_by"
    <*> o .: "created_at"
    <*> o .: "commitment_count"

data CommitResponse = CommitResponse
  { cmrStatus :: Text
  , cmrPhase  :: Phase
  } deriving stock (Eq, Show, Generic)

instance ToJSON CommitResponse where
  toJSON r = object ["status" .= cmrStatus r, "phase" .= cmrPhase r]

instance FromJSON CommitResponse where
  parseJSON = withObject "CommitResponse" $ \o -> CommitResponse
    <$> o .: "status"
    <*> o .: "phase"

data RevealResponse = RevealResponse
  { rvrsStatus :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON RevealResponse where
  toJSON r = object ["status" .= rvrsStatus r]

instance FromJSON RevealResponse where
  parseJSON = withObject "RevealResponse" $ \o -> RevealResponse
    <$> o .: "status"

data OutcomeResponse = OutcomeResponse
  { orOutcome         :: Value
  , orCombinedEntropy :: Text
  , orResolvedAt      :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON OutcomeResponse where
  toJSON r = object
    [ "outcome"          .= orOutcome r
    , "combined_entropy" .= orCombinedEntropy r
    , "resolved_at"      .= orResolvedAt r
    ]

instance FromJSON OutcomeResponse where
  parseJSON = withObject "OutcomeResponse" $ \o -> OutcomeResponse
    <$> o .: "outcome"
    <*> o .: "combined_entropy"
    <*> o .: "resolved_at"

data AuditLogResponse = AuditLogResponse
  { alrEntries :: [AuditLogEntryResponse]
  } deriving stock (Eq, Show, Generic)

instance ToJSON AuditLogResponse where
  toJSON r = object ["entries" .= alrEntries r]

instance FromJSON AuditLogResponse where
  parseJSON = withObject "AuditLogResponse" $ \o -> AuditLogResponse
    <$> o .: "entries"

data AuditLogEntryResponse = AuditLogEntryResponse
  { alerSequenceNum :: Int
  , alerEventType   :: Text
  , alerEventData   :: Value
  , alerPrevHash    :: Text
  , alerEntryHash   :: Text
  , alerCreatedAt   :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON AuditLogEntryResponse where
  toJSON r = object
    [ "sequence_num" .= alerSequenceNum r
    , "event_type"   .= alerEventType r
    , "event_data"   .= alerEventData r
    , "prev_hash"    .= alerPrevHash r
    , "entry_hash"   .= alerEntryHash r
    , "created_at"   .= alerCreatedAt r
    ]

instance FromJSON AuditLogEntryResponse where
  parseJSON = withObject "AuditLogEntryResponse" $ \o -> AuditLogEntryResponse
    <$> o .: "sequence_num"
    <*> o .: "event_type"
    <*> o .: "event_data"
    <*> o .: "prev_hash"
    <*> o .: "entry_hash"
    <*> o .: "created_at"

data VerifyResponse = VerifyResponse
  { vrValid  :: Bool
  , vrErrors :: [Text]
  } deriving stock (Eq, Show, Generic)

instance ToJSON VerifyResponse where
  toJSON r = object ["valid" .= vrValid r, "errors" .= vrErrors r]

instance FromJSON VerifyResponse where
  parseJSON = withObject "VerifyResponse" $ \o -> VerifyResponse
    <$> o .: "valid"
    <*> o .: "errors"

data HealthResponse = HealthResponse
  { hrStatus  :: Text
  , hrVersion :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON HealthResponse where
  toJSON r = object ["status" .= hrStatus r, "version" .= hrVersion r]

instance FromJSON HealthResponse where
  parseJSON = withObject "HealthResponse" $ \o -> HealthResponse
    <$> o .: "status"
    <*> o .: "version"

data RandomCoinResponse = RandomCoinResponse
  { rcrResult :: Bool
  } deriving stock (Eq, Show, Generic)

instance ToJSON RandomCoinResponse where
  toJSON r = object ["result" .= rcrResult r]

instance FromJSON RandomCoinResponse where
  parseJSON = withObject "RandomCoinResponse" $ \o -> RandomCoinResponse
    <$> o .: "result"

data RandomIntResponse = RandomIntResponse
  { rirResult :: Int
  , rirMin    :: Int
  , rirMax    :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON RandomIntResponse where
  toJSON r = object ["result" .= rirResult r, "min" .= rirMin r, "max" .= rirMax r]

instance FromJSON RandomIntResponse where
  parseJSON = withObject "RandomIntResponse" $ \o -> RandomIntResponse
    <$> o .: "result"
    <*> o .: "min"
    <*> o .: "max"

data RandomUUIDResponse = RandomUUIDResponse
  { rurResult :: UUID
  } deriving stock (Eq, Show, Generic)

instance ToJSON RandomUUIDResponse where
  toJSON r = object ["result" .= rurResult r]

instance FromJSON RandomUUIDResponse where
  parseJSON = withObject "RandomUUIDResponse" $ \o -> RandomUUIDResponse
    <$> o .: "result"

data ServerPubKeyResponse = ServerPubKeyResponse
  { spkPublicKey :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON ServerPubKeyResponse where
  toJSON r = object ["public_key" .= spkPublicKey r]

instance FromJSON ServerPubKeyResponse where
  parseJSON = withObject "ServerPubKeyResponse" $ \o -> ServerPubKeyResponse
    <$> o .: "public_key"
