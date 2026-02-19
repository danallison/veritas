module Veritas.Core.RevealSpec (spec) where

import Data.ByteString (ByteString)
import Data.Either (isLeft)
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Types
import Veritas.Core.StateMachine
import Veritas.Core.Entropy (verifySealForReveal, buildEntropyContributions)
import Veritas.Core.Resolution (resolve)
import Veritas.Crypto.CommitReveal (createSeal, defaultEntropyValue)
import Veritas.API.Handlers (validateTwoPartySafety, validateMethodParams)

-- Test helpers
testCeremonyId :: CeremonyId
testCeremonyId = CeremonyId UUID.nil

testParticipant1 :: ParticipantId
testParticipant1 = ParticipantId (UUID.fromWords 1 0 0 0)

testParticipant2 :: ParticipantId
testParticipant2 = ParticipantId (UUID.fromWords 2 0 0 0)

testParticipant3 :: ParticipantId
testParticipant3 = ParticipantId (UUID.fromWords 3 0 0 0)

futureTime :: UTCTime -> UTCTime
futureTime = addUTCTime 3600

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
  describe "Two-party safety check" $ do
    it "rejects DefaultSubstitution for 2-party ceremonies" $ do
      validateTwoPartySafety 2 (Just DefaultSubstitution)
        `shouldBe` Left "DefaultSubstitution is not allowed for 2-party ceremonies: one party would control the outcome"

    it "allows DefaultSubstitution for 3+ party ceremonies" $ do
      validateTwoPartySafety 3 (Just DefaultSubstitution) `shouldBe` Right ()
      validateTwoPartySafety 5 (Just DefaultSubstitution) `shouldBe` Right ()

    it "allows Exclusion for 2-party ceremonies" $ do
      validateTwoPartySafety 2 (Just Exclusion) `shouldBe` Right ()

    it "allows Cancellation for 2-party ceremonies" $ do
      validateTwoPartySafety 2 (Just Cancellation) `shouldBe` Right ()

    it "allows no policy for 2-party ceremonies" $ do
      validateTwoPartySafety 2 Nothing `shouldBe` Right ()

  describe "Method parameter validation" $ do
    it "requires reveal_deadline for ParticipantReveal" $ do
      validateMethodParams ParticipantReveal Nothing (Just Cancellation)
        `shouldSatisfy` isLeft

    it "requires non_participation_policy for ParticipantReveal" $ do
      now <- getCurrentTime
      validateMethodParams ParticipantReveal (Just (futureTime now)) Nothing
        `shouldSatisfy` isLeft

    it "accepts valid ParticipantReveal params" $ do
      now <- getCurrentTime
      validateMethodParams ParticipantReveal (Just (futureTime now)) (Just Cancellation)
        `shouldBe` Right ()

    it "requires reveal_deadline for Combined" $ do
      validateMethodParams Combined Nothing (Just Cancellation)
        `shouldSatisfy` isLeft

    it "accepts valid Combined params" $ do
      now <- getCurrentTime
      validateMethodParams Combined (Just (futureTime now)) (Just Exclusion)
        `shouldBe` Right ()

    it "rejects reveal_deadline for ExternalBeacon" $ do
      now <- getCurrentTime
      validateMethodParams ExternalBeacon (Just (futureTime now)) Nothing
        `shouldSatisfy` isLeft

    it "rejects non_participation_policy for OfficiantVRF" $ do
      validateMethodParams OfficiantVRF Nothing (Just Cancellation)
        `shouldSatisfy` isLeft

    it "accepts ExternalBeacon with no reveal params" $ do
      validateMethodParams ExternalBeacon Nothing Nothing
        `shouldBe` Right ()

    it "accepts OfficiantVRF with no reveal params" $ do
      validateMethodParams OfficiantVRF Nothing Nothing
        `shouldBe` Right ()

  describe "Seal verification" $ do
    it "correct seal verifies successfully" $ do
      let entropy = "my-secret-entropy"
          seal = createSeal testCeremonyId testParticipant1 entropy
      verifySealForReveal testCeremonyId testParticipant1 entropy seal `shouldBe` True

    it "wrong entropy value fails seal verification" $ do
      let entropy = "my-secret-entropy"
          wrong = "different-entropy"
          seal = createSeal testCeremonyId testParticipant1 entropy
      verifySealForReveal testCeremonyId testParticipant1 wrong seal `shouldBe` False

    it "wrong participant fails seal verification" $ do
      let entropy = "my-secret-entropy"
          seal = createSeal testCeremonyId testParticipant1 entropy
      verifySealForReveal testCeremonyId testParticipant2 entropy seal `shouldBe` False

  describe "Full Method A lifecycle" $ do
    it "create → commit with seals → reveal → resolve" $ do
      now <- getCurrentTime
      let ceremony0 = mkCeremony ParticipantReveal Immediate 2 (futureTime now)

      -- Participant 1 commits with seal
      let entropy1 = "entropy-from-participant-1"
          seal1 = createSeal testCeremonyId testParticipant1 entropy1
          commit1 = mkCommitment testParticipant1 (Just seal1) now

      case transition ceremony0 [] [] (AddCommitment commit1) of
        Left err -> expectationFailure $ "Commit 1 failed: " ++ show err
        Right TransitionResult{..} -> do
          trNewPhase `shouldBe` Pending  -- 1/2

          -- Participant 2 commits with seal
          let entropy2 = "entropy-from-participant-2"
              seal2 = createSeal testCeremonyId testParticipant2 entropy2
              commit2 = mkCommitment testParticipant2 (Just seal2) now

          case transition ceremony0 [commit1] [] (AddCommitment commit2) of
            Left err -> expectationFailure $ "Commit 2 failed: " ++ show err
            Right TransitionResult{..} -> do
              trNewPhase `shouldBe` AwaitingReveals

              let ceremony1 = ceremony0 { phase = AwaitingReveals }
                  commitments = [commit1, commit2]

              -- Verify seals before revealing
              verifySealForReveal testCeremonyId testParticipant1 entropy1 seal1 `shouldBe` True
              verifySealForReveal testCeremonyId testParticipant2 entropy2 seal2 `shouldBe` True

              -- Participant 1 reveals
              case transition ceremony1 commitments [] (SubmitReveal testParticipant1 entropy1) of
                Left err -> expectationFailure $ "Reveal 1 failed: " ++ show err
                Right TransitionResult{..} -> do
                  trNewPhase `shouldBe` AwaitingReveals  -- 1/2 revealed

                  -- Participant 2 reveals
                  case transition ceremony1 commitments [testParticipant1] (SubmitReveal testParticipant2 entropy2) of
                    Left err -> expectationFailure $ "Reveal 2 failed: " ++ show err
                    Right TransitionResult{..} -> do
                      trNewPhase `shouldBe` Resolving

                      -- Build contributions and resolve
                      let contributions = buildEntropyContributions testCeremonyId
                            [(testParticipant1, entropy1), (testParticipant2, entropy2)]
                          outcome = resolve CoinFlip contributions

                      -- Verify outcome is deterministic
                      let outcome2 = resolve CoinFlip contributions
                      outcomeValue outcome `shouldBe` outcomeValue outcome2
                      combinedEntropy outcome `shouldBe` combinedEntropy outcome2

    it "rejects reveal with wrong entropy (seal mismatch detected at application level)" $ do
      let entropy = "my-secret-entropy"
          wrong = "wrong-entropy"
          seal = createSeal testCeremonyId testParticipant1 entropy
      -- At the application level, the handler checks the seal
      verifySealForReveal testCeremonyId testParticipant1 wrong seal `shouldBe` False

  describe "Default entropy substitution" $ do
    it "default values are deterministic" $ do
      let d1 = defaultEntropyValue testCeremonyId testParticipant1
          d2 = defaultEntropyValue testCeremonyId testParticipant1
      d1 `shouldBe` d2

    it "default values differ between participants" $ do
      let d1 = defaultEntropyValue testCeremonyId testParticipant1
          d2 = defaultEntropyValue testCeremonyId testParticipant2
      d1 `shouldNotBe` d2

    it "3-party ceremony with default substitution resolves" $ do
      now <- getCurrentTime
      let ceremony0 = (mkCeremony ParticipantReveal Immediate 3 (futureTime now))
            { nonParticipationPolicy = Just DefaultSubstitution }

      -- All 3 commit
      let entropy1 = "entropy-1"
          entropy2 = "entropy-2"
          seal1 = createSeal testCeremonyId testParticipant1 entropy1
          seal2 = createSeal testCeremonyId testParticipant2 entropy2
          -- Participant 3 will not reveal, so their seal doesn't matter for the test
          seal3 = createSeal testCeremonyId testParticipant3 "entropy-3"
          commit1 = mkCommitment testParticipant1 (Just seal1) now
          commit2 = mkCommitment testParticipant2 (Just seal2) now
          commit3 = mkCommitment testParticipant3 (Just seal3) now
          commitments = [commit1, commit2, commit3]

      -- After quorum, phase moves to AwaitingReveals
      case transition ceremony0 [commit1, commit2] [] (AddCommitment commit3) of
        Left err -> expectationFailure $ "Commit 3 failed: " ++ show err
        Right TransitionResult{..} -> do
          trNewPhase `shouldBe` AwaitingReveals

          let ceremony1 = ceremony0 { phase = AwaitingReveals }

          -- Participants 1 and 2 reveal, but 3 doesn't
          -- Simulate what the worker would do: apply DefaultSubstitution for participant 3
          let defVal3 = defaultEntropyValue testCeremonyId testParticipant3
              entries = [ NonParticipationEntry
                            { npeParticipant = testParticipant3
                            , npePolicyApplied = DefaultSubstitution
                            , npeSubstitutedValue = Just defVal3
                            }
                        ]

          -- After reveals from 1 and 2 (simulated), apply non-participation
          case transition ceremony1 commitments [testParticipant1, testParticipant2, testParticipant3]
                 (ApplyNonParticipation entries) of
            Left err -> expectationFailure $ "ApplyNonParticipation failed: " ++ show err
            Right TransitionResult{..} -> do
              trNewPhase `shouldBe` Resolving

              -- Resolve with actual reveals + default
              let contributions = buildEntropyContributions testCeremonyId
                    [ (testParticipant1, entropy1)
                    , (testParticipant2, entropy2)
                    , (testParticipant3, defVal3)
                    ]
                  outcome = resolve CoinFlip contributions

              -- Outcome should be deterministic
              let outcome2 = resolve CoinFlip contributions
              outcomeValue outcome `shouldBe` outcomeValue outcome2
