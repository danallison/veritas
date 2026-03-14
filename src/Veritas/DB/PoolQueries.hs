-- | Database queries for the common-pool computing tables.
module Veritas.DB.PoolQueries
  ( -- * Pools
    insertPool
  , getPool
  , listPools
  , insertPoolV2
  , getPoolV2
  , listPoolsV2
  , PoolRow(..)
  , PoolV2Row(..)

    -- * Pool Members
  , insertPoolMember
  , insertPoolMemberV2
  , getPoolMembers
  , getPoolMembersV2
  , getPoolMember
  , PoolMemberRow(..)
  , PoolMemberV2Row(..)

    -- * Cache Entries
  , insertCacheEntry
  , getCacheEntry
  , getPoolCacheEntries
  , getAllCacheEntries
  , countCacheEntries
  , CacheEntryRow(..)

    -- * Verifications
  , insertVerification
  , getVerification
  , listVerifications
  , updateVerificationSubmissionCount
  , updateVerificationVerdict
  , VerificationRow(..)

    -- * Validation Rounds
  , insertValidationRound
  , getValidationRound
  , getPoolRounds
  , updateRoundPhase
  , updateRoundSelection
  , getSelectingRounds
  , ValidationRoundRow(..)

    -- * Validation Seals
  , insertValidationSeal
  , getValidationSeals
  , updateSealReveal
  , ValidationSealRow(..)
  ) where

import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromRow

import Veritas.Pool.Types (ValidationPhase, showValidationPhase)

-- === Pool Row Types ===

data PoolRow = PoolRow
  { prId        :: UUID
  , prName      :: Text
  , prConfig    :: Value
  , prCreatedAt :: UTCTime
  } deriving stock (Show)

instance FromRow PoolRow where
  fromRow = PoolRow <$> field <*> field <*> field <*> field

data PoolMemberRow = PoolMemberRow
  { pmrPoolId      :: UUID
  , pmrAgentId     :: UUID
  , pmrPublicKey   :: ByteString
  , pmrPrincipalId :: Text
  , pmrJoinedAt    :: UTCTime
  } deriving stock (Show)

instance FromRow PoolMemberRow where
  fromRow = PoolMemberRow <$> field <*> field <*> field <*> field <*> field

data CacheEntryRow = CacheEntryRow
  { cerPoolId          :: UUID
  , cerFingerprint     :: ByteString
  , cerResult          :: ByteString
  , cerProvenance      :: Value
  , cerComputationSpec :: Value
  , cerCreatedAt       :: UTCTime
  , cerExpiresAt       :: Maybe UTCTime
  } deriving stock (Show)

instance FromRow CacheEntryRow where
  fromRow = CacheEntryRow <$> field <*> field <*> field <*> field <*> field <*> field <*> field

data ValidationRoundRow = ValidationRoundRow
  { vrrId              :: UUID
  , vrrPoolId          :: UUID
  , vrrFingerprint     :: ByteString
  , vrrComputationSpec :: Value
  , vrrComparisonMethod :: Text
  , vrrPhase           :: Text
  , vrrRequesterId     :: UUID
  , vrrBeaconRound     :: Maybe Int
  , vrrSelectionProof  :: Maybe ByteString
  , vrrCreatedAt       :: UTCTime
  , vrrDeadline        :: Maybe UTCTime
  } deriving stock (Show)

instance FromRow ValidationRoundRow where
  fromRow = ValidationRoundRow
    <$> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field <*> field <*> field

data ValidationSealRow = ValidationSealRow
  { vsrRoundId          :: UUID
  , vsrAgentId          :: UUID
  , vsrRole             :: Text
  , vsrSealHash         :: ByteString
  , vsrSealSig          :: ByteString
  , vsrRevealedResult   :: Maybe ByteString
  , vsrRevealedEvidence :: Maybe Value
  , vsrRevealedNonce    :: Maybe ByteString
  , vsrPhase            :: Text
  } deriving stock (Show)

instance FromRow ValidationSealRow where
  fromRow = ValidationSealRow
    <$> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field

-- === Pool Operations ===

insertPool :: Connection -> UUID -> Text -> Value -> UTCTime -> IO ()
insertPool conn pid name config createdAt = do
  _ <- execute conn
    "INSERT INTO pools (id, name, config, created_at) VALUES (?, ?, ?, ?)"
    (pid, name, config, createdAt)
  pure ()

getPool :: Connection -> UUID -> IO (Maybe PoolRow)
getPool conn pid =
  safeHead <$> query conn
    "SELECT id, name, config, created_at FROM pools WHERE id = ?"
    (Only pid)

