-- | Pure state machine for ceremony lifecycle.
--
-- All transitions are pure functions that take the current state and an action,
-- returning either a TransitionError or the new phase plus any events to log.
module Veritas.Core.StateMachine
  ( Action(..)
  , TransitionResult(..)
  , transition
  , canCommit
  , isTerminal
  ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Time (UTCTime)

import Veritas.Core.Types

-- | Actions that can be applied to a ceremony
data Action
  = AddCommitment Commitment
  | SubmitReveal ParticipantId ByteString
  | ApplyNonParticipation [NonParticipationEntry]
  | AnchorBeacon BeaconAnchor
  | GenerateVRF VRFOutput
  | ResolveOutcome Outcome
  | Finalize
  | CheckDeadline UTCTime  -- ^ current time for deadline checks
  | Dispute Text
  deriving stock (Show)

-- | Result of a state transition
data TransitionResult = TransitionResult
  { trNewPhase :: Phase
  , trEvents   :: [CeremonyEvent]
  } deriving stock (Show)

-- | Apply an action to a ceremony, returning the new phase and events or an error.
transition :: Ceremony           -- ^ current ceremony state
           -> [Commitment]       -- ^ existing commitments
           -> [ParticipantId]    -- ^ participants who have revealed
           -> Action             -- ^ action to apply
           -> Either TransitionError TransitionResult
transition ceremony commitments revealedParties action =
  case (phase ceremony, action) of

    -- === Pending phase ===

    (Pending, AddCommitment commit) -> do
      -- Validate entropy method requires seal
      case entropyMethod ceremony of
        ParticipantReveal
          | Nothing <- entropySealHash commit ->
              Left (InvariantViolation "ParticipantReveal requires entropy seal")
        Combined
          | Nothing <- entropySealHash commit ->
              Left (InvariantViolation "Combined method requires entropy seal")
        _ -> pure ()

      let newCount = fromIntegral (length commitments) + 1
          quorum = requiredParties ceremony
          event = ParticipantCommitted commit

      case commitmentMode ceremony of
        Immediate
          | newCount >= quorum -> do
              let nextPhase = postCommitPhase (entropyMethod ceremony)
              pure TransitionResult
                { trNewPhase = nextPhase
                , trEvents = [event]
                }
        _ ->
          pure TransitionResult
            { trNewPhase = Pending
            , trEvents = [event]
            }

    (Pending, CheckDeadline now)
      | now >= commitDeadline ceremony -> do
          let count = fromIntegral (length commitments)
              quorum = requiredParties ceremony
          if count >= quorum
            then do
              let nextPhase = postCommitPhase (entropyMethod ceremony)
              pure TransitionResult
                { trNewPhase = nextPhase
                , trEvents = []
                }
            else
              pure TransitionResult
                { trNewPhase = Expired
                , trEvents = [CeremonyExpired]
                }
      | otherwise ->
          Left (DeadlineNotPassed (commitDeadline ceremony) now)

    -- === AwaitingReveals phase ===

    (AwaitingReveals, SubmitReveal pid _val) -> do
      -- Validate the participant committed
      let committed = any (\c -> commitParty c == pid) commitments
      if not committed
        then Left (NotCommitted pid)
        else do
          let alreadyRevealed = pid `elem` revealedParties
          if alreadyRevealed
            then Left (AlreadyRevealed pid)
            else do
              let newRevealedCount = length revealedParties + 1
                  totalCommitted = length commitments
                  allRevealed = newRevealedCount >= totalCommitted
              if allRevealed
                then do
                  let nextPhase = case entropyMethod ceremony of
                        Combined -> AwaitingBeacon
                        _        -> Resolving
                  pure TransitionResult
                    { trNewPhase = nextPhase
                    , trEvents = []  -- reveals are batched; not published individually
                    }
                else
                  pure TransitionResult
                    { trNewPhase = AwaitingReveals
                    , trEvents = []  -- reveals are batched; not published individually
                    }

    (AwaitingReveals, ApplyNonParticipation entries) -> do
      let events = map NonParticipationApplied entries
          anyCancellation = any (\e -> npePolicyApplied e == Cancellation) entries
      if anyCancellation
        then
          pure TransitionResult
            { trNewPhase = Cancelled
            , trEvents = events ++ [CeremonyCancelled "Non-participation cancellation policy applied"]
            }
        else do
          let nextPhase = case entropyMethod ceremony of
                Combined -> AwaitingBeacon
                _        -> Resolving
          pure TransitionResult
            { trNewPhase = nextPhase
            , trEvents = events
            }

    (AwaitingReveals, CheckDeadline now) ->
      case revealDeadline ceremony of
        Nothing -> Left MissingRevealDeadline
        Just dl
          | now >= dl ->
              -- Deadline passed — caller should apply non-participation policy
              -- We just signal that the deadline has passed; the handler applies the policy
              pure TransitionResult
                { trNewPhase = AwaitingReveals  -- handler will follow up with ApplyNonParticipation
                , trEvents = []
                }
          | otherwise ->
              Left (DeadlineNotPassed dl now)

    -- === AwaitingBeacon phase ===

    (AwaitingBeacon, AnchorBeacon anchor) ->
      pure TransitionResult
        { trNewPhase = Resolving
        , trEvents = [BeaconAnchored anchor]
        }

    -- === Resolving phase ===

    (Resolving, ResolveOutcome outcome) ->
      pure TransitionResult
        { trNewPhase = Finalized
        , trEvents = [CeremonyResolved outcome, CeremonyFinalized]
        }

    -- === Dispute (from any non-terminal phase) ===

    (p, Dispute reason)
      | not (isTerminal p) ->
          pure TransitionResult
            { trNewPhase = Disputed
            , trEvents = [CeremonyDisputed reason]
            }

    -- === VRF generation (during transition from Pending for Method C) ===
    -- This is handled by the Resolving phase via ResolveOutcome.
    -- The VRF is generated by the handler and entropy is included in the outcome.

    -- === Invalid transitions ===

    (currentPhase, _) ->
      Left (InvalidPhase currentPhase (actionTargetPhase action))

-- | Determine the next phase after commitment quorum is reached
postCommitPhase :: EntropyMethod -> Phase
postCommitPhase = \case
  ParticipantReveal -> AwaitingReveals
  ExternalBeacon    -> AwaitingBeacon
  OfficiantVRF      -> Resolving
  Combined          -> AwaitingReveals

-- | Check if a participant can still commit to a ceremony
canCommit :: Ceremony -> [Commitment] -> ParticipantId -> UTCTime -> Either TransitionError ()
canCommit ceremony commitments pid now = do
  if phase ceremony /= Pending
    then Left (InvalidPhase (phase ceremony) Pending)
    else if now >= commitDeadline ceremony
      then Left (DeadlinePassed (commitDeadline ceremony) now)
      else if any (\c -> commitParty c == pid) commitments
        then Left (AlreadyCommitted pid)
        else Right ()

-- | Whether a phase is terminal (no further transitions possible except Dispute)
isTerminal :: Phase -> Bool
isTerminal = \case
  Finalized -> True
  Expired   -> True
  Cancelled -> True
  Disputed  -> True
  _         -> False

-- | Best-effort guess at what phase an action is targeting (for error messages)
actionTargetPhase :: Action -> Phase
actionTargetPhase = \case
  AddCommitment{}        -> Pending
  SubmitReveal{}         -> AwaitingReveals
  ApplyNonParticipation{} -> AwaitingReveals
  AnchorBeacon{}         -> AwaitingBeacon
  GenerateVRF{}          -> Resolving
  ResolveOutcome{}       -> Resolving
  Finalize               -> Finalized
  CheckDeadline{}        -> Pending
  Dispute{}              -> Disputed
