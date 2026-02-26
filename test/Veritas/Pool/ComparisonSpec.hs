module Veritas.Pool.ComparisonSpec (spec) where

import qualified Data.ByteString as BS
import Data.UUID as UUID
import Test.Hspec

import Veritas.Pool.Types
import Veritas.Pool.Comparison

spec :: Spec
spec = do
  describe "Comparison" $ do
    let aid1 = AgentId UUID.nil
        aid2 = AgentId (UUID.fromWords 1 0 0 0)
        aid3 = AgentId (UUID.fromWords 2 0 0 0)

    describe "Exact comparison" $ do
      it "returns Unanimous when all results match" $ do
        let results = [(aid1, "result"), (aid2, "result"), (aid3, "result")]
        compareResults Exact results `shouldBe` CompUnanimous

      it "returns Majority with dissenter when 2/3 agree" $ do
        let results = [(aid1, "good"), (aid2, "good"), (aid3, "bad")]
        case compareResults Exact results of
          CompMajority d -> d `shouldBe` aid3
          other -> expectationFailure ("Expected CompMajority, got " <> show other)

      it "identifies correct dissenter regardless of position" $ do
        let results = [(aid1, "bad"), (aid2, "good"), (aid3, "good")]
        case compareResults Exact results of
          CompMajority d -> d `shouldBe` aid1
          other -> expectationFailure ("Expected CompMajority, got " <> show other)

      it "returns Inconclusive when all different" $ do
        let results = [(aid1, "a"), (aid2, "b"), (aid3, "c")]
        compareResults Exact results `shouldBe` CompInconclusive

      it "returns Inconclusive with fewer than 2 results" $ do
        let results = [(aid1, "result")]
        compareResults Exact results `shouldBe` CompInconclusive

      it "returns Inconclusive with empty results" $ do
        compareResults Exact [] `shouldBe` CompInconclusive

      it "handles binary data correctly" $ do
        let binData = BS.pack [0x00, 0x01, 0x02, 0xff]
            results = [(aid1, binData), (aid2, binData), (aid3, binData)]
        compareResults Exact results `shouldBe` CompUnanimous

      it "distinguishes single byte differences" $ do
        let r1 = BS.pack [0x00, 0x01]
            r2 = BS.pack [0x00, 0x02]
            results = [(aid1, r1), (aid2, r1), (aid3, r2)]
        case compareResults Exact results of
          CompMajority d -> d `shouldBe` aid3
          other -> expectationFailure ("Expected CompMajority, got " <> show other)

    describe "Canonical comparison" $ do
      it "treats reordered JSON keys as equal" $ do
        -- Aeson normalizes key order alphabetically on re-encode
        let r1 = "{\"a\":1,\"b\":2}"
            r2 = "{\"b\":2,\"a\":1}"
            results = [(aid1, r1), (aid2, r2), (aid3, r1)]
        compareResults Canonical results `shouldBe` CompUnanimous

      it "byte-identical JSON is unanimous" $ do
        let r = "{\"answer\":42}"
            results = [(aid1, r), (aid2, r), (aid3, r)]
        compareResults Canonical results `shouldBe` CompUnanimous

      it "falls back to byte comparison for non-JSON" $ do
        let r = "not json"
            results = [(aid1, r), (aid2, r), (aid3, r)]
        compareResults Canonical results `shouldBe` CompUnanimous

      it "non-JSON different values are not equal" $ do
        let results = [(aid1, "hello"), (aid2, "hello"), (aid3, "world")]
        case compareResults Canonical results of
          CompMajority d -> d `shouldBe` aid3
          other -> expectationFailure ("Expected CompMajority, got " <> show other)

    describe "FieldLevel comparison (POC: falls back to exact)" $ do
      it "unanimous when all match exactly" $ do
        let cfg = FieldComparisonConfig [("field1", ExactMatch)]
            results = [(aid1, "result"), (aid2, "result"), (aid3, "result")]
        compareResults (FieldLevel cfg) results `shouldBe` CompUnanimous

      it "dissent when one differs" $ do
        let cfg = FieldComparisonConfig [("field1", ExactMatch)]
            results = [(aid1, "result"), (aid2, "result"), (aid3, "different")]
        case compareResults (FieldLevel cfg) results of
          CompMajority d -> d `shouldBe` aid3
          other -> expectationFailure ("Expected CompMajority, got " <> show other)
