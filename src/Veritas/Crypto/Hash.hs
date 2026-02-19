module Veritas.Crypto.Hash
  ( sha256
  , sha256Lazy
  , hkdfSHA256
  , deriveUniform
  , deriveNth
  , bytesToInteger
  , genesisHash
  ) where

import Crypto.Hash (SHA256(..), hashWith)
import Crypto.KDF.HKDF (PRK, extract, expand)
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

-- | Compute SHA-256 hash
sha256 :: ByteString -> ByteString
sha256 = convert . hashWith SHA256

-- | Compute SHA-256 hash of lazy bytestring
sha256Lazy :: LBS.ByteString -> ByteString
sha256Lazy = sha256 . LBS.toStrict

-- | HKDF-SHA256: extract + expand
hkdfSHA256 :: ByteString  -- ^ info/label
           -> ByteString  -- ^ input keying material
           -> Int          -- ^ output length in bytes
           -> ByteString
hkdfSHA256 info ikm len =
  let prk :: PRK SHA256
      prk = extract ("veritas-salt" :: ByteString) ikm
  in expand prk info len

-- | Derive a uniform Rational in [0, 1) from entropy using HKDF
deriveUniform :: ByteString -> Rational
deriveUniform entropy =
  let n = bytesToInteger (hkdfSHA256 "veritas-uniform" entropy 32)
  in fromInteger n / fromInteger (2 ^ (256 :: Integer))

-- | Derive the nth sub-value for Fisher-Yates shuffle
deriveNth :: ByteString -> Int -> Rational
deriveNth entropy i =
  let label = "veritas-shuffle-" <> BS.pack (map (fromIntegral . fromEnum) (show i))
      n = bytesToInteger (hkdfSHA256 label entropy 32)
  in fromInteger n / fromInteger (2 ^ (256 :: Integer))

-- | Convert a big-endian ByteString to an Integer
bytesToInteger :: ByteString -> Integer
bytesToInteger = BS.foldl' (\acc b -> acc * 256 + fromIntegral b) 0

-- | The genesis hash (all zeros) used as prevHash for the first log entry
genesisHash :: ByteString
genesisHash = BS.replicate 32 0
