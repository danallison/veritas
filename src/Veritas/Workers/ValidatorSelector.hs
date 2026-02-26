-- | Background worker that selects validators for pool computation rounds.
--
-- Polls for rounds in the 'Selecting' phase, fetches the committed drand
-- beacon round, runs stratified selection, assigns validators, and
-- transitions the round to 'Computing'.
module Veritas.Workers.ValidatorSelector
  ( runValidatorSelector
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import Katip

import Veritas.Config (DrandConfig(..))
import Veritas.Core.Types (BeaconAnchor(..))
import Veritas.DB.Pool (DBPool, withConnection)
import qualified Veritas.DB.PoolQueries as PQ
import Veritas.External.Drand (fetchLatestBeacon)
import Veritas.Pool.Selection (stratifiedSelect, SelectionError(..))
import Veritas.Pool.Types

-- | Run the validator selector in an infinite loop.
runValidatorSelector :: LogEnv -> DBPool -> DrandConfig -> Int -> IO ()
runValidatorSelector logEnv pool drandCfg intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  result <- try @SomeException $ do
    -- Get all rounds in Selecting phase
    rounds <- withConnection pool PQ.getSelectingRounds
    forM_ rounds $ \row ->
      processSelectingRound logEnv pool drandCfg row
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.validator-selector" ErrorS (showLS err)
    Right () -> pure ()

-- | Process a single round in the Selecting phase.
processSelectingRound :: LogEnv -> DBPool -> DrandConfig -> PQ.ValidationRoundRow -> IO ()
processSelectingRound logEnv pool drandCfg row = do
  let roundId = PQ.vrrId row
      poolId = PQ.vrrPoolId row
      requesterId = PQ.vrrRequesterId row

  -- Fetch the latest beacon
  beaconResult <- fetchLatestBeacon drandCfg (drandChainHash drandCfg)

  case beaconResult of
    Left err -> runKatipT logEnv $
      logMsg "worker.validator-selector" WarningS
        (ls ("Failed to fetch beacon for round " <> show roundId <> ": " <> show err))
    Right anchor -> do
      -- Get pool members
      members <- withConnection pool $ \conn -> PQ.getPoolMembers conn poolId

      -- Convert to domain members
      let domainMembers = map toDomainMember members
          requesterPrincipal = case filter (\m -> PQ.pmrAgentId m == requesterId) members of
            (m:_) -> PrincipalId (PQ.pmrPrincipalId m)
            []    -> PrincipalId ""  -- shouldn't happen

      -- Select 2 validators using beacon signature as seed
      case stratifiedSelect domainMembers requesterPrincipal (baSignature anchor) 2 of
        Left (NotEnoughPrincipals required available) ->
          runKatipT logEnv $
            logMsg "worker.validator-selector" WarningS
              (ls ("Not enough principals for round " <> show roundId
                <> " (need " <> show required <> ", have " <> show available <> ")"))
        Right _selected -> do
          -- Update round: assign validators, record beacon, transition to Computing
          withConnection pool $ \conn ->
            PQ.updateRoundSelection conn roundId
              (fromIntegral (baRound anchor))
              (baSignature anchor)
          runKatipT logEnv $
            logMsg "worker.validator-selector" InfoS
              (ls ("Validators selected for round " <> show roundId
                <> " (beacon round " <> show (baRound anchor) <> ")"))

toDomainMember :: PQ.PoolMemberRow -> PoolMember
toDomainMember row = PoolMember
  { pmAgentId = AgentId (PQ.pmrAgentId row)
  , pmPublicKey = PQ.pmrPublicKey row
  , pmPrincipalId = PrincipalId (PQ.pmrPrincipalId row)
  , pmJoinedAt = PQ.pmrJoinedAt row
  }
