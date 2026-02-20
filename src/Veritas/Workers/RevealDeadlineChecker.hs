-- | Background worker that enforces reveal deadlines for Method A/D ceremonies.
--
-- When a ceremony is in AwaitingReveals and its reveal_deadline has passed,
-- this worker applies the ceremony's NonParticipationPolicy to unrevealed
-- participants, then transitions the ceremony forward.
module Veritas.Workers.RevealDeadlineChecker
  ( runRevealDeadlineChecker
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import Data.Time (getCurrentTime)
import Katip

import Veritas.Core.Types
import Veritas.Core.StateMachine (Action(..), TransitionResult(..), transition)
import Veritas.Crypto.CommitReveal (defaultEntropyValue)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q

-- | Run the reveal deadline checker in an infinite loop.
runRevealDeadlineChecker :: LogEnv -> DBPool -> Int -> IO ()
runRevealDeadlineChecker logEnv pool intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  now <- getCurrentTime
  result <- try @SomeException $ withConnection pool $ \conn -> do
    pastDeadlineIds <- Q.getAwaitingRevealsCeremonies conn now
    forM_ pastDeadlineIds $ \cid -> do
      withSerializableTransaction conn $ \conn' -> do
        mrow <- Q.getCeremony conn' (CeremonyId cid)
        case mrow of
          Nothing -> pure ()
          Just row -> do
            let ceremony = Q.ceremonyRowToDomain row
                policy = nonParticipationPolicy ceremony
            unrevealed <- Q.getUnrevealedParticipants conn' (CeremonyId cid)
            commitments <- map Q.commitmentRowToDomain <$> Q.getCommitments conn' (CeremonyId cid)
            revealedPids <- Q.getRevealedParticipants conn' (CeremonyId cid)

            case policy of
              Just Cancellation -> do
                let entries = [ NonParticipationEntry
                                  { npeParticipant = pid
                                  , npePolicyApplied = Cancellation
                                  , npeSubstitutedValue = Nothing
                                  }
                              | pid <- unrevealed
                              ]
                case transition ceremony commitments revealedPids (ApplyNonParticipation entries) of
                  Left tErr -> runKatipT logEnv $
                    logMsg "worker.reveal_deadline" WarningS (showLS tErr)
                  Right TransitionResult{..} -> do
                    Q.updateCeremonyPhase conn' (CeremonyId cid) trNewPhase
                    mapM_ (Q.appendAuditLog conn' (CeremonyId cid)) trEvents

              Just DefaultSubstitution -> do
                -- Insert default entropy values for unrevealed participants
                let entries = [ NonParticipationEntry
                                  { npeParticipant = pid
                                  , npePolicyApplied = DefaultSubstitution
                                  , npeSubstitutedValue = Just (defaultEntropyValue (CeremonyId cid) pid)
                                  }
                              | pid <- unrevealed
                              ]
                forM_ unrevealed $ \pid -> do
                  let defVal = defaultEntropyValue (CeremonyId cid) pid
                  Q.insertEntropyReveal conn' (CeremonyId cid) pid defVal True

                -- Update revealed list to include defaults
                let allRevealedPids = revealedPids ++ unrevealed
                case transition ceremony commitments allRevealedPids (ApplyNonParticipation entries) of
                  Left tErr -> runKatipT logEnv $
                    logMsg "worker.reveal_deadline" WarningS (showLS tErr)
                  Right TransitionResult{..} -> do
                    Q.updateCeremonyPhase conn' (CeremonyId cid) trNewPhase
                    mapM_ (Q.appendAuditLog conn' (CeremonyId cid)) trEvents
                    -- Batch publish all reveals
                    Q.markRevealsPublished conn' (CeremonyId cid)
                    reveals <- Q.getEntropyReveals conn' (CeremonyId cid)
                    let contributions = Q.revealsToContributions (CeremonyId cid) reveals
                    Q.appendAuditLog conn' (CeremonyId cid) (RevealsPublished contributions)

              Just Exclusion -> do
                -- Exclude unrevealed participants — just skip them
                let entries = [ NonParticipationEntry
                                  { npeParticipant = pid
                                  , npePolicyApplied = Exclusion
                                  , npeSubstitutedValue = Nothing
                                  }
                              | pid <- unrevealed
                              ]
                case transition ceremony commitments revealedPids (ApplyNonParticipation entries) of
                  Left tErr -> runKatipT logEnv $
                    logMsg "worker.reveal_deadline" WarningS (showLS tErr)
                  Right TransitionResult{..} -> do
                    Q.updateCeremonyPhase conn' (CeremonyId cid) trNewPhase
                    mapM_ (Q.appendAuditLog conn' (CeremonyId cid)) trEvents
                    -- Batch publish only the actual reveals
                    Q.markRevealsPublished conn' (CeremonyId cid)
                    reveals <- Q.getEntropyReveals conn' (CeremonyId cid)
                    let contributions = Q.revealsToContributions (CeremonyId cid) reveals
                    Q.appendAuditLog conn' (CeremonyId cid) (RevealsPublished contributions)

              Nothing -> pure ()  -- no policy configured; skip

  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.reveal_deadline" ErrorS (showLS err)
    Right () -> pure ()
