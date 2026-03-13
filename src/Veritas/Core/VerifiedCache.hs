-- | Content-addressed cache of verified computation results.
--
-- Results are cached after successful verification (unanimous or majority).
-- Entries are immutable — once cached, they cannot be overwritten.
-- Removal only through TTL expiration or explicit challenge.
--
-- Pure domain logic, no IO.
module Veritas.Core.VerifiedCache
  ( -- * Types
    VerifiedCache
  , CacheEntry(..)
  , CacheProvenance(..)

    -- * Operations
  , emptyCache
  , cacheVerifiedResult
  , lookupCache
  , cacheSize
  , expireCache
  , removeEntry
  ) where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (UTCTime, NominalDiffTime, addUTCTime, diffUTCTime)

import Veritas.Core.Verification (Verdict(..), VerdictOutcome(..), isVerified)

-- | Provenance of a cached result.
data CacheProvenance = CacheProvenance
  { ceVerdictOutcome  :: VerdictOutcome
  , ceAgreementCount  :: Int
  , ceCachedAt        :: UTCTime
  } deriving stock (Eq, Show)

-- | A cached verified result.
data CacheEntry = CacheEntry
  { ceFingerprint :: Text              -- ^ Content hash of the computation spec
  , ceResult      :: ByteString        -- ^ The verified result
  , ceProvenance  :: CacheProvenance   -- ^ How it was verified
  , ceTtlSeconds  :: Maybe NominalDiffTime  -- ^ Optional time-to-live
  } deriving stock (Eq, Show)

-- | The verified result cache (in-memory, pure).
newtype VerifiedCache = VerifiedCache (Map Text CacheEntry)
  deriving stock (Eq, Show)

-- | An empty cache.
emptyCache :: VerifiedCache
emptyCache = VerifiedCache Map.empty

-- | Cache a verified result. Only caches if the verdict indicates success
-- (unanimous or majority). Does not overwrite existing entries (immutability).
cacheVerifiedResult :: VerifiedCache
                    -> Text           -- ^ fingerprint
                    -> ByteString     -- ^ result
                    -> Verdict        -- ^ the verification verdict
                    -> Maybe Int      -- ^ TTL in seconds (Nothing = no expiry)
                    -> VerifiedCache
cacheVerifiedResult cache@(VerifiedCache m) fingerprint result verdict ttlSeconds
  | not (isVerified verdict) = cache  -- don't cache inconclusive
  | Map.member fingerprint m = cache  -- immutability: don't overwrite
  | otherwise =
      let entry = CacheEntry
            { ceFingerprint = fingerprint
            , ceResult = result
            , ceProvenance = CacheProvenance
                { ceVerdictOutcome = verdictOutcome verdict
                , ceAgreementCount = verdictAgreementCount verdict
                , ceCachedAt = verdictDecidedAt verdict
                }
            , ceTtlSeconds = fmap fromIntegral ttlSeconds
            }
      in VerifiedCache (Map.insert fingerprint entry m)

-- | Look up a cached result by fingerprint.
lookupCache :: VerifiedCache -> Text -> Maybe CacheEntry
lookupCache (VerifiedCache m) = flip Map.lookup m

-- | Number of entries in the cache.
cacheSize :: VerifiedCache -> Int
cacheSize (VerifiedCache m) = Map.size m

-- | Remove expired entries based on current time.
expireCache :: VerifiedCache -> UTCTime -> VerifiedCache
expireCache (VerifiedCache m) now =
  VerifiedCache (Map.filter (not . isExpired) m)
  where
    isExpired entry = case ceTtlSeconds entry of
      Nothing -> False
      Just ttl ->
        let cachedAt = ceCachedAt (ceProvenance entry)
            expiresAt = addUTCTime ttl cachedAt
        in now >= expiresAt

-- | Remove a specific entry (for challenges/disputes).
removeEntry :: VerifiedCache -> Text -> VerifiedCache
removeEntry (VerifiedCache m) fingerprint =
  VerifiedCache (Map.delete fingerprint m)