-- === Pool Member Operations ===

insertPoolMember :: Connection -> UUID -> UUID -> ByteString -> Text -> UTCTime -> IO ()
insertPoolMember conn poolId agentId pk principalId joinedAt = do
  _ <- execute conn
    "INSERT INTO pool_members (pool_id, agent_id, public_key, principal_id, joined_at) \
    \VALUES (?, ?, ?, ?, ?)"
    (poolId, agentId, Binary pk, principalId, joinedAt)
  pure ()

getPoolMembers :: Connection -> UUID -> IO [PoolMemberRow]
getPoolMembers conn poolId =
  query conn
    "SELECT pool_id, agent_id, public_key, principal_id, joined_at \
    \FROM pool_members WHERE pool_id = ? ORDER BY joined_at"
    (Only poolId)

getPoolMember :: Connection -> UUID -> UUID -> IO (Maybe PoolMemberRow)
getPoolMember conn poolId agentId =
  safeHead <$> query conn
    "SELECT pool_id, agent_id, public_key, principal_id, joined_at \
    \FROM pool_members WHERE pool_id = ? AND agent_id = ?"
    (poolId, agentId)

-- === Cache Entry Operations ===

insertCacheEntry :: Connection -> UUID -> ByteString -> ByteString -> Value -> Value -> UTCTime -> Maybe UTCTime -> IO ()
insertCacheEntry conn poolId fingerprint result provenance compSpec createdAt expiresAt = do
  _ <- execute conn
    "INSERT INTO cache_entries (pool_id, fingerprint, result, provenance, computation_spec, created_at, expires_at) \
    \VALUES (?, ?, ?, ?, ?, ?, ?)"
    (poolId, Binary fingerprint, Binary result, provenance, compSpec, createdAt, expiresAt)
  pure ()

getCacheEntry :: Connection -> UUID -> ByteString -> IO (Maybe CacheEntryRow)
getCacheEntry conn poolId fingerprint =
  safeHead <$> query conn
    "SELECT pool_id, fingerprint, result, provenance, computation_spec, created_at, expires_at \
    \FROM cache_entries WHERE pool_id = ? AND fingerprint = ?"
    (poolId, Binary fingerprint)

getPoolCacheEntries :: Connection -> UUID -> IO [CacheEntryRow]
getPoolCacheEntries conn poolId =
  query conn
    "SELECT pool_id, fingerprint, result, provenance, computation_spec, created_at, expires_at \
    \FROM cache_entries WHERE pool_id = ? ORDER BY created_at DESC"
    (Only poolId)

-- === Validation Round Operations ===

insertValidationRound :: Connection
                      -> UUID -> UUID -> ByteString -> Value -> Text -> Text -> UUID -> UTCTime -> Maybe UTCTime
                      -> IO ()
insertValidationRound conn roundId poolId fingerprint compSpec compMethod phase requesterId createdAt deadline = do
  _ <- execute conn
    "INSERT INTO validation_rounds \
    \(id, pool_id, fingerprint, computation_spec, comparison_method, phase, requester_id, created_at, deadline) \
    \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ((roundId, poolId, Binary fingerprint, compSpec, compMethod)
      :. (phase, requesterId, createdAt, deadline))
  pure ()

getValidationRound :: Connection -> UUID -> IO (Maybe ValidationRoundRow)
getValidationRound conn roundId =
  safeHead <$> query conn
    "SELECT id, pool_id, fingerprint, computation_spec, comparison_method, \
    \phase, requester_id, beacon_round, selection_proof, created_at, deadline \
    \FROM validation_rounds WHERE id = ?"
    (Only roundId)

getPoolRounds :: Connection -> UUID -> IO [ValidationRoundRow]
getPoolRounds conn poolId =
  query conn
    "SELECT id, pool_id, fingerprint, computation_spec, comparison_method, \
    \phase, requester_id, beacon_round, selection_proof, created_at, deadline \
    \FROM validation_rounds WHERE pool_id = ? ORDER BY created_at DESC"
    (Only poolId)

updateRoundPhase :: Connection -> UUID -> ValidationPhase -> IO ()
updateRoundPhase conn roundId phase = do
  _ <- execute conn
    "UPDATE validation_rounds SET phase = ? WHERE id = ?"
    (showValidationPhase phase, roundId)
  pure ()

