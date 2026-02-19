-- | Statistical distribution tests for resolution functions.
--
-- Uses large deterministic samples and chi-squared goodness-of-fit
-- to verify that HKDF-SHA256 derivation produces uniform outputs.
module Properties.StatisticalProperties (spec) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List (foldl', group, sort)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.Map.Strict as Map
import Test.Hspec

import Veritas.Core.Resolution
    (deriveCoinFlip, deriveChoice, deriveShuffle, deriveIntRange, deriveWeightedChoice)
import Veritas.Crypto.Hash (sha256, deriveUniform)

-- | Generate a deterministic chain of N entropy values by iterated SHA-256.
entropyChain :: Int -> [ByteString]
entropyChain n = take n (iterate sha256 (sha256 "veritas-statistical-test-seed"))

-- | Chi-squared statistic: sum of (observed - expected)^2 / expected.
chiSquared :: [(Double, Double)] -> Double
chiSquared = sum . map (\(obs, expected) -> (obs - expected) ^ (2 :: Int) / expected)

-- | Count occurrences of each value in a list, return (value, count) pairs.
countOccurrences :: Ord a => [a] -> Map.Map a Int
countOccurrences = foldl' (\m x -> Map.insertWith (+) x 1 m) Map.empty

spec :: Spec
spec = do
  describe "Statistical Distribution Tests" $ do

    -- Test 1: Coin flip uniformity
    it "coin flips are uniformly distributed (chi-squared, p=0.01)" $ do
      let n = 10000
          results = map deriveCoinFlip (entropyChain n)
          trueCount = length (filter id results)
          falseCount = n - trueCount
          expected = fromIntegral n / 2 :: Double
          chi2 = chiSquared
            [ (fromIntegral trueCount, expected)
            , (fromIntegral falseCount, expected)
            ]
      -- k=2, df=1, p=0.01 => critical value 6.63
      chi2 `shouldSatisfy` (< 6.63)

    -- Test 2: Uniform choice distribution
    it "uniform choice over 6 items is evenly distributed (chi-squared, p=0.01)" $ do
      let n = 10000
          items = "A" :| ["B", "C", "D", "E", "F"]
          results = map (`deriveChoice` items) (entropyChain n)
          counts = countOccurrences results
          expected = fromIntegral n / 6.0 :: Double
          chi2 = chiSquared
            [ (fromIntegral (Map.findWithDefault 0 label counts), expected)
            | label <- ["A", "B", "C", "D", "E", "F"]
            ]
      -- k=6, df=5, p=0.01 => critical value 15.09
      chi2 `shouldSatisfy` (< 15.09)

    -- Test 3: Integer range uniformity
    it "deriveIntRange [1..10] is uniformly distributed (chi-squared, p=0.01)" $ do
      let n = 10000
          results = map (\e -> deriveIntRange e 1 10) (entropyChain n)
          counts = countOccurrences results
          expected = fromIntegral n / 10.0 :: Double
          chi2 = chiSquared
            [ (fromIntegral (Map.findWithDefault 0 i counts), expected)
            | i <- [1..10]
            ]
      -- k=10, df=9, p=0.01 => critical value 21.67
      chi2 `shouldSatisfy` (< 21.67)

    -- Test 4: Weighted choice accuracy
    it "weighted choice [3,2,1] matches expected proportions (chi-squared, p=0.01)" $ do
      let n = 10000
          weights = ("A", 3) :| [("B", 2), ("C", 1)]
          results = map (`deriveWeightedChoice` weights) (entropyChain n)
          counts = countOccurrences results
          totalWeight = 6.0 :: Double
          chi2 = chiSquared
            [ (fromIntegral (Map.findWithDefault 0 "A" counts), fromIntegral n * 3.0 / totalWeight)
            , (fromIntegral (Map.findWithDefault 0 "B" counts), fromIntegral n * 2.0 / totalWeight)
            , (fromIntegral (Map.findWithDefault 0 "C" counts), fromIntegral n * 1.0 / totalWeight)
            ]
      -- k=3, df=2, p=0.01 => critical value 9.21
      chi2 `shouldSatisfy` (< 9.21)

    -- Test 5: Shuffle permutation coverage
    it "shuffle of 3 items covers all 6 permutations (chi-squared, p=0.01)" $ do
      let n = 5000
          items = "X" :| ["Y", "Z"]
          results = map (`deriveShuffle` items) (entropyChain n)
          counts = countOccurrences results
          expected = fromIntegral n / 6.0 :: Double
          allPerms = sort (map sort (Map.keys counts))
      -- All 6 permutations should appear
      length (Map.keys counts) `shouldBe` 6
      -- Each permutation should contain the same elements
      allPerms `shouldSatisfy` all (== ["X", "Y", "Z"])
      let chi2 = chiSquared
            [ (fromIntegral c, expected)
            | c <- Map.elems counts
            ]
      -- k=6, df=5, p=0.01 => critical value 15.09
      chi2 `shouldSatisfy` (< 15.09)

    -- Test 6: deriveUniform bucket test
    it "deriveUniform distributes evenly across 10 buckets (chi-squared, p=0.01)" $ do
      let n = 10000
          results = map deriveUniform (entropyChain n)
          toBucket :: Rational -> Int
          toBucket r = min 9 (floor (r * 10))
          buckets = map toBucket results
          counts = countOccurrences buckets
          expected = fromIntegral n / 10.0 :: Double
          chi2 = chiSquared
            [ (fromIntegral (Map.findWithDefault 0 b counts), expected)
            | b <- [0..9]
            ]
      -- k=10, df=9, p=0.01 => critical value 21.67
      chi2 `shouldSatisfy` (< 21.67)

    -- Test 7: Sequential correlation (runs test)
    it "coin flip runs count is within expected range" $ do
      let n = 10000
          results = map deriveCoinFlip (entropyChain n)
          -- Count runs: consecutive sequences of the same value
          runs = length (group results)
          -- Expected number of runs for n trials with p=0.5:
          -- E[runs] = (n + 1) / 2 = 5000.5
          -- Var[runs] = (n - 1) / 4 = 2499.75
          -- StdDev = ~49.997
          -- Accept within 3 standard deviations
          expectedRuns = fromIntegral (n + 1) / 2.0 :: Double
          stdDev = sqrt (fromIntegral (n - 1) / 4.0 :: Double)
          runsD = fromIntegral runs :: Double
      abs (runsD - expectedRuns) `shouldSatisfy` (< 3 * stdDev)

    -- Test 8: Monobit frequency test
    it "entropy bytes have approximately equal bit frequencies" $ do
      let n = 10000
          chain = entropyChain n
          -- Take first byte of each entropy value
          bytes = map (BS.head) chain
          -- Count total bits set
          popCount8 :: Int -> Int
          popCount8 w = length (filter id [testBit w b | b <- [0..7]])
          testBit :: Int -> Int -> Bool
          testBit w b = (w `div` (2 ^ b)) `mod` 2 == 1
          totalBits = n * 8
          onesCount = sum (map (popCount8 . fromIntegral) bytes)
          proportion = fromIntegral onesCount / fromIntegral totalBits :: Double
      -- Should be close to 0.5 — within 0.02
      abs (proportion - 0.5) `shouldSatisfy` (< 0.02)
