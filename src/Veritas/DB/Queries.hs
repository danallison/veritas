-- | All database queries for the Veritas service.
module Veritas.DB.Queries
  ( -- * Ceremonies
    insertCeremony
  , getCeremony
  , listCeremonies
  , updateCeremonyPhase

    -- * Commitments
  , insertCommitment
  , getCommitments
  , getCommitmentCount
  , getCommittedParticipants
  , getCommitmentCountsBatch
  , getCommittedParticipantsBatch
  , CommittedParticipant(..)

    -- * Entropy Reveals
  , insertEntropyReveal
  , getEntropyReveals
  , getRevealedParticipants
  , markRevealsPublished

    -- * Beacon Anchors
  , insertBeaconAnchor
  , getBeaconAnchor

    -- * Outcomes
  , insertOutcome
  , getOutcome

    -- * Audit Log
  , insertAuditLogEntry
  , getAuditLog
  , getLastAuditLogEntry
  , appendAuditLog
  , eventTypeName

    -- * Ceremony Updates
  , updateRevealDeadline

    -- * Worker Queries
  , getPendingExpiredCeremonies
  , getResolvingCeremonies
  , getAwaitingBeaconCeremonies
  , getUnrevealedParticipants
  , getAwaitingRevealsCeremonies

    -- * Reveal Helpers
  , revealsToContributions

    -- * Domain Conversions
  , ceremonyRowToDomain
  , commitmentRowToDomain
  , parsePhase
  , parseEntropyMethod
  , parseCommitmentMode
  , parseNonParticipationPolicy
  , showPhase
  , showEntropyMethod
  , showCommitmentMode
  , showNonParticipationPolicy

    -- * Row types
  , CeremonyRow(..)
  , CommitmentRow(..)
  , BeaconAnchorRow(..)
  , OutcomeRow(..)
  , AuditLogRow(..)
  ) where

import Data.Aeson (Value, toJSON)
import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromRow

import Veritas.Core.Types
import Veritas.Core.AuditLog (createLogEntry)
import Veritas.Crypto.Hash (genesisHash)

-- === Ceremonies ===

insertCeremony :: Connection -> Ceremony -> IO ()
insertCeremony conn Ceremony{..} = do
  _ <- execute conn
    "INSERT INTO ceremonies (id, question, ceremony_type, entropy_method, \
    \required_parties, commitment_mode, commit_deadline, reveal_deadline, \
    \non_participation_policy, beacon_spec, phase, created_by, created_at) \
    \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ( ( unCeremonyId ceremonyId
      , question
      , toJSON ceremonyType
      , showEntropyMethod entropyMethod
      , (fromIntegral requiredParties :: Int)
      , showCommitmentMode commitmentMode
      , commitDeadline
      ) :. ( revealDeadline
           , fmap showNonParticipationPolicy nonParticipationPolicy
           , fmap toJSON beaconSpec
           , showPhase phase
           , unParticipantId createdBy
           , createdAt
           )
    )
  pure ()

getCeremony :: Connection -> CeremonyId -> IO (Maybe CeremonyRow)
getCeremony conn (CeremonyId cid) =
  safeHead <$> query conn
    "SELECT id, question, ceremony_type, entropy_method, required_parties, \
    \commitment_mode, commit_deadline, reveal_deadline, non_participation_policy, \
    \beacon_spec, phase, created_by, created_at \
    \FROM ceremonies WHERE id = ?"
    (Only cid)

listCeremonies :: Connection -> Maybe Text -> IO [CeremonyRow]
listCeremonies conn Nothing =
  query_ conn
    "SELECT id, question, ceremony_type, entropy_method, required_parties, \
    \commitment_mode, commit_deadline, reveal_deadline, non_participation_policy, \
    \beacon_spec, phase, created_by, created_at \
    \FROM ceremonies ORDER BY created_at DESC"
listCeremonies conn (Just phaseFilter) =
  query conn
    "SELECT id, question, ceremony_type, entropy_method, required_parties, \
    \commitment_mode, commit_deadline, reveal_deadline, non_participation_policy, \
    \beacon_spec, phase, created_by, created_at \
    \FROM ceremonies WHERE phase = ? ORDER BY created_at DESC"
    (Only phaseFilter)

updateCeremonyPhase :: Connection -> CeremonyId -> Phase -> IO ()
updateCeremonyPhase conn (CeremonyId cid) newPhase = do
  _ <- execute conn
    "UPDATE ceremonies SET phase = ? WHERE id = ?"
    (showPhase newPhase, cid)
  pure ()

