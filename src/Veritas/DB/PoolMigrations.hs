-- | Database schema migrations for the common-pool computing tables.
module Veritas.DB.PoolMigrations
  ( runPoolMigrations
  ) where

import Database.PostgreSQL.Simple (Connection, Query, execute_)

-- | Run all pool-related migrations (idempotent).
runPoolMigrations :: Connection -> IO ()
runPoolMigrations conn = do
  execute_ conn createPoolsTable
  execute_ conn createPoolMembersTable
  execute_ conn createCacheEntriesTable
  execute_ conn createValidationRoundsTable
  execute_ conn createValidationSealsTable
  -- Verification pivot: extend pools and pool_members
  execute_ conn addPoolDescription
  execute_ conn addPoolTaskType
  execute_ conn addPoolSelectionSize
  execute_ conn addMemberDisplayName
  execute_ conn addMemberCapabilities
  execute_ conn addMemberStatus
  -- Verification pivot: new tables
  execute_ conn createVerificationsTable
  pure ()

createPoolsTable :: Query
createPoolsTable =
  "CREATE TABLE IF NOT EXISTS pools (\
  \  id         UUID PRIMARY KEY,\
  \  name       TEXT NOT NULL,\
  \  config     JSONB NOT NULL,\
  \  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"

createPoolMembersTable :: Query
createPoolMembersTable =
  "CREATE TABLE IF NOT EXISTS pool_members (\
  \  pool_id      UUID NOT NULL REFERENCES pools(id),\
  \  agent_id     UUID PRIMARY KEY,\
  \  public_key   BYTEA NOT NULL,\
  \  principal_id TEXT NOT NULL,\
  \  joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"

createCacheEntriesTable :: Query
createCacheEntriesTable =
  "CREATE TABLE IF NOT EXISTS cache_entries (\
  \  pool_id          UUID NOT NULL REFERENCES pools(id),\
  \  fingerprint      BYTEA NOT NULL,\
  \  result           BYTEA NOT NULL,\
  \  provenance       JSONB NOT NULL,\
  \  computation_spec JSONB NOT NULL,\
  \  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
  \  expires_at       TIMESTAMPTZ,\
  \  PRIMARY KEY (pool_id, fingerprint)\
  \)"

createValidationRoundsTable :: Query
createValidationRoundsTable =
  "CREATE TABLE IF NOT EXISTS validation_rounds (\
  \  id                UUID PRIMARY KEY,\
  \  pool_id           UUID NOT NULL REFERENCES pools(id),\
  \  fingerprint       BYTEA NOT NULL,\
  \  computation_spec  JSONB NOT NULL,\
  \  comparison_method TEXT NOT NULL,\
  \  phase             TEXT NOT NULL DEFAULT 'requested',\
  \  requester_id      UUID NOT NULL,\
  \  beacon_round      BIGINT,\
  \  selection_proof   BYTEA,\
  \  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
  \  deadline          TIMESTAMPTZ\
  \)"

createValidationSealsTable :: Query
createValidationSealsTable =
  "CREATE TABLE IF NOT EXISTS validation_seals (\
  \  round_id          UUID NOT NULL REFERENCES validation_rounds(id),\
  \  agent_id          UUID NOT NULL,\
  \  role              TEXT NOT NULL,\
  \  seal_hash         BYTEA NOT NULL,\
  \  seal_sig          BYTEA NOT NULL,\
  \  revealed_result   BYTEA,\
  \  revealed_evidence JSONB,\
  \  revealed_nonce    BYTEA,\
  \  phase             TEXT NOT NULL DEFAULT 'sealed',\
  \  PRIMARY KEY (round_id, agent_id)\
  \)"

-- === Verification Pivot Migrations ===

-- Extend pools table with verification-pivot columns
addPoolDescription :: Query
addPoolDescription =
  "ALTER TABLE pools ADD COLUMN IF NOT EXISTS description TEXT DEFAULT ''"

addPoolTaskType :: Query
addPoolTaskType =
  "ALTER TABLE pools ADD COLUMN IF NOT EXISTS task_type TEXT DEFAULT 'cross_validation'"

addPoolSelectionSize :: Query
addPoolSelectionSize =
  "ALTER TABLE pools ADD COLUMN IF NOT EXISTS selection_size INTEGER DEFAULT 2"

-- Extend pool_members with verification-pivot columns
addMemberDisplayName :: Query
addMemberDisplayName =
  "ALTER TABLE pool_members ADD COLUMN IF NOT EXISTS display_name TEXT DEFAULT ''"

addMemberCapabilities :: Query
addMemberCapabilities =
  "ALTER TABLE pool_members ADD COLUMN IF NOT EXISTS capabilities JSONB DEFAULT '[]'"

addMemberStatus :: Query
addMemberStatus =
  "ALTER TABLE pool_members ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active'"

-- New verifications table for cross-validation requests
createVerificationsTable :: Query
createVerificationsTable =
  "CREATE TABLE IF NOT EXISTS verifications (\
  \  id                  UUID PRIMARY KEY,\
  \  pool_id             UUID NOT NULL REFERENCES pools(id),\
  \  description         TEXT NOT NULL,\
  \  fingerprint         TEXT NOT NULL,\
  \  submitted_result    TEXT,\
  \  comparison_method   TEXT NOT NULL DEFAULT 'exact',\
  \  validator_count     INTEGER NOT NULL DEFAULT 2,\
  \  submitter           UUID NOT NULL,\
  \  validators          JSONB NOT NULL DEFAULT '[]',\
  \  submission_count    INTEGER NOT NULL DEFAULT 0,\
  \  expected_submissions INTEGER NOT NULL DEFAULT 3,\
  \  phase               TEXT NOT NULL DEFAULT 'collecting',\
  \  verdict             JSONB,\
  \  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"
