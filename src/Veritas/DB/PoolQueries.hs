-- | Database queries for the common-pool computing tables.
module Veritas.DB.PoolQueries
  ( -- * Pools
    insertPool
  , getPool
  , PoolRow(..)

    -- * Pool Members
  , insertPoolMember
  , getPoolMembers
  , getPoolMember
  , PoolMemberRow(..)

    -- * Cache Entries
  , insertCacheEntry
  , getCacheEntry
  , getPoolCacheEntries
  , CacheEntryRow(..)

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

-- === Helpers ===

safeHead :: [a] -> Maybe a
safeHead []    = Nothing
safeHead (x:_) = Just x