updateRevealDeadline :: Connection -> CeremonyId -> UTCTime -> IO ()
updateRevealDeadline conn (CeremonyId cid) newDeadline = do
  _ <- execute conn
    "UPDATE ceremonies SET reveal_deadline = ? WHERE id = ?"
    (newDeadline, cid)
  pure ()

-- === Commitments ===

insertCommitment :: Connection -> Commitment -> Maybe Text -> IO ()
insertCommitment conn Commitment{..} mDisplayName = do
  _ <- execute conn
    "INSERT INTO commitments (ceremony_id, participant_id, entropy_seal, committed_at, display_name) \
    \VALUES (?, ?, ?, ?, ?)"
    ( unCeremonyId commitCeremony
    , unParticipantId commitParty
    , fmap Binary entropySealHash
    , committedAt
    , mDisplayName
    )
  pure ()

getCommitments :: Connection -> CeremonyId -> IO [CommitmentRow]
getCommitments conn (CeremonyId cid) =
  query conn
    "SELECT ceremony_id, participant_id, entropy_seal, committed_at, display_name \
    \FROM commitments WHERE ceremony_id = ? ORDER BY committed_at"
    (Only cid)

getCommitmentCount :: Connection -> CeremonyId -> IO Int
getCommitmentCount conn (CeremonyId cid) = do
  [Only n] <- query conn
    "SELECT COUNT(*) FROM commitments WHERE ceremony_id = ?"
    (Only cid)
  pure n

data CommittedParticipant = CommittedParticipant
  { cpParticipantId :: UUID
  , cpDisplayName   :: Maybe Text
  } deriving stock (Show)

instance FromRow CommittedParticipant where
  fromRow = CommittedParticipant <$> field <*> field

getCommittedParticipants :: Connection -> CeremonyId -> IO [CommittedParticipant]
getCommittedParticipants conn (CeremonyId cid) =
  query conn
    "SELECT participant_id, display_name FROM commitments WHERE ceremony_id = ? ORDER BY committed_at"
    (Only cid)

getCommitmentCountsBatch :: Connection -> [CeremonyId] -> IO [(UUID, Int)]
getCommitmentCountsBatch _ [] = pure []
getCommitmentCountsBatch conn cids =
  query conn
    "SELECT ceremony_id, COUNT(*)::int FROM commitments WHERE ceremony_id IN ? GROUP BY ceremony_id"
    (Only (In (map unCeremonyId cids)))

getCommittedParticipantsBatch :: Connection -> [CeremonyId] -> IO [(UUID, UUID, Maybe Text)]
getCommittedParticipantsBatch _ [] = pure []
getCommittedParticipantsBatch conn cids =
  query conn
    "SELECT ceremony_id, participant_id, display_name FROM commitments \
    \WHERE ceremony_id IN ? ORDER BY committed_at"
    (Only (In (map unCeremonyId cids)))

-- === Entropy Reveals ===

insertEntropyReveal :: Connection -> CeremonyId -> ParticipantId -> ByteString -> Bool -> IO ()
insertEntropyReveal conn (CeremonyId cid) (ParticipantId pid) val isDefault = do
  _ <- execute conn
    "INSERT INTO entropy_reveals (ceremony_id, participant_id, revealed_value, is_default) \
    \VALUES (?, ?, ?, ?)"
    (cid, pid, Binary val, isDefault)
  pure ()

getEntropyReveals :: Connection -> CeremonyId -> IO [(UUID, ByteString, Bool, Bool)]
getEntropyReveals conn (CeremonyId cid) =
  query conn
    "SELECT participant_id, revealed_value, is_default, is_published \
    \FROM entropy_reveals WHERE ceremony_id = ? ORDER BY participant_id"
    (Only cid)

getRevealedParticipants :: Connection -> CeremonyId -> IO [ParticipantId]
getRevealedParticipants conn (CeremonyId cid) =
  map (\(Only pid) -> ParticipantId pid) <$> query conn
    "SELECT participant_id FROM entropy_reveals WHERE ceremony_id = ?"
    (Only cid)

markRevealsPublished :: Connection -> CeremonyId -> IO ()
markRevealsPublished conn (CeremonyId cid) = do
  _ <- execute conn
    "UPDATE entropy_reveals SET is_published = TRUE WHERE ceremony_id = ?"
    (Only cid)
  pure ()

