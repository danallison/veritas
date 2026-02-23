-- | Shared test helpers and orphan Arbitrary instances.
{-# OPTIONS_GHC -Wno-orphans #-}
module TestHelpers
  ( -- re-exported for convenience
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Test.QuickCheck

import Veritas.Core.Types

-- | Arbitrary ByteString — generates random byte sequences.
instance Arbitrary ByteString where
  arbitrary = BS.pack <$> arbitrary

instance Arbitrary Phase where
  arbitrary = elements
    [Gathering, AwaitingRosterAcks, Pending, AwaitingReveals, AwaitingBeacon, Resolving, Finalized, Expired, Cancelled, Disputed]

instance Arbitrary EntropyMethod where
  arbitrary = elements [ParticipantReveal, ExternalBeacon, OfficiantVRF, Combined]

instance Arbitrary CommitmentMode where
  arbitrary = elements [Immediate, DeadlineWait]
