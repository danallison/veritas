module Veritas.Core.StateMachineSpec (spec) where

import Data.ByteString (ByteString)
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Types
import Veritas.Core.StateMachine

-- Test helpers
testCeremonyId :: CeremonyId
testCeremonyId = CeremonyId UUID.nil

testParticipant1 :: ParticipantId
testParticipant1 = ParticipantId (UUID.fromWords 1 0 0 0)

testParticipant2 :: ParticipantId
testParticipant2 = ParticipantId (UUID.fromWords 2 0 0 0)

futureTime :: UTCTime -> UTCTime
futureTime = addUTCTime 3600

pastTime :: UTCTime -> UTCTime
pastTime = addUTCTime (-3600)

mkCeremony :: EntropyMethod -> CommitmentMode -> Natural -> UTCTime -> Ceremony
mkCeremony method mode parties deadline = Ceremony
  { ceremonyId = testCeremonyId
  , question = "Test question"
  , ceremonyType = CoinFlip
  , entropyMethod = method
  , requiredParties = parties
  , commitmentMode = mode
  , commitDeadline = deadline
  , revealDeadline = Just (addUTCTime 7200 deadline)
  , nonParticipationPolicy = Just Cancellation
  , beaconSpec = Nothing
  , phase = Pending
  , createdBy = testParticipant1
  , createdAt = deadline
  }

mkCommitment :: ParticipantId -> Maybe ByteString -> UTCTime -> Commitment
mkCommitment pid seal ts = Commitment
  { commitCeremony = testCeremonyId
  , commitParty = pid
  , commitSignature = "test-sig"
  , entropySealHash = seal
  , committedAt = ts
  }