-- === Beacon Anchors ===

insertBeaconAnchor :: Connection -> CeremonyId -> BeaconAnchor -> IO ()
insertBeaconAnchor conn (CeremonyId cid) BeaconAnchor{..} = do
  _ <- execute conn
    "INSERT INTO beacon_anchors (ceremony_id, network, round_number, value, signature, fetched_at) \
    \VALUES (?, ?, ?, ?, ?, ?)"
    (cid, baNetwork, (fromIntegral baRound :: Int), Binary baValue, Binary baSignature, baFetchedAt)
  pure ()

getBeaconAnchor :: Connection -> CeremonyId -> IO (Maybe BeaconAnchorRow)
getBeaconAnchor conn (CeremonyId cid) =
  safeHead <$> query conn
    "SELECT network, round_number, value, signature, fetched_at \
    \FROM beacon_anchors WHERE ceremony_id = ?"
    (Only cid)

-- === Outcomes ===

insertOutcome :: Connection -> CeremonyId -> Outcome -> IO ()
insertOutcome conn (CeremonyId cid) Outcome{..} = do
  _ <- execute conn
    "INSERT INTO outcomes (ceremony_id, outcome_value, combined_entropy, proof, resolved_at) \
    \VALUES (?, ?, ?, ?, NOW())"
    ( cid
    , toJSON outcomeValue
    , Binary combinedEntropy
    , toJSON outcomeProof
    )
  pure ()

getOutcome :: Connection -> CeremonyId -> IO (Maybe OutcomeRow)
getOutcome conn (CeremonyId cid) =
  safeHead <$> query conn
    "SELECT outcome_value, combined_entropy, proof, resolved_at \
    \FROM outcomes WHERE ceremony_id = ?"
    (Only cid)

-- === Audit Log ===

insertAuditLogEntry :: Connection -> CeremonyId -> Int -> Text -> Value -> ByteString -> ByteString -> UTCTime -> IO ()
insertAuditLogEntry conn (CeremonyId cid) seqNum eventType eventData prevHash entryHash createdAt = do
  _ <- execute conn
    "INSERT INTO audit_log (sequence_num, ceremony_id, event_type, event_data, prev_hash, entry_hash, created_at) \
    \VALUES (?, ?, ?, ?, ?, ?, ?)"
    (seqNum, cid, eventType, eventData, Binary prevHash, Binary entryHash, createdAt)
  pure ()

getAuditLog :: Connection -> CeremonyId -> IO [AuditLogRow]
getAuditLog conn (CeremonyId cid) =
  query conn
    "SELECT sequence_num, ceremony_id, event_type, event_data, prev_hash, entry_hash, created_at \
    \FROM audit_log WHERE ceremony_id = ? ORDER BY sequence_num"
    (Only cid)

getLastAuditLogEntry :: Connection -> CeremonyId -> IO (Maybe AuditLogRow)
getLastAuditLogEntry conn (CeremonyId cid) =
  safeHead <$> query conn
    "SELECT sequence_num, ceremony_id, event_type, event_data, prev_hash, entry_hash, created_at \
    \FROM audit_log WHERE ceremony_id = ? ORDER BY sequence_num DESC LIMIT 1"
    (Only cid)

-- === Worker Queries ===

getPendingExpiredCeremonies :: Connection -> UTCTime -> IO [UUID]
getPendingExpiredCeremonies conn now =
  map fromOnly <$> query conn
    "SELECT id FROM ceremonies WHERE phase = 'pending' AND commit_deadline < ?"
    (Only now)

getResolvingCeremonies :: Connection -> IO [UUID]
getResolvingCeremonies conn =
  map fromOnly <$> query_ conn
    "SELECT id FROM ceremonies WHERE phase = 'resolving'"

getAwaitingBeaconCeremonies :: Connection -> IO [UUID]
getAwaitingBeaconCeremonies conn =
  map fromOnly <$> query_ conn
    "SELECT id FROM ceremonies WHERE phase = 'awaiting_beacon'"

getUnrevealedParticipants :: Connection -> CeremonyId -> IO [ParticipantId]
getUnrevealedParticipants conn (CeremonyId cid) =
  map (\(Only pid) -> ParticipantId pid) <$> query conn
    "SELECT c.participant_id FROM commitments c \
    \WHERE c.ceremony_id = ? \
    \AND c.participant_id NOT IN \
    \(SELECT participant_id FROM entropy_reveals WHERE ceremony_id = ?)"
    (cid, cid)

