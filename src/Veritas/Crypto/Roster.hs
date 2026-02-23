-- | Cryptographic functions for self-certified ceremony identity.
--
-- Handles roster payload serialization, signature verification for roster
-- acknowledgments, and commitment signing for self-certified ceremonies.
module Veritas.Crypto.Roster
  ( buildRosterPayload
  , verifyRosterSignature
  , buildCommitPayload
  , verifyCommitSignature
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List (sortBy)
import Data.Ord (comparing)
import Data.UUID (toASCIIBytes)

import Veritas.Core.Types (CeremonyId(..), ParticipantId(..), Roster)
import Veritas.Crypto.Signatures (verifyMsg)

-- | Build the canonical roster payload for signing (v2 with params hash).
-- Format: "veritas-roster-v2:" ++ ceremony_id ++ params_hash (32 bytes) ++ sorted [(pid, pk)]
-- Participants are sorted by ParticipantId (UUID lexicographic).
buildRosterPayload :: CeremonyId -> ByteString -> Roster -> ByteString
buildRosterPayload (CeremonyId cid) paramsHash roster =
  let sorted = sortBy (comparing fst) roster
      cidBytes = toASCIIBytes cid
      entryBytes = concatMap (\(ParticipantId pid, pk) ->
        [toASCIIBytes pid, pk]) sorted
  in BS.concat (["veritas-roster-v2:", cidBytes, paramsHash] ++ entryBytes)

-- | Verify a participant's Ed25519 signature over the canonical roster payload.
-- Looks up the participant's public key in the roster and verifies.
verifyRosterSignature :: CeremonyId
                      -> ByteString    -- ^ params hash (32 bytes)
                      -> Roster
                      -> ParticipantId
                      -> ByteString    -- ^ signature
                      -> Bool
verifyRosterSignature cid paramsHash roster pid sig =
  case lookup pid roster of
    Nothing -> False
    Just pk ->
      let payload = buildRosterPayload cid paramsHash roster
      in verifyMsg pk sig payload

-- | Build the commit payload for self-certified ceremony commitment signing (v2).
-- Format: "veritas-commit-v2:" ++ ceremony_id ++ participant_id ++ params_hash (32 bytes) ++ seal
buildCommitPayload :: CeremonyId -> ParticipantId -> ByteString -> Maybe ByteString -> ByteString
buildCommitPayload (CeremonyId cid) (ParticipantId pid) paramsHash mSeal =
  BS.concat
    [ "veritas-commit-v2:"
    , toASCIIBytes cid
    , toASCIIBytes pid
    , paramsHash
    , maybe BS.empty id mSeal
    ]

-- | Verify a participant's Ed25519 signature over the commit payload.
verifyCommitSignature :: ByteString  -- ^ public key
                      -> ByteString  -- ^ signature
                      -> CeremonyId
                      -> ParticipantId
                      -> ByteString  -- ^ params hash (32 bytes)
                      -> Maybe ByteString  -- ^ seal hash
                      -> Bool
verifyCommitSignature pk sig cid pid paramsHash mSeal =
  let payload = buildCommitPayload cid pid paramsHash mSeal
  in verifyMsg pk sig payload
