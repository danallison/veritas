-- | Background worker that resolves ceremonies with all entropy collected.
module Veritas.Workers.AutoResolver
  ( runAutoResolver
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (forever, forM_)
import qualified Data.Aeson as Aeson
import Database.PostgreSQL.Simple (Connection)

import Veritas.Core.Types
import Veritas.Core.Resolution (resolve)
import Veritas.Crypto.Signatures (KeyPair)
import Veritas.Crypto.VRF (generateVRF)
import Veritas.DB.Pool (DBPool, withConnection, withSerializableTransaction)
import qualified Veritas.DB.Queries as Q

-- | Run the auto resolver in an infinite loop.
-- Picks up ceremonies in the Resolving phase and computes outcomes.
runAutoResolver :: DBPool -> KeyPair -> Int -> IO ()
runAutoResolver pool keyPair intervalSeconds = forever $ do
  threadDelay (intervalSeconds * 1_000_000)
  result <- try @SomeException $ withConnection pool $ \conn -> do
    resolvingIds <- Q.getResolvingCeremonies conn
    forM_ resolvingIds $ \cid -> do
      withSerializableTransaction conn $ \conn' -> do
        mrow <- Q.getCeremony conn' (CeremonyId cid)
        case mrow of
          Nothing -> pure ()
          Just row -> do
            contributions <- gatherEntropy conn' (CeremonyId cid) row keyPair

            let ctype = case Aeson.fromJSON (Q.crCeremonyType row) of
                  Aeson.Success ct -> ct
                  _                -> CoinFlip
                outcome = resolve ctype contributions

            Q.insertOutcome conn' (CeremonyId cid) outcome
            Q.updateCeremonyPhase conn' (CeremonyId cid) Finalized
  case result of
    Left _err -> pure ()
    Right ()  -> pure ()

-- | Gather entropy contributions for a ceremony based on its method
gatherEntropy :: Connection -> CeremonyId -> Q.CeremonyRow -> KeyPair -> IO [EntropyContribution]
gatherEntropy conn cid row keyPair = case Q.crEntropyMethod row of
  "officiant_vrf" -> do
    let vrfOut = generateVRF keyPair cid
    pure [EntropyContribution
      { ecCeremony = cid
      , ecSource = VRFEntropy vrfOut
      , ecValue = vrfValue vrfOut
      }]

  "participant_reveal" -> do
    reveals <- Q.getEntropyReveals conn cid
    pure [ EntropyContribution
             { ecCeremony = cid
             , ecSource = if isDefault
                          then DefaultEntropy (ParticipantId pid)
                          else ParticipantEntropy (ParticipantId pid)
             , ecValue = val
             }
         | (pid, val, isDefault, _published) <- reveals
         ]

  "combined" -> do
    reveals <- Q.getEntropyReveals conn cid
    let participantContributions =
          [ EntropyContribution
              { ecCeremony = cid
              , ecSource = if isDefault
                           then DefaultEntropy (ParticipantId pid)
                           else ParticipantEntropy (ParticipantId pid)
              , ecValue = val
              }
          | (pid, val, isDefault, _published) <- reveals
          ]
    mbeacon <- Q.getBeaconAnchor conn cid
    let beaconContributions = case mbeacon of
          Nothing -> []
          Just bar -> [EntropyContribution
            { ecCeremony = cid
            , ecSource = BeaconEntropy BeaconAnchor
                { baNetwork = Q.barNetwork bar
                , baRound = fromIntegral (Q.barRound bar)
                , baValue = Q.barValue bar
                , baSignature = Q.barSignature bar
                , baFetchedAt = Q.barFetchedAt bar
                }
            , ecValue = Q.barValue bar
            }]
    pure (participantContributions ++ beaconContributions)

  "external_beacon" -> do
    mbeacon <- Q.getBeaconAnchor conn cid
    case mbeacon of
      Nothing -> pure []
      Just bar -> pure [EntropyContribution
        { ecCeremony = cid
        , ecSource = BeaconEntropy BeaconAnchor
            { baNetwork = Q.barNetwork bar
            , baRound = fromIntegral (Q.barRound bar)
            , baValue = Q.barValue bar
            , baSignature = Q.barSignature bar
            , baFetchedAt = Q.barFetchedAt bar
            }
        , ecValue = Q.barValue bar
        }]

  _ -> pure []