getAwaitingRevealsCeremonies :: Connection -> UTCTime -> IO [UUID]
getAwaitingRevealsCeremonies conn now =
  map fromOnly <$> query conn
    "SELECT id FROM ceremonies \
    \WHERE phase = 'awaiting_reveals' AND reveal_deadline < ?"
    (Only now)

-- === Row types ===

data CeremonyRow = CeremonyRow
  { crId                     :: UUID
  , crQuestion               :: Text
  , crCeremonyType           :: Value
  , crEntropyMethod          :: Text
  , crRequiredParties        :: Int
  , crCommitmentMode         :: Text
  , crCommitDeadline         :: UTCTime
  , crRevealDeadline         :: Maybe UTCTime
  , crNonParticipationPolicy :: Maybe Text
  , crBeaconSpec             :: Maybe Value
  , crPhase                  :: Text
  , crCreatedBy              :: UUID
  , crCreatedAt              :: UTCTime
  } deriving stock (Show)

instance FromRow CeremonyRow where
  fromRow = CeremonyRow
    <$> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field

data CommitmentRow = CommitmentRow
  { cmrCeremonyId    :: UUID
  , cmrParticipantId :: UUID
  , cmrEntropySeal   :: Maybe ByteString
  , cmrCommittedAt   :: UTCTime
  , cmrDisplayName   :: Maybe Text
  } deriving stock (Show)

instance FromRow CommitmentRow where
  fromRow = CommitmentRow <$> field <*> field <*> field <*> field <*> field

data BeaconAnchorRow = BeaconAnchorRow
  { barNetwork   :: Text
  , barRound     :: Int
  , barValue     :: ByteString
  , barSignature :: ByteString
  , barFetchedAt :: UTCTime
  } deriving stock (Show)

instance FromRow BeaconAnchorRow where
  fromRow = BeaconAnchorRow <$> field <*> field <*> field <*> field <*> field

data OutcomeRow = OutcomeRow
  { orOutcomeValue    :: Value
  , orCombinedEntropy :: ByteString
  , orProof           :: Value
  , orResolvedAt      :: UTCTime
  } deriving stock (Show)

instance FromRow OutcomeRow where
  fromRow = OutcomeRow <$> field <*> field <*> field <*> field

data AuditLogRow = AuditLogRow
  { alrSequenceNum :: Int
  , alrCeremonyId  :: UUID
  , alrEventType   :: Text
  , alrEventData   :: Value
  , alrPrevHash    :: ByteString
  , alrEntryHash   :: ByteString
  , alrCreatedAt   :: UTCTime
  } deriving stock (Show)

instance FromRow AuditLogRow where
  fromRow = AuditLogRow <$> field <*> field <*> field <*> field <*> field <*> field <*> field

-- === Reveal Helpers ===

-- | Convert raw entropy reveal rows into domain EntropyContributions.
-- Correctly tags default-substituted entries as DefaultEntropy.
revealsToContributions :: CeremonyId -> [(UUID, ByteString, Bool, Bool)] -> [EntropyContribution]
revealsToContributions cid reveals =
  [ EntropyContribution
      { ecCeremony = cid
      , ecSource = if isDefault
                   then DefaultEntropy (ParticipantId rpid)
                   else ParticipantEntropy (ParticipantId rpid)
      , ecValue = rval
      }
  | (rpid, rval, isDefault, _published) <- reveals
  ]

-- === Domain Conversions ===

ceremonyRowToDomain :: CeremonyRow -> Ceremony
ceremonyRowToDomain CeremonyRow{..} = Ceremony
  { ceremonyId = CeremonyId crId
  , question = crQuestion
  , ceremonyType = case Aeson.fromJSON crCeremonyType of
      Aeson.Success ct -> ct
      _                -> CoinFlip
  , entropyMethod = parseEntropyMethod crEntropyMethod
  , requiredParties = fromIntegral crRequiredParties
  , commitmentMode = parseCommitmentMode crCommitmentMode
  , commitDeadline = crCommitDeadline
  , revealDeadline = crRevealDeadline
  , nonParticipationPolicy = fmap parseNonParticipationPolicy crNonParticipationPolicy
  , beaconSpec = crBeaconSpec >>= \v -> case Aeson.fromJSON v of
      Aeson.Success bs -> Just bs
      _                -> Nothing
  , phase = parsePhase crPhase
  , createdBy = ParticipantId crCreatedBy
  , createdAt = crCreatedAt
  }

