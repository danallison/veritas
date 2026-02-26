-- | Seal construction and verification for computation cross-validation.
--
-- Seal: SHA-256(fingerprint || agent_id || result_bytes || evidence_hash || nonce)
-- Reuses Veritas.Crypto.Hash.sha256 for consistency.
module Veritas.Pool.Seal
  ( computeFingerprint
  , createSeal
  , verifySeal
  , verifySealSignature
  , computeEvidenceHash
  ) where

import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.UUID (toASCIIBytes)

import Veritas.Crypto.Hash (sha256)
import Veritas.Crypto.Signatures (verifyMsg)
import Veritas.Pool.Types (AgentId(..), Fingerprint(..), ComputationSpec, ExecutionEvidence)

-- | Compute a content-addressed fingerprint for a computation spec.
-- fingerprint = SHA-256(canonical_json(spec))
computeFingerprint :: ComputationSpec -> Fingerprint
computeFingerprint spec =
  Fingerprint (sha256 (LBS.toStrict (Aeson.encode spec)))

-- | Create a seal over a computation result.
-- seal = SHA-256(fingerprint || agent_id || result_bytes || evidence_hash || nonce)
createSeal :: Fingerprint
           -> AgentId
           -> ByteString    -- ^ result bytes
           -> ByteString    -- ^ evidence hash
           -> ByteString    -- ^ nonce
           -> ByteString
createSeal (Fingerprint fp) (AgentId aid) resultBytes evidenceHash nonce =
  sha256 (fp <> toASCIIBytes aid <> resultBytes <> evidenceHash <> nonce)

-- | Verify a seal by recomputing it from revealed values and comparing.
verifySeal :: Fingerprint
           -> AgentId
           -> ByteString    -- ^ result bytes
           -> ByteString    -- ^ evidence hash
           -> ByteString    -- ^ nonce
           -> ByteString    -- ^ submitted seal hash
           -> Bool
verifySeal fp aid resultBytes evidenceHash nonce submittedSeal =
  createSeal fp aid resultBytes evidenceHash nonce == submittedSeal

-- | Verify an Ed25519 signature over a seal hash.
-- The agent signs the seal hash with their secret key; this verifies
-- using their registered public key.
verifySealSignature :: ByteString    -- ^ agent's public key (32 bytes)
                    -> ByteString    -- ^ seal hash (the message that was signed)
                    -> ByteString    -- ^ seal signature (64 bytes)
                    -> Bool
verifySealSignature publicKey sealHash sealSig =
  verifyMsg publicKey sealSig sealHash

-- | Compute a hash of execution evidence for inclusion in seals.
-- evidence_hash = SHA-256(canonical_json(evidence))
computeEvidenceHash :: ExecutionEvidence -> ByteString
computeEvidenceHash evidence =
  sha256 (LBS.toStrict (Aeson.encode evidence))
