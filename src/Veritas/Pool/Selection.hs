-- | Stratified validator selection using drand beacon randomness.
--
-- Given a pool of agents, a requester's principal, and a beacon signature,
-- select N validators from different principals than the requester and each other.
module Veritas.Pool.Selection
  ( stratifiedSelect
  , deterministicShuffle
  , SelectionError(..)
  ) where

import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List (foldl', nub)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import Data.Word (Word8)
import Control.Monad (forM_)
import Control.Monad.ST (runST)

import Veritas.Crypto.Hash (sha256)
import Veritas.Pool.Types (PoolMember(..), PrincipalId)

-- | Errors from validator selection
data SelectionError
  = NotEnoughPrincipals Int Int  -- ^ required (N validators + 1 requester), available
  deriving stock (Eq, Show)

-- | Select N validators from the pool using stratified selection.
--
-- Rules:
-- 1. Exclude agents belonging to the requester's principal
-- 2. No two selected validators share the same principal
-- 3. Selection order is deterministic given the same seed
--
-- The seed should be a drand beacon signature.
-- Returns an error if there aren't enough distinct principals to fill N validator slots.
-- The protocol requires N+1 distinct principals (1 requester + N validators).
stratifiedSelect :: [PoolMember]    -- ^ all pool members
                 -> PrincipalId     -- ^ requester's principal (excluded)
                 -> ByteString      -- ^ seed (drand beacon signature)
                 -> Int             -- ^ number of validators to select
                 -> Either SelectionError [PoolMember]
stratifiedSelect members requesterPrincipal seed n =
  let -- Filter out members from the requester's principal
      eligible = filter (\m -> pmPrincipalId m /= requesterPrincipal) members
      -- Count distinct eligible principals
      distinctPrincipals = length (nub (map pmPrincipalId eligible))
      -- Shuffle deterministically
      shuffled = deterministicShuffle eligible seed
      -- Pick first N from different principals
      pickDistinct [] _ _ = []
      pickDistinct _ 0 _ = []
      pickDistinct (m:ms) remaining usedPrincipals
        | pmPrincipalId m `elem` usedPrincipals = pickDistinct ms remaining usedPrincipals
        | otherwise = m : pickDistinct ms (remaining - 1) (pmPrincipalId m : usedPrincipals)
      selected = pickDistinct shuffled n []
  in if length selected < n
     then Left (NotEnoughPrincipals (n + 1) (distinctPrincipals + 1))
     else Right selected

-- | Fisher-Yates shuffle using a seed derived from beacon randomness.
--
-- For each position i from (n-1) down to 1, derive a swap index j in [0..i]
-- using SHA-256(seed || i) to generate deterministic randomness.
deterministicShuffle :: [a] -> ByteString -> [a]
deterministicShuffle [] _ = []
deterministicShuffle [x] _ = [x]
deterministicShuffle xs seed = runST $ do
  let vec = V.fromList xs
      len = V.length vec
  mvec <- V.thaw vec
  forM_ [len - 1, len - 2 .. 1] $ \i -> do
    let indexBytes = BS.pack (encodeInt i)
        hash = sha256 (seed <> indexBytes)
        j = bytesToNat hash `mod` (i + 1)
    -- Swap elements at positions i and j
    vi <- MV.read mvec i
    vj <- MV.read mvec j
    MV.write mvec i vj
    MV.write mvec j vi
  result <- V.freeze mvec
  pure (V.toList result)

-- | Encode an Int as big-endian bytes (4 bytes)
encodeInt :: Int -> [Word8]
encodeInt n =
  [ fromIntegral (n `shiftR` 24 .&. 0xff)
  , fromIntegral (n `shiftR` 16 .&. 0xff)
  , fromIntegral (n `shiftR` 8  .&. 0xff)
  , fromIntegral (n             .&. 0xff)
  ]

-- | Convert first 8 bytes of a ByteString to a non-negative Int
bytesToNat :: ByteString -> Int
bytesToNat bs =
  let bytes = BS.unpack (BS.take 8 bs)
  in foldl' (\acc b -> acc * 256 + fromIntegral b) 0 bytes
