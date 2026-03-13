module Properties.PoolProperties (spec) where

import qualified Data.ByteString as BS
import Data.List (nub)
import Data.Text (Text, pack)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import GHC.Natural (Natural)
import Test.Hspec
import Test.QuickCheck

import Veritas.Core.Pool
import Veritas.Core.TaskAssignment
import Veritas.Core.Verification
import Veritas.Pool.Types (AgentId(..), PoolId(..), ComparisonMethod(..))

-- === Generators ===

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

genAgentId :: Int -> AgentId
genAgentId n = AgentId (UUID.fromWords (fromIntegral n) 0 0 0)

genMember :: Int -> [Text] -> VolunteerMember
genMember n caps = VolunteerMember
  { vmAgentId = genAgentId n
  , vmPublicKey = BS.replicate 32 (fromIntegral n)
  , vmDisplayName = pack ("Agent-" <> show n)
  , vmCapabilities = caps
  , vmStatus = Active
  , vmJoinedAt = epoch
  }

mkPool :: Natural -> [VolunteerMember] -> VolunteerPool
mkPool selSize members = VolunteerPool
  { vpId = PoolId UUID.nil
  , vpName = "Prop Pool"
  , vpDescription = "Property test pool"
  , vpTaskType = CrossValidation
  , vpSelectionSize = selSize
  , vpMembers = members
  , vpCreatedAt = epoch
  }

genSeed :: Gen BS.ByteString
genSeed = BS.pack <$> vectorOf 32 arbitrary

spec :: Spec
spec = do
  describe "Pool Properties" $ do
    it "addMember is idempotent on member count (no duplicates)" $
      property $ \(Positive n) -> n <= (100 :: Int) ==>
        let members = [genMember i [] | i <- [1..n]]
            pool = mkPool 1 []
            result = foldl (\acc m -> acc >>= \p -> addMember p m) (Right pool) members
        in case result of
             Right p -> length (vpMembers p) == n
             Left _ -> False

    it "activeMembers never includes suspended or withdrawn members" $
      property $ \(Positive n) -> n <= (50 :: Int) ==>
        let members = [genMember i [] | i <- [1..n]]
            pool = mkPool 1 members
            -- Suspend even-indexed, withdraw those divisible by 3
            suspendEvens p = foldl (\acc i -> acc >>= \p' -> suspendMember p' (genAgentId i))
                               (Right p) [i | i <- [2,4..n]]
            withdrawThirds p = foldl (\acc i -> acc >>= \p' -> removeMember p' (genAgentId i))
                                 (Right p) [i | i <- [3,6..n], i `mod` 2 /= 0]  -- skip already suspended
        in case suspendEvens pool >>= withdrawThirds of
             Right p -> all (\m -> vmStatus m == Active) (activeMembers p)
             Left _ -> False

    it "selection size never exceeds requested count" $
      property $ forAll ((,) <$> choose (1, 20) <*> genSeed) $ \(selSize, seed) ->
        let n = selSize + 5  -- ensure enough members
            members = [genMember i [] | i <- [1..n]]
            pool = mkPool (fromIntegral selSize) members
            taskSpec = TaskSpec "test" [] 300
        in case selectVolunteers pool taskSpec seed of
             Right selected -> length selected == selSize
             Left _ -> False

    it "selection produces no duplicate agents" $
      property $ forAll ((,) <$> choose (1, 15) <*> genSeed) $ \(selSize, seed) ->
        let n = selSize + 10
            members = [genMember i [] | i <- [1..n]]
            pool = mkPool (fromIntegral selSize) members
            taskSpec = TaskSpec "test" [] 300
        in case selectVolunteers pool taskSpec seed of
             Right selected ->
               let aids = map vmAgentId selected
               in nub aids == aids
             Left _ -> False

    it "selection is deterministic" $
      property $ forAll ((,) <$> choose (1, 10) <*> genSeed) $ \(selSize, seed) ->
        let n = selSize + 5
            members = [genMember i [] | i <- [1..n]]
            pool = mkPool (fromIntegral selSize) members
            taskSpec = TaskSpec "test" [] 300
        in case (selectVolunteers pool taskSpec seed,
                 selectVolunteers pool taskSpec seed) of
             (Right s1, Right s2) -> map vmAgentId s1 == map vmAgentId s2
             _ -> False

  describe "Verification Properties" $ do
    it "unanimous verdict when all submit identical results" $
      property $ forAll (choose (2, 10)) $ \nValidators ->
        let submitter = genAgentId 0
            validators = [genAgentId i | i <- [1..nValidators]]
            allAgents = submitter : validators
            result = BS.pack [42, 42, 42, 42]
            submissions = [(aid, result) | aid <- allAgents]
            v = Verification
              { vfId = VerificationId UUID.nil
              , vfPoolId = PoolId UUID.nil
              , vfSpec = VerificationSpec "test" "fp" Nothing Exact (fromIntegral nValidators)
              , vfSubmitter = submitter
              , vfValidators = validators
              , vfSubmissions = submissions
              , vfPhase = Deciding
              , vfVerdict = Nothing
              , vfCreatedAt = epoch
              }
        in case computeVerdict v epoch of
             Right v' -> case vfVerdict v' of
               Just verdict -> verdictOutcome verdict == Unanimous
                            && verdictAgreementCount verdict == length allAgents
               Nothing -> False
             Left _ -> False

    it "isVerified is consistent with verdict outcome" $
      property $ \() ->
        let unanimousVerdict = Verdict Unanimous 3 (Just "r") epoch
            majorityVerdict = Verdict (MajorityAgree [genAgentId 1]) 2 (Just "r") epoch
            inconclusiveVerdict = Verdict Inconclusive 1 Nothing epoch
        in isVerified unanimousVerdict
           && isVerified majorityVerdict
           && not (isVerified inconclusiveVerdict)
