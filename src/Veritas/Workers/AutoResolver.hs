-- | Background worker that resolves ceremonies with all entropy collected.
module Veritas.Workers.AutoResolver
  ( runAutoResolver
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_, when)
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import qualified Data.Text as T
import Database.PostgreSQL.Simple (Connection)
import Katip

import Veritas.Core.Types
import Veritas.Core.Resolution (resolve)
import Veritas.Crypto.Signatures (KeyPair)
import Veritas.Crypto.VRF (generateVRF)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q

-- | Run the auto resolver in an infinite loop.
-- Picks up ceremonies in the Resolving phase and computes outcomes.
runAutoResolver :: LogEnv -> DBPool -> KeyPair -> Int -> IO ()
runAutoResolver logEnv pool keyPair intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  result <- try @SomeException $ withConnection pool $ \conn -> do
    resolvingIds <- Q.getResolvingCeremonies conn
    forM_ resolvingIds $ \cid -> do
      withSerializableTransaction conn $ \conn' -> do
        mrow <- Q.getCeremony conn' (CeremonyId cid)
        case mrow of
          Nothing -> pure ()
          Just row -> do
            case Aeson.fromJSON (Q.crCeremonyType row) of
              Aeson.Error msg -> do
                runKatipT logEnv $
                  logMsg "worker.resolver" ErrorS (ls ("Failed to parse ceremony_type for " <> show cid <> ": " <> msg))
                disputeCeremony conn' logEnv (CeremonyId cid) ("Failed to parse ceremony_type: " <> showT msg)
              Aeson.Success ctype -> do
                contributions <- gatherEntropy conn' logEnv (CeremonyId cid) row keyPair

                if null contributions
                then disputeCeremony conn' logEnv (CeremonyId cid) "No entropy contributions available"
                else do
                  -- Log VRF generation for officiant_vrf method
                  when (Q.crEntropyMethod row == "officiant_vrf") $
                    case contributions of
                      [ec] | VRFEntropy vrfOut <- ecSource ec ->
                        Q.appendAuditLog conn' (CeremonyId cid) (VRFGenerated vrfOut)
                      _ -> pure ()

                  let outcome = resolve ctype contributions

                  Q.insertOutcome conn' (CeremonyId cid) outcome
                  Q.updateCeremonyPhase conn' (CeremonyId cid) Finalized
                  Q.appendAuditLog conn' (CeremonyId cid) (CeremonyResolved outcome)
                  Q.appendAuditLog conn' (CeremonyId cid) CeremonyFinalized
  case result of
    Left err -> runKatipT logEnv $
      logMsg "worker.resolver" ErrorS (showLS err)
    Right () -> pure ()

-- | Move a ceremony to the Disputed phase with a reason
disputeCeremony :: Connection -> LogEnv -> CeremonyId -> Text -> IO ()
disputeCeremony conn logEnv cid reason = do
  Q.updateCeremonyPhase conn cid Disputed
  Q.appendAuditLog conn cid (CeremonyDisputed reason)
  runKatipT logEnv $
    logMsg "worker.resolver" WarningS (ls ("Ceremony disputed: " <> show cid <> " — " <> show reason))

showT :: Show a => a -> Text
showT = T.pack . show

-- | Gather entropy contributions for a ceremony based on its method
gatherEntropy :: Connection -> LogEnv -> CeremonyId -> Q.CeremonyRow -> KeyPair -> IO [EntropyContribution]
gatherEntropy conn logEnv cid row keyPair = case Q.crEntropyMethod row of
  "officiant_vrf" -> do
    let vrfOut = generateVRF keyPair cid
    pure [EntropyContribution
      { ecCeremony = cid
      , ecSource = VRFEntropy vrfOut
      , ecValue = vrfValue vrfOut
      }]

  "participant_reveal" -> do
    reveals <- Q.getEntropyReveals conn cid
    pure $ Q.revealsToContributions cid reveals

  "combined" -> do
    reveals <- Q.getEntropyReveals conn cid
    let participantContributions = Q.revealsToContributions cid reveals
    mbeacon <- Q.getBeaconAnchor conn cid
    case mbeacon of
      Nothing -> do
        runKatipT logEnv $
          logMsg "worker.resolver" ErrorS
            (ls ("Combined method: no beacon anchor for ceremony " <> show cid))
        pure []  -- caller will dispute due to empty contributions
      Just bar ->
        pure (participantContributions ++ [beaconRowToContribution cid bar])

  "external_beacon" -> do
    mbeacon <- Q.getBeaconAnchor conn cid
    case mbeacon of
      Nothing -> do
        runKatipT logEnv $
          logMsg "worker.resolver" ErrorS
            (ls ("External beacon: no beacon anchor for ceremony " <> show cid))
        pure []  -- caller will dispute due to empty contributions
      Just bar -> pure [beaconRowToContribution cid bar]

  _ -> pure []

-- | Convert a beacon anchor row to an entropy contribution
beaconRowToContribution :: CeremonyId -> Q.BeaconAnchorRow -> EntropyContribution
beaconRowToContribution cid bar = EntropyContribution
  { ecCeremony = cid
  , ecSource = BeaconEntropy BeaconAnchor
      { baNetwork = Q.barNetwork bar
      , baRound = fromIntegral (Q.barRound bar)
      , baValue = Q.barValue bar
      , baSignature = Q.barSignature bar
      , baFetchedAt = Q.barFetchedAt bar
      }
  , ecValue = Q.barValue bar
  }
