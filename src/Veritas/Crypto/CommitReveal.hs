-- | Commit-reveal scheme for Methods A and D.
--
-- Seal: H(ceremony_id || participant_id || entropy_value)
-- Verify: recompute the seal from the revealed value and compare.
module Veritas.Crypto.CommitReveal
  ( createSeal
  , verifySeal
  , defaultEntropyValue
  ) where

import Data.ByteString (ByteString)
import Data.UUID (toASCIIBytes)

import Veritas.Core.Types (CeremonyId(..), ParticipantId(..))
import Veritas.Crypto.Hash (sha256)

-- | Create an entropy seal: H(ceremony_id || participant_id || entropy_value)
createSeal :: CeremonyId -> ParticipantId -> ByteString -> ByteString
createSeal (CeremonyId cid) (ParticipantId pid) entropyValue =
  sha256 (toASCIIBytes cid <> toASCIIBytes pid <> entropyValue)

-- | Verify that a revealed value matches its seal
verifySeal :: CeremonyId -> ParticipantId -> ByteString -> ByteString -> Bool
verifySeal cid pid entropyValue sealHash =
  createSeal cid pid entropyValue == sealHash

-- | Deterministic default value for non-participating participants.
-- Used when NonParticipationPolicy = DefaultSubstitution.
-- The default is deterministic so the outcome remains reproducible.
defaultEntropyValue :: CeremonyId -> ParticipantId -> ByteString
defaultEntropyValue (CeremonyId cid) (ParticipantId pid) =
  sha256 ("veritas-default-entropy:" <> toASCIIBytes cid <> toASCIIBytes pid)