updateRoundSelection :: Connection -> UUID -> Int -> ByteString -> IO ()
updateRoundSelection conn roundId beaconRound selectionProof = do
  _ <- execute conn
    "UPDATE validation_rounds SET beacon_round = ?, selection_proof = ?, phase = 'computing' WHERE id = ?"
    (beaconRound, Binary selectionProof, roundId)
  pure ()

getSelectingRounds :: Connection -> IO [ValidationRoundRow]
getSelectingRounds conn =
  query_ conn
    "SELECT id, pool_id, fingerprint, computation_spec, comparison_method, \
    \phase, requester_id, beacon_round, selection_proof, created_at, deadline \
    \FROM validation_rounds WHERE phase = 'selecting'"

-- === Validation Seal Operations ===

insertValidationSeal :: Connection -> UUID -> UUID -> Text -> ByteString -> ByteString -> IO ()
insertValidationSeal conn roundId agentId role sealHash sealSig = do
  _ <- execute conn
    "INSERT INTO validation_seals (round_id, agent_id, role, seal_hash, seal_sig) \
    \VALUES (?, ?, ?, ?, ?)"
    (roundId, agentId, role, Binary sealHash, Binary sealSig)
  pure ()

getValidationSeals :: Connection -> UUID -> IO [ValidationSealRow]
getValidationSeals conn roundId =
  query conn
    "SELECT round_id, agent_id, role, seal_hash, seal_sig, \
    \revealed_result, revealed_evidence, revealed_nonce, phase \
    \FROM validation_seals WHERE round_id = ? ORDER BY agent_id"
    (Only roundId)

updateSealReveal :: Connection -> UUID -> UUID -> ByteString -> Value -> ByteString -> IO ()
updateSealReveal conn roundId agentId result evidence nonce = do
  _ <- execute conn
    "UPDATE validation_seals \
    \SET revealed_result = ?, revealed_evidence = ?, revealed_nonce = ?, phase = 'revealed' \
    \WHERE round_id = ? AND agent_id = ?"
    (Binary result, evidence, Binary nonce, roundId, agentId)
  pure ()

-- === Pool V2 Operations (verification pivot) ===

data PoolV2Row = PoolV2Row
  { pv2Id            :: UUID
  , pv2Name          :: Text
  , pv2Description   :: Text
  , pv2TaskType      :: Text
  , pv2SelectionSize :: Int
  , pv2CreatedAt     :: UTCTime
  } deriving stock (Show)

instance FromRow PoolV2Row where
  fromRow = PoolV2Row <$> field <*> field <*> field <*> field <*> field <*> field

listPools :: Connection -> IO [PoolRow]
listPools conn =
  query_ conn "SELECT id, name, config, created_at FROM pools ORDER BY created_at DESC"

listPoolsV2 :: Connection -> IO [PoolV2Row]
listPoolsV2 conn =
  query_ conn
    "SELECT id, name, COALESCE(description, ''), COALESCE(task_type, 'cross_validation'), \
    \COALESCE(selection_size, 2), created_at FROM pools ORDER BY created_at DESC"

getPoolV2 :: Connection -> UUID -> IO (Maybe PoolV2Row)
getPoolV2 conn pid =
  safeHead <$> query conn
    "SELECT id, name, COALESCE(description, ''), COALESCE(task_type, 'cross_validation'), \
    \COALESCE(selection_size, 2), created_at FROM pools WHERE id = ?"
    (Only pid)

insertPoolV2 :: Connection -> UUID -> Text -> Text -> Text -> Int -> UTCTime -> IO ()
insertPoolV2 conn pid name description taskType selectionSize createdAt = do
  _ <- execute conn
    "INSERT INTO pools (id, name, config, description, task_type, selection_size, created_at) \
    \VALUES (?, ?, '{}', ?, ?, ?, ?)"
    (pid, name, description, taskType, selectionSize, createdAt)
  pure ()

-- === Pool Member V2 Operations (verification pivot) ===

data PoolMemberV2Row = PoolMemberV2Row
  { pmv2PoolId       :: UUID
  , pmv2AgentId      :: UUID
  , pmv2PublicKey     :: ByteString
  , pmv2DisplayName  :: Text
  , pmv2Capabilities :: Value
  , pmv2Status       :: Text
  , pmv2JoinedAt     :: UTCTime
  } deriving stock (Show)

instance FromRow PoolMemberV2Row where
  fromRow = PoolMemberV2Row <$> field <*> field <*> field <*> field <*> field <*> field <*> field

getPoolMembersV2 :: Connection -> UUID -> IO [PoolMemberV2Row]
getPoolMembersV2 conn poolId =
  query conn
    "SELECT pool_id, agent_id, public_key, COALESCE(display_name, principal_id), \
    \COALESCE(capabilities, '[]'), COALESCE(status, 'active'), joined_at \
    \FROM pool_members WHERE pool_id = ? ORDER BY joined_at"
    (Only poolId)

