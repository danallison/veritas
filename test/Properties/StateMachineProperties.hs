module Properties.StateMachineProperties (spec) where

import Data.UUID as UUID
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

import Veritas.Core.Types
import Veritas.Core.StateMachine

-- Arbitrary instances

instance Arbitrary Phase where
  arbitrary = elements
    [Pending, AwaitingReveals, AwaitingBeacon, Resolving, Finalized, Expired, Cancelled, Disputed]

instance Arbitrary EntropyMethod where
  arbitrary = elements [ParticipantReveal, ExternalBeacon, OfficiantVRF, Combined]

instance Arbitrary CommitmentMode where
  arbitrary = elements [Immediate, DeadlineWait]

spec :: Spec
spec = do
  describe "StateMachine Properties" $ do
    prop "terminal phases reject all non-dispute actions" $ \p ->
      isTerminal p ==>
        let ceremony = mkTestCeremony { phase = p }
            commit = mkTestCommitment
        in case transition ceremony [] [] (AddCommitment commit) of
          Left (InvalidPhase _ _) -> True
          _                       -> False

    prop "Pending -> post-commit phase is consistent with entropy method" $
      forAll arbitrary $ \method ->
        postCommitPhaseIsConsistent method

    prop "no valid transition produces a phase that violates method ordering" $
      -- Method D: must go through AwaitingReveals before AwaitingBeacon
      let ceremony = mkTestCeremony { entropyMethod = Combined, phase = Pending }
      in -- From Pending, Combined method should go to AwaitingReveals (not AwaitingBeacon)
         case transition ceremony [mkTestCommitment] [] (AddCommitment mkTestCommitment2) of
           Right TransitionResult{..} -> trNewPhase /= AwaitingBeacon
           Left _ -> True

-- Helpers

mkTestCeremony :: Ceremony
mkTestCeremony = Ceremony
  { ceremonyId = CeremonyId UUID.nil
  , question = "test"
  , ceremonyType = CoinFlip
  , entropyMethod = OfficiantVRF
  , requiredParties = 2
  , commitmentMode = Immediate
  , commitDeadline = read "2030-01-01 00:00:00 UTC"
  , revealDeadline = Just (read "2030-01-01 01:00:00 UTC")
  , nonParticipationPolicy = Just Cancellation
  , beaconSpec = Nothing
  , phase = Pending
  , createdBy = ParticipantId UUID.nil
  , createdAt = read "2025-01-01 00:00:00 UTC"
  }

mkTestCommitment :: Commitment
mkTestCommitment = Commitment
  { commitCeremony = CeremonyId UUID.nil
  , commitParty = ParticipantId (UUID.fromWords 1 0 0 0)
  , commitSignature = "sig"
  , entropySealHash = Nothing
  , committedAt = read "2025-01-01 00:00:00 UTC"
  }

mkTestCommitment2 :: Commitment
mkTestCommitment2 = mkTestCommitment
  { commitParty = ParticipantId (UUID.fromWords 2 0 0 0)
  }

postCommitPhaseIsConsistent :: EntropyMethod -> Bool
postCommitPhaseIsConsistent method =
  let expected = case method of
        ParticipantReveal -> AwaitingReveals
        ExternalBeacon    -> AwaitingBeacon
        OfficiantVRF      -> Resolving
        Combined          -> AwaitingReveals
      ceremony = mkTestCeremony
        { entropyMethod = method
        , requiredParties = 2
        }
      commit = case method of
        ParticipantReveal -> mkTestCommitment2 { entropySealHash = Just "seal" }
        Combined          -> mkTestCommitment2 { entropySealHash = Just "seal" }
        _                 -> mkTestCommitment2
      existing = case method of
        ParticipantReveal -> [mkTestCommitment { entropySealHash = Just "seal" }]
        Combined          -> [mkTestCommitment { entropySealHash = Just "seal" }]
        _                 -> [mkTestCommitment]
  in case transition ceremony existing [] (AddCommitment commit) of
       Right TransitionResult{..} -> trNewPhase == expected
       Left _ -> False  -- should not fail
