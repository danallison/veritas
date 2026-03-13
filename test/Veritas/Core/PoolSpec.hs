module Veritas.Core.PoolSpec (spec) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as Data.Text
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Core.Pool
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

mkTestPool :: Natural -> VolunteerPool
mkTestPool selectionSize = VolunteerPool
  { vpId = PoolId UUID.nil
  , vpName = "Test Pool"
  , vpDescription = "A test volunteer pool"
  , vpTaskType = CrossValidation
  , vpSelectionSize = selectionSize
  , vpMembers = []
  , vpCreatedAt = epoch
  }

mkMember :: AgentId -> [Text] -> VolunteerMember
mkMember aid caps = VolunteerMember
  { vmAgentId = aid
  , vmPublicKey = BS.replicate 32 0
  , vmDisplayName = "Agent " <> tshow (unAgentId aid)
  , vmCapabilities = caps
  , vmStatus = Active
  , vmJoinedAt = epoch
  }
  where
    tshow :: Show a => a -> Text
    tshow = Data.Text.pack . show

-- === Specs ===

spec :: Spec
spec = do
  describe "Volunteer Pool" $ do
    describe "addMember" $ do
      it "adds a member to an empty pool" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 ["claude-sonnet"]
        case addMember pool member of
          Right pool' -> length (vpMembers pool') `shouldBe` 1
          Left e -> expectationFailure (show e)

      it "adds multiple members" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 ["claude-sonnet"]
            m2 = mkMember agent2 ["gpt-4"]
        case addMember pool m1 >>= \p -> addMember p m2 of
          Right pool' -> length (vpMembers pool') `shouldBe` 2
          Left e -> expectationFailure (show e)

      it "rejects duplicate agent" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 ["claude-sonnet"]
        case addMember pool member >>= \p -> addMember p member of
          Left (MemberAlreadyJoined _) -> pure ()
          other -> expectationFailure ("Expected MemberAlreadyJoined, got " <> show other)

      it "rejects adding a member with Withdrawn status" $ do
        let pool = mkTestPool 2
            member = (mkMember agent1 []) { vmStatus = Withdrawn }
        case addMember pool member of
          Left (MemberNotActive _) -> pure ()
          other -> expectationFailure ("Expected MemberNotActive, got " <> show other)

    describe "removeMember" $ do
      it "sets member status to Withdrawn" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 ["claude-sonnet"]
        case addMember pool member >>= \p -> removeMember p agent1 of
          Right pool' -> do
            let m = findMember pool' agent1
            fmap vmStatus m `shouldBe` Just Withdrawn
          Left e -> expectationFailure (show e)

      it "rejects removing non-existent member" $ do
        let pool = mkTestPool 2
        case removeMember pool agent1 of
          Left (MemberNotFound _) -> pure ()
          other -> expectationFailure ("Expected MemberNotFound, got " <> show other)

      it "rejects removing an already withdrawn member" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member
             >>= \p -> removeMember p agent1
             >>= \p -> removeMember p agent1 of
          Left (MemberAlreadyWithdrawn _) -> pure ()
          other -> expectationFailure ("Expected MemberAlreadyWithdrawn, got " <> show other)

    describe "suspendMember" $ do
      it "sets member status to Suspended" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member >>= \p -> suspendMember p agent1 of
          Right pool' -> do
            let m = findMember pool' agent1
            fmap vmStatus m `shouldBe` Just Suspended
          Left e -> expectationFailure (show e)

      it "rejects suspending non-existent member" $ do
        let pool = mkTestPool 2
        case suspendMember pool agent1 of
          Left (MemberNotFound _) -> pure ()
          other -> expectationFailure ("Expected MemberNotFound, got " <> show other)

      it "rejects suspending an already suspended member" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member
             >>= \p -> suspendMember p agent1
             >>= \p -> suspendMember p agent1 of
          Left (MemberAlreadySuspended _) -> pure ()
          other -> expectationFailure ("Expected MemberAlreadySuspended, got " <> show other)

      it "rejects suspending a withdrawn member" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member
             >>= \p -> removeMember p agent1
             >>= \p -> suspendMember p agent1 of
          Left (MemberNotActive _) -> pure ()
          other -> expectationFailure ("Expected MemberNotActive, got " <> show other)

    describe "reactivateMember" $ do
      it "reactivates a suspended member" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member
             >>= \p -> suspendMember p agent1
             >>= \p -> reactivateMember p agent1 of
          Right pool' -> do
            let m = findMember pool' agent1
            fmap vmStatus m `shouldBe` Just Active
          Left e -> expectationFailure (show e)

      it "rejects reactivating an already active member" $ do
        let pool = mkTestPool 2
            member = mkMember agent1 []
        case addMember pool member >>= \p -> reactivateMember p agent1 of
          Left (MemberAlreadyActive _) -> pure ()
          other -> expectationFailure ("Expected MemberAlreadyActive, got " <> show other)

    describe "activeMembers" $ do
      it "returns only active members" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 []
            m2 = mkMember agent2 []
            m3 = mkMember agent3 []
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> addMember p m3
             >>= \p -> suspendMember p agent2 of
          Right pool' -> length (activeMembers pool') `shouldBe` 2
          Left e -> expectationFailure (show e)

      it "excludes withdrawn members" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 []
            m2 = mkMember agent2 []
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> removeMember p agent1 of
          Right pool' -> do
            length (activeMembers pool') `shouldBe` 1
            vmAgentId (head (activeMembers pool')) `shouldBe` agent2
          Left e -> expectationFailure (show e)

    describe "TaskType" $ do
      it "supports CrossValidation type" $ do
        let pool = mkTestPool 2
        vpTaskType pool `shouldBe` CrossValidation

      it "supports CustomTask type" $ do
        let pool = (mkTestPool 2) { vpTaskType = CustomTask "code-review" }
        vpTaskType pool `shouldBe` CustomTask "code-review"

    describe "poolReady" $ do
      it "returns True when pool has enough active members for selection" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 []
            m2 = mkMember agent2 []
            m3 = mkMember agent3 []
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> addMember p m3 of
          Right pool' -> poolReady pool' `shouldBe` True
          Left e -> expectationFailure (show e)

      it "returns False when not enough active members" $ do
        let pool = mkTestPool 3
            m1 = mkMember agent1 []
        case addMember pool m1 of
          Right pool' -> poolReady pool' `shouldBe` False
          Left e -> expectationFailure (show e)

      it "only counts active members toward readiness" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 []
            m2 = mkMember agent2 []
            m3 = mkMember agent3 []
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> addMember p m3
             >>= \p -> suspendMember p agent2
             >>= \p -> removeMember p agent3 of
          Right pool' -> poolReady pool' `shouldBe` False
          Left e -> expectationFailure (show e)

    describe "filterByCapabilities" $ do
      it "returns members with all required capabilities" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 ["claude-sonnet", "python"]
            m2 = mkMember agent2 ["gpt-4"]
            m3 = mkMember agent3 ["claude-sonnet", "python", "node"]
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> addMember p m3 of
          Right pool' -> do
            let filtered = filterByCapabilities pool' ["claude-sonnet", "python"]
            length filtered `shouldBe` 2
            map vmAgentId filtered `shouldBe` [agent1, agent3]
          Left e -> expectationFailure (show e)

      it "returns all active members when no capabilities required" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 ["claude-sonnet"]
            m2 = mkMember agent2 []
        case addMember pool m1 >>= \p -> addMember p m2 of
          Right pool' -> length (filterByCapabilities pool' []) `shouldBe` 2
          Left e -> expectationFailure (show e)

      it "excludes non-active members" $ do
        let pool = mkTestPool 2
            m1 = mkMember agent1 ["claude-sonnet"]
            m2 = mkMember agent2 ["claude-sonnet"]
        case addMember pool m1
             >>= \p -> addMember p m2
             >>= \p -> suspendMember p agent2 of
          Right pool' -> length (filterByCapabilities pool' ["claude-sonnet"]) `shouldBe` 1
          Left e -> expectationFailure (show e)
