module Veritas.Crypto.HashSpec (spec) where

import qualified Data.ByteString as BS
import Test.Hspec

import Veritas.Crypto.Hash

spec :: Spec
spec = do
  describe "Hash" $ do
    describe "sha256" $ do
      it "produces a 32-byte hash" $ do
        BS.length (sha256 "hello") `shouldBe` 32

      it "is deterministic" $ do
        sha256 "test" `shouldBe` sha256 "test"

      it "produces different hashes for different inputs" $ do
        sha256 "a" `shouldNotBe` sha256 "b"

    describe "hkdfSHA256" $ do
      it "produces output of requested length" $ do
        BS.length (hkdfSHA256 "label" "input" 32) `shouldBe` 32
        BS.length (hkdfSHA256 "label" "input" 16) `shouldBe` 16

      it "is deterministic" $ do
        hkdfSHA256 "l" "i" 32 `shouldBe` hkdfSHA256 "l" "i" 32

      it "different labels produce different outputs" $ do
        hkdfSHA256 "label1" "input" 32 `shouldNotBe` hkdfSHA256 "label2" "input" 32

    describe "deriveUniform" $ do
      it "returns a value in [0, 1)" $ do
        let r = deriveUniform "test-entropy"
        r `shouldSatisfy` (>= 0)
        r `shouldSatisfy` (< 1)

      it "is deterministic" $ do
        deriveUniform "test" `shouldBe` deriveUniform "test"

    describe "deriveNth" $ do
      it "returns a value in [0, 1)" $ do
        let r = deriveNth "test-entropy" 0
        r `shouldSatisfy` (>= 0)
        r `shouldSatisfy` (< 1)

      it "different indices produce different values" $ do
        deriveNth "test" 0 `shouldNotBe` deriveNth "test" 1

    describe "bytesToInteger" $ do
      it "converts empty bytes to 0" $ do
        bytesToInteger BS.empty `shouldBe` 0

      it "converts single byte correctly" $ do
        bytesToInteger (BS.singleton 42) `shouldBe` 42

      it "converts multi-byte big-endian correctly" $ do
        bytesToInteger (BS.pack [1, 0]) `shouldBe` 256

    describe "genesisHash" $ do
      it "is 32 bytes of zeros" $ do
        BS.length genesisHash `shouldBe` 32
        genesisHash `shouldBe` BS.replicate 32 0
