-- | Servant API type definition and request/response types.
module Veritas.API.Types
  ( VeritasAPI
  , FullAPI
  , api
  , fullApi

    -- * Request types
  , CreateCeremonyRequest(..)
  , CommitRequest(..)
  , RevealRequest(..)

    -- * Response types
  , CeremonyResponse(..)
  , CommittedParticipantResponse(..)
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
import Control.Lens ((&), (.~), (?~))
import qualified Data.HashMap.Strict.InsOrd as IOHM
import qualified Data.OpenApi
import Data.OpenApi (ToSchema(..))
import qualified Data.OpenApi as OA
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

-- | Full API including the docs endpoint
type FullAPI = VeritasAPI :<|> "docs" :> Get '[JSON] Data.OpenApi.OpenApi

fullApi :: Proxy FullAPI
fullApi = Proxy

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
  , cmrqDisplayName   :: Maybe Text
  } deriving stock (Eq, Show, Generic)

instance FromJSON CommitRequest where
  parseJSON = withObject "CommitRequest" $ \o -> CommitRequest
    <$> o .: "participant_id"
    <*> o .: "signature"
    <*> o .:? "entropy_seal"
    <*> o .:? "display_name"

instance ToJSON CommitRequest where
  toJSON r = object
    [ "participant_id" .= cmrqParticipantId r
    , "signature"      .= cmrqSignature r
    , "entropy_seal"   .= cmrqEntropySeal r
    , "display_name"   .= cmrqDisplayName r
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

data CommittedParticipantResponse = CommittedParticipantResponse
  { cprParticipantId :: UUID
  , cprDisplayName   :: Maybe Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON CommittedParticipantResponse where
  toJSON r = object
    [ "participant_id" .= cprParticipantId r
    , "display_name"   .= cprDisplayName r
    ]

instance FromJSON CommittedParticipantResponse where
  parseJSON = withObject "CommittedParticipantResponse" $ \o -> CommittedParticipantResponse
    <$> o .: "participant_id"
    <*> o .:? "display_name"

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
  , crspCommittedParticipants   :: [CommittedParticipantResponse]
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
    , "committed_participants"   .= crspCommittedParticipants r
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
    <*> o .: "committed_participants"

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

-- === OpenAPI helpers ===

-- | Build a properties map from a list of (name, schema) pairs
props :: [(Text, OA.Schema)] -> IOHM.InsOrdHashMap Text (OA.Referenced OA.Schema)
props = IOHM.fromList . map (fmap OA.Inline)

-- === OpenAPI ToSchema instances ===

instance ToSchema CreateCeremonyRequest where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "CreateCeremonyRequest") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.description ?~ "Request to create a new randomness ceremony"
    & OA.properties .~ props
      [ ("question", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("ceremony_type", mempty & OA.description ?~ "CoinFlip | UniformChoice | Shuffle | IntRange | WeightedChoice")
      , ("entropy_method", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "ParticipantReveal | ExternalBeacon | OfficiantVRF | Combined")
      , ("required_parties", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("commitment_mode", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Immediate | DeadlineWait")
      , ("commit_deadline", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      , ("reveal_deadline", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      , ("non_participation_policy", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "DefaultSubstitution | Exclusion | Cancellation")
      , ("beacon_spec", mempty & OA.description ?~ "Beacon source configuration (required for ExternalBeacon/Combined)")
      ]
    & OA.required .~ ["question", "ceremony_type", "entropy_method", "required_parties", "commitment_mode", "commit_deadline"]

instance ToSchema CommitRequest where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "CommitRequest") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("participant_id", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "uuid")
      , ("signature", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("entropy_seal", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "SHA-256 seal of entropy (required for ParticipantReveal/Combined)")
      , ("display_name", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Optional display name for the participant")
      ]
    & OA.required .~ ["participant_id", "signature"]

instance ToSchema RevealRequest where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "RevealRequest") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("participant_id", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "uuid")
      , ("entropy_value", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Hex-encoded entropy value matching the seal")
      ]
    & OA.required .~ ["participant_id", "entropy_value"]

instance ToSchema CeremonyResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "CeremonyResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("id", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "uuid")
      , ("question", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("ceremony_type", mempty)
      , ("entropy_method", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("required_parties", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("commitment_mode", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("commit_deadline", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      , ("reveal_deadline", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      , ("non_participation_policy", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("beacon_spec", mempty)
      , ("phase", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Pending | AwaitingReveals | AwaitingBeacon | Resolving | Finalized | Expired | Cancelled | Disputed")
      , ("created_by", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "uuid")
      , ("created_at", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      , ("commitment_count", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("committed_participants", mempty & OA.type_ ?~ OA.OpenApiArray & OA.description ?~ "List of committed participants with optional display names")
      ]

instance ToSchema CommitResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "CommitResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("status", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("phase", mempty & OA.type_ ?~ OA.OpenApiString)
      ]

instance ToSchema RevealResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "RevealResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("status", mempty & OA.type_ ?~ OA.OpenApiString)
      ]

instance ToSchema OutcomeResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "OutcomeResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("outcome", mempty & OA.description ?~ "The computed random result")
      , ("combined_entropy", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Hex-encoded combined entropy")
      , ("resolved_at", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      ]

instance ToSchema AuditLogResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "AuditLogResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("entries", mempty & OA.type_ ?~ OA.OpenApiArray & OA.description ?~ "Array of audit log entries")
      ]

instance ToSchema AuditLogEntryResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "AuditLogEntryResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("sequence_num", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("event_type", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("event_data", mempty & OA.description ?~ "Event-specific data")
      , ("prev_hash", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Hash of previous log entry")
      , ("entry_hash", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Hash of this log entry")
      , ("created_at", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "date-time")
      ]

instance ToSchema VerifyResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "VerifyResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("valid", mempty & OA.type_ ?~ OA.OpenApiBoolean)
      , ("errors", mempty & OA.type_ ?~ OA.OpenApiArray & OA.description ?~ "List of verification errors, if any")
      ]

instance ToSchema HealthResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "HealthResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("status", mempty & OA.type_ ?~ OA.OpenApiString)
      , ("version", mempty & OA.type_ ?~ OA.OpenApiString)
      ]

instance ToSchema RandomCoinResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "RandomCoinResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("result", mempty & OA.type_ ?~ OA.OpenApiBoolean)
      ]

instance ToSchema RandomIntResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "RandomIntResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("result", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("min", mempty & OA.type_ ?~ OA.OpenApiInteger)
      , ("max", mempty & OA.type_ ?~ OA.OpenApiInteger)
      ]

instance ToSchema RandomUUIDResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "RandomUUIDResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("result", mempty & OA.type_ ?~ OA.OpenApiString & OA.format ?~ "uuid")
      ]

instance ToSchema ServerPubKeyResponse where
  declareNamedSchema _ = pure $ OA.NamedSchema (Just "ServerPubKeyResponse") $ mempty
    & OA.type_ ?~ OA.OpenApiObject
    & OA.properties .~ props
      [ ("public_key", mempty & OA.type_ ?~ OA.OpenApiString & OA.description ?~ "Hex-encoded Ed25519 public key")
      ]
