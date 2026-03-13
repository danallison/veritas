module Veritas.Core.TaskAssignmentSpec (spec) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Pool
import Veritas.Core.TaskAssignment
import Veritas.Pool.Types (AgentId(..), PoolId(..))

-- === Test fixtures ===

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

agent1, agent2, agent3, agent4, agent5 :: AgentId
agent1 = AgentId (UUID.fromWords 1 0 0 0)
agent2 = AgentId (UUID.fromWords 2 0 0 0)
agent3 = AgentId (UUID.fromWords 3 0 0 0)
agent4 = AgentId (UUID.fromWords 4 0 0 0)
agent5 = AgentId (UUID.fromWords 5 0 0 0)

testSeed :: BS.ByteString
testSeed = BS.pack [1..32]

testSeed2 :: BS.ByteString
testSeed2 = BS.pack [33..64]

mkTestPool :: Natural -> [VolunteerMember] -> VolunteerPool
mkTestPool selectionSize members = VolunteerPool
  { vpId = PoolId UUID.nil
  , vpName = "Test Pool"
  , vpDescription = "A test volunteer pool"
  , vpTaskType = CrossValidation
  , vpSelectionSize = selectionSize
  , vpMembers = members
  , vpCreatedAt = epoch
  }

mkMember :: AgentId -> [Text] -> VolunteerMember
mkMember aid caps = VolunteerMember
  { vmAgentId = aid
  , vmPublicKey = BS.replicate 32 (fromIntegral (UUID.toWords (unAgentId aid) & fst4))
  , vmDisplayName = "Agent"
  , vmCapabilities = caps
  , vmStatus = Active
  , vmJoinedAt = epoch
  }
  where
    fst4 (a, _, _, _) = a
    (&) x f = f x

mkTaskSpec :: Text -> TaskSpec
mkTaskSpec desc = TaskSpec
  { tsDescription = desc
  , tsRequiredCapabilities = []
  , tsDeadlineSeconds = 300
  }

mkTaskSpecWithCaps :: Text -> [Text] -> TaskSpec
mkTaskSpecWithCaps desc caps = TaskSpec
  { tsDescription = desc
  , tsRequiredCapabilities = caps
  , tsDeadlineSeconds = 300
  }

-- === Specs ===

