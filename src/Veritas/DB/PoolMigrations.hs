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
