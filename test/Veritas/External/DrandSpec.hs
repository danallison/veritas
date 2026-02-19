module Veritas.External.DrandSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.Either (isLeft)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Veritas.Core.Types (BeaconAnchor(..))
import Veritas.External.Drand

-- A fixed timestamp for tests
testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime 0)

spec :: Spec
spec = do
  describe "parseDrandResponse" $ do
    it "parses a valid drand JSON response" $ do
      let json = LBS8.pack
            "{ \"round\": 12345, \
            \  \"randomness\": \"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\", \
            \  \"signature\": \"deadbeef01020304\" }"
      case parseDrandResponse json of
        Right dr -> do
          drRound dr `shouldBe` 12345
          drRandomness dr `shouldBe` "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
          drSignature dr `shouldBe` "deadbeef01020304"
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    it "rejects JSON missing required fields" $ do
      let json = LBS8.pack "{ \"round\": 12345 }"
      parseDrandResponse json `shouldSatisfy` isLeft

    it "rejects invalid JSON" $ do
      parseDrandResponse "not json" `shouldSatisfy` isLeft

    it "rejects empty object" $ do
      parseDrandResponse "{}" `shouldSatisfy` isLeft

  describe "drandResponseToAnchor" $ do
    it "constructs a BeaconAnchor from a valid response" $ do
      let dr = DrandResponse
            { drRound = 42
            , drRandomness = "abcdef0123456789"
            , drSignature  = "0102030405060708"
            }
      case drandResponseToAnchor "test-chain" dr testTime of
        Right anchor -> do
          baNetwork anchor `shouldBe` "test-chain"
          baRound anchor `shouldBe` 42
          baFetchedAt anchor `shouldBe` testTime
          -- Value should be decoded from hex (8 bytes from "abcdef0123456789")
          baValue anchor `shouldNotBe` mempty
          baSignature anchor `shouldNotBe` mempty
        Left err -> expectationFailure $ "Conversion failed: " ++ show err

    it "rejects invalid hex in randomness" $ do
      let dr = DrandResponse
            { drRound = 42
            , drRandomness = "not-valid-hex!"
            , drSignature  = "0102030405060708"
            }
      drandResponseToAnchor "test-chain" dr testTime `shouldSatisfy` isLeft

    it "rejects invalid hex in signature" $ do
      let dr = DrandResponse
            { drRound = 42
            , drRandomness = "abcdef0123456789"
            , drSignature  = "xyz"
            }
      drandResponseToAnchor "test-chain" dr testTime `shouldSatisfy` isLeft

    it "preserves round number" $ do
      let dr = DrandResponse
            { drRound = 999999
            , drRandomness = "aabb"
            , drSignature  = "ccdd"
            }
      case drandResponseToAnchor "chain" dr testTime of
        Right anchor -> baRound anchor `shouldBe` 999999
        Left err -> expectationFailure $ "Conversion failed: " ++ show err
