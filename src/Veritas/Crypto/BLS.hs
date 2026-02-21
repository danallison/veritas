-- | BLS12-381 signature verification for drand quicknet beacons.
--
-- drand quicknet uses the @bls-unchained-g1-rfc9380@ scheme:
-- signatures on G1 (48 bytes compressed), public key on G2 (96 bytes compressed).
-- Message = SHA-256(big_endian_uint64(round)).
module Veritas.Crypto.BLS
  ( verifyDrandBeacon
  , DrandVerifyError(..)
  , roundToMessage
  ) where

import Crypto.BLST
  ( PublicKey, Signature, BlstError(..), Curve(..), EncodeMethod(..)
  , decompressPk, decompressSignature, verify
  )
import Crypto.Hash (SHA256(..), hashWith)
import Data.Bits (shiftR)
import Data.ByteArray (convert)
import Data.ByteArray.Sized (SizedByteArray, sizedByteArray)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word8)
import GHC.Natural (Natural)

import Veritas.Crypto.Hash (sha256)

-- | Errors from drand beacon BLS verification.
data DrandVerifyError
  = BLSInvalidPublicKey Text
  | BLSInvalidSignature Text
  | BLSSignatureVerifyFailed
  | BLSRandomnessMismatch
    -- ^ @randomness /= SHA-256(signature)@
  deriving stock (Show, Eq)

-- | The DST for drand quicknet (bls-unchained-g1-rfc9380).
quicknetDST :: ByteString
quicknetDST = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"

-- | Verify a drand quicknet beacon response.
--
-- Parameters:
--   * @pkBytes@ — 96-byte compressed G2 public key
--   * @roundNum@ — the beacon round number
--   * @sigBytes@ — 48-byte compressed G1 signature
--   * @randomnessBytes@ — 32-byte randomness (must equal SHA-256 of signature)
verifyDrandBeacon
  :: ByteString   -- ^ public key (96 bytes, compressed G2)
  -> Natural      -- ^ round number
  -> ByteString   -- ^ signature (48 bytes, compressed G1)
  -> ByteString   -- ^ randomness (32 bytes)
  -> Either DrandVerifyError ()
verifyDrandBeacon pkBytes roundNum sigBytes randomnessBytes = do
  -- Step 1: Verify randomness == SHA-256(signature)
  let expectedRandomness = sha256 sigBytes
  if randomnessBytes /= expectedRandomness
    then Left BLSRandomnessMismatch
    else pure ()

  -- Step 2: Decompress public key (G2, 96 bytes)
  pk <- decompressPkG2 pkBytes

  -- Step 3: Decompress signature (G1, 48 bytes)
  sig <- decompressSigG1 sigBytes

  -- Step 4: Construct message = SHA-256(big_endian_uint64(round))
  let msg = roundToMessage roundNum

  -- Step 5: Verify BLS signature
  let result = verify sig pk msg (Just quicknetDST)
  if result == BlstSuccess
    then Right ()
    else Left BLSSignatureVerifyFailed

-- | Decompress a 96-byte compressed G2 public key.
decompressPkG2 :: ByteString -> Either DrandVerifyError (PublicKey 'G2)
decompressPkG2 bs = case sizedByteArray bs :: Maybe (SizedByteArray 96 ByteString) of
  Nothing -> Left (BLSInvalidPublicKey (T.pack ("expected 96 bytes, got " <> show (BS.length bs))))
  Just sized -> case decompressPk sized of
    Left err -> Left (BLSInvalidPublicKey (T.pack (show err)))
    Right pk -> Right pk

-- | Decompress a 48-byte compressed G1 signature.
decompressSigG1 :: ByteString -> Either DrandVerifyError (Signature 'G2 'Hash)
decompressSigG1 bs = case sizedByteArray bs :: Maybe (SizedByteArray 48 ByteString) of
  Nothing -> Left (BLSInvalidSignature (T.pack ("expected 48 bytes, got " <> show (BS.length bs))))
  Just sized -> case decompressSignature sized of
    Left err  -> Left (BLSInvalidSignature (T.pack (show err)))
    Right sig -> Right sig

-- | Construct the drand unchained message: @SHA-256(big_endian_uint64(round))@.
roundToMessage :: Natural -> ByteString
roundToMessage n = convert (hashWith SHA256 (roundToBytes n))

-- | Encode a round number as 8-byte big-endian.
roundToBytes :: Natural -> ByteString
roundToBytes n = BS.pack
  [ byte 56, byte 48, byte 40, byte 32
  , byte 24, byte 16, byte 8, byte 0
  ]
  where
    byte :: Int -> Word8
    byte shift = fromIntegral (n `shiftR` shift)
