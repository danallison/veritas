-- | Domain types for the common-pool computing protocol.
module Veritas.Pool.Types
  ( -- * Identifiers
    PoolId(..)
  , AgentId(..)
  , PrincipalId(..)
  , RoundId(..)
  , Fingerprint(..)

    -- * Pool
  , Pool(..)
  , PoolConfig(..)
  , PoolMember(..)

    -- * Computation
  , ComputationSpec(..)
  , CacheEntry(..)
  , ResultProvenance(..)
  , ProvenanceOutcome(..)

    -- * Validation Round
  , ValidationRound(..)
  , ValidationPhase(..)
  , SealRecord(..)
  , SealPhase(..)
  , ParticipantRole(..)
  , ExecutionEvidence(..)

    -- * Comparison
  , ComparisonMethod(..)
  , ComparisonOutcome(..)
  , FieldComparisonConfig(..)
  , FieldTolerance(..)

    -- * Phase helpers
  , showValidationPhase
  , parseValidationPhase

    -- * Errors
  , PoolTransitionError(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withObject, (.:), (.:?), object, (.=))
import Data.Aeson.Types (Parser)
import Data.ByteArray.Encoding (Base(..), convertFromBase)
import Data.ByteString (ByteString)
import qualified Data.Text.Encoding as TE
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import GHC.Natural (Natural)
import Veritas.Crypto.Hash (hexEncode)

-- | Unique identifier for a pool
newtype PoolId = PoolId { unPoolId :: UUID }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Unique identifier for an agent in a pool
newtype AgentId = AgentId { unAgentId :: UUID }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Identifier for the principal (organization) an agent belongs to
newtype PrincipalId = PrincipalId { unPrincipalId :: Text }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Unique identifier for a validation round
newtype RoundId = RoundId { unRoundId :: UUID }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Content-addressed computation fingerprint (SHA-256)
newtype Fingerprint = Fingerprint { unFingerprint :: ByteString }
  deriving newtype (Eq, Ord, Show)

instance ToJSON Fingerprint where
  toJSON = toJSON . hexEncode . unFingerprint

instance FromJSON Fingerprint where
  parseJSON v = Fingerprint <$> (parseJSON v >>= parseHexField "fingerprint")

-- | A computation pool
data Pool = Pool
  { poolId        :: PoolId
  , poolName      :: Text
  , poolConfig    :: PoolConfig
  , poolCreatedAt :: UTCTime
  } deriving stock (Eq, Show, Generic)

-- | Pool configuration
data PoolConfig = PoolConfig
  { pcComparisonMethod       :: ComparisonMethod
  , pcComputeDeadlineSeconds :: Int
  , pcMinPrincipals          :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON PoolConfig where
  toJSON c = object
    [ "comparison_method"        .= pcComparisonMethod c
    , "compute_deadline_seconds" .= pcComputeDeadlineSeconds c
    , "min_principals"           .= pcMinPrincipals c
    ]

instance FromJSON PoolConfig where
  parseJSON = withObject "PoolConfig" $ \o -> PoolConfig
    <$> o .: "comparison_method"
    <*> o .: "compute_deadline_seconds"
    <*> o .: "min_principals"

-- | A member of a pool
data PoolMember = PoolMember
  { pmAgentId     :: AgentId
  , pmPublicKey   :: ByteString
  , pmPrincipalId :: PrincipalId
  , pmJoinedAt    :: UTCTime
  } deriving stock (Eq, Show, Generic)

-- | Specification of a computation to be cross-validated
data ComputationSpec = ComputationSpec
  { csProvider         :: Text
  , csModel            :: Text
  , csTemperature      :: Double
  , csSeed             :: Maybe Int
  , csMaxTokens        :: Maybe Int
  , csSystemPrompt     :: Text
  , csUserPrompt       :: Text
  , csStructuredOutput :: Maybe Value
  , csInputRefs        :: [Text]
  } deriving stock (Eq, Show, Generic)

instance ToJSON ComputationSpec where
  toJSON c = object
    [ "provider"          .= csProvider c
    , "model"             .= csModel c
    , "temperature"       .= csTemperature c
    , "seed"              .= csSeed c
    , "max_tokens"        .= csMaxTokens c
    , "system_prompt"     .= csSystemPrompt c
    , "user_prompt"       .= csUserPrompt c
    , "structured_output" .= csStructuredOutput c
    , "input_refs"        .= csInputRefs c
    ]

instance FromJSON ComputationSpec where
  parseJSON = withObject "ComputationSpec" $ \o -> ComputationSpec
    <$> o .: "provider"
    <*> o .: "model"
    <*> o .: "temperature"
    <*> o .:? "seed"
    <*> o .:? "max_tokens"
    <*> o .: "system_prompt"
    <*> o .: "user_prompt"
    <*> o .:? "structured_output"
    <*> (maybe [] id <$> o .:? "input_refs")

-- | A cached computation result
data CacheEntry = CacheEntry
  { ceFingerprint     :: Fingerprint
  , ceResult          :: ByteString
  , ceProvenance      :: ResultProvenance
  , ceComputationSpec :: ComputationSpec
  , ceCreatedAt       :: UTCTime
  , ceExpiresAt       :: Maybe UTCTime
  } deriving stock (Eq, Show, Generic)

-- | How the cached result was validated
data ProvenanceOutcome
  = Unanimous
  | Majority AgentId
  deriving stock (Eq, Show, Generic)

instance ToJSON ProvenanceOutcome where
  toJSON Unanimous      = object ["tag" .= ("Unanimous" :: Text)]
  toJSON (Majority aid) = object ["tag" .= ("Majority" :: Text), "dissenter" .= aid]

instance FromJSON ProvenanceOutcome where
  parseJSON = withObject "ProvenanceOutcome" $ \o -> do
    tag <- o .: "tag" :: Parser Text
    case tag of
      "Unanimous" -> pure Unanimous
      "Majority"  -> Majority <$> o .: "dissenter"
      _           -> fail ("Unknown ProvenanceOutcome tag: " <> T.unpack tag)

-- | Provenance record for a cached result
data ResultProvenance = ResultProvenance
  { rpOutcome        :: ProvenanceOutcome
  , rpAgreementCount :: Int
  , rpBeaconRound    :: Maybe Natural
  , rpSelectionProof :: Maybe ByteString
  , rpValidatedAt    :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON ResultProvenance where
  toJSON p = object
    [ "outcome"         .= rpOutcome p
    , "agreement_count" .= rpAgreementCount p
    , "beacon_round"    .= rpBeaconRound p
    , "selection_proof"  .= fmap hexEncode (rpSelectionProof p)
    , "validated_at"    .= rpValidatedAt p
    ]

instance FromJSON ResultProvenance where
  parseJSON = withObject "ResultProvenance" $ \o -> ResultProvenance
    <$> o .: "outcome"
    <*> o .: "agreement_count"
    <*> o .:? "beacon_round"
    <*> (o .:? "selection_proof" >>= mapM (parseHexField "selection_proof"))
    <*> o .: "validated_at"

-- | A validation round tracking cross-validation of a computation
data ValidationRound = ValidationRound
  { vrId               :: RoundId
  , vrPoolId           :: PoolId
  , vrFingerprint      :: Fingerprint
  , vrComputationSpec  :: ComputationSpec
  , vrComparisonMethod :: ComparisonMethod
  , vrPhase            :: ValidationPhase
  , vrRequester        :: AgentId
  , vrValidators       :: [AgentId]
  , vrSeals            :: [(AgentId, SealRecord)]
  , vrBeaconRound      :: Maybe Natural
  , vrSelectionProof   :: Maybe ByteString
  , vrCreatedAt        :: UTCTime
  , vrDeadline         :: Maybe UTCTime
  } deriving stock (Eq, Show, Generic)

-- | Phases of a validation round
data ValidationPhase
  = Requested       -- ^ Initial: requester has submitted seal
  | Selecting       -- ^ Waiting for drand beacon to select validators
  | Computing       -- ^ Validators assigned, computing results
  | Sealing         -- ^ Validators submitting sealed results
  | Revealing       -- ^ All sealed, revealing results
  | Validated       -- ^ Successfully compared, result cached
  | Failed          -- ^ Comparison failed (inconclusive)
  | Cancelled       -- ^ Round was cancelled
  deriving stock (Eq, Show, Generic)

instance ToJSON ValidationPhase where
  toJSON = toJSON . showValidationPhase

instance FromJSON ValidationPhase where
  parseJSON v = parseJSON v >>= \t -> case parseValidationPhase t of
    Just p  -> pure p
    Nothing -> fail ("Unknown ValidationPhase: " <> T.unpack t)

showValidationPhase :: ValidationPhase -> Text
showValidationPhase = \case
  Requested -> "requested"
  Selecting -> "selecting"
  Computing -> "computing"
  Sealing   -> "sealing"
  Revealing -> "revealing"
  Validated -> "validated"
  Failed    -> "failed"
  Cancelled -> "cancelled"

parseValidationPhase :: Text -> Maybe ValidationPhase
parseValidationPhase = \case
  "requested" -> Just Requested
  "selecting" -> Just Selecting
  "computing" -> Just Computing
  "sealing"   -> Just Sealing
  "revealing" -> Just Revealing
  "validated" -> Just Validated
  "failed"    -> Just Failed
  "cancelled" -> Just Cancelled
  _           -> Nothing

-- | A sealed result from a participant
data SealRecord = SealRecord
  { srSealHash         :: ByteString
  , srSealSig          :: ByteString
  , srRevealedResult   :: Maybe ByteString
  , srRevealedEvidence :: Maybe ExecutionEvidence
  , srRevealedNonce    :: Maybe ByteString
  , srPhase            :: SealPhase
  } deriving stock (Eq, Show, Generic)

-- | Phase of a seal
data SealPhase
  = Sealed
  | Revealed
  | Verified
  deriving stock (Eq, Show, Generic)

instance ToJSON SealPhase where
  toJSON Sealed   = "Sealed"
  toJSON Revealed = "Revealed"
  toJSON Verified = "Verified"

instance FromJSON SealPhase where
  parseJSON v = parseJSON v >>= \(t :: Text) -> case t of
    "Sealed"   -> pure Sealed
    "Revealed" -> pure Revealed
    "Verified" -> pure Verified
    _          -> fail ("Unknown SealPhase: " <> T.unpack t)

-- | Role of a participant in a validation round
data ParticipantRole
  = Requester
  | Validator
  deriving stock (Eq, Show, Generic)

instance ToJSON ParticipantRole where
  toJSON Requester = "requester"
  toJSON Validator = "validator"

instance FromJSON ParticipantRole where
  parseJSON v = parseJSON v >>= \(t :: Text) -> case t of
    "requester" -> pure Requester
    "validator" -> pure Validator
    _           -> fail ("Unknown ParticipantRole: " <> T.unpack t)

-- | Evidence of computation execution
data ExecutionEvidence = ExecutionEvidence
  { eeProviderRequestId :: Maybe Text
  , eeModelEcho         :: Maybe Text
  , eeTokenCounts       :: Maybe Value
  , eeTimestamps        :: Maybe Value
  , eeRequestBodyHash   :: Maybe ByteString
  } deriving stock (Eq, Show, Generic)

instance ToJSON ExecutionEvidence where
  toJSON e = object
    [ "provider_request_id" .= eeProviderRequestId e
    , "model_echo"          .= eeModelEcho e
    , "token_counts"        .= eeTokenCounts e
    , "timestamps"          .= eeTimestamps e
    , "request_body_hash"   .= fmap hexEncode (eeRequestBodyHash e)
    ]

instance FromJSON ExecutionEvidence where
  parseJSON = withObject "ExecutionEvidence" $ \o -> ExecutionEvidence
    <$> o .:? "provider_request_id"
    <*> o .:? "model_echo"
    <*> o .:? "token_counts"
    <*> o .:? "timestamps"
    <*> (o .:? "request_body_hash" >>= mapM (parseHexField "request_body_hash"))

-- | Method for comparing computation results
data ComparisonMethod
  = Exact
  | Canonical
  | FieldLevel FieldComparisonConfig
  deriving stock (Eq, Show, Generic)

instance ToJSON ComparisonMethod where
  toJSON Exact           = object ["method" .= ("exact" :: Text)]
  toJSON Canonical       = object ["method" .= ("canonical" :: Text)]
  toJSON (FieldLevel fc) = object ["method" .= ("field_level" :: Text), "config" .= fc]

instance FromJSON ComparisonMethod where
  parseJSON = withObject "ComparisonMethod" $ \o -> do
    method <- o .: "method" :: Parser Text
    case method of
      "exact"       -> pure Exact
      "canonical"   -> pure Canonical
      "field_level" -> FieldLevel <$> o .: "config"
      _             -> fail ("Unknown ComparisonMethod: " <> T.unpack method)

-- | Configuration for field-level comparison
data FieldComparisonConfig = FieldComparisonConfig
  { flcFields :: [(Text, FieldTolerance)]
  } deriving stock (Eq, Show, Generic)

instance ToJSON FieldComparisonConfig where
  toJSON c = object ["fields" .= map (\(k, v) -> object ["name" .= k, "tolerance" .= v]) (flcFields c)]

instance FromJSON FieldComparisonConfig where
  parseJSON = withObject "FieldComparisonConfig" $ \o -> do
    fields <- o .: "fields"
    FieldComparisonConfig <$> mapM parseFieldEntry fields
    where
      parseFieldEntry = withObject "FieldEntry" $ \o ->
        (,) <$> o .: "name" <*> o .: "tolerance"

-- | Tolerance for a field-level comparison
data FieldTolerance
  = ExactMatch
  | NumericTolerance Double
  deriving stock (Eq, Show, Generic)

instance ToJSON FieldTolerance where
  toJSON ExactMatch           = object ["type" .= ("exact" :: Text)]
  toJSON (NumericTolerance d) = object ["type" .= ("numeric" :: Text), "tolerance" .= d]

instance FromJSON FieldTolerance where
  parseJSON = withObject "FieldTolerance" $ \o -> do
    t <- o .: "type" :: Parser Text
    case t of
      "exact"   -> pure ExactMatch
      "numeric" -> NumericTolerance <$> o .: "tolerance"
      _         -> fail ("Unknown FieldTolerance type: " <> T.unpack t)

-- | Outcome of comparing results from multiple agents
data ComparisonOutcome
  = CompUnanimous
  | CompMajority AgentId   -- ^ dissenter
  | CompInconclusive
  deriving stock (Eq, Show, Generic)

-- | Errors from validation round transitions
data PoolTransitionError
  = InvalidRoundPhase ValidationPhase ValidationPhase
  | AgentNotInRound AgentId
  | AgentNotValidator AgentId
  | SealAlreadySubmitted AgentId
  | SealSignatureInvalid AgentId
  | RevealSealMismatch AgentId
  | NotAllSealed
  | NotAllRevealed
  | RoundAlreadyTerminal
  | InsufficientPrincipals Int Int  -- ^ required, available
  deriving stock (Eq, Show, Generic)

-- === Helpers ===

-- | Parse a hex-encoded JSON string field as ByteString
parseHexField :: String -> Text -> Parser ByteString
parseHexField fieldName t = case convertFromBase Base16 (TE.encodeUtf8 t) of
  Right bs -> pure bs
  Left _   -> fail ("invalid hex in field " <> fieldName)
