-- | Result comparison for cross-validated computations.
--
-- Supports exact byte comparison, canonical JSON comparison,
-- and field-level comparison with configurable tolerances.
module Veritas.Pool.Comparison
  ( compareResults
  ) where

import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import Data.List (sortBy)
import Data.Ord (comparing, Down(..))

import Veritas.Pool.Types

-- | Compare results from multiple agents using the specified method.
--
-- Returns:
--   Unanimous   — all results match
--   Majority d  — 2 of 3 agree, d is the dissenter
--   Inconclusive — no majority
compareResults :: ComparisonMethod -> [(AgentId, ByteString)] -> ComparisonOutcome
compareResults _ [] = CompInconclusive
compareResults _ [_] = CompInconclusive
compareResults method results =
  let compareFn = case method of
        Exact           -> (==)
        Canonical       -> canonicalEqual
        FieldLevel _cfg -> (==)  -- POC: field-level uses exact for now
      -- Group results by equivalence
      grouped = groupByEquivalence compareFn results
  in classifyGroups grouped (length results)

-- | Group results by equivalence using the comparison function.
-- Returns list of groups, each group is a list of (AgentId, ByteString).
groupByEquivalence :: (ByteString -> ByteString -> Bool)
                   -> [(AgentId, ByteString)]
                   -> [[(AgentId, ByteString)]]
groupByEquivalence _ [] = []
groupByEquivalence eq (x:xs) =
  let (same, diff) = partitionWith (\y -> snd x `eq` snd y) xs
  in (x : same) : groupByEquivalence eq diff

-- | Partition a list based on a predicate, maintaining order
partitionWith :: (a -> Bool) -> [a] -> ([a], [a])
partitionWith _ [] = ([], [])
partitionWith p (x:xs)
  | p x       = let (yes, no) = partitionWith p xs in (x:yes, no)
  | otherwise  = let (yes, no) = partitionWith p xs in (yes, x:no)

-- | Classify groups into Unanimous, Majority, or Inconclusive.
classifyGroups :: [[(AgentId, ByteString)]] -> Int -> ComparisonOutcome
classifyGroups [_] _ = CompUnanimous       -- single group = all agree
classifyGroups groups total
  | length groups == 2 =
      -- Sort by group size descending
      let sorted = sortBy (comparing (Down . length)) groups
          majorityGroup = head sorted
          minorityGroup = sorted !! 1
      in if length majorityGroup > total `div` 2
         then case minorityGroup of
                [(aid, _)] -> CompMajority aid
                _          -> CompInconclusive  -- multiple dissenters
         else CompInconclusive
  | otherwise = CompInconclusive

-- | Canonical JSON comparison: parse both as JSON, re-encode canonically, compare.
canonicalEqual :: ByteString -> ByteString -> Bool
canonicalEqual a b =
  case (Aeson.decodeStrict a :: Maybe Aeson.Value, Aeson.decodeStrict b :: Maybe Aeson.Value) of
    (Just va, Just vb) -> Aeson.encode va == Aeson.encode vb
    _ -> a == b  -- fallback to byte comparison if not valid JSON
