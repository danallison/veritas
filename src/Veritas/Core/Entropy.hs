-- | Entropy combination and seal verification utilities.
module Veritas.Core.Entropy
  ( verifySealForReveal
  , buildEntropyContributions
  ) where

import Data.ByteString (ByteString)

import Veritas.Core.Types
import Veritas.Crypto.CommitReveal (verifySeal)

-- | Verify that a revealed entropy value matches the committed seal.
verifySealForReveal :: CeremonyId
                    -> ParticipantId
                    -> ByteString      -- ^ revealed value
                    -> ByteString      -- ^ committed seal hash
                    -> Bool
verifySealForReveal = verifySeal

-- | Build entropy contributions from revealed values.
-- Each reveal becomes a ParticipantEntropy source.
buildEntropyContributions :: CeremonyId
                          -> [(ParticipantId, ByteString)]  -- ^ (participant, revealed value)
                          -> [EntropyContribution]
buildEntropyContributions cid reveals =
  [ EntropyContribution
      { ecCeremony = cid
      , ecSource = ParticipantEntropy pid
      , ecValue = val
      }
  | (pid, val) <- reveals
  ]
