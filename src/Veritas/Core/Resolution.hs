-- | Deterministic outcome derivation from entropy.
--
-- Given the same entropy inputs, the same outcome is always produced.
-- Uses HKDF-SHA256 for uniform derivation with negligible bias.
module Veritas.Core.Resolution
  ( resolve
  , combineEntropy
  , deriveCoinFlip
  , deriveChoice
  , deriveShuffle
  , deriveIntRange
  , deriveWeightedChoice
  ) where

import Data.Bits (xor)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List (sortBy)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Data.Ord (comparing)
import Data.Text (Text)
import Data.UUID (toASCIIBytes)

import Veritas.Core.Types
import Veritas.Crypto.Hash (sha256, deriveUniform, deriveNth)

-- | Resolve a ceremony: combine entropy and derive the outcome.
resolve :: CeremonyType -> [EntropyContribution] -> Outcome
resolve ctype contributions =
  let entropy = combineEntropy contributions
      result = deriveResult ctype entropy
  in Outcome
    { outcomeValue = result
    , combinedEntropy = entropy
    , outcomeProof = OutcomeProof
        { proofEntropyInputs = contributions
        , proofDerivation = "HKDF-SHA256 derivation from combined entropy"
        }
    }

-- | Combine multiple entropy contributions into a single value.
-- Contributions are sorted by source for determinism, then XORed,
-- and the result is hashed with SHA-256.
combineEntropy :: [EntropyContribution] -> ByteString
combineEntropy [] = sha256 "veritas-empty-entropy"
combineEntropy contributions =
  let sorted = sortBy (comparing sourceKey) contributions
      xored = foldl1 xorBytes (map ecValue sorted)
  in sha256 xored

-- | Deterministic sort key for an entropy source.
-- Uses a stable serialization for ordering.
sourceKey :: EntropyContribution -> (Int, ByteString)
sourceKey ec = case ecSource ec of
  ParticipantEntropy (ParticipantId pid) -> (0, toASCIIBytes pid)
  DefaultEntropy (ParticipantId pid)     -> (1, toASCIIBytes pid)
  BeaconEntropy _                        -> (2, "beacon")
  VRFEntropy _                           -> (3, "vrf")

-- | XOR two bytestrings, padding the shorter one with zeros
xorBytes :: ByteString -> ByteString -> ByteString
xorBytes a b =
  let len = max (BS.length a) (BS.length b)
      a' = a <> BS.replicate (len - BS.length a) 0
      b' = b <> BS.replicate (len - BS.length b) 0
  in BS.pack (BS.zipWith xor a' b')

-- | Derive the appropriate result type from entropy
deriveResult :: CeremonyType -> ByteString -> CeremonyResult
deriveResult ctype entropy = case ctype of
  CoinFlip              -> CoinFlipResult (deriveCoinFlip entropy)
  UniformChoice choices -> ChoiceResult (deriveChoice entropy choices)
  Shuffle items         -> ShuffleResult (deriveShuffle entropy items)
  IntRange lo hi        -> IntRangeResult (deriveIntRange entropy lo hi)
  WeightedChoice wcs    -> WeightedChoiceResult (deriveWeightedChoice entropy wcs)

-- | Derive a fair coin flip from entropy
deriveCoinFlip :: ByteString -> Bool
deriveCoinFlip entropy = deriveUniform entropy >= (1/2 :: Rational)

-- | Derive a uniform choice from a non-empty list
deriveChoice :: ByteString -> NonEmpty Text -> Text
deriveChoice entropy choices =
  let n = NE.length choices
      r = deriveUniform entropy
      idx = floor (r * fromIntegral n) :: Int
      safeIdx = min idx (n - 1)
  in NE.toList choices !! safeIdx

-- | Derive a Fisher-Yates shuffle from entropy
deriveShuffle :: ByteString -> NonEmpty Text -> [Text]
deriveShuffle entropy items =
  let xs = NE.toList items
      n = length xs
      tagged = zip [0 :: Int ..] xs
      shuffled = fisherYates entropy n tagged
  in map snd shuffled

-- | Fisher-Yates shuffle using deterministic sub-values from HKDF
fisherYates :: ByteString -> Int -> [(Int, a)] -> [(Int, a)]
fisherYates _ 0 xs = xs
fisherYates _ 1 xs = xs
fisherYates entropy n xs = go (n - 1) xs
  where
    go 0 ys = ys
    go i ys =
      let r = deriveNth entropy i
          j = floor (r * fromIntegral (i + 1)) :: Int
          safeJ = min j i
          swapped = swap safeJ i ys
      in go (i - 1) swapped

    swap i j ys
      | i == j    = ys
      | otherwise =
          let yi = ys !! i
              yj = ys !! j
          in replaceAt i yj (replaceAt j yi ys)

    replaceAt idx val xs' =
      case splitAt idx xs' of
        (before, _:after) -> before ++ [val] ++ after
        (before, [])      -> before ++ [val]

-- | Derive an integer in [lo, hi] from entropy
deriveIntRange :: ByteString -> Int -> Int -> Int
deriveIntRange entropy lo hi
  | lo > hi   = deriveIntRange entropy hi lo
  | lo == hi  = lo
  | otherwise =
      let range = hi - lo + 1
          r = deriveUniform entropy
          offset = floor (r * fromIntegral range) :: Int
      in lo + min offset (range - 1)

-- | Derive a weighted choice from entropy
deriveWeightedChoice :: ByteString -> NonEmpty (Text, Rational) -> Text
deriveWeightedChoice entropy wcs =
  let total = sum (map snd (NE.toList wcs))
      r = deriveUniform entropy * total
  in pick r (NE.toList wcs)
  where
    pick _ [(label, _)] = label
    pick remaining ((label, weight):rest)
      | remaining < weight = label
      | otherwise = pick (remaining - weight) rest
    pick _ [] = error "deriveWeightedChoice: impossible empty list"
