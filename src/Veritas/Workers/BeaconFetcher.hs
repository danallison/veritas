-- | Background worker that fetches drand beacon values for ceremonies
-- in the AwaitingBeacon phase (Methods B and D).
module Veritas.Workers.BeaconFetcher
  ( runBeaconFetcher
  , resolveChainHash
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import Data.Time (addUTCTime)
import Katip

import Veritas.Config (DrandConfig(..))
import Veritas.Core.Types
import Veritas.Core.StateMachine (Action(..), TransitionResult(..), transition)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q
import Veritas.External.Drand (fetchBeaconRound, fetchLatestBeacon, DrandError)

-- | Run the beacon fetcher in an infinite loop.
-- Picks up ceremonies in the AwaitingBeacon phase and fetches drand beacon values.
runBeaconFetcher :: LogEnv -> DBPool -> DrandConfig -> Int -> IO ()
runBeaconFetcher logEnv pool drandCfg intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  result <- try @SomeException $ do
    -- Query for awaiting IDs, then release the connection before processing.
    -- Each processBeaconCeremony acquires its own connections, so holding
    -- the query connection during the loop would risk pool deadlock.
    awaitingIds <- withConnection pool Q.getAwaitingBeaconCeremonies
    forM_ awaitingIds $ \cid ->
      processBeaconCeremony logEnv pool drandCfg (CeremonyId cid)
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.beacon" ErrorS (showLS err)
    Right () -> pure ()

-- | Process a single ceremony that is awaiting a beacon value.
-- HTTP fetch happens outside the DB transaction to avoid holding the connection.
processBeaconCeremony :: LogEnv -> DBPool -> DrandConfig -> CeremonyId -> IO ()
processBeaconCeremony logEnv pool drandCfg cid = do
  -- Read ceremony data (outside transaction — just a read)
  mSpec <- withConnection pool $ \conn -> do
    mrow <- Q.getCeremony conn cid
    pure $ case mrow of
      Nothing  -> Nothing
      Just row -> case Q.crBeaconSpec row of
        Nothing -> Nothing
        Just v  -> case Aeson.fromJSON v of
          Aeson.Success bs -> Just bs
          _                -> Nothing

  case mSpec of
    Nothing   -> pure ()  -- no beacon spec, skip
    Just spec -> fetchAndAnchor logEnv pool drandCfg cid spec 0

-- | Fetch beacon and anchor it, handling fallback strategies.
-- maxDepth prevents infinite recursion on AlternateSource chains.
fetchAndAnchor :: LogEnv -> DBPool -> DrandConfig -> CeremonyId -> BeaconSpec -> Int -> IO ()
fetchAndAnchor logEnv pool drandCfg cid spec depth
  | depth >= 3 = cancelCeremony logEnv pool cid "Beacon fallback chain exceeded maximum depth"
  | otherwise = do
      let chainHash = resolveChainHash drandCfg (beaconNetwork spec)
      beaconResult <- case beaconRound spec of
        Just roundNum -> fetchBeaconRound drandCfg chainHash roundNum
        Nothing       -> fetchLatestBeacon drandCfg chainHash

      case beaconResult of
        Right anchor -> anchorBeacon logEnv pool cid anchor
        Left err     -> handleFallback logEnv pool drandCfg cid spec depth err

-- | Resolve well-known network names to the config's chain hash, otherwise use as-is
resolveChainHash :: DrandConfig -> Text -> Text
resolveChainHash cfg network
  | network == "default"        = drandChainHash cfg
  | network == "drand-quicknet" = drandChainHash cfg
  | otherwise                   = network

-- | Apply the fallback strategy when beacon fetch fails
handleFallback :: LogEnv -> DBPool -> DrandConfig -> CeremonyId -> BeaconSpec -> Int -> DrandError -> IO ()
handleFallback logEnv pool drandCfg cid spec depth err = do
  runKatipT logEnv $
    logMsg "worker.beacon.fallback" WarningS (showLS err)
  case beaconFallback spec of
    ExtendDeadline duration -> do
      extendResult <- try @SomeException $ withConnection pool $ \conn ->
        withSerializableTransaction conn $ \conn' -> do
          mrow <- Q.getCeremony conn' cid
          case mrow of
            Nothing -> pure ()
            Just row -> do
              let currentDeadline = case Q.crRevealDeadline row of
                    Just rd -> rd
                    Nothing -> Q.crCommitDeadline row
                  newDeadline = addUTCTime duration currentDeadline
              Q.updateRevealDeadline conn' cid newDeadline
              Q.appendAuditLog conn' cid (DeadlineExtended duration newDeadline)
              runKatipT logEnv $
                logMsg "worker.beacon.extend" InfoS (ls ("Extended deadline for ceremony " <> show cid <> " to " <> show newDeadline))
      case extendResult of
        Left extErr -> runKatipT logEnv $
          logMsg "worker.beacon.extend" ErrorS (showLS extErr)
        Right () -> pure ()
    AlternateSource altSpec ->
      fetchAndAnchor logEnv pool drandCfg cid altSpec (depth + 1)
    CancelCeremony ->
      cancelCeremony logEnv pool cid "Beacon fetch failed and fallback is CancelCeremony"

-- | Anchor a beacon value: insert it and run the state machine transition
anchorBeacon :: LogEnv -> DBPool -> CeremonyId -> BeaconAnchor -> IO ()
anchorBeacon logEnv pool cid anchor = do
  result <- try @SomeException $ withConnection pool $ \conn ->
    withSerializableTransaction conn $ \conn' -> do
      mrow <- Q.getCeremony conn' cid
      case mrow of
        Nothing -> pure ()
        Just row -> do
          let ceremony = Q.ceremonyRowToDomain row
          case transition ceremony [] [] (AnchorBeacon anchor) of
            Left tErr -> runKatipT logEnv $
              logMsg "worker.beacon.anchor" WarningS (showLS tErr)
            Right TransitionResult{..} -> do
              Q.insertBeaconAnchor conn' cid anchor
              Q.updateCeremonyPhase conn' cid trNewPhase
              Q.appendAuditLog conn' cid (BeaconAnchored anchor)
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.beacon.anchor" ErrorS (showLS err)
    Right () -> pure ()

-- | Cancel a ceremony with a reason.
-- Re-reads the ceremony inside the transaction to guard against races
-- (e.g., beacon was anchored between poll and cancel).
cancelCeremony :: LogEnv -> DBPool -> CeremonyId -> Text -> IO ()
cancelCeremony logEnv pool cid reason = do
  result <- try @SomeException $ withConnection pool $ \conn ->
    withSerializableTransaction conn $ \conn' -> do
      mrow <- Q.getCeremony conn' cid
      case mrow of
        Nothing -> pure ()
        Just row
          | Q.crPhase row /= "awaiting_beacon" -> pure ()  -- no longer cancellable
          | otherwise -> do
              Q.updateCeremonyPhase conn' cid Cancelled
              Q.appendAuditLog conn' cid (CeremonyCancelled reason)
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.beacon.cancel" ErrorS (showLS err)
    Right () -> pure ()
