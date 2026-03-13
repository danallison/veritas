-- | Task assignment for volunteer pools — posting tasks and selecting
-- volunteers via verifiable random selection.
--
-- Pure domain logic, no IO.
module Veritas.Core.TaskAssignment
  ( -- * Types
    TaskSpec(..)
  , TaskAssignment(..)
  , TaskStatus(..)
  , TaskId(..)
  , SelectionError(..)

    -- * Operations
  , selectVolunteers
  , createTaskAssignment
  , startTask
  , completeTask
  , failTask
  , TaskTransitionError(..)
  ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Natural (Natural)

import Veritas.Core.Pool
import Veritas.Pool.Types (AgentId(..), PoolId(..))
import Veritas.Pool.Selection (deterministicShuffle)

-- | Unique identifier for a task assignment.
newtype TaskId = TaskId { unTaskId :: UUID }
  deriving newtype (Eq, Ord, Show)

-- | Specification for a task to be assigned.
data TaskSpec = TaskSpec
  { tsDescription          :: Text
  , tsRequiredCapabilities :: [Text]
  , tsDeadlineSeconds      :: Int
  } deriving stock (Eq, Show)

-- | Status of a task assignment.
data TaskStatus
  = Assigned      -- ^ Volunteers selected, not yet started
  | InProgress    -- ^ Task underway
  | Complete      -- ^ Task finished successfully
  | TaskFailed    -- ^ Task failed
  deriving stock (Eq, Show)

-- | A task assignment — selected volunteers for a specific task.
data TaskAssignment = TaskAssignment
  { taTaskId        :: TaskId
  , taPoolId        :: PoolId
  , taTaskSpec      :: TaskSpec
  , taSelected      :: [AgentId]       -- ^ Randomly selected volunteers
  , taSelectionSeed :: ByteString      -- ^ drand beacon signature used for selection
  , taBeaconRound   :: Natural         -- ^ drand round number
  , taStatus        :: TaskStatus
  , taFailureReason :: Maybe Text
  } deriving stock (Eq, Show)

-- | Errors from volunteer selection.
data SelectionError
  = InsufficientVolunteers Natural Natural  -- ^ needed, available
  deriving stock (Eq, Show)

-- | Errors from task status transitions.
data TaskTransitionError
  = InvalidTransition TaskStatus TaskStatus  -- ^ from, attempted to
  deriving stock (Eq, Show)

-- | Select volunteers from a pool for a task.
--
-- 1. Filters to active members only
-- 2. Filters by required capabilities
-- 3. Shuffles deterministically using the seed (drand beacon)
-- 4. Takes the first N
selectVolunteers :: VolunteerPool -> TaskSpec -> ByteString -> Either SelectionError [VolunteerMember]
selectVolunteers pool taskSpec seed =
  let eligible = case tsRequiredCapabilities taskSpec of
        [] -> activeMembers pool
        caps -> filterByCapabilities pool caps
      needed = vpSelectionSize pool
      available = fromIntegral (length eligible) :: Natural
  in if available < needed
     then Left (InsufficientVolunteers needed available)
     else
       let shuffled = deterministicShuffle eligible seed
       in Right (take (fromIntegral needed) shuffled)

-- | Create a task assignment by selecting volunteers from the pool.
createTaskAssignment :: VolunteerPool
                     -> TaskId
                     -> TaskSpec
                     -> ByteString    -- ^ selection seed (drand beacon signature)
                     -> Natural       -- ^ beacon round number
                     -> Either SelectionError TaskAssignment
createTaskAssignment pool taskId taskSpec seed beaconRound = do
  selected <- selectVolunteers pool taskSpec seed
  Right TaskAssignment
    { taTaskId = taskId
    , taPoolId = vpId pool
    , taTaskSpec = taskSpec
    , taSelected = map vmAgentId selected
    , taSelectionSeed = seed
    , taBeaconRound = beaconRound
    , taStatus = Assigned
    , taFailureReason = Nothing
    }

-- | Transition task from Assigned to InProgress.
startTask :: TaskAssignment -> Either TaskTransitionError TaskAssignment
startTask ta
  | taStatus ta == Assigned = Right ta { taStatus = InProgress }
  | otherwise = Left (InvalidTransition (taStatus ta) InProgress)

-- | Transition task to Complete (must be InProgress).
completeTask :: TaskAssignment -> Either TaskTransitionError TaskAssignment
completeTask ta
  | taStatus ta == InProgress = Right ta { taStatus = Complete }
  | otherwise = Left (InvalidTransition (taStatus ta) Complete)

-- | Transition task to Failed (from Assigned or InProgress).
failTask :: TaskAssignment -> Text -> Either TaskTransitionError TaskAssignment
failTask ta reason
  | taStatus ta `elem` [Assigned, InProgress] =
      Right ta { taStatus = TaskFailed, taFailureReason = Just reason }
  | otherwise = Left (InvalidTransition (taStatus ta) TaskFailed)
