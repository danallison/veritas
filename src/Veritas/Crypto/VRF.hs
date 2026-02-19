-- | VRF (Verifiable Random Function) implementation for Method C.
--
-- Uses Ed25519 signatures as a simple VRF: the signature of a deterministic
-- input is unpredictable without the secret key, and verifiable with the
-- public key. The VRF output is the SHA-256 hash of the signature.
--
-- This is the ECVRF-ED25519-SHA512-ELL2 simplification: while not a full
-- standards-compliant VRF, it provides the core property we need — a
-- deterministic, verifiable random output that requires the secret key
-- to produce but only the public key to verify.
module Veritas.Crypto.VRF
  ( generateVRF
  , verifyVRF
  , vrfInput
  ) where

import Data.ByteString (ByteString)
import Data.UUID (toASCIIBytes)

import Veritas.Core.Types (CeremonyId(..), VRFOutput(..))
import Veritas.Crypto.Hash (sha256)
import Veritas.Crypto.Signatures (KeyPair(..), signMsg, verifyMsg, publicKeyBytes)

-- | Construct the deterministic VRF input for a ceremony
vrfInput :: CeremonyId -> ByteString
vrfInput (CeremonyId uuid) = "veritas-vrf-v1:" <> toASCIIBytes uuid

-- | Generate a VRF output for a ceremony using the server's key pair
generateVRF :: KeyPair -> CeremonyId -> VRFOutput
generateVRF KeyPair{..} cid =
  let input = vrfInput cid
      proof = signMsg kpSecret kpPublic input
      value = sha256 proof  -- VRF output = H(signature)
  in VRFOutput
    { vrfValue = value
    , vrfProof = proof
    , vrfPublicKey = publicKeyBytes kpPublic
    }

-- | Verify a VRF output: check the signature, then confirm value = H(signature)
verifyVRF :: CeremonyId -> VRFOutput -> Bool
verifyVRF cid VRFOutput{..} =
  let input = vrfInput cid
      sigValid = verifyMsg vrfPublicKey vrfProof input
      valueCorrect = sha256 vrfProof == vrfValue
  in sigValid && valueCorrect
