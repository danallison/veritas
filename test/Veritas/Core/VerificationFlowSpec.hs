-- | End-to-end test for the full verification flow:
-- Pool creation → member join → task assignment → verification → caching
module Veritas.Core.VerificationFlowSpec (spec) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Pool
import Veritas.Core.TaskAssignment
import Veritas.Core.Verification
import Veritas.Core.VerifiedCache
import Veritas.Pool.Types (AgentId(..), PoolId(..), ComparisonMethod(..))

-- === Fixtures ===

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

agentSubmitter, agentVal1, agentVal2, agentVal3, agentVal4 :: AgentId
agentSubmitter = AgentId (UUID.fromWords 1 0 0 0)
agentVal1 = AgentId (UUID.fromWords 2 0 0 0)
agentVal2 = AgentId (UUID.fromWords 3 0 0 0)
agentVal3 = AgentId (UUID.fromWords 4 0 0 0)
agentVal4 = AgentId (UUID.fromWords 5 0 0 0)

drandSeed :: BS.ByteString
drandSeed = BS.pack [1..32]

mkMember :: AgentId -> [Text] -> VolunteerMember
mkMember aid caps = VolunteerMember
  { vmAgentId = aid
  , vmPublicKey = BS.replicate 32 0
  , vmDisplayName = "Agent"
  , vmCapabilities = caps
  , vmStatus = Active
  , vmJoinedAt = epoch
  }

