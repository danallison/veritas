-- | Database schema migrations.
module Veritas.DB.Migrations
  ( runMigrations
  ) where

import Database.PostgreSQL.Simple (Connection, Query, execute_)

-- | Run all migrations (idempotent).
runMigrations :: Connection -> IO ()
runMigrations conn = do
  execute_ conn createCeremoniesTable
  execute_ conn createCommitmentsTable
  execute_ conn createEntropyRevealsTable
  execute_ conn createBeaconAnchorsTable
  execute_ conn createOutcomesTable
  execute_ conn createAuditLogTable
  pure ()

createCeremoniesTable :: Query
createCeremoniesTable =
  "CREATE TABLE IF NOT EXISTS ceremonies (\
  \  id                       UUID PRIMARY KEY,\
  \  question                 TEXT NOT NULL,\
  \  ceremony_type            JSONB NOT NULL,\
  \  entropy_method           TEXT NOT NULL,\
  \  required_parties         INTEGER NOT NULL CHECK (required_parties > 0),\
  \  commitment_mode          TEXT NOT NULL DEFAULT 'immediate',\
  \  commit_deadline          TIMESTAMPTZ NOT NULL,\
  \  reveal_deadline          TIMESTAMPTZ,\
  \  non_participation_policy TEXT,\
  \  beacon_spec              JSONB,\
  \  phase                    TEXT NOT NULL DEFAULT 'pending',\
  \  created_by               UUID NOT NULL,\
  \  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"

createCommitmentsTable :: Query
createCommitmentsTable =
  "CREATE TABLE IF NOT EXISTS commitments (\
  \  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),\
  \  ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),\
  \  participant_id   UUID NOT NULL,\
  \  signature        BYTEA NOT NULL,\
  \  entropy_seal     BYTEA,\
  \  committed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
  \  UNIQUE (ceremony_id, participant_id)\
  \)"

createEntropyRevealsTable :: Query
createEntropyRevealsTable =
  "CREATE TABLE IF NOT EXISTS entropy_reveals (\
  \  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),\
  \  ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),\
  \  participant_id   UUID NOT NULL,\
  \  revealed_value   BYTEA NOT NULL,\
  \  is_default       BOOLEAN NOT NULL DEFAULT FALSE,\
  \  is_published     BOOLEAN NOT NULL DEFAULT FALSE,\
  \  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
  \  UNIQUE (ceremony_id, participant_id)\
  \)"

createBeaconAnchorsTable :: Query
createBeaconAnchorsTable =
  "CREATE TABLE IF NOT EXISTS beacon_anchors (\
  \  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),\
  \  ceremony_id      UUID NOT NULL UNIQUE REFERENCES ceremonies(id),\
  \  network          TEXT NOT NULL,\
  \  round_number     BIGINT NOT NULL,\
  \  value            BYTEA NOT NULL,\
  \  signature        BYTEA NOT NULL,\
  \  fetched_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"

createOutcomesTable :: Query
createOutcomesTable =
  "CREATE TABLE IF NOT EXISTS outcomes (\
  \  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),\
  \  ceremony_id      UUID NOT NULL UNIQUE REFERENCES ceremonies(id),\
  \  outcome_value    JSONB NOT NULL,\
  \  combined_entropy BYTEA NOT NULL,\
  \  proof            JSONB NOT NULL,\
  \  resolved_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()\
  \)"

createAuditLogTable :: Query
createAuditLogTable =
  "CREATE TABLE IF NOT EXISTS audit_log (\
  \  sequence_num     BIGSERIAL,\
  \  ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),\
  \  event_type       TEXT NOT NULL,\
  \  event_data       JSONB NOT NULL,\
  \  prev_hash        BYTEA NOT NULL,\
  \  entry_hash       BYTEA NOT NULL,\
  \  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
  \  PRIMARY KEY (ceremony_id, sequence_num)\
  \)"

-- Query type is imported from Database.PostgreSQL.Simple
