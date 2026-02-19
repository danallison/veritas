-- | Ed25519 request authentication.
--
-- For Phase 1, authentication is simplified: we trust participant IDs
-- in requests and verify signatures on commitments. Full request-level
-- auth (signed headers) is deferred to Phase 4.
module Veritas.API.Auth
  ( verifyCommitmentSignature
  ) where

import Data.ByteString (ByteString)
import Data.UUID (toASCIIBytes, UUID)

import Veritas.Crypto.Signatures (verifyMsg)

-- | Verify that a commitment signature is valid.
-- The signed message is (ceremony_id || participant_id).
verifyCommitmentSignature :: ByteString  -- ^ participant's public key
                          -> ByteString  -- ^ signature
                          -> UUID        -- ^ ceremony ID
                          -> UUID        -- ^ participant ID
                          -> Bool
verifyCommitmentSignature pubKey sig ceremonyId participantId =
  let msg = toASCIIBytes ceremonyId <> toASCIIBytes participantId
  in verifyMsg pubKey sig msg
