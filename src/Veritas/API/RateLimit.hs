-- | Simple per-IP token bucket rate limiter as WAI middleware.
module Veritas.API.RateLimit
  ( RateLimitConfig(..)
  , newRateLimiter
  ) where

import Data.IORef (IORef, newIORef, atomicModifyIORef')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Network.HTTP.Types (status429)
import Network.Wai (Middleware, rawPathInfo, remoteHost, responseLBS)
import Network.Socket (SockAddr(..))

-- | Configuration for the rate limiter
data RateLimitConfig = RateLimitConfig
  { rlMaxRequests   :: Int  -- ^ Max requests per window
  , rlWindowSeconds :: Int  -- ^ Window duration in seconds
  }

data BucketEntry = BucketEntry
  { beCount     :: !Int
  , beWindowStart :: !UTCTime
  }

-- | Create a new rate limiter middleware.
-- Health check (/health) is exempt.
newRateLimiter :: RateLimitConfig -> IO Middleware
newRateLimiter cfg = do
  ref <- newIORef (Map.empty :: Map ByteString BucketEntry)
  pure (rateLimitMiddleware cfg ref)

rateLimitMiddleware :: RateLimitConfig -> IORef (Map ByteString BucketEntry) -> Middleware
rateLimitMiddleware cfg ref app req respond = do
  -- Exempt health check
  if rawPathInfo req == "/health"
    then app req respond
    else do
      now <- getCurrentTime
      let ip = sockAddrToBS (remoteHost req)
          windowSecs = fromIntegral (rlWindowSeconds cfg)
      allowed <- atomicModifyIORef' ref $ \buckets ->
        let -- Prune stale entries (older than 2x window)
            pruned = Map.filter (\e -> diffUTCTime now (beWindowStart e) < 2 * windowSecs) buckets
        in case Map.lookup ip pruned of
          Nothing ->
            let entry = BucketEntry { beCount = 1, beWindowStart = now }
            in (Map.insert ip entry pruned, True)
          Just entry
            | diffUTCTime now (beWindowStart entry) >= windowSecs ->
                -- Window expired, reset
                let entry' = BucketEntry { beCount = 1, beWindowStart = now }
                in (Map.insert ip entry' pruned, True)
            | beCount entry >= rlMaxRequests cfg ->
                -- Over limit
                (pruned, False)
            | otherwise ->
                -- Increment
                let entry' = entry { beCount = beCount entry + 1 }
                in (Map.insert ip entry' pruned, True)
      if allowed
        then app req respond
        else respond $ responseLBS status429 [("Content-Type", "text/plain")] "Too Many Requests"

-- | Extract a key from a SockAddr for rate limiting
sockAddrToBS :: SockAddr -> ByteString
sockAddrToBS (SockAddrInet _ host) = BS8.pack (show host)
sockAddrToBS (SockAddrInet6 _ _ host _) = BS8.pack (show host)
sockAddrToBS (SockAddrUnix path) = BS8.pack path
