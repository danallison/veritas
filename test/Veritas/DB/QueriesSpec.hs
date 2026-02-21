module Veritas.DB.QueriesSpec (spec) where

import Control.Exception (evaluate)
import qualified Data.ByteString as BS
import Data.UUID (fromWords)
import Test.Hspec

import Veritas.Core.Types
import Veritas.DB.Queries

spec :: Spec
spec = do
  describe "parsePhase / showPhase round-trip" $ do
    it "Pending round-trips" $
      parsePhase (showPhase Pending) `shouldBe` Pending
    it "AwaitingReveals round-trips" $
      parsePhase (showPhase AwaitingReveals) `shouldBe` AwaitingReveals
    it "AwaitingBeacon round-trips" $
      parsePhase (showPhase AwaitingBeacon) `shouldBe` AwaitingBeacon
    it "Resolving round-trips" $
      parsePhase (showPhase Resolving) `shouldBe` Resolving
    it "Finalized round-trips" $
      parsePhase (showPhase Finalized) `shouldBe` Finalized
    it "Expired round-trips" $
      parsePhase (showPhase Expired) `shouldBe` Expired
    it "Cancelled round-trips" $
      parsePhase (showPhase Cancelled) `shouldBe` Cancelled
    it "Disputed round-trips" $
      parsePhase (showPhase Disputed) `shouldBe` Disputed
    it "unknown text throws an error" $
      evaluate (parsePhase "bogus") `shouldThrow` anyErrorCall

  describe "parseEntropyMethod / showEntropyMethod round-trip" $ do
    it "ParticipantReveal round-trips" $
      parseEntropyMethod (showEntropyMethod ParticipantReveal) `shouldBe` ParticipantReveal
    it "ExternalBeacon round-trips" $
      parseEntropyMethod (showEntropyMethod ExternalBeacon) `shouldBe` ExternalBeacon
    it "OfficiantVRF round-trips" $
      parseEntropyMethod (showEntropyMethod OfficiantVRF) `shouldBe` OfficiantVRF
    it "Combined round-trips" $
      parseEntropyMethod (showEntropyMethod Combined) `shouldBe` Combined
    it "unknown text throws an error" $
      evaluate (parseEntropyMethod "bogus") `shouldThrow` anyErrorCall

  describe "parseCommitmentMode / showCommitmentMode round-trip" $ do
    it "Immediate round-trips" $
      parseCommitmentMode (showCommitmentMode Immediate) `shouldBe` Immediate
    it "DeadlineWait round-trips" $
      parseCommitmentMode (showCommitmentMode DeadlineWait) `shouldBe` DeadlineWait
    it "unknown text throws an error" $
      evaluate (parseCommitmentMode "bogus") `shouldThrow` anyErrorCall

  describe "parseNonParticipationPolicy / showNonParticipationPolicy round-trip" $ do
    it "DefaultSubstitution round-trips" $
      parseNonParticipationPolicy (showNonParticipationPolicy DefaultSubstitution)
        `shouldBe` DefaultSubstitution
    it "Exclusion round-trips" $
      parseNonParticipationPolicy (showNonParticipationPolicy Exclusion)
        `shouldBe` Exclusion
    it "Cancellation round-trips" $
      parseNonParticipationPolicy (showNonParticipationPolicy Cancellation)
        `shouldBe` Cancellation
    it "unknown text throws an error" $
      evaluate (parseNonParticipationPolicy "bogus") `shouldThrow` anyErrorCall

  describe "eventTypeName" $ do
    it "CeremonyCreated" $
      eventTypeName (CeremonyCreated undefined) `shouldBe` "ceremony_created"
    it "ParticipantCommitted" $
      eventTypeName (ParticipantCommitted undefined) `shouldBe` "participant_committed"
    it "EntropyRevealed" $
      eventTypeName (EntropyRevealed undefined BS.empty) `shouldBe` "entropy_revealed"
    it "RevealsPublished" $
      eventTypeName (RevealsPublished []) `shouldBe` "reveals_published"
    it "NonParticipationApplied" $
      eventTypeName (NonParticipationApplied undefined) `shouldBe` "non_participation_applied"
    it "BeaconAnchored" $
      eventTypeName (BeaconAnchored undefined) `shouldBe` "beacon_anchored"
    it "VRFGenerated" $
      eventTypeName (VRFGenerated undefined) `shouldBe` "vrf_generated"
    it "CeremonyResolved" $
      eventTypeName (CeremonyResolved undefined) `shouldBe` "ceremony_resolved"
    it "CeremonyFinalized" $
      eventTypeName CeremonyFinalized `shouldBe` "ceremony_finalized"
    it "CeremonyExpired" $
      eventTypeName CeremonyExpired `shouldBe` "ceremony_expired"
    it "CeremonyCancelled" $
      eventTypeName (CeremonyCancelled "reason") `shouldBe` "ceremony_cancelled"
    it "CeremonyDisputed" $
      eventTypeName (CeremonyDisputed "reason") `shouldBe` "ceremony_disputed"

  describe "revealsToContributions" $ do
    let cid = CeremonyId (fromWords 1 2 3 4)
        pid1 = fromWords 10 20 30 40
        pid2 = fromWords 50 60 70 80
        val1 = BS.pack [1,2,3]
        val2 = BS.pack [4,5,6]

    it "tags non-default reveals as ParticipantEntropy" $ do
      let reveals = [(pid1, val1, False, True)]
          [c] = revealsToContributions cid reveals
      ecSource c `shouldBe` ParticipantEntropy (ParticipantId pid1)
      ecValue c `shouldBe` val1

    it "tags default reveals as DefaultEntropy" $ do
      let reveals = [(pid1, val1, True, True)]
          [c] = revealsToContributions cid reveals
      ecSource c `shouldBe` DefaultEntropy (ParticipantId pid1)

    it "preserves ceremony id on contributions" $ do
      let reveals = [(pid1, val1, False, False)]
          [c] = revealsToContributions cid reveals
      ecCeremony c `shouldBe` cid

    it "handles multiple reveals correctly" $ do
      let reveals = [(pid1, val1, False, True), (pid2, val2, True, False)]
          cs = revealsToContributions cid reveals
      length cs `shouldBe` 2
      ecSource (head cs) `shouldBe` ParticipantEntropy (ParticipantId pid1)
      ecSource (cs !! 1) `shouldBe` DefaultEntropy (ParticipantId pid2)
