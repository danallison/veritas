module Properties.ResolutionProperties (spec) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.UUID as UUID
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

import Veritas.Core.Types
import Veritas.Core.Resolution
import Veritas.Crypto.Hash (deriveUniform)

-- Arbitrary instances
instance Arbitrary ByteString where
  arbitrary = BS.pack <$> arbitrary

spec :: Spec
spec = do
  describe "Resolution Properties" $ do
    prop "deriveUniform always produces a value in [0, 1)" $
      \(bs :: ByteString) ->
        not (BS.null bs) ==>
          let r = deriveUniform bs
          in r >= 0 && r < 1

    prop "combineEntropy is deterministic" $
      \(bs1 :: ByteString) (bs2 :: ByteString) ->
        not (BS.null bs1) && not (BS.null bs2) ==>
          let cid = CeremonyId UUID.nil
              pid1 = ParticipantId (UUID.fromWords 1 0 0 0)
              pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
              c1 = EntropyContribution cid (ParticipantEntropy pid1) bs1
              c2 = EntropyContribution cid (ParticipantEntropy pid2) bs2
          in combineEntropy [c1, c2] == combineEntropy [c1, c2]

    prop "combineEntropy is order-independent" $
      \(bs1 :: ByteString) (bs2 :: ByteString) ->
        not (BS.null bs1) && not (BS.null bs2) ==>
          let cid = CeremonyId UUID.nil
              pid1 = ParticipantId (UUID.fromWords 1 0 0 0)
              pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
              c1 = EntropyContribution cid (ParticipantEntropy pid1) bs1
              c2 = EntropyContribution cid (ParticipantEntropy pid2) bs2
          in combineEntropy [c1, c2] == combineEntropy [c2, c1]

    prop "deriveCoinFlip is deterministic" $
      \(bs :: ByteString) ->
        not (BS.null bs) ==>
          deriveCoinFlip bs == deriveCoinFlip bs

    prop "deriveIntRange always returns value in range" $
      \(bs :: ByteString) ->
        not (BS.null bs) ==>
          forAll (choose (0, 1000)) $ \lo ->
            forAll (choose (lo, lo + 1000)) $ \hi ->
              let result = deriveIntRange bs lo hi
              in result >= lo && result <= hi

    prop "deriveShuffle preserves all elements" $
      \(bs :: ByteString) ->
        not (BS.null bs) ==>
          let items = "a" :| ["b", "c", "d", "e"]
              result = deriveShuffle bs items
          in length result == NE.length items &&
             all (`elem` result) (NE.toList items)

    prop "resolve is deterministic for CoinFlip" $
      \(bs :: ByteString) ->
        not (BS.null bs) ==>
          let cid = CeremonyId UUID.nil
              c = EntropyContribution cid (VRFEntropy (VRFOutput bs "proof" "pk")) bs
          in resolve CoinFlip [c] == resolve CoinFlip [c]