spec :: Spec
spec = do
  describe "Verification Flow (end-to-end)" $ do

    it "full happy path: pool → select → verify (unanimous) → cache" $ do
      -- Step 1: Create pool and add members
      let pool = VolunteerPool
            { vpId = PoolId UUID.nil
            , vpName = "AI Verification Pool"
            , vpDescription = "Cross-validates AI output"
            , vpTaskType = CrossValidation
            , vpSelectionSize = 2
            , vpMembers = []
            , vpCreatedAt = epoch
            }

      pool1 <- shouldSucceed $ addMember pool (mkMember agentSubmitter ["claude-sonnet"])
      pool2 <- shouldSucceed $ addMember pool1 (mkMember agentVal1 ["claude-sonnet"])
      pool3 <- shouldSucceed $ addMember pool2 (mkMember agentVal2 ["claude-sonnet"])
      pool4 <- shouldSucceed $ addMember pool3 (mkMember agentVal3 ["claude-sonnet"])
      pool5 <- shouldSucceed $ addMember pool4 (mkMember agentVal4 ["claude-sonnet"])

      poolReady pool5 `shouldBe` True
      length (activeMembers pool5) `shouldBe` 5

      -- Step 2: Select volunteers for verification task
      let taskSpec = TaskSpec "Verify Claude output" ["claude-sonnet"] 300
      volunteers <- shouldSucceed $ selectVolunteers pool5 taskSpec drandSeed
      length volunteers `shouldBe` 2

      -- Step 3: Create verification round
      -- In a real system, the submitter + selected validators participate
      let selectedIds = map vmAgentId volunteers
          -- For this test, submitter is agentSubmitter, validators are whoever was selected
          verif = Verification
            { vfId = VerificationId UUID.nil
            , vfPoolId = vpId pool5
            , vfSpec = VerificationSpec
                { vsDescription = "Verify: What is 2+2?"
                , vsComputationFingerprint = "sha256:abc123"
                , vsSubmittedResult = Just "4"
                , vsComparisonMethod = Exact
                , vsValidatorCount = 2
                }
            , vfSubmitter = agentSubmitter
            , vfValidators = selectedIds
            , vfSubmissions = []
            , vfPhase = Collecting
            , vfVerdict = Nothing
            , vfCreatedAt = epoch
            }

      -- Step 4: Everyone independently submits the same result (unanimous)
      v1 <- shouldSucceed $ recordSubmission verif agentSubmitter "4"
      v2 <- shouldSucceed $ recordSubmission v1 (selectedIds !! 0) "4"
      v3 <- shouldSucceed $ recordSubmission v2 (selectedIds !! 1) "4"

      vfPhase v3 `shouldBe` Deciding

      -- Step 5: Compute verdict
      v4 <- shouldSucceed $ computeVerdict v3 epoch
      vfPhase v4 `shouldBe` Decided
      case vfVerdict v4 of
        Just verdict -> do
          verdictOutcome verdict `shouldBe` Unanimous
          verdictAgreementCount verdict `shouldBe` 3
          isVerified verdict `shouldBe` True
        Nothing -> expectationFailure "Expected a verdict"

      -- Step 6: Cache the verified result
      let cache = cacheVerifiedResult emptyCache "sha256:abc123" "4"
                    (maybe (error "no verdict") id (vfVerdict v4))
                    Nothing
      cacheSize cache `shouldBe` 1
      case lookupCache cache "sha256:abc123" of
        Just entry -> do
          ceResult entry `shouldBe` "4"
          ceVerdictOutcome (ceProvenance entry) `shouldBe` Unanimous
        Nothing -> expectationFailure "Expected cache entry"

    it "full path with majority agreement: dissenter identified" $ do
      let pool = VolunteerPool
            { vpId = PoolId UUID.nil
            , vpName = "Test Pool"
            , vpDescription = ""
            , vpTaskType = CrossValidation
            , vpSelectionSize = 2
            , vpMembers = map (\a -> mkMember a []) [agentVal1, agentVal2, agentVal3, agentVal4]
            , vpCreatedAt = epoch
            }

      volunteers <- shouldSucceed $ selectVolunteers pool (TaskSpec "test" [] 300) drandSeed
      let selectedIds = map vmAgentId volunteers
          verif = Verification
            { vfId = VerificationId UUID.nil
            , vfPoolId = vpId pool
            , vfSpec = VerificationSpec "test" "fp:xyz" (Just "correct") Exact 2
            , vfSubmitter = agentSubmitter
            , vfValidators = selectedIds
            , vfSubmissions = []
            , vfPhase = Collecting
            , vfVerdict = Nothing
            , vfCreatedAt = epoch
            }

      -- Submitter and one validator agree, one dissents
      v1 <- shouldSucceed $ recordSubmission verif agentSubmitter "correct"
      v2 <- shouldSucceed $ recordSubmission v1 (selectedIds !! 0) "correct"
      v3 <- shouldSucceed $ recordSubmission v2 (selectedIds !! 1) "wrong-answer"

      v4 <- shouldSucceed $ computeVerdict v3 epoch
      case vfVerdict v4 of
        Just verdict -> do
          verdictAgreementCount verdict `shouldBe` 2
          isVerified verdict `shouldBe` True
          -- The dissenter should be identified
          case verdictOutcome verdict of
            MajorityAgree dissenters -> dissenters `shouldBe` [selectedIds !! 1]
            other -> expectationFailure ("Expected MajorityAgree, got " <> show other)
        Nothing -> expectationFailure "Expected a verdict"

    it "inconclusive result: all disagree, nothing cached" $ do
      let verif = Verification
            { vfId = VerificationId UUID.nil
            , vfPoolId = PoolId UUID.nil
            , vfSpec = VerificationSpec "test" "fp:bad" Nothing Exact 2
            , vfSubmitter = agentSubmitter
            , vfValidators = [agentVal1, agentVal2]
            , vfSubmissions = []
            , vfPhase = Collecting
            , vfVerdict = Nothing
            , vfCreatedAt = epoch
            }

      v1 <- shouldSucceed $ recordSubmission verif agentSubmitter "result-A"
      v2 <- shouldSucceed $ recordSubmission v1 agentVal1 "result-B"
      v3 <- shouldSucceed $ recordSubmission v2 agentVal2 "result-C"
      v4 <- shouldSucceed $ computeVerdict v3 epoch

      case vfVerdict v4 of
        Just verdict -> do
          verdictOutcome verdict `shouldBe` Inconclusive
          isVerified verdict `shouldBe` False
          -- Should NOT be cached
          let cache = cacheVerifiedResult emptyCache "fp:bad" "result-A" verdict Nothing
          cacheSize cache `shouldBe` 0
        Nothing -> expectationFailure "Expected a verdict"

-- | Helper: unwrap Right or fail test
shouldSucceed :: Show e => Either e a -> IO a
shouldSucceed (Right a) = pure a
shouldSucceed (Left e) = do
  expectationFailure ("Expected Right, got Left: " <> show e)
  error "unreachable"
