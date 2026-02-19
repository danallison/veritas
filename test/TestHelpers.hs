-- | Shared test helpers and orphan Arbitrary instances.
module TestHelpers
  ( -- re-exported for convenience
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Test.QuickCheck

-- | Arbitrary ByteString — generates random byte sequences.
-- Shared across property test modules to avoid orphan duplication.
instance Arbitrary ByteString where
  arbitrary = BS.pack <$> arbitrary
