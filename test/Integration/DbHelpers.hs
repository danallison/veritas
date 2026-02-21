-- | Database helpers for integration tests.
-- Table truncation for test isolation and ceremony resolution helper.
module Integration.DbHelpers
  ( truncateAllTables
  , resolveTestCeremony
  ) where

import qualified Data.Aeson as Aeson
import Database.PostgreSQL.Simple (Connection, execute_)

import Veritas.Core.Types
import Veritas.Core.Resolution (resolve)
import Veritas.Crypto.Signatures (KeyPair)
import Veritas.Crypto.VRF (generateVRF)
import Veritas.DB.Pool (DBPool, withConnection)
import qualified Veritas.DB.Queries as Q

-- | Truncate all tables for test isolation.
-- Uses CASCADE to handle foreign key constraints.
truncateAllTables :: Connection -> IO ()
truncateAllTables conn = do
  execute_ conn
    "TRUNCATE audit_log, outcomes, beacon_anchors, entropy_reveals, commitments, ceremonies RESTART IDENTITY CASCADE"
  pure ()

-- | Resolve a ceremony in the Resolving phase.
-- Replicates the AutoResolver logic for a single ceremony using the same
-- library functions. Used for ParticipantReveal tests where the worker isn't running.
resolveTestCeremony :: DBPool -> KeyPair -> CeremonyId -> IO ()
resolveTestCeremony pool keyPair cid = do
  withConnection pool $ \conn -> do
    mrow <- Q.getCeremony conn cid
    case mrow of
      Nothing -> error ("resolveTestCeremony: ceremony not found: " <> show cid)
      Just row -> do
        let method = Q.crEntropyMethod row
        contributions <- case method of
          "participant_reveal" -> do
            reveals <- Q.getEntropyReveals conn cid
            pure $ Q.revealsToContributions cid reveals

          "officiant_vrf" -> do
            let vrfOut = generateVRF keyPair cid
            Q.appendAuditLog conn cid (VRFGenerated vrfOut)
            pure [EntropyContribution
              { ecCeremony = cid
              , ecSource = VRFEntropy vrfOut
              , ecValue = vrfValue vrfOut
              }]

          _ -> error ("resolveTestCeremony: unsupported method: " <> show method)

        case Aeson.fromJSON (Q.crCeremonyType row) of
          Aeson.Error msg -> error ("resolveTestCeremony: bad ceremony_type: " <> msg)
          Aeson.Success ctype -> do
            let outcome = resolve ctype contributions
            Q.insertOutcome conn cid outcome
            Q.updateCeremonyPhase conn cid Finalized
            Q.appendAuditLog conn cid (CeremonyResolved outcome)
            Q.appendAuditLog conn cid CeremonyFinalized