insertPoolMemberV2 :: Connection -> UUID -> UUID -> ByteString -> Text -> Text -> Value -> UTCTime -> IO ()
insertPoolMemberV2 conn poolId agentId pk displayName principalId capabilities joinedAt = do
  _ <- execute conn
    "INSERT INTO pool_members (pool_id, agent_id, public_key, principal_id, display_name, capabilities, joined_at) \
    \VALUES (?, ?, ?, ?, ?, ?, ?)"
    (poolId, agentId, Binary pk, principalId, displayName, capabilities, joinedAt)
  pure ()

-- === Cache Extended Operations ===

getAllCacheEntries :: Connection -> IO [CacheEntryRow]
getAllCacheEntries conn =
  query_ conn
    "SELECT pool_id, fingerprint, result, provenance, computation_spec, created_at, expires_at \
    \FROM cache_entries ORDER BY created_at DESC"

countCacheEntries :: Connection -> IO (Int, Int, Int)
countCacheEntries conn = do
  rows <- query_ conn
    "SELECT \
    \  COUNT(*), \
    \  COUNT(*) FILTER (WHERE provenance->'outcome'->>'tag' = 'Unanimous'), \
    \  COUNT(*) FILTER (WHERE provenance->'outcome'->>'tag' = 'Majority') \
    \FROM cache_entries"
    :: IO [(Int, Int, Int)]
  case rows of
    ((total, unan, maj):_) -> pure (total, unan, maj)
    []                     -> pure (0, 0, 0)

-- === Verification Operations ===

data VerificationRow = VerificationRow
  { vrId                  :: UUID
  , vrPoolId              :: UUID
  , vrDescription         :: Text
  , vrFingerprint         :: Text
  , vrSubmittedResult     :: Maybe Text
  , vrComparisonMethod    :: Text
  , vrValidatorCount      :: Int
  , vrSubmitter           :: UUID
  , vrValidators          :: Value
  , vrSubmissionCount     :: Int
  , vrExpectedSubmissions :: Int
  , vrPhase               :: Text
  , vrVerdict             :: Maybe Value
  , vrCreatedAt           :: UTCTime
  } deriving stock (Show)

instance FromRow VerificationRow where
  fromRow = VerificationRow
    <$> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field

insertVerification :: Connection -> UUID -> UUID -> Text -> Text -> Maybe Text -> Text -> Int -> UUID -> Value -> Int -> UTCTime -> IO ()
insertVerification conn vid poolId description fingerprint submittedResult compMethod validatorCount submitter validators expectedSubmissions createdAt = do
  _ <- execute conn
    "INSERT INTO verifications \
    \(id, pool_id, description, fingerprint, submitted_result, comparison_method, \
    \validator_count, submitter, validators, submission_count, expected_submissions, phase, created_at) \
    \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 'collecting', ?)"
    ((vid, poolId, description, fingerprint, submittedResult)
      :. (compMethod, validatorCount, submitter, validators, expectedSubmissions, createdAt))
  pure ()

getVerification :: Connection -> UUID -> IO (Maybe VerificationRow)
getVerification conn vid =
  safeHead <$> query conn
    "SELECT id, pool_id, description, fingerprint, submitted_result, comparison_method, \
    \validator_count, submitter, validators, submission_count, expected_submissions, \
    \phase, verdict, created_at \
    \FROM verifications WHERE id = ?"
    (Only vid)

listVerifications :: Connection -> IO [VerificationRow]
listVerifications conn =
  query_ conn
    "SELECT id, pool_id, description, fingerprint, submitted_result, comparison_method, \
    \validator_count, submitter, validators, submission_count, expected_submissions, \
    \phase, verdict, created_at \
    \FROM verifications ORDER BY created_at DESC"

updateVerificationSubmissionCount :: Connection -> UUID -> Int -> IO ()
updateVerificationSubmissionCount conn vid count = do
  _ <- execute conn
    "UPDATE verifications SET submission_count = ? WHERE id = ?"
    (count, vid)
  pure ()

updateVerificationVerdict :: Connection -> UUID -> Text -> Value -> IO ()
updateVerificationVerdict conn vid phase verdict = do
  _ <- execute conn
    "UPDATE verifications SET phase = ?, verdict = ? WHERE id = ?"
    (phase, verdict, vid)
  pure ()

-- === Helpers ===

safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x
