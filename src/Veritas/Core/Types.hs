module Veritas.Core.Types
  ( -- * Identifiers
    CeremonyId(..)
  , ParticipantId(..)
  , LogSequence(..)

    -- * Ceremony Configuration
  , CommitmentMode(..)
  , EntropyMethod(..)
  , NonParticipationPolicy(..)
  , IdentityMode(..)
  , CeremonyType(..)
  , BeaconSpec(..)
  , BeaconFallback(..)

    -- * Phase
  , Phase(..)

    -- * Ceremony
  , Ceremony(..)

    -- * Commitment
  , Commitment(..)

    -- * Participant Registration
  , ParticipantRegistration(..)
  , Roster

    -- * Entropy
  , EntropyContribution(..)
  , EntropySource(..)
  , BeaconAnchor(..)
  , VRFOutput(..)

    -- * Outcome
  , Outcome(..)
  , CeremonyResult(..)
  , OutcomeProof(..)

    -- * Audit Log
  , CeremonyEvent(..)
  , NonParticipationEntry(..)
  , LogEntry(..)

    -- * Errors
  , TransitionError(..)
  ) where

import Data.Aeson
  ( FromJSON(..), ToJSON(..), Value(..)
  , withObject, (.:), (.=), object
  )
import Data.Aeson.Types (Pair, Parser)
import Data.ByteString (ByteString)
import Data.ByteArray.Encoding (Base(..), convertFromBase)
import qualified Data.Text.Encoding as TE
import qualified Data.OpenApi
import Data.OpenApi (ToSchema(..))
import Data.Text (Text)
import qualified Data.Text as T
import Veritas.Crypto.Hash (hexEncode)
import Data.Time (UTCTime, NominalDiffTime)
import Data.UUID (UUID)
import Data.List.NonEmpty (NonEmpty)
import GHC.Generics (Generic)
import GHC.Natural (Natural)

-- | Unique identifier for a ceremony
newtype CeremonyId = CeremonyId { unCeremonyId :: UUID }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Unique identifier for a participant
newtype ParticipantId = ParticipantId { unParticipantId :: UUID }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON)

-- | Sequence number within a ceremony's audit log
newtype LogSequence = LogSequence { unLogSequence :: Natural }
  deriving newtype (Eq, Ord, Show, Num, FromJSON, ToJSON)

-- | When to transition from Pending after quorum is reached
data CommitmentMode
  = Immediate     -- ^ Proceed as soon as quorum is reached
  | DeadlineWait  -- ^ Wait for commit deadline even if quorum is met early
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON, ToSchema)

-- | How entropy is sourced for a ceremony
data EntropyMethod
  = ParticipantReveal  -- ^ Method A: commit-reveal from participants
  | ExternalBeacon     -- ^ Method B: external randomness beacon (drand)
  | OfficiantVRF       -- ^ Method C: server-generated VRF
  | Combined           -- ^ Method D: participant reveal + beacon
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON, ToSchema)

-- | Policy for participants who commit but don't reveal (Methods A, D)
data NonParticipationPolicy
  = DefaultSubstitution  -- ^ Use deterministic default value
  | Exclusion            -- ^ Exclude from entropy combination
  | Cancellation         -- ^ Cancel the entire ceremony
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON, ToSchema)

-- | The kind of random outcome to produce
data CeremonyType
  = CoinFlip Text Text          -- ^ sideA, sideB labels
  | UniformChoice (NonEmpty Text)
  | Shuffle (NonEmpty Text)
  | IntRange Int Int
  | WeightedChoice (NonEmpty (Text, Rational))
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Specification for an external randomness beacon source
data BeaconSpec = BeaconSpec
  { beaconNetwork  :: Text
  , beaconRound    :: Maybe Natural
  , beaconFallback :: BeaconFallback
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | What to do if the beacon source fails
data BeaconFallback
  = ExtendDeadline NominalDiffTime
  | AlternateSource BeaconSpec
  | CancelCeremony
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Whether participants are anonymous or self-certified via Ed25519 keys
data IdentityMode
  = Anonymous       -- ^ Ephemeral participant IDs, no authentication
  | SelfCertified   -- ^ Participants register Ed25519 public keys and sign commitments
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToSchema)

