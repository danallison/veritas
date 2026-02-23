-- | Background worker that expires past-deadline pending ceremonies.
module Veritas.Workers.ExpiryChecker
  ( runExpiryChecker
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import Data.Time (getCurrentTime)
import Katip

import Veritas.Core.Types (CeremonyId(..), CeremonyEvent(..), Phase(..))
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q
import Data.List (sort)

-- | Run the expiry checker in an infinite loop.
-- Checks for pending ceremonies past their commit deadline.
runExpiryChecker :: LogEnv -> DBPool -> Int -> IO ()
runExpiryChecker logEnv pool intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  now <- getCurrentTime
  result <- try @SomeException $ withConnection pool $ \conn -> do
    expiredIds <- Q.getPendingExpiredCeremonies conn now
    forM_ expiredIds $ \cid -> do
      withSerializableTransaction conn $ \conn' -> do
        count <- Q.getCommitmentCount conn' (CeremonyId cid)
        mrow <- Q.getCeremony conn' (CeremonyId cid)
        case mrow of
          Nothing -> pure ()
          Just row -> do
            let currentPhase = Q.crPhase row
            case currentPhase of
              -- Gathering: check if registration quorum is met; if so, advance to AwaitingRosterAcks
              "gathering" -> do
                regCount <- Q.getCeremonyParticipantCount conn' (CeremonyId cid)
                let required = Q.crRequiredParties row
                if regCount >= required
                  then do
                    participants <- Q.getCeremonyParticipants conn' (CeremonyId cid)
                    let roster = sort (Q.participantRowsToRoster participants)
                    Q.updateCeremonyPhase conn' (CeremonyId cid) AwaitingRosterAcks
                    Q.appendAuditLog conn' (CeremonyId cid) (RosterFinalized roster)
                  else do
                    Q.updateCeremonyPhase conn' (CeremonyId cid) Expired
                    Q.appendAuditLog conn' (CeremonyId cid) CeremonyExpired
              -- AwaitingRosterAcks: expire (incomplete acknowledgments)
              "awaiting_roster_acks" -> do
                Q.updateCeremonyPhase conn' (CeremonyId cid) Expired
                Q.appendAuditLog conn' (CeremonyId cid) CeremonyExpired
              -- Pending: check quorum as before
              _ -> do
                let required = Q.crRequiredParties row
                if count < required
                  then do
                    Q.updateCeremonyPhase conn' (CeremonyId cid) Expired
                    Q.appendAuditLog conn' (CeremonyId cid) CeremonyExpired
                  else do
                    -- Quorum met at deadline: transition based on entropy method
                    let method = Q.crEntropyMethod row
                        nextPhase = case method of
                          "participant_reveal" -> AwaitingReveals
                          "external_beacon"    -> AwaitingBeacon
                          "officiant_vrf"      -> Resolving
                          "combined"           -> AwaitingReveals
                          _                    -> Resolving
                    Q.updateCeremonyPhase conn' (CeremonyId cid) nextPhase
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.expiry" ErrorS (showLS err)
    Right () -> pure ()
