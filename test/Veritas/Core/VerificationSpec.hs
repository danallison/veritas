module Veritas.Core.VerificationSpec (spec) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Verification
import Veritas.Pool.Types (AgentId(..), PoolId(..), ComparisonMethod(..))

-- === Test fixtures ===

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

agent1, agent2, agent3 :: AgentId
agent1 = AgentId (UUID.fromWords 1 0 0 0)
agent2 = AgentId (UUID.fromWords 2 0 0 0)
agent3 = AgentId (UUID.fromWords 3 0 0 0)

verificationId :: VerificationId
verificationId = VerificationId UUID.nil

mkVerification :: VerificationPhase -> [(AgentId, BS.ByteString)] -> Verification
mkVerification vPhase submissions = Verification
  { vfId = verificationId
  , vfPoolId = PoolId UUID.nil
  , vfSpec = VerificationSpec
      { vsDescription = "Test verification"
      , vsComputationFingerprint = "abc123"
      , vsSubmittedResult = Just "expected-result"
      , vsComparisonMethod = Exact
      , vsValidatorCount = 2
      }
  , vfSubmitter = agent1
  , vfValidators = [agent2, agent3]
  , vfSubmissions = submissions
  , vfPhase = vPhase
  , vfVerdict = Nothing
  , vfCreatedAt = epoch
  }

-- === Specs ===

spec :: Spec
spec = do
  describe "Verification" $ do
    describe "VerificationSpec" $ do
      it "captures all required fields" $ do
        let spec' = VerificationSpec
              { vsDescription = "Verify Claude output"
              , vsComputationFingerprint = "sha256:abcdef"
              , vsSubmittedResult = Just "the answer is 42"
              , vsComparisonMethod = Exact
              , vsValidatorCount = 2
              }
        vsValidatorCount spec' `shouldBe` 2
        vsComparisonMethod spec' `shouldBe` Exact

    describe "recordSubmission" $ do
      it "records a validator's result" $ do
        let v = mkVerification Collecting []
        case recordSubmission v agent2 "result-bytes" of
          Right v' -> length (vfSubmissions v') `shouldBe` 1
          Left e -> expectationFailure (show e)

      it "rejects submission from non-validator" $ do
        let v = mkVerification Collecting []
            nonValidator = AgentId (UUID.fromWords 99 0 0 0)
        case recordSubmission v nonValidator "result" of
          Left (NotAValidator _) -> pure ()
          other -> expectationFailure ("Expected NotAValidator, got " <> show other)

      it "rejects duplicate submission" $ do
        let v = mkVerification Collecting [(agent2, "result")]
        case recordSubmission v agent2 "result2" of
          Left (AlreadySubmitted _) -> pure ()
          other -> expectationFailure ("Expected AlreadySubmitted, got " <> show other)

      it "rejects submission in wrong phase" $ do
        let v = mkVerification Decided []
        case recordSubmission v agent2 "result" of
          Left (WrongPhase _ _) -> pure ()
          other -> expectationFailure ("Expected WrongPhase, got " <> show other)

      it "transitions to Deciding when all submissions are in" $ do
        let v = mkVerification Collecting [(agent1, "result0"), (agent2, "result1")]
        case recordSubmission v agent3 "result2" of
          Right v' -> vfPhase v' `shouldBe` Deciding
          Left e -> expectationFailure (show e)

    describe "computeVerdict" $ do
      it "returns Unanimous when all results match" $ do
        let submissions =
              [ (agent1, "same-result")
              , (agent2, "same-result")
              , (agent3, "same-result")
              ]
            v = mkVerification Deciding submissions
        case computeVerdict v epoch of
          Right v' -> do
            vfPhase v' `shouldBe` Decided
            case vfVerdict v' of
              Just verdict -> do
                verdictOutcome verdict `shouldBe` Unanimous
                verdictAgreementCount verdict `shouldBe` 3
              Nothing -> expectationFailure "Expected verdict"
          Left e -> expectationFailure (show e)

      it "returns MajorityAgree when 2/3 match" $ do
        let submissions =
              [ (agent1, "majority-result")
              , (agent2, "majority-result")
              , (agent3, "different-result")
              ]
            v = mkVerification Deciding submissions
        case computeVerdict v epoch of
          Right v' -> do
            vfPhase v' `shouldBe` Decided
            case vfVerdict v' of
              Just verdict -> do
                verdictOutcome verdict `shouldBe` MajorityAgree [agent3]
                verdictAgreementCount verdict `shouldBe` 2
                verdictMajorityResult verdict `shouldBe` Just "majority-result"
              Nothing -> expectationFailure "Expected verdict"
          Left e -> expectationFailure (show e)

      it "returns Inconclusive when all differ" $ do
        let submissions =
              [ (agent1, "result-1")
              , (agent2, "result-2")
              , (agent3, "result-3")
              ]
            v = mkVerification Deciding submissions
        case computeVerdict v epoch of
          Right v' -> do
            vfPhase v' `shouldBe` Decided
            case vfVerdict v' of
              Just verdict -> do
                verdictOutcome verdict `shouldBe` Inconclusive
                verdictAgreementCount verdict `shouldBe` 1
              Nothing -> expectationFailure "Expected verdict"
          Left e -> expectationFailure (show e)

      it "rejects verdict computation in wrong phase" $ do
        let v = mkVerification Collecting []
        case computeVerdict v epoch of
          Left (WrongPhase _ _) -> pure ()
          other -> expectationFailure ("Expected WrongPhase, got " <> show other)

      it "rejects verdict when not all submitted" $ do
        let v = mkVerification Deciding [(agent2, "result")]
        case computeVerdict v epoch of
          Left NotAllSubmitted -> pure ()
          other -> expectationFailure ("Expected NotAllSubmitted, got " <> show other)

    describe "Verdict properties" $ do
      it "Unanimous verdict includes submitter in agreement" $ do
        -- When submitter and all validators agree, it's unanimous
        let submissions =
              [ (agent1, "agreed")   -- submitter
              , (agent2, "agreed")   -- validator
              , (agent3, "agreed")   -- validator
              ]
            v = mkVerification Deciding submissions
        case computeVerdict v epoch of
          Right v' -> case vfVerdict v' of
            Just verdict -> verdictAgreementCount verdict `shouldBe` 3
            Nothing -> expectationFailure "Expected verdict"
          Left e -> expectationFailure (show e)

      it "identifies the correct dissenter" $ do
        let submissions =
              [ (agent1, "consensus")
              , (agent2, "dissent")
              , (agent3, "consensus")
              ]
            v = mkVerification Deciding submissions
        case computeVerdict v epoch of
          Right v' -> case vfVerdict v' of
            Just verdict -> verdictOutcome verdict `shouldBe` MajorityAgree [agent2]
            Nothing -> expectationFailure "Expected verdict"
          Left e -> expectationFailure (show e)

    describe "isVerified" $ do
      it "returns True for Unanimous verdict" $ do
        let verdict = Verdict Unanimous 3 (Just "result") epoch
        isVerified verdict `shouldBe` True

      it "returns True for Majority verdict" $ do
        let verdict = Verdict (MajorityAgree [agent3]) 2 (Just "result") epoch
        isVerified verdict `shouldBe` True

      it "returns False for Inconclusive verdict" $ do
        let verdict = Verdict Inconclusive 1 Nothing epoch
        isVerified verdict `shouldBe` False