commitmentRowToDomain :: CommitmentRow -> Commitment
commitmentRowToDomain CommitmentRow{..} = Commitment
  { commitCeremony = CeremonyId cmrCeremonyId
  , commitParty = ParticipantId cmrParticipantId
  , entropySealHash = cmrEntropySeal
  , committedAt = cmrCommittedAt
  }

appendAuditLog :: Connection -> CeremonyId -> CeremonyEvent -> IO ()
appendAuditLog conn cid event = do
  now <- getCurrentTime
  mlast <- getLastAuditLogEntry conn cid
  let prevHash = maybe genesisHash alrEntryHash mlast
      seqNum = maybe 0 (\e -> alrSequenceNum e + 1) mlast
      entry = createLogEntry (LogSequence (fromIntegral seqNum)) cid event now prevHash
  insertAuditLogEntry conn cid seqNum (eventTypeName event) (toJSON event) prevHash (logEntryHash entry) now

eventTypeName :: CeremonyEvent -> Text
eventTypeName = \case
  CeremonyCreated{}          -> "ceremony_created"
  ParticipantCommitted{}     -> "participant_committed"
  EntropyRevealed{}          -> "entropy_revealed"
  RevealsPublished{}         -> "reveals_published"
  NonParticipationApplied{}  -> "non_participation_applied"
  BeaconAnchored{}           -> "beacon_anchored"
  VRFGenerated{}             -> "vrf_generated"
  CeremonyResolved{}         -> "ceremony_resolved"
  CeremonyFinalized          -> "ceremony_finalized"
  CeremonyExpired            -> "ceremony_expired"
  CeremonyCancelled{}        -> "ceremony_cancelled"
  CeremonyDisputed{}         -> "ceremony_disputed"
  DeadlineExtended{}         -> "deadline_extended"

parsePhase :: Text -> Phase
parsePhase = \case
  "pending"          -> Pending
  "awaiting_reveals" -> AwaitingReveals
  "awaiting_beacon"  -> AwaitingBeacon
  "resolving"        -> Resolving
  "finalized"        -> Finalized
  "expired"          -> Expired
  "cancelled"        -> Cancelled
  "disputed"         -> Disputed
  x                  -> error ("Unknown phase: " <> T.unpack x)

parseEntropyMethod :: Text -> EntropyMethod
parseEntropyMethod = \case
  "participant_reveal" -> ParticipantReveal
  "external_beacon"    -> ExternalBeacon
  "officiant_vrf"      -> OfficiantVRF
  "combined"           -> Combined
  x                    -> error ("Unknown entropy method: " <> T.unpack x)

parseCommitmentMode :: Text -> CommitmentMode
parseCommitmentMode = \case
  "immediate"     -> Immediate
  "deadline_wait" -> DeadlineWait
  x               -> error ("Unknown commitment mode: " <> T.unpack x)

parseNonParticipationPolicy :: Text -> NonParticipationPolicy
parseNonParticipationPolicy = \case
  "default_substitution" -> DefaultSubstitution
  "exclusion"            -> Exclusion
  "cancellation"         -> Cancellation
  x                      -> error ("Unknown non-participation policy: " <> T.unpack x)

-- === Helpers ===

safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x

showPhase :: Phase -> Text
showPhase = \case
  Pending         -> "pending"
  AwaitingReveals -> "awaiting_reveals"
  AwaitingBeacon  -> "awaiting_beacon"
  Resolving       -> "resolving"
  Finalized       -> "finalized"
  Expired         -> "expired"
  Cancelled       -> "cancelled"
  Disputed        -> "disputed"

showEntropyMethod :: EntropyMethod -> Text
showEntropyMethod = \case
  ParticipantReveal -> "participant_reveal"
  ExternalBeacon    -> "external_beacon"
  OfficiantVRF      -> "officiant_vrf"
  Combined          -> "combined"

showCommitmentMode :: CommitmentMode -> Text
showCommitmentMode = \case
  Immediate    -> "immediate"
  DeadlineWait -> "deadline_wait"

showNonParticipationPolicy :: NonParticipationPolicy -> Text
showNonParticipationPolicy = \case
  DefaultSubstitution -> "default_substitution"
  Exclusion           -> "exclusion"
  Cancellation        -> "cancellation"
