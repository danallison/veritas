module Veritas.Crypto.BLSSpec (spec) where

import Data.ByteArray.Encoding (Base(..), convertFromBase)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Either (isLeft, isRight)
import GHC.Natural (Natural)
import Test.Hspec

import Veritas.Crypto.BLS
import Veritas.Crypto.Hash (sha256)

-- Quicknet public key (96 bytes, from drand /info endpoint)
quicknetPubKeyHex :: ByteString
quicknetPubKeyHex = "83cf0f2896adee7eb8b5f01fcad3912212c437e0073e911fb90022d3e760183c8c4b450b6a0a6c3ac6a5776a2d1064510d1fec758c921cc22b0e17e63aaf4bcb5ed66304de9cf809bd274ca73bab4af5a6e9c76a4bc09e76eae8991ef5ece45a"

quicknetPubKey :: ByteString
quicknetPubKey = fromHex quicknetPubKeyHex

-- Real drand quicknet beacon round 1000
testRound :: Natural
testRound = 1000

testSignatureHex :: ByteString
testSignatureHex = "b44679b9a59af2ec876b1a6b1ad52ea9b1615fc3982b19576350f93447cb1125e342b73a8dd2bacbe47e4b6b63ed5e39"

testSignature :: ByteString
testSignature = fromHex testSignatureHex

testRandomnessHex :: ByteString
testRandomnessHex = "fe290beca10872ef2fb164d2aa4442de4566183ec51c56ff3cd603d930e54fdd"

testRandomness :: ByteString
testRandomness = fromHex testRandomnessHex

fromHex :: ByteString -> ByteString
fromHex hex = case convertFromBase Base16 hex of
  Left err -> error ("fromHex failed: " <> show err)
  Right bs -> bs

spec :: Spec
spec = do
  describe "roundToMessage" $ do
    it "encodes round 0 as SHA-256 of 8 zero bytes" $ do
      let msg = roundToMessage 0
      -- SHA-256 of 8 zero bytes
      msg `shouldBe` sha256 (BS.replicate 8 0)

    it "encodes round 1 as SHA-256 of [0,0,0,0,0,0,0,1]" $ do
      let msg = roundToMessage 1
      msg `shouldBe` sha256 (BS.pack [0,0,0,0,0,0,0,1])

    it "encodes round 256 correctly" $ do
      let msg = roundToMessage 256
      msg `shouldBe` sha256 (BS.pack [0,0,0,0,0,0,1,0])

    it "encodes round 1000 correctly" $ do
      let msg = roundToMessage 1000
      -- 1000 = 0x03E8
      msg `shouldBe` sha256 (BS.pack [0,0,0,0,0,0,0x03,0xE8])

  describe "verifyDrandBeacon" $ do
    it "verifies a real drand quicknet beacon (round 1000)" $ do
      let result = verifyDrandBeacon quicknetPubKey testRound testSignature testRandomness
      result `shouldSatisfy` isRight

    it "rejects a tampered randomness value" $ do
      -- Use valid signature but wrong randomness
      let fakeRandomness = BS.replicate 32 0xAA
      let result = verifyDrandBeacon quicknetPubKey testRound testSignature fakeRandomness
      result `shouldSatisfy` isLeft
      result `shouldBe` Left BLSRandomnessMismatch

    it "rejects an invalid signature" $ do
      -- Corrupt one byte of the signature
      let badSig = BS.cons 0x00 (BS.tail testSignature)
          -- Recompute randomness to match the bad signature (so we isolate the BLS check)
          badRandomness = sha256 badSig
      let result = verifyDrandBeacon quicknetPubKey testRound badSig badRandomness
      result `shouldSatisfy` isLeft
      -- Should fail at either decompression or verification, not randomness mismatch
      result `shouldNotBe` Left BLSRandomnessMismatch

    it "rejects a wrong round number" $ do
      -- Correct signature for round 1000, but claim it's round 1001
      let correctRandomness = sha256 testSignature
      let result = verifyDrandBeacon quicknetPubKey 1001 testSignature correctRandomness
      result `shouldSatisfy` isLeft

    it "rejects an incorrectly sized public key" $ do
      let shortPk = BS.take 48 quicknetPubKey
      let result = verifyDrandBeacon shortPk testRound testSignature testRandomness
      result `shouldSatisfy` isLeft

    it "rejects an incorrectly sized signature" $ do
      let shortSig = BS.take 24 testSignature
          fakeRand = sha256 shortSig
      let result = verifyDrandBeacon quicknetPubKey testRound shortSig fakeRand
      result `shouldSatisfy` isLeft

    it "confirms randomness == SHA-256(signature) for the test fixture" $ do
      sha256 testSignature `shouldBe` testRandomness
