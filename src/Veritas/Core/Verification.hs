-- | Cross-validation verification protocol.
--
-- A verification round collects independent results from multiple agents
-- (submitter + validators) and compares them to determine a verdict.
--
-- Pure domain logic, no IO.
module Veritas.Core.Verification
  ( -- * Types
    VerificationId(..)
  , VerificationSpec(..)
  , Verification(..)
  , VerificationPhase(..)
  , Verdict(..)
  , VerdictOutcome(..)
  , VerificationError(..)

    -- * Operations
  , recordSubmission
  , computeVerdict
  , isVerified
  ) where

import Data.ByteString (ByteString)
import Data.List (find, sortBy)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Natural (Natural)

import Veritas.Pool.Types (AgentId(..), PoolId(..), ComparisonMethod(..))

-- | Unique identifier for a verification round.
newtype VerificationId = VerificationId { unVerificationId :: UUID }
  deriving newtype (Eq, Ord, Show)

-- | Specification for what needs to be verified.
data VerificationSpec = VerificationSpec
  { vsDescription            :: Text
  , vsComputationFingerprint :: Text          -- ^ Content hash of the computation
  , vsSubmittedResult        :: Maybe ByteString  -- ^ The result being verified (optional)
  , vsComparisonMethod       :: ComparisonMethod
  , vsValidatorCount         :: Natural       -- ^ How many independent validators
  } deriving stock (Eq, Show)

-- | Phase of a verification round.
data VerificationPhase
  = Collecting    -- ^ Gathering submissions from validators
  | Deciding      -- ^ All submissions in, computing verdict
  | Decided       -- ^ Verdict reached
  deriving stock (Eq, Show)

-- | The outcome of comparing submissions.
data VerdictOutcome
  = Unanimous                 -- ^ All participants agree
  | MajorityAgree [AgentId]   -- ^ Majority agrees, dissenters identified
  | Inconclusive              -- ^ No clear majority
  deriving stock (Eq, Show)

-- | The verdict of a verification round.
data Verdict = Verdict
  { verdictOutcome        :: VerdictOutcome
  , verdictAgreementCount :: Int
  , verdictMajorityResult :: Maybe ByteString  -- ^ The agreed-upon result
  , verdictDecidedAt      :: UTCTime
  } deriving stock (Eq, Show)

-- | A verification round.
data Verification = Verification
  { vfId          :: VerificationId
  , vfPoolId      :: PoolId
  , vfSpec        :: VerificationSpec
  , vfSubmitter   :: AgentId               -- ^ Who submitted the output to verify
  , vfValidators  :: [AgentId]             -- ^ Selected validators
  , vfSubmissions :: [(AgentId, ByteString)]  -- ^ Collected results
  , vfPhase       :: VerificationPhase
  , vfVerdict     :: Maybe Verdict
  , vfCreatedAt   :: UTCTime
  } deriving stock (Eq, Show)

-- | Errors from verification operations.
data VerificationError
  = NotAValidator AgentId
  | AlreadySubmitted AgentId
  | WrongPhase VerificationPhase VerificationPhase  -- ^ expected, actual
  | NotAllSubmitted
  deriving stock (Eq, Show)

-- | All agents who should submit (submitter + validators).
allParticipants :: Verification -> [AgentId]
allParticipants v = vfSubmitter v : vfValidators v

-- | Record a submission from a validator (or submitter).
-- Transitions to Deciding when all submissions are collected.
recordSubmission :: Verification -> AgentId -> ByteString -> Either VerificationError Verification
recordSubmission v aid result
  | vfPhase v /= Collecting = Left (WrongPhase Collecting (vfPhase v))
  | aid `notElem` allParticipants v = Left (NotAValidator aid)
  | any (\(a, _) -> a == aid) (vfSubmissions v) = Left (AlreadySubmitted aid)
  | otherwise =
      let newSubmissions = vfSubmissions v ++ [(aid, result)]
          allIn = length newSubmissions == length (allParticipants v)
          newPhase = if allIn then Deciding else Collecting
      in Right v
        { vfSubmissions = newSubmissions
        , vfPhase = newPhase
        }

-- | Compute the verdict by comparing all submissions.
-- Requires all submissions to be in (Deciding phase).
computeVerdict :: Verification -> UTCTime -> Either VerificationError Verification
computeVerdict v now
  | vfPhase v /= Deciding = Left (WrongPhase Deciding (vfPhase v))
  | length (vfSubmissions v) /= length (allParticipants v) = Left NotAllSubmitted
  | otherwise =
      let results = vfSubmissions v
          outcome = classifyResults results
          verdict = Verdict
            { verdictOutcome = outcome
            , verdictAgreementCount = countAgreement outcome results
            , verdictMajorityResult = majorityResult outcome results
            , verdictDecidedAt = now
            }
      in Right v
        { vfPhase = Decided
        , vfVerdict = Just verdict
        }

-- | Check if a verdict indicates successful verification.
isVerified :: Verdict -> Bool
isVerified v = case verdictOutcome v of
  Unanimous       -> True
  MajorityAgree _ -> True
  Inconclusive    -> False

-- === Internal ===

-- | Classify results into unanimous, majority, or inconclusive.
classifyResults :: [(AgentId, ByteString)] -> VerdictOutcome
classifyResults results =
  let groups = groupByValue results
      total = length results
  in case groups of
    [_] -> Unanimous
    _ ->
      let sorted = sortBy (comparing (Down . length)) groups
          majorityGroup = head sorted
          minorityGroups = tail sorted
      in if length majorityGroup > total `div` 2
         then let dissenters = concatMap (map fst) minorityGroups
              in MajorityAgree dissenters
         else Inconclusive

-- | Group results by value equality.
groupByValue :: [(AgentId, ByteString)] -> [[(AgentId, ByteString)]]
groupByValue [] = []
groupByValue (x:xs) =
  let (same, diff) = partition' (\y -> snd x == snd y) xs
  in (x : same) : groupByValue diff

partition' :: (a -> Bool) -> [a] -> ([a], [a])
partition' _ [] = ([], [])
partition' p (x:xs)
  | p x       = let (yes, no) = partition' p xs in (x:yes, no)
  | otherwise  = let (yes, no) = partition' p xs in (yes, x:no)

-- | Count how many agents are in the majority group.
countAgreement :: VerdictOutcome -> [(AgentId, ByteString)] -> Int
countAgreement Unanimous results = length results
countAgreement (MajorityAgree dissenters) results =
  length results - length dissenters
countAgreement Inconclusive results =
  -- Return the size of the largest group
  let groups = groupByValue results
  in case groups of
    [] -> 0
    _  -> maximum (map length groups)

-- | Get the majority result value.
majorityResult :: VerdictOutcome -> [(AgentId, ByteString)] -> Maybe ByteString
majorityResult Inconclusive _ = Nothing
majorityResult Unanimous results = Just (snd (head results))
majorityResult (MajorityAgree dissenters) results =
  fmap snd (find (\(aid, _) -> aid `notElem` dissenters) results)