spec :: Spec
spec = do
  describe "Task Assignment" $ do
    describe "selectVolunteers" $ do
      it "selects the requested number of volunteers" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3, agent4, agent5]
            pool = mkTestPool 3 members
        case selectVolunteers pool (mkTaskSpec "test") testSeed of
          Right selected -> length selected `shouldBe` 3
          Left e -> expectationFailure (show e)

      it "returns error when pool has too few active members" $ do
        let members = [mkMember agent1 []]
            pool = mkTestPool 3 members
        case selectVolunteers pool (mkTaskSpec "test") testSeed of
          Left (InsufficientVolunteers 3 1) -> pure ()
          other -> expectationFailure ("Expected InsufficientVolunteers, got " <> show other)

      it "selection is deterministic given same seed" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3, agent4, agent5]
            pool = mkTestPool 2 members
        case (selectVolunteers pool (mkTaskSpec "test") testSeed,
              selectVolunteers pool (mkTaskSpec "test") testSeed) of
          (Right s1, Right s2) ->
            map vmAgentId s1 `shouldBe` map vmAgentId s2
          (Left e, _) -> expectationFailure (show e)
          (_, Left e) -> expectationFailure (show e)

      it "different seeds produce different selections" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3, agent4, agent5]
            pool = mkTestPool 2 members
        case (selectVolunteers pool (mkTaskSpec "test") testSeed,
              selectVolunteers pool (mkTaskSpec "test") testSeed2) of
          (Right s1, Right s2) ->
            -- With 5 members choosing 2, different seeds should usually differ
            -- (probabilistically; very unlikely to be same)
            map vmAgentId s1 `shouldNotBe` map vmAgentId s2
          (Left e, _) -> expectationFailure (show e)
          (_, Left e) -> expectationFailure (show e)

      it "only selects from active members" $ do
        let m1 = mkMember agent1 []
            m2 = (mkMember agent2 []) { vmStatus = Suspended }
            m3 = (mkMember agent3 []) { vmStatus = Withdrawn }
            m4 = mkMember agent4 []
            m5 = mkMember agent5 []
            pool = mkTestPool 2 [m1, m2, m3, m4, m5]
        case selectVolunteers pool (mkTaskSpec "test") testSeed of
          Right selected -> do
            length selected `shouldBe` 2
            all (\m -> vmStatus m == Active) selected `shouldBe` True
            -- agent2 and agent3 should never be selected
            all (\m -> vmAgentId m `notElem` [agent2, agent3]) selected `shouldBe` True
          Left e -> expectationFailure (show e)

      it "filters by required capabilities" $ do
        let m1 = mkMember agent1 ["claude-sonnet", "python"]
            m2 = mkMember agent2 ["gpt-4"]
            m3 = mkMember agent3 ["claude-sonnet", "python", "node"]
            m4 = mkMember agent4 ["claude-sonnet"]
            m5 = mkMember agent5 ["claude-sonnet", "python"]
            pool = mkTestPool 2 [m1, m2, m3, m4, m5]
            taskSpec = mkTaskSpecWithCaps "test" ["claude-sonnet", "python"]
        case selectVolunteers pool taskSpec testSeed of
          Right selected -> do
            length selected `shouldBe` 2
            -- Only agent1, agent3, agent5 have both capabilities
            all (\m -> vmAgentId m `elem` [agent1, agent3, agent5]) selected `shouldBe` True
          Left e -> expectationFailure (show e)

      it "returns error when not enough capable members" $ do
        let m1 = mkMember agent1 ["claude-sonnet"]
            m2 = mkMember agent2 ["gpt-4"]
            pool = mkTestPool 2 [m1, m2]
            taskSpec = mkTaskSpecWithCaps "test" ["claude-sonnet", "python"]
        case selectVolunteers pool taskSpec testSeed of
          Left (InsufficientVolunteers 2 0) -> pure ()
          other -> expectationFailure ("Expected InsufficientVolunteers, got " <> show other)

    describe "createTaskAssignment" $ do
      it "creates an assignment in Selecting status" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskSpec = mkTaskSpec "verify output"
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId taskSpec testSeed 42 of
          Right assignment -> do
            taStatus assignment `shouldBe` Assigned
            length (taSelected assignment) `shouldBe` 2
            taBeaconRound assignment `shouldBe` 42
            taSelectionSeed assignment `shouldBe` testSeed
          Left e -> expectationFailure (show e)

      it "fails when pool is too small" $ do
        let members = [mkMember agent1 []]
            pool = mkTestPool 3 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Left (InsufficientVolunteers _ _) -> pure ()
          other -> expectationFailure ("Expected InsufficientVolunteers, got " <> show other)

      it "selected agents match selectVolunteers output" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3, agent4, agent5]
            pool = mkTestPool 2 members
            taskSpec = mkTaskSpec "test"
            taskId = TaskId UUID.nil
        case (selectVolunteers pool taskSpec testSeed,
              createTaskAssignment pool taskId taskSpec testSeed 42) of
          (Right volunteers, Right assignment) ->
            map vmAgentId volunteers `shouldBe` taSelected assignment
          (Left e, _) -> expectationFailure (show e)
          (_, Left e) -> expectationFailure (show e)

    describe "TaskAssignment status transitions" $ do
      it "transitions from Assigned to InProgress" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case startTask assignment of
              Right assignment' -> taStatus assignment' `shouldBe` InProgress
              Left e -> expectationFailure (show e)
          Left e -> expectationFailure (show e)

      it "transitions from InProgress to Complete" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case startTask assignment >>= completeTask of
              Right assignment' -> taStatus assignment' `shouldBe` Complete
              Left e -> expectationFailure (show e)
          Left e -> expectationFailure (show e)

      it "transitions from InProgress to Failed" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case startTask assignment >>= \a -> failTask a "timeout" of
              Right assignment' -> do
                taStatus assignment' `shouldBe` TaskFailed
                taFailureReason assignment' `shouldBe` Just "timeout"
              Left e -> expectationFailure (show e)
          Left e -> expectationFailure (show e)

      it "rejects starting an already-started task" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case startTask assignment >>= startTask of
              Left (InvalidTransition InProgress InProgress) -> pure ()
              other -> expectationFailure ("Expected InvalidTransition, got " <> show other)
          Left e -> expectationFailure (show e)

      it "rejects completing an Assigned task" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case completeTask assignment of
              Left (InvalidTransition Assigned Complete) -> pure ()
              other -> expectationFailure ("Expected InvalidTransition, got " <> show other)
          Left e -> expectationFailure (show e)

      it "rejects failing a completed task" $ do
        let members = map (\a -> mkMember a []) [agent1, agent2, agent3]
            pool = mkTestPool 2 members
            taskId = TaskId UUID.nil
        case createTaskAssignment pool taskId (mkTaskSpec "test") testSeed 42 of
          Right assignment ->
            case startTask assignment >>= completeTask >>= \a -> failTask a "oops" of
              Left (InvalidTransition Complete TaskFailed) -> pure ()
              other -> expectationFailure ("Expected InvalidTransition, got " <> show other)
          Left e -> expectationFailure (show e)
