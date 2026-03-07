-- | Test data builders for integration tests.
module Integration.CeremonyFixtures
  ( TestParticipant(..)
  , mkTestParticipant
  , mkVRFCeremonyReq
  , mkParticipantRevealCeremonyReq
  , mkJoinRequest
  , mkAckRosterRequest
  , mkSignedCommitRequest
  , mkSignedCommitRequestWithSeal
  , mkCommitRequest
  , mkRevealRequest
  , makeEntropyValue
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.ByteArray.Encoding (convertFromBase, Base(Base16))
import Data.Time (addUTCTime, getCurrentTime)
import Data.UUID (UUID)
import qualified Data.UUID.V4 as UUID4
import GHC.Natural (Natural)

import Veritas.API.Types
  ( CreateCeremonyRequest(..), CommitRequest(..), RevealRequest(..)
  , JoinRequest(..), AckRosterRequest(..)
  , CeremonyResponse(..), RosterEntryResponse(..)
  )
import Veritas.Core.Types (CeremonyId(..), CeremonyType(..), CommitmentMode(..), EntropyMethod(..), IdentityMode(..), NonParticipationPolicy(..), ParticipantId(..))
import Veritas.Crypto.CommitReveal (createSeal)
import Veritas.Crypto.Hash (sha256, hexEncode)
import Veritas.Crypto.Roster (buildRosterPayload, buildCommitPayload)
import Veritas.Crypto.Signatures (KeyPair(..), generateKeyPair, signMsg, publicKeyBytes)

-- | A test participant with a UUID and an Ed25519 keypair.
data TestParticipant = TestParticipant
  { tpId      :: UUID
  , tpKeyPair :: KeyPair
  }

-- | Generate a test participant with a fresh UUID and keypair.
mkTestParticipant :: IO TestParticipant
mkTestParticipant = do
  pid <- UUID4.nextRandom
  kp <- generateKeyPair
  pure TestParticipant { tpId = pid, tpKeyPair = kp }

-- | Create a request for an OfficiantVRF ceremony.
-- Uses Immediate mode with a 1-hour commit deadline.
mkVRFCeremonyReq :: Natural -> IO CreateCeremonyRequest
mkVRFCeremonyReq numParties = do
  now <- getCurrentTime
  pure CreateCeremonyRequest
    { crqQuestion               = "Test VRF ceremony"
    , crqCeremonyType           = CoinFlip "Heads" "Tails"
    , crqEntropyMethod          = OfficiantVRF
    , crqRequiredParties        = numParties
    , crqCommitmentMode         = Immediate
    , crqCommitDeadline         = addUTCTime 3600 now
    , crqRevealDeadline         = Nothing
    , crqNonParticipationPolicy = Nothing
    , crqBeaconSpec             = Nothing
    , crqCreatedBy              = Nothing
    , crqIdentityMode           = Just SelfCertified
    }

-- | Create a request for a ParticipantReveal ceremony.
-- Uses Immediate mode with 1-hour deadlines and Exclusion policy.
mkParticipantRevealCeremonyReq :: Natural -> IO CreateCeremonyRequest
mkParticipantRevealCeremonyReq numParties = do
  now <- getCurrentTime
  pure CreateCeremonyRequest
    { crqQuestion               = "Test participant-reveal ceremony"
    , crqCeremonyType           = CoinFlip "Heads" "Tails"
    , crqEntropyMethod          = ParticipantReveal
    , crqRequiredParties        = numParties
    , crqCommitmentMode         = Immediate
    , crqCommitDeadline         = addUTCTime 3600 now
    , crqRevealDeadline         = Just (addUTCTime 7200 now)
    , crqNonParticipationPolicy = Just Exclusion
    , crqBeaconSpec             = Nothing
    , crqCreatedBy              = Nothing
    , crqIdentityMode           = Just SelfCertified
    }

-- | Create a JoinRequest for a test participant.
mkJoinRequest :: TestParticipant -> JoinRequest
mkJoinRequest tp = JoinRequest
  { jrqParticipantId = tpId tp
  , jrqPublicKey = hexEncode (publicKeyBytes (kpPublic (tpKeyPair tp)))
  , jrqDisplayName = Nothing
  }

-- | Create an AckRosterRequest for a test participant.
-- Signs the roster payload using the participant's keypair.
mkAckRosterRequest :: UUID -> CeremonyResponse -> TestParticipant -> AckRosterRequest
mkAckRosterRequest cid ceremony tp =
  let paramsHash = hexDecodeUnsafe (crspParamsHash ceremony)
      roster = rosterFromResponse (fromMaybe [] (crspRoster ceremony))
      payload = buildRosterPayload (CeremonyId cid) paramsHash roster
      sig = signMsg (kpSecret (tpKeyPair tp)) (kpPublic (tpKeyPair tp)) payload
  in AckRosterRequest
    { arrqParticipantId = tpId tp
    , arrqSignature = hexEncode sig
    }

-- | Create a signed CommitRequest without a seal (for VRF ceremonies).
mkSignedCommitRequest :: UUID -> CeremonyResponse -> TestParticipant -> CommitRequest
mkSignedCommitRequest cid ceremony tp =
  let paramsHash = hexDecodeUnsafe (crspParamsHash ceremony)
      payload = buildCommitPayload (CeremonyId cid) (ParticipantId (tpId tp)) paramsHash Nothing
      sig = signMsg (kpSecret (tpKeyPair tp)) (kpPublic (tpKeyPair tp)) payload
  in CommitRequest
    { cmrqParticipantId = tpId tp
    , cmrqEntropySeal = Nothing
    , cmrqDisplayName = Nothing
    , cmrqSignature = Just (hexEncode sig)
    }

-- | Create a signed CommitRequest with an entropy seal (for ParticipantReveal).
mkSignedCommitRequestWithSeal :: UUID -> CeremonyResponse -> TestParticipant -> Int -> CommitRequest
mkSignedCommitRequestWithSeal cid ceremony tp idx =
  let entropyVal = makeEntropyValue idx
      seal = createSeal (CeremonyId cid) (ParticipantId (tpId tp)) entropyVal
      paramsHash = hexDecodeUnsafe (crspParamsHash ceremony)
      payload = buildCommitPayload (CeremonyId cid) (ParticipantId (tpId tp)) paramsHash (Just seal)
      sig = signMsg (kpSecret (tpKeyPair tp)) (kpPublic (tpKeyPair tp)) payload
  in CommitRequest
    { cmrqParticipantId = tpId tp
    , cmrqEntropySeal = Just (hexEncode seal)
    , cmrqDisplayName = Just ("Participant " <> T.pack (show idx))
    , cmrqSignature = Just (hexEncode sig)
    }

-- | Create a commit request without a seal or signature (for error testing).
mkCommitRequest :: UUID -> CommitRequest
mkCommitRequest pid = CommitRequest
  { cmrqParticipantId = pid
  , cmrqEntropySeal   = Nothing
  , cmrqDisplayName   = Nothing
  , cmrqSignature     = Nothing
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

-- | Decode hex Text to ByteString (errors on invalid hex).
hexDecodeUnsafe :: T.Text -> ByteString
hexDecodeUnsafe t = case convertFromBase Base16 (TE.encodeUtf8 t) of
  Left err -> error ("hexDecodeUnsafe: " <> show (err :: String))
  Right bs -> bs

-- | Convert RosterEntryResponse list to Roster [(ParticipantId, ByteString)].
rosterFromResponse :: [RosterEntryResponse] -> [(ParticipantId, ByteString)]
rosterFromResponse = map (\re -> (ParticipantId (reParticipantId re), hexDecodeUnsafe (rePublicKey re)))
