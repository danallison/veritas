module Veritas.API.HandlersSpec (spec) where

import Data.Time (UTCTime, addUTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Test.Hspec

import Veritas.Core.Types
import Data.List.NonEmpty (NonEmpty(..))
import Veritas.API.Handlers (validateCeremonyType, validateRequest, validateMethodParams, validateTwoPartySafety, validateBeaconSpec, validateTemporalConstraints)

-- Helper: a fixed UTCTime for tests that need a deadline
someTime :: UTCTime
someTime = posixSecondsToUTCTime 1700000000

someBeaconSpec :: BeaconSpec
someBeaconSpec = BeaconSpec
  { beaconNetwork  = "default"
  , beaconRound    = Just 1234
  , beaconFallback = CancelCeremony
  }

spec :: Spec
spec = do
  describe "validateRequest" $ do
    it "accepts a valid question and parties" $
      validateRequest "Who goes first?" 2
        `shouldBe` Right ()

    it "rejects an empty question" $
      validateRequest "" 2
        `shouldSatisfy` isLeft

    it "rejects a whitespace-only question" $
      validateRequest "   " 2
        `shouldSatisfy` isLeft

    it "rejects zero required_parties" $
      validateRequest "Who goes first?" 0
        `shouldSatisfy` isLeft

    it "accepts 1 required_parties" $
      validateRequest "Who goes first?" 1
        `shouldBe` Right ()

  describe "validateCeremonyType" $ do
    -- CoinFlip
    it "accepts a valid CoinFlip" $
      validateCeremonyType (CoinFlip "Heads" "Tails")
        `shouldBe` Right ()

    it "rejects CoinFlip with empty side A" $
      validateCeremonyType (CoinFlip "" "Tails")
        `shouldSatisfy` isLeft

    it "rejects CoinFlip with empty side B" $
      validateCeremonyType (CoinFlip "Heads" "")
        `shouldSatisfy` isLeft

    it "rejects CoinFlip with duplicate labels" $
      validateCeremonyType (CoinFlip "Heads" "Heads")
        `shouldSatisfy` isLeft

    -- UniformChoice
    it "accepts a valid UniformChoice" $
      validateCeremonyType (UniformChoice ("A" :| ["B", "C"]))
        `shouldBe` Right ()

    it "rejects UniformChoice with an empty label" $
      validateCeremonyType (UniformChoice ("A" :| ["", "C"]))
        `shouldSatisfy` isLeft

    it "rejects UniformChoice with only 1 choice" $
      validateCeremonyType (UniformChoice ("A" :| []))
        `shouldSatisfy` isLeft

    it "rejects UniformChoice with duplicate labels" $
      validateCeremonyType (UniformChoice ("A" :| ["B", "A"]))
        `shouldSatisfy` isLeft

    -- IntRange
    it "accepts a valid IntRange" $
      validateCeremonyType (IntRange 1 10)
        `shouldBe` Right ()

    it "accepts IntRange where lo == hi" $
      validateCeremonyType (IntRange 5 5)
        `shouldBe` Right ()

    it "rejects IntRange where lo > hi" $
      validateCeremonyType (IntRange 10 1)
        `shouldSatisfy` isLeft

    -- Shuffle
    it "accepts a valid Shuffle" $
      validateCeremonyType (Shuffle ("X" :| ["Y", "Z"]))
        `shouldBe` Right ()

    it "rejects Shuffle with an empty label" $
      validateCeremonyType (Shuffle ("X" :| [""]))
        `shouldSatisfy` isLeft

    it "rejects Shuffle with only 1 item" $
      validateCeremonyType (Shuffle ("X" :| []))
        `shouldSatisfy` isLeft

    -- WeightedChoice
    it "accepts WeightedChoice with weights summing to 1" $
      validateCeremonyType (WeightedChoice (("A", 1/2) :| [("B", 1/3), ("C", 1/6)]))
        `shouldBe` Right ()

    it "rejects WeightedChoice with weights not summing to 1" $
      validateCeremonyType (WeightedChoice (("A", 1/2) :| [("B", 1/4)]))
        `shouldSatisfy` isLeft

    it "rejects WeightedChoice with a zero weight" $
      validateCeremonyType (WeightedChoice (("A", 1) :| [("B", 0)]))
        `shouldSatisfy` isLeft

    it "rejects WeightedChoice with a negative weight" $
      validateCeremonyType (WeightedChoice (("A", 3/2) :| [("B", -1/2)]))
        `shouldSatisfy` isLeft

    it "rejects WeightedChoice with an empty label" $
      validateCeremonyType (WeightedChoice (("", 1/2) :| [("B", 1/2)]))
        `shouldSatisfy` isLeft

    it "rejects WeightedChoice with only 1 choice" $
      validateCeremonyType (WeightedChoice (("A", 1) :| []))
        `shouldSatisfy` isLeft

    it "rejects WeightedChoice with duplicate labels" $
      validateCeremonyType (WeightedChoice (("A", 1/2) :| [("A", 1/2)]))
        `shouldSatisfy` isLeft

  describe "validateMethodParams" $ do
    -- ParticipantReveal requires both reveal_deadline and non_participation_policy
    it "accepts ParticipantReveal with both reveal_deadline and policy" $
      validateMethodParams ParticipantReveal (Just someTime) (Just Cancellation)
        `shouldBe` Right ()

    it "rejects ParticipantReveal without reveal_deadline" $
      validateMethodParams ParticipantReveal Nothing (Just Cancellation)
        `shouldSatisfy` isLeft

    it "rejects ParticipantReveal without non_participation_policy" $
      validateMethodParams ParticipantReveal (Just someTime) Nothing
        `shouldSatisfy` isLeft

    -- Combined has the same requirements as ParticipantReveal
    it "accepts Combined with both reveal_deadline and policy" $
      validateMethodParams Combined (Just someTime) (Just Exclusion)
        `shouldBe` Right ()

    it "rejects Combined without reveal_deadline" $
      validateMethodParams Combined Nothing (Just Exclusion)
        `shouldSatisfy` isLeft

    it "rejects Combined without non_participation_policy" $
      validateMethodParams Combined (Just someTime) Nothing
        `shouldSatisfy` isLeft

    -- ExternalBeacon rejects reveal params
    it "accepts ExternalBeacon with no reveal params" $
      validateMethodParams ExternalBeacon Nothing Nothing
        `shouldBe` Right ()

    it "rejects ExternalBeacon with reveal_deadline" $
      validateMethodParams ExternalBeacon (Just someTime) Nothing
        `shouldSatisfy` isLeft

    it "rejects ExternalBeacon with non_participation_policy" $
      validateMethodParams ExternalBeacon Nothing (Just Cancellation)
        `shouldSatisfy` isLeft

    -- OfficiantVRF rejects reveal params
    it "accepts OfficiantVRF with no reveal params" $
      validateMethodParams OfficiantVRF Nothing Nothing
        `shouldBe` Right ()

    it "rejects OfficiantVRF with reveal_deadline" $
      validateMethodParams OfficiantVRF (Just someTime) Nothing
        `shouldSatisfy` isLeft

    it "rejects OfficiantVRF with non_participation_policy" $
      validateMethodParams OfficiantVRF Nothing (Just DefaultSubstitution)
        `shouldSatisfy` isLeft

  describe "validateTwoPartySafety" $ do
    it "rejects DefaultSubstitution for 2-party ceremonies" $
      validateTwoPartySafety 2 (Just DefaultSubstitution)
        `shouldSatisfy` isLeft

    it "accepts DefaultSubstitution for 3-party ceremonies" $
      validateTwoPartySafety 3 (Just DefaultSubstitution)
        `shouldBe` Right ()

    it "accepts Exclusion for 2-party ceremonies" $
      validateTwoPartySafety 2 (Just Exclusion)
        `shouldBe` Right ()

    it "accepts Cancellation for 2-party ceremonies" $
      validateTwoPartySafety 2 (Just Cancellation)
        `shouldBe` Right ()

    it "accepts no policy at all" $
      validateTwoPartySafety 2 Nothing
        `shouldBe` Right ()

  describe "validateBeaconSpec" $ do
    it "requires beacon_spec for ExternalBeacon" $
      validateBeaconSpec ExternalBeacon Nothing
        `shouldSatisfy` isLeft

    it "accepts beacon_spec for ExternalBeacon" $
      validateBeaconSpec ExternalBeacon (Just someBeaconSpec)
        `shouldBe` Right ()

    it "requires beacon_spec for Combined" $
      validateBeaconSpec Combined Nothing
        `shouldSatisfy` isLeft

    it "accepts beacon_spec for Combined" $
      validateBeaconSpec Combined (Just someBeaconSpec)
        `shouldBe` Right ()

    it "rejects beacon_spec for ParticipantReveal" $
      validateBeaconSpec ParticipantReveal (Just someBeaconSpec)
        `shouldSatisfy` isLeft

    it "accepts no beacon_spec for ParticipantReveal" $
      validateBeaconSpec ParticipantReveal Nothing
        `shouldBe` Right ()

    it "rejects beacon_spec for OfficiantVRF" $
      validateBeaconSpec OfficiantVRF (Just someBeaconSpec)
        `shouldSatisfy` isLeft

    it "accepts no beacon_spec for OfficiantVRF" $
      validateBeaconSpec OfficiantVRF Nothing
        `shouldBe` Right ()

  describe "validateTemporalConstraints" $ do
    let now = someTime
        future = addUTCTime 3600 now
        farFuture = addUTCTime 7200 now
        past = addUTCTime (-3600) now

    it "accepts commit_deadline in the future" $
      validateTemporalConstraints now future Nothing
        `shouldBe` Right ()

    it "rejects commit_deadline in the past" $
      validateTemporalConstraints now past Nothing
        `shouldSatisfy` isLeft

    it "rejects commit_deadline equal to now" $
      validateTemporalConstraints now now Nothing
        `shouldSatisfy` isLeft

    it "accepts valid reveal_deadline after commit_deadline" $
      validateTemporalConstraints now future (Just farFuture)
        `shouldBe` Right ()

    it "rejects reveal_deadline before commit_deadline" $
      validateTemporalConstraints now farFuture (Just future)
        `shouldSatisfy` isLeft

    it "rejects reveal_deadline in the past" $
      validateTemporalConstraints now future (Just past)
        `shouldSatisfy` isLeft

    it "rejects reveal_deadline equal to commit_deadline" $
      validateTemporalConstraints now future (Just future)
        `shouldSatisfy` isLeft

-- | Helper: check if an Either is Left
isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False
