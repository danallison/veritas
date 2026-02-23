-- | Deterministic hashing of ceremony parameters.
--
-- Computes a canonical SHA-256 hash of all ceremony parameters so that
-- participants can cryptographically bind their roster acks and commitments
-- to the exact ceremony configuration they agreed to.
module Veritas.Crypto.CeremonyParams
  ( buildCeremonyParamsBytes
  , computeParamsHash
  , paramsHashHex
  ) where

import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Format.ISO8601 (iso8601Show)

import Veritas.Core.Types
import Veritas.Crypto.Hash (sha256, hexEncode)

-- | Build a deterministic binary serialization of all ceremony parameters.
buildCeremonyParamsBytes :: Ceremony -> ByteString
buildCeremonyParamsBytes Ceremony{..} = BS.concat
  [ "veritas-params-v1:"
  , lpString question
  , ceremonyTypeBytes ceremonyType
  , lpString (T.pack (show entropyMethod))
  , u32be (fromIntegral requiredParties)
  , lpString (T.pack (show commitmentMode))
  , lpString (T.pack (iso8601Show commitDeadline))
  , optional (fmap (lpString . T.pack . iso8601Show) revealDeadline)
  , optional (fmap (lpString . T.pack . show) nonParticipationPolicy)
  , optional (fmap beaconSpecBytes beaconSpec)
  , lpString (T.pack (show identityMode))
  ]

-- | Compute the SHA-256 hash of the canonical ceremony parameters.
computeParamsHash :: Ceremony -> ByteString
computeParamsHash = sha256 . buildCeremonyParamsBytes

-- | Hex-encoded params hash for inclusion in API responses.
paramsHashHex :: Ceremony -> Text
paramsHashHex = hexEncode . computeParamsHash

-- === Binary encoding helpers ===

-- | Length-prefixed string: u32be(byteLength) ++ utf8Bytes(s)
lpString :: Text -> ByteString
lpString t =
  let bs = TE.encodeUtf8 t
  in u32be (BS.length bs) <> bs

-- | Big-endian 32-bit unsigned integer
u32be :: Int -> ByteString
u32be n = BS.pack
  [ fromIntegral (shiftR n 24 .&. 0xff)
  , fromIntegral (shiftR n 16 .&. 0xff)
  , fromIntegral (shiftR n  8 .&. 0xff)
  , fromIntegral (n           .&. 0xff)
  ]

-- | Optional encoding: Nothing -> 0x00, Just x -> 0x01 ++ x
optional :: Maybe ByteString -> ByteString
optional Nothing  = BS.singleton 0x00
optional (Just x) = BS.singleton 0x01 <> x

-- | Encode a CeremonyType to bytes.
ceremonyTypeBytes :: CeremonyType -> ByteString
ceremonyTypeBytes = \case
  CoinFlip a b -> lpString "CoinFlip" <> lpString a <> lpString b
  UniformChoice opts ->
    lpString "UniformChoice" <> u32be (NE.length opts) <> BS.concat (map lpString (NE.toList opts))
  Shuffle items ->
    lpString "Shuffle" <> u32be (NE.length items) <> BS.concat (map lpString (NE.toList items))
  IntRange lo hi ->
    lpString "IntRange" <> u32be lo <> u32be hi
  WeightedChoice wcs ->
    lpString "WeightedChoice" <> u32be (NE.length wcs)
      <> BS.concat [lpString label <> lpString (T.pack (show weight)) | (label, weight) <- NE.toList wcs]

-- | Encode a BeaconSpec to bytes.
beaconSpecBytes :: BeaconSpec -> ByteString
beaconSpecBytes BeaconSpec{..} = BS.concat
  [ lpString beaconNetwork
  , optional (fmap (u32be . fromIntegral) beaconRound)
  , beaconFallbackBytes beaconFallback
  ]

-- | Encode a BeaconFallback to bytes.
beaconFallbackBytes :: BeaconFallback -> ByteString
beaconFallbackBytes = \case
  ExtendDeadline dur ->
    BS.singleton 0x01 <> lpString (T.pack (show dur))
  AlternateSource spec ->
    BS.singleton 0x02 <> beaconSpecBytes spec
  CancelCeremony ->
    BS.singleton 0x03
