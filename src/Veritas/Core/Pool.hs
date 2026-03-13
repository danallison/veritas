-- | Volunteer Pool primitive — a collection of agents who commit to
-- performing a task if randomly selected.
--
-- Pure domain logic, no IO.
module Veritas.Core.Pool
  ( -- * Types
    VolunteerPool(..)
  , VolunteerMember(..)
  , MemberStatus(..)
  , TaskType(..)
  , PoolError(..)

    -- * Pool operations
  , addMember
  , removeMember
  , suspendMember
  , reactivateMember
  , activeMembers
  , findMember
  , poolReady
  , filterByCapabilities
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ByteString (ByteString)
import GHC.Natural (Natural)

import Veritas.Pool.Types (AgentId(..), PoolId(..))

-- | The type of task this pool serves.
data TaskType
  = CrossValidation           -- ^ AI output verification through independent cross-validation
  | CustomTask Text           -- ^ Any other task type
  deriving stock (Eq, Show)

-- | Status of a pool member.
data MemberStatus
  = Active
  | Suspended
  | Withdrawn
  deriving stock (Eq, Show)

-- | A member of a volunteer pool.
data VolunteerMember = VolunteerMember
  { vmAgentId      :: AgentId
  , vmPublicKey    :: ByteString      -- ^ Ed25519 public key (32 bytes)
  , vmDisplayName  :: Text
  , vmCapabilities :: [Text]          -- ^ What this agent can do (models, tools, etc.)
  , vmStatus       :: MemberStatus
  , vmJoinedAt     :: UTCTime
  } deriving stock (Eq, Show)

-- | A volunteer pool — a group of agents ready to be selected for tasks.
data VolunteerPool = VolunteerPool
  { vpId            :: PoolId
  , vpName          :: Text
  , vpDescription   :: Text
  , vpTaskType      :: TaskType
  , vpSelectionSize :: Natural        -- ^ How many members to select per task
  , vpMembers       :: [VolunteerMember]
  , vpCreatedAt     :: UTCTime
  } deriving stock (Eq, Show)

-- | Errors from pool operations.
data PoolError
  = MemberAlreadyJoined AgentId
  | MemberNotFound AgentId
  | MemberNotActive AgentId
  | MemberAlreadyActive AgentId
  | PoolTooSmall Natural Natural      -- ^ needed, available
  | MemberAlreadySuspended AgentId
  | MemberAlreadyWithdrawn AgentId
  deriving stock (Eq, Show)

-- | Add a member to the pool.
addMember :: VolunteerPool -> VolunteerMember -> Either PoolError VolunteerPool
addMember pool member
  | vmStatus member /= Active =
      Left (MemberNotActive (vmAgentId member))
  | any (\m -> vmAgentId m == vmAgentId member) (vpMembers pool) =
      Left (MemberAlreadyJoined (vmAgentId member))
  | otherwise =
      Right pool { vpMembers = vpMembers pool ++ [member] }

-- | Remove a member from the pool (sets status to Withdrawn).
-- Only Active or Suspended members can be withdrawn.
removeMember :: VolunteerPool -> AgentId -> Either PoolError VolunteerPool
removeMember pool aid =
  case findMember pool aid of
    Nothing -> Left (MemberNotFound aid)
    Just m
      | vmStatus m == Withdrawn -> Left (MemberAlreadyWithdrawn aid)
      | otherwise ->
          case updateMemberStatus pool aid Withdrawn of
            Nothing -> Left (MemberNotFound aid)
            Just pool' -> Right pool'

-- | Suspend a member (sets status to Suspended).
-- Only Active members can be suspended.
suspendMember :: VolunteerPool -> AgentId -> Either PoolError VolunteerPool
suspendMember pool aid =
  case findMember pool aid of
    Nothing -> Left (MemberNotFound aid)
    Just m
      | vmStatus m == Suspended -> Left (MemberAlreadySuspended aid)
      | vmStatus m == Withdrawn -> Left (MemberNotActive aid)
      | otherwise ->
          case updateMemberStatus pool aid Suspended of
            Nothing -> Left (MemberNotFound aid)
            Just pool' -> Right pool'

-- | Reactivate a suspended or withdrawn member.
reactivateMember :: VolunteerPool -> AgentId -> Either PoolError VolunteerPool
reactivateMember pool aid =
  case findMember pool aid of
    Nothing -> Left (MemberNotFound aid)
    Just m
      | vmStatus m == Active -> Left (MemberAlreadyActive aid)
      | otherwise ->
          case updateMemberStatus pool aid Active of
            Nothing -> Left (MemberNotFound aid)
            Just pool' -> Right pool'

-- | Get all active members of the pool.
activeMembers :: VolunteerPool -> [VolunteerMember]
activeMembers = filter (\m -> vmStatus m == Active) . vpMembers

-- | Find a member by AgentId.
findMember :: VolunteerPool -> AgentId -> Maybe VolunteerMember
findMember pool aid = case filter (\m -> vmAgentId m == aid) (vpMembers pool) of
  (m:_) -> Just m
  []    -> Nothing

-- | Check if the pool has enough active members for its selection size.
poolReady :: VolunteerPool -> Bool
poolReady pool =
  let active = fromIntegral (length (activeMembers pool)) :: Natural
  in active >= vpSelectionSize pool

-- | Filter active members by required capabilities.
-- Returns members who have ALL of the required capabilities.
filterByCapabilities :: VolunteerPool -> [Text] -> [VolunteerMember]
filterByCapabilities pool required =
  filter hasAll (activeMembers pool)
  where
    hasAll m = all (`elem` vmCapabilities m) required

-- === Internal helpers ===

-- | Update a member's status if found.
updateMemberStatus :: VolunteerPool -> AgentId -> MemberStatus -> Maybe VolunteerPool
updateMemberStatus pool aid newStatus =
  let (before, match, after) = splitOnAgent aid (vpMembers pool)
  in case match of
    Nothing -> Nothing
    Just m  -> Just pool { vpMembers = before ++ [m { vmStatus = newStatus }] ++ after }

-- | Split member list around a target agent.
splitOnAgent :: AgentId -> [VolunteerMember] -> ([VolunteerMember], Maybe VolunteerMember, [VolunteerMember])
splitOnAgent _ [] = ([], Nothing, [])
splitOnAgent aid (m:ms)
  | vmAgentId m == aid = ([], Just m, ms)
  | otherwise =
      let (before, match, after) = splitOnAgent aid ms
      in (m : before, match, after)