spec :: Spec
spec = do
  describe "StateMachine" $ do
    describe "Pending phase" $ do
      it "accepts a commitment in Pending phase" $ do
        now <- getCurrentTime
        let ceremony = mkCeremony OfficiantVRF Immediate 2 (futureTime now)
            commit = mkCommitment testParticipant1 Nothing now
        case transition ceremony [] [] (AddCommitment commit) of
          Right TransitionResult{..} -> do
            trNewPhase `shouldBe` Pending  -- quorum not yet reached (1/2)
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "transitions to Resolving when VRF quorum reached (Immediate mode)" $ do
        now <- getCurrentTime
        let ceremony = mkCeremony OfficiantVRF Immediate 2 (futureTime now)
            existing = [mkCommitment testParticipant1 Nothing now]
            newCommit = mkCommitment testParticipant2 Nothing now
        case transition ceremony existing [] (AddCommitment newCommit) of
          Right TransitionResult{..} -> do
            trNewPhase `shouldBe` Resolving
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "transitions to AwaitingReveals when ParticipantReveal quorum reached" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ParticipantReveal Immediate 2 (futureTime now)) { phase = Pending }
            existing = [mkCommitment testParticipant1 (Just "seal1") now]
            newCommit = mkCommitment testParticipant2 (Just "seal2") now
        case transition ceremony existing [] (AddCommitment newCommit) of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` AwaitingReveals
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "requires entropy seal for ParticipantReveal method" $ do
        now <- getCurrentTime
        let ceremony = mkCeremony ParticipantReveal Immediate 2 (futureTime now)
            commit = mkCommitment testParticipant1 Nothing now  -- no seal!
        case transition ceremony [] [] (AddCommitment commit) of
          Left (InvariantViolation _) -> pure ()
          other -> expectationFailure $ "Expected InvariantViolation, got: " ++ show other

      it "expires when deadline passes without quorum" $ do
        now <- getCurrentTime
        let ceremony = mkCeremony OfficiantVRF Immediate 2 (pastTime now)
        case transition ceremony [] [] (CheckDeadline now) of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Expired
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "transitions when deadline passes with quorum met" $ do
        now <- getCurrentTime
        let ceremony = mkCeremony OfficiantVRF Immediate 2 (pastTime now)
            existing = [ mkCommitment testParticipant1 Nothing now
                       , mkCommitment testParticipant2 Nothing now ]
        case transition ceremony existing [] (CheckDeadline now) of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Resolving
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

    describe "AwaitingReveals phase" $ do
      it "accepts a reveal from a committed participant" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ParticipantReveal Immediate 2 (futureTime now))
              { phase = AwaitingReveals }
            commitments = [ mkCommitment testParticipant1 (Just "seal1") now
                          , mkCommitment testParticipant2 (Just "seal2") now ]
        case transition ceremony commitments [] (SubmitReveal testParticipant1 "entropy1") of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` AwaitingReveals  -- 1/2 revealed
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "transitions to Resolving when all reveals are in (Method A)" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ParticipantReveal Immediate 2 (futureTime now))
              { phase = AwaitingReveals }
            commitments = [ mkCommitment testParticipant1 (Just "seal1") now
                          , mkCommitment testParticipant2 (Just "seal2") now ]
            alreadyRevealed = [testParticipant1]
        case transition ceremony commitments alreadyRevealed (SubmitReveal testParticipant2 "entropy2") of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Resolving
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "transitions to AwaitingBeacon when all reveals are in (Method D)" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony Combined Immediate 2 (futureTime now))
              { phase = AwaitingReveals }
            commitments = [ mkCommitment testParticipant1 (Just "seal1") now
                          , mkCommitment testParticipant2 (Just "seal2") now ]
            alreadyRevealed = [testParticipant1]
        case transition ceremony commitments alreadyRevealed (SubmitReveal testParticipant2 "entropy2") of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` AwaitingBeacon
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

      it "rejects reveal from non-committed participant" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ParticipantReveal Immediate 2 (futureTime now))
              { phase = AwaitingReveals }
            commitments = [mkCommitment testParticipant1 (Just "seal1") now]
        case transition ceremony commitments [] (SubmitReveal testParticipant2 "entropy") of
          Left (NotCommitted _) -> pure ()
          other -> expectationFailure $ "Expected NotCommitted, got: " ++ show other

      it "rejects duplicate reveal" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ParticipantReveal Immediate 2 (futureTime now))
              { phase = AwaitingReveals }
            commitments = [ mkCommitment testParticipant1 (Just "seal1") now
                          , mkCommitment testParticipant2 (Just "seal2") now ]
        case transition ceremony commitments [testParticipant1] (SubmitReveal testParticipant1 "entropy") of
          Left (AlreadyRevealed _) -> pure ()
          other -> expectationFailure $ "Expected AlreadyRevealed, got: " ++ show other

    describe "AwaitingBeacon phase" $ do
      it "transitions to Resolving when beacon is anchored" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony ExternalBeacon Immediate 2 (futureTime now))
              { phase = AwaitingBeacon }
            anchor = BeaconAnchor
              { baNetwork = "drand mainnet"
              , baRound = 12345
              , baValue = "beacon-value"
              , baSignature = "beacon-sig"
              , baFetchedAt = now
              }
        case transition ceremony [] [] (AnchorBeacon anchor) of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Resolving
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

    describe "Resolving phase" $ do
      it "transitions to Finalized when outcome is resolved" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony OfficiantVRF Immediate 2 (futureTime now))
              { phase = Resolving }
            outcome = Outcome
              { outcomeValue = CoinFlipResult True
              , combinedEntropy = "entropy"
              , outcomeProof = OutcomeProof [] "test"
              }
        case transition ceremony [] [] (ResolveOutcome outcome) of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Finalized
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

    describe "Terminal phases" $ do
      it "rejects actions on Finalized ceremonies" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony OfficiantVRF Immediate 2 (futureTime now))
              { phase = Finalized }
            commit = mkCommitment testParticipant1 Nothing now
        case transition ceremony [] [] (AddCommitment commit) of
          Left (InvalidPhase Finalized _) -> pure ()
          other -> expectationFailure $ "Expected InvalidPhase, got: " ++ show other

      it "allows dispute from non-terminal phase" $ do
        now <- getCurrentTime
        let ceremony = (mkCeremony OfficiantVRF Immediate 2 (futureTime now))
              { phase = Resolving }
        case transition ceremony [] [] (Dispute "verification failed") of
          Right TransitionResult{..} ->
            trNewPhase `shouldBe` Disputed
          Left err -> expectationFailure $ "Expected success, got: " ++ show err

    describe "isTerminal" $ do
      it "identifies terminal phases" $ do
        isTerminal Finalized `shouldBe` True
        isTerminal Expired `shouldBe` True
        isTerminal Cancelled `shouldBe` True
        isTerminal Disputed `shouldBe` True
        isTerminal Pending `shouldBe` False
        isTerminal AwaitingReveals `shouldBe` False
        isTerminal AwaitingBeacon `shouldBe` False
        isTerminal Resolving `shouldBe` False
