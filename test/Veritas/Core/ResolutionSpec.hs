module Veritas.Core.ResolutionSpec (spec) where

import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.UUID as UUID
import Test.Hspec

import Veritas.Core.Types
import Veritas.Core.Resolution

spec :: Spec
spec = do
  describe "Resolution" $ do
    let testCid = CeremonyId UUID.nil
        mkContribution val = EntropyContribution
          { ecCeremony = testCid
          , ecSource = VRFEntropy VRFOutput
              { vrfValue = val
              , vrfProof = "proof"
              , vrfPublicKey = "pk"
              }
          , ecValue = val
          }

    describe "combineEntropy" $ do
      it "produces a deterministic result" $ do
        let c1 = mkContribution "entropy1"
            c2 = mkContribution "entropy2"
            result1 = combineEntropy [c1, c2]
            result2 = combineEntropy [c1, c2]
        result1 `shouldBe` result2

      it "is order-independent (sorted by source key)" $ do
        let c1 = EntropyContribution testCid (ParticipantEntropy (ParticipantId (UUID.fromWords 1 0 0 0))) "entropy1"
            c2 = EntropyContribution testCid (ParticipantEntropy (ParticipantId (UUID.fromWords 2 0 0 0))) "entropy2"
        combineEntropy [c1, c2] `shouldBe` combineEntropy [c2, c1]

    describe "deriveCoinFlip" $ do
      it "returns a Bool" $ do
        let result = deriveCoinFlip "some-entropy"
        result `shouldSatisfy` (\r -> r == True || r == False)

      it "is deterministic" $ do
        deriveCoinFlip "test-entropy" `shouldBe` deriveCoinFlip "test-entropy"

    describe "deriveChoice" $ do
      it "picks from the provided options" $ do
        let options = "alpha" :| ["beta", "gamma"]
            result = deriveChoice "test-entropy" options
        result `shouldSatisfy` (`elem` NE.toList options)

      it "is deterministic" $ do
        let options = "alpha" :| ["beta", "gamma"]
        deriveChoice "test" options `shouldBe` deriveChoice "test" options

    describe "deriveShuffle" $ do
      it "returns all items" $ do
        let items = "a" :| ["b", "c", "d"]
            result = deriveShuffle "test-entropy" items
        length result `shouldBe` NE.length items

      it "contains all original items" $ do
        let items = "a" :| ["b", "c", "d"]
            result = deriveShuffle "test-entropy" items
        all (`elem` result) (NE.toList items) `shouldBe` True

      it "is deterministic" $ do
        let items = "a" :| ["b", "c", "d"]
        deriveShuffle "test" items `shouldBe` deriveShuffle "test" items

    describe "deriveIntRange" $ do
      it "returns a value in range" $ do
        let result = deriveIntRange "test-entropy" 1 10
        result `shouldSatisfy` (\r -> r >= 1 && r <= 10)

      it "handles reversed range" $ do
        let result = deriveIntRange "test-entropy" 10 1
        result `shouldSatisfy` (\r -> r >= 1 && r <= 10)

      it "returns the value when lo == hi" $ do
        deriveIntRange "test-entropy" 5 5 `shouldBe` 5

      it "is deterministic" $ do
        deriveIntRange "test" 1 100 `shouldBe` deriveIntRange "test" 1 100

    describe "deriveWeightedChoice" $ do
      it "picks from the provided options" $ do
        let wcs = ("alpha", 1) :| [("beta", 2), ("gamma", 3)]
            result = deriveWeightedChoice "test-entropy" wcs
        result `shouldSatisfy` (`elem` map fst (NE.toList wcs))

      it "is deterministic" $ do
        let wcs = ("alpha", 1) :| [("beta", 2), ("gamma", 3)]
        deriveWeightedChoice "test" wcs `shouldBe` deriveWeightedChoice "test" wcs

    describe "resolve" $ do
      it "produces a complete outcome for CoinFlip" $ do
        let contributions = [mkContribution "test"]
            outcome = resolve (CoinFlip "Heads" "Tails") contributions
        case outcomeValue outcome of
          CoinFlipResult _ -> pure ()
          other -> expectationFailure $ "Expected CoinFlipResult, got: " ++ show other

      it "produces a complete outcome for Shuffle" $ do
        let contributions = [mkContribution "test"]
            items = "a" :| ["b", "c"]
            outcome = resolve (Shuffle items) contributions
        case outcomeValue outcome of
          ShuffleResult xs -> length xs `shouldBe` NE.length items
          other -> expectationFailure $ "Expected ShuffleResult, got: " ++ show other
