-- | Background worker that expires past-deadline pending ceremonies.
module Veritas.Workers.ExpiryChecker
  ( runExpiryChecker
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import Data.Time (getCurrentTime)

import Veritas.Core.Types (CeremonyId(..), Phase(..))
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q

-- | Run the expiry checker in an infinite loop.
-- Checks for pending ceremonies past their commit deadline.
runExpiryChecker :: DBPool -> Int -> IO ()
runExpiryChecker pool intervalSeconds = forever $ do
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
            let required = Q.crRequiredParties row
            if count < required
              then do
                Q.updateCeremonyPhase conn' (CeremonyId cid) Expired
                -- Audit log entry handled by appendAuditLog in handlers
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
    Left _err -> pure ()  -- log error in production
    Right ()  -> pure ()
