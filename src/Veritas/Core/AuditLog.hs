-- | Hash-chained audit log construction and verification.
--
-- Each ceremony has its own independent hash chain. Each entry's hash
-- covers the sequence number, ceremony ID, event, timestamp, and previous hash.
module Veritas.Core.AuditLog
  ( createLogEntry
  , computeEntryHash
  , verifyChain
  , verifyEntry
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Time (UTCTime)
import Data.UUID (toASCIIBytes)
import GHC.Natural (Natural)

import Veritas.Core.Types
import Veritas.Crypto.Hash (sha256, genesisHash)

-- | Create a new log entry, computing its hash from its contents and the previous hash.
createLogEntry :: LogSequence       -- ^ sequence number
              -> CeremonyId         -- ^ ceremony this belongs to
              -> CeremonyEvent      -- ^ the event
              -> UTCTime            -- ^ timestamp
              -> ByteString         -- ^ previous entry's hash (genesisHash for first)
              -> LogEntry
createLogEntry seqNum cid event ts prevHash =
  let entryHash = computeEntryHash seqNum cid event ts prevHash
  in LogEntry
    { logSequence  = seqNum
    , logCeremony  = cid
    , logEvent     = event
    , logTimestamp  = ts
    , logPrevHash  = prevHash
    , logEntryHash = entryHash
    }

-- | Compute the hash for a log entry.
-- hash = SHA-256(sequence || ceremony_id || event || timestamp || prev_hash)
computeEntryHash :: LogSequence -> CeremonyId -> CeremonyEvent -> UTCTime -> ByteString -> ByteString
computeEntryHash (LogSequence seqNum) (CeremonyId cid) event ts prevHash =
  sha256 $ BS.concat
    [ encodeNatural seqNum
    , toASCIIBytes cid
    , serializeEvent event
    , BS8.pack (show ts)
    , prevHash
    ]

-- | Verify an entire chain of log entries.
-- Returns Nothing if valid, or Just the first invalid entry's sequence number.
verifyChain :: [LogEntry] -> Maybe LogSequence
verifyChain [] = Nothing
verifyChain entries = go genesisHash entries
  where
    go _ [] = Nothing
    go expectedPrevHash (e:es)
      | logPrevHash e /= expectedPrevHash = Just (logSequence e)
      | not (verifyEntry e) = Just (logSequence e)
      | otherwise = go (logEntryHash e) es

-- | Verify a single log entry: recompute its hash and compare.
verifyEntry :: LogEntry -> Bool
verifyEntry LogEntry{..} =
  let computed = computeEntryHash logSequence logCeremony logEvent logTimestamp logPrevHash
  in computed == logEntryHash

-- | Encode a Natural as bytes for hashing
encodeNatural :: Natural -> ByteString
encodeNatural = BS8.pack . show

-- | Serialize a CeremonyEvent to bytes for hashing.
-- Uses a simple canonical serialization.
serializeEvent :: CeremonyEvent -> ByteString
serializeEvent = BS8.pack . show
