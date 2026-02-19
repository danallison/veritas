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

    -- * Worker Queries
  , getPendingExpiredCeremonies
  , getResolvingCeremonies

    -- * Row types
  , CeremonyRow(..)
  , CommitmentRow(..)
  , BeaconAnchorRow(..)
  , OutcomeRow(..)
  , AuditLogRow(..)
  ) where

import Data.Aeson (Value, toJSON)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromRow

import Veritas.Core.Types

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

-- === Commitments ===

insertCommitment :: Connection -> Commitment -> IO ()
insertCommitment conn Commitment{..} = do
  _ <- execute conn
    "INSERT INTO commitments (ceremony_id, participant_id, signature, entropy_seal, committed_at) \
    \VALUES (?, ?, ?, ?, ?)"
    ( unCeremonyId commitCeremony
    , unParticipantId commitParty
    , Binary commitSignature
    , fmap Binary entropySealHash
    , committedAt
    )
  pure ()

getCommitments :: Connection -> CeremonyId -> IO [CommitmentRow]
getCommitments conn (CeremonyId cid) =
  query conn
    "SELECT ceremony_id, participant_id, signature, entropy_seal, committed_at \
    \FROM commitments WHERE ceremony_id = ? ORDER BY committed_at"
    (Only cid)

getCommitmentCount :: Connection -> CeremonyId -> IO Int
getCommitmentCount conn (CeremonyId cid) = do
  [Only n] <- query conn
    "SELECT COUNT(*) FROM commitments WHERE ceremony_id = ?"
    (Only cid)
  pure n

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

insertAuditLogEntry :: Connection -> CeremonyId -> Text -> Value -> ByteString -> ByteString -> IO ()
insertAuditLogEntry conn (CeremonyId cid) eventType eventData prevHash entryHash = do
  _ <- execute conn
    "INSERT INTO audit_log (ceremony_id, event_type, event_data, prev_hash, entry_hash) \
    \VALUES (?, ?, ?, ?, ?)"
    (cid, eventType, eventData, Binary prevHash, Binary entryHash)
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
  , cmrSignature     :: ByteString
  , cmrEntropySeal   :: Maybe ByteString
  , cmrCommittedAt   :: UTCTime
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