instance ToJSON IdentityMode where
  toJSON Anonymous     = "Anonymous"
  toJSON SelfCertified = "SelfCertified"

instance FromJSON IdentityMode where
  parseJSON = \case
    String "Anonymous"     -> pure Anonymous
    String "SelfCertified" -> pure SelfCertified
    _                      -> fail "Expected \"Anonymous\" or \"SelfCertified\""

-- | Ceremony lifecycle phase
data Phase
  = Gathering          -- ^ Self-certified: accepting participant registrations
  | AwaitingRosterAcks -- ^ Self-certified: waiting for roster acknowledgments
  | Pending            -- ^ Accepting commitments
  | AwaitingReveals    -- ^ Collecting entropy reveals (Methods A, D)
  | AwaitingBeacon     -- ^ Waiting for external beacon value (Methods B, D)
  | Resolving          -- ^ Computing outcome
  | Finalized          -- ^ Outcome sealed
  | Expired            -- ^ Commitment deadline passed without quorum
  | Cancelled          -- ^ Aborted
  | Disputed           -- ^ Verification failed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON, ToSchema)

-- | A ceremony instance
data Ceremony = Ceremony
  { ceremonyId             :: CeremonyId
  , question               :: Text
  , ceremonyType           :: CeremonyType
  , entropyMethod          :: EntropyMethod
  , requiredParties        :: Natural
  , commitmentMode         :: CommitmentMode
  , commitDeadline         :: UTCTime
  , revealDeadline         :: Maybe UTCTime
  , nonParticipationPolicy :: Maybe NonParticipationPolicy
  , beaconSpec             :: Maybe BeaconSpec
  , identityMode           :: IdentityMode
  , phase                  :: Phase
  , createdBy              :: ParticipantId
  , createdAt              :: UTCTime
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | A participant's commitment to a ceremony
data Commitment = Commitment
  { commitCeremony  :: CeremonyId
  , commitParty     :: ParticipantId
  , entropySealHash :: Maybe ByteString
  , committedAt     :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON Commitment where
  toJSON c = object
    [ "commitCeremony"  .= commitCeremony c
    , "commitParty"     .= commitParty c
    , "entropySealHash" .= fmap hexEncode (entropySealHash c)
    , "committedAt"     .= committedAt c
    ]

instance FromJSON Commitment where
  parseJSON = withObject "Commitment" $ \o -> Commitment
    <$> o .: "commitCeremony"
    <*> o .: "commitParty"
    <*> (o .: "entropySealHash" >>= mapM (parseHexField "entropySealHash"))
    <*> o .: "committedAt"

-- | A participant registration in a self-certified ceremony
data ParticipantRegistration = ParticipantRegistration
  { prCeremony    :: CeremonyId
  , prParticipant :: ParticipantId
  , prPublicKey   :: ByteString      -- Ed25519 32 bytes
  , prDisplayName :: Maybe Text
  , prJoinedAt    :: UTCTime
  } deriving stock (Eq, Show, Generic)

-- | A roster is a sorted list of (participant_id, public_key) pairs
type Roster = [(ParticipantId, ByteString)]

-- | A contribution of entropy to a ceremony
data EntropyContribution = EntropyContribution
  { ecCeremony :: CeremonyId
  , ecSource   :: EntropySource
  , ecValue    :: ByteString
  } deriving stock (Eq, Show, Generic)

instance ToJSON EntropyContribution where
  toJSON ec = object
    [ "ecCeremony" .= ecCeremony ec
    , "ecSource"   .= ecSource ec
    , "ecValue"    .= hexEncode (ecValue ec)
    ]

instance FromJSON EntropyContribution where
  parseJSON = withObject "EntropyContribution" $ \o -> EntropyContribution
    <$> o .: "ecCeremony"
    <*> o .: "ecSource"
    <*> (o .: "ecValue" >>= parseHexField "ecValue")

-- | Where entropy came from
data EntropySource
  = ParticipantEntropy ParticipantId
  | DefaultEntropy ParticipantId
  | BeaconEntropy BeaconAnchor
  | VRFEntropy VRFOutput
  deriving stock (Eq, Show, Generic)

instance ToJSON EntropySource where
  toJSON = \case
    ParticipantEntropy pid -> object ["tag" .= ("ParticipantEntropy" :: Text), "participant" .= pid]
    DefaultEntropy pid     -> object ["tag" .= ("DefaultEntropy" :: Text), "participant" .= pid]
    BeaconEntropy anchor   -> object ["tag" .= ("BeaconEntropy" :: Text), "anchor" .= anchor]
    VRFEntropy vrf         -> object ["tag" .= ("VRFEntropy" :: Text), "vrf" .= vrf]

instance FromJSON EntropySource where
  parseJSON = withObject "EntropySource" $ \o -> do
    tag <- o .: "tag" :: Parser Text
    case tag of
      "ParticipantEntropy" -> ParticipantEntropy <$> o .: "participant"
      "DefaultEntropy"     -> DefaultEntropy <$> o .: "participant"
      "BeaconEntropy"      -> BeaconEntropy <$> o .: "anchor"
      "VRFEntropy"         -> VRFEntropy <$> o .: "vrf"
      _                    -> fail ("Unknown EntropySource tag: " <> T.unpack tag)

-- | Anchored external beacon value
data BeaconAnchor = BeaconAnchor
  { baNetwork   :: Text
  , baRound     :: Natural
  , baValue     :: ByteString
  , baSignature :: ByteString
  , baFetchedAt :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON BeaconAnchor where
  toJSON ba = object
    [ "baNetwork"   .= baNetwork ba
    , "baRound"     .= baRound ba
    , "baValue"     .= hexEncode (baValue ba)
    , "baSignature" .= hexEncode (baSignature ba)
    , "baFetchedAt" .= baFetchedAt ba
    ]

instance FromJSON BeaconAnchor where
  parseJSON = withObject "BeaconAnchor" $ \o -> BeaconAnchor
    <$> o .: "baNetwork"
    <*> o .: "baRound"
    <*> (o .: "baValue" >>= parseHexField "baValue")
    <*> (o .: "baSignature" >>= parseHexField "baSignature")
    <*> o .: "baFetchedAt"

-- | VRF output with proof
data VRFOutput = VRFOutput
  { vrfValue     :: ByteString
  , vrfProof     :: ByteString
  , vrfPublicKey :: ByteString
  } deriving stock (Eq, Show, Generic)

instance ToJSON VRFOutput where
  toJSON v = object
    [ "vrfValue"     .= hexEncode (vrfValue v)
    , "vrfProof"     .= hexEncode (vrfProof v)
    , "vrfPublicKey" .= hexEncode (vrfPublicKey v)
    ]

instance FromJSON VRFOutput where
  parseJSON = withObject "VRFOutput" $ \o -> VRFOutput
    <$> (o .: "vrfValue" >>= parseHexField "vrfValue")
    <*> (o .: "vrfProof" >>= parseHexField "vrfProof")
    <*> (o .: "vrfPublicKey" >>= parseHexField "vrfPublicKey")

-- | The computed outcome of a ceremony
data Outcome = Outcome
  { outcomeValue     :: CeremonyResult
  , combinedEntropy  :: ByteString
  , outcomeProof     :: OutcomeProof
  } deriving stock (Eq, Show, Generic)

instance ToJSON Outcome where
  toJSON o = object
    [ "outcomeValue"    .= outcomeValue o
    , "combinedEntropy" .= hexEncode (combinedEntropy o)
    , "outcomeProof"    .= outcomeProof o
    ]

instance FromJSON Outcome where
  parseJSON = withObject "Outcome" $ \o -> Outcome
    <$> o .: "outcomeValue"
    <*> (o .: "combinedEntropy" >>= parseHexField "combinedEntropy")
    <*> o .: "outcomeProof"

-- | The actual random result
data CeremonyResult
  = CoinFlipResult Text
  | ChoiceResult Text
  | ShuffleResult [Text]
  | IntRangeResult Int
  | WeightedChoiceResult Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Proof that the outcome was derived correctly
data OutcomeProof = OutcomeProof
  { proofEntropyInputs :: [EntropyContribution]
  , proofDerivation    :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON OutcomeProof where
  toJSON p = object
    [ "proofEntropyInputs" .= proofEntropyInputs p
    , "proofDerivation"    .= proofDerivation p
    ]

instance FromJSON OutcomeProof where
  parseJSON = withObject "OutcomeProof" $ \o -> OutcomeProof
    <$> o .: "proofEntropyInputs"
    <*> o .: "proofDerivation"

-- | Events recorded in the audit log
data CeremonyEvent
  = CeremonyCreated Ceremony
  | ParticipantCommitted Commitment
  | EntropyRevealed ParticipantId ByteString
  | RevealsPublished [EntropyContribution]
  | NonParticipationApplied NonParticipationEntry
  | BeaconAnchored BeaconAnchor
  | VRFGenerated VRFOutput
  | CeremonyResolved Outcome
  | CeremonyFinalized
  | CeremonyExpired
  | CeremonyCancelled Text
  | CeremonyDisputed Text
  | DeadlineExtended NominalDiffTime UTCTime
  | ParticipantJoined ParticipantId ByteString     -- ^ pid, public key
  | RosterFinalized [(ParticipantId, ByteString)]   -- ^ locked roster
  | RosterAcknowledged ParticipantId ByteString     -- ^ pid, signature
  deriving stock (Eq, Show, Generic)

instance ToJSON CeremonyEvent where
  toJSON = \case
    CeremonyCreated c         -> tagged "CeremonyCreated" ["ceremony" .= c]
    ParticipantCommitted c    -> tagged "ParticipantCommitted" ["commitment" .= c]
    EntropyRevealed pid val   -> tagged "EntropyRevealed" ["participant" .= pid, "value" .= hexEncode val]
    RevealsPublished cs       -> tagged "RevealsPublished" ["contributions" .= cs]
    NonParticipationApplied e -> tagged "NonParticipationApplied" ["entry" .= e]
    BeaconAnchored a          -> tagged "BeaconAnchored" ["anchor" .= a]
    VRFGenerated v            -> tagged "VRFGenerated" ["vrf" .= v]
    CeremonyResolved o        -> tagged "CeremonyResolved" ["outcome" .= o]
    CeremonyFinalized         -> tagged "CeremonyFinalized" []
    CeremonyExpired           -> tagged "CeremonyExpired" []
    CeremonyCancelled reason  -> tagged "CeremonyCancelled" ["reason" .= reason]
    CeremonyDisputed reason   -> tagged "CeremonyDisputed" ["reason" .= reason]
    DeadlineExtended dur newDl -> tagged "DeadlineExtended" ["duration" .= dur, "newDeadline" .= newDl]
    ParticipantJoined pid pk   -> tagged "ParticipantJoined" ["participant" .= pid, "publicKey" .= hexEncode pk]
    RosterFinalized roster     -> tagged "RosterFinalized" ["roster" .= map (\(pid, pk) -> object ["participant" .= pid, "publicKey" .= hexEncode pk]) roster]
    RosterAcknowledged pid sig -> tagged "RosterAcknowledged" ["participant" .= pid, "signature" .= hexEncode sig]
    where
      tagged :: Text -> [Pair] -> Value
      tagged tag fields = object (("tag" .= tag) : fields)

instance FromJSON CeremonyEvent where
  parseJSON = withObject "CeremonyEvent" $ \o -> do
    tag <- o .: "tag" :: Parser Text
    case tag of
      "CeremonyCreated"         -> CeremonyCreated <$> o .: "ceremony"
      "ParticipantCommitted"    -> ParticipantCommitted <$> o .: "commitment"
      "EntropyRevealed"         -> EntropyRevealed <$> o .: "participant"
                                                   <*> (o .: "value" >>= parseHexField "value")
      "RevealsPublished"        -> RevealsPublished <$> o .: "contributions"
      "NonParticipationApplied" -> NonParticipationApplied <$> o .: "entry"
      "BeaconAnchored"          -> BeaconAnchored <$> o .: "anchor"
      "VRFGenerated"            -> VRFGenerated <$> o .: "vrf"
      "CeremonyResolved"        -> CeremonyResolved <$> o .: "outcome"
      "CeremonyFinalized"       -> pure CeremonyFinalized
      "CeremonyExpired"         -> pure CeremonyExpired
      "CeremonyCancelled"       -> CeremonyCancelled <$> o .: "reason"
      "CeremonyDisputed"        -> CeremonyDisputed <$> o .: "reason"
      "DeadlineExtended"        -> DeadlineExtended <$> o .: "duration"
                                                    <*> o .: "newDeadline"
      "ParticipantJoined"       -> ParticipantJoined <$> o .: "participant"
                                                     <*> (o .: "publicKey" >>= parseHexField "publicKey")
      "RosterFinalized"         -> do
                                     entries <- o .: "roster"
                                     roster <- mapM (\entry -> withObject "RosterEntry" (\e ->
                                       (,) <$> e .: "participant"
                                           <*> (e .: "publicKey" >>= parseHexField "publicKey")
                                       ) entry) entries
                                     pure (RosterFinalized roster)
      "RosterAcknowledged"      -> RosterAcknowledged <$> o .: "participant"
                                                      <*> (o .: "signature" >>= parseHexField "signature")
      _                         -> fail ("Unknown CeremonyEvent tag: " <> T.unpack tag)

-- | Record of non-participation and how it was handled
data NonParticipationEntry = NonParticipationEntry
  { npeParticipant      :: ParticipantId
  , npePolicyApplied    :: NonParticipationPolicy
  , npeSubstitutedValue :: Maybe ByteString
  } deriving stock (Eq, Show, Generic)

instance ToJSON NonParticipationEntry where
  toJSON e = object
    [ "npeParticipant"      .= npeParticipant e
    , "npePolicyApplied"    .= npePolicyApplied e
    , "npeSubstitutedValue" .= fmap hexEncode (npeSubstitutedValue e)
    ]

instance FromJSON NonParticipationEntry where
  parseJSON = withObject "NonParticipationEntry" $ \o -> NonParticipationEntry
    <$> o .: "npeParticipant"
    <*> o .: "npePolicyApplied"
    <*> (o .: "npeSubstitutedValue" >>= mapM (parseHexField "npeSubstitutedValue"))

-- | An entry in the per-ceremony audit log
data LogEntry = LogEntry
  { logSequence  :: LogSequence
  , logCeremony  :: CeremonyId
  , logEvent     :: CeremonyEvent
  , logTimestamp  :: UTCTime
  , logPrevHash  :: ByteString
  , logEntryHash :: ByteString
  } deriving stock (Eq, Show, Generic)

-- | Errors that can occur during state transitions
data TransitionError
  = InvalidPhase Phase Phase
  | QuorumNotReached Natural Natural
  | DeadlineNotPassed UTCTime UTCTime
  | DeadlinePassed UTCTime UTCTime
  | AlreadyCommitted ParticipantId
  | NotCommitted ParticipantId
  | AlreadyRevealed ParticipantId
  | SealMismatch ParticipantId
  | MethodMismatch EntropyMethod
  | MissingRevealDeadline
  | MissingBeaconSpec
  | InvariantViolation Text
  | AlreadyJoined ParticipantId
  | NotJoined ParticipantId
  | AlreadyAcknowledged ParticipantId
  | InvalidSignature ParticipantId Text
  | IdentityRequired
  deriving stock (Eq, Show, Generic)

-- === OpenAPI schema instances for complex types ===

instance ToSchema CeremonyType where
  declareNamedSchema _ = pure $ Data.OpenApi.NamedSchema (Just "CeremonyType") mempty

instance ToSchema BeaconSpec where
  declareNamedSchema _ = pure $ Data.OpenApi.NamedSchema (Just "BeaconSpec") mempty

instance ToSchema BeaconFallback where
  declareNamedSchema _ = pure $ Data.OpenApi.NamedSchema (Just "BeaconFallback") mempty

-- | Helper: decode hex-encoded text to ByteString, failing on invalid hex
textToBS :: Text -> Either String ByteString
textToBS t = convertFromBase Base16 (TE.encodeUtf8 t)

-- | Parse a hex-encoded JSON string field as ByteString (for use in FromJSON instances)
parseHexField :: String -> Text -> Parser ByteString
parseHexField fieldName t = case textToBS t of
  Right bs -> pure bs
  Left _   -> fail ("invalid hex in field " <> fieldName)
