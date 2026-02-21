-- | Test data builders for integration tests.
module Integration.CeremonyFixtures
  ( mkVRFCeremonyReq
  , mkParticipantRevealCeremonyReq
  , mkCommitRequest
  , mkCommitRequestWithSeal
  , mkRevealRequest
  , makeEntropyValue
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.Text as T
import Data.Time (addUTCTime, getCurrentTime)
import Data.UUID (UUID)
import GHC.Natural (Natural)

import Veritas.API.Types (CreateCeremonyRequest(..), CommitRequest(..), RevealRequest(..))
import Veritas.Core.Types (CeremonyId(..), CeremonyType(..), CommitmentMode(..), EntropyMethod(..), NonParticipationPolicy(..), ParticipantId(..))
import Veritas.Crypto.CommitReveal (createSeal)
import Veritas.Crypto.Hash (sha256, hexEncode)

-- | Create a request for an OfficiantVRF ceremony.
-- Uses Immediate mode with a 1-hour commit deadline.
mkVRFCeremonyReq :: Natural -> IO CreateCeremonyRequest
mkVRFCeremonyReq numParties = do
  now <- getCurrentTime
  pure CreateCeremonyRequest
    { crqQuestion               = "Test VRF ceremony"
    , crqCeremonyType           = CoinFlip
    , crqEntropyMethod          = OfficiantVRF
    , crqRequiredParties        = numParties
    , crqCommitmentMode         = Immediate
    , crqCommitDeadline         = addUTCTime 3600 now
    , crqRevealDeadline         = Nothing
    , crqNonParticipationPolicy = Nothing
    , crqBeaconSpec             = Nothing
    , crqCreatedBy              = Nothing
    }

-- | Create a request for a ParticipantReveal ceremony.
-- Uses Immediate mode with 1-hour deadlines and Exclusion policy.
mkParticipantRevealCeremonyReq :: Natural -> IO CreateCeremonyRequest
mkParticipantRevealCeremonyReq numParties = do
  now <- getCurrentTime
  pure CreateCeremonyRequest
    { crqQuestion               = "Test participant-reveal ceremony"
    , crqCeremonyType           = CoinFlip
    , crqEntropyMethod          = ParticipantReveal
    , crqRequiredParties        = numParties
    , crqCommitmentMode         = Immediate
    , crqCommitDeadline         = addUTCTime 3600 now
    , crqRevealDeadline         = Just (addUTCTime 7200 now)
    , crqNonParticipationPolicy = Just Exclusion
    , crqBeaconSpec             = Nothing
    , crqCreatedBy              = Nothing
    }

-- | Create a commit request without a seal (for VRF ceremonies).
mkCommitRequest :: UUID -> CommitRequest
mkCommitRequest pid = CommitRequest
  { cmrqParticipantId = pid
  , cmrqEntropySeal   = Nothing
  , cmrqDisplayName   = Nothing
  }

-- | Create a commit request with an entropy seal (for ParticipantReveal).
-- The seal is computed as: SHA-256(ceremony_id || participant_id || entropy_value)
mkCommitRequestWithSeal :: UUID -> UUID -> Int -> CommitRequest
mkCommitRequestWithSeal ceremonyUuid pid idx =
  let entropyVal = makeEntropyValue idx
      seal = createSeal (CeremonyId ceremonyUuid) (ParticipantId pid) entropyVal
  in CommitRequest
    { cmrqParticipantId = pid
    , cmrqEntropySeal   = Just (hexEncode seal)
    , cmrqDisplayName   = Just ("Participant " <> T.pack (show idx))
    }

-- | Create a reveal request with hex-encoded entropy matching the seal.
mkRevealRequest :: UUID -> Int -> RevealRequest
mkRevealRequest pid idx = RevealRequest
  { rvrqParticipantId = pid
  , rvrqEntropyValue  = hexEncode (makeEntropyValue idx)
  }

-- | Generate a deterministic 32-byte entropy value for a given participant index.
makeEntropyValue :: Int -> ByteString
makeEntropyValue idx = sha256 (BS.pack (replicate 32 (fromIntegral idx)))
