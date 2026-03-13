module Veritas.Core.VerifiedCacheSpec (spec) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime, addUTCTime)
import Data.UUID as UUID
import Test.Hspec

import Veritas.Core.Verification
import Veritas.Core.VerifiedCache
import Veritas.Pool.Types (AgentId(..), PoolId(..))

-- === Test fixtures ===

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

later :: UTCTime
later = addUTCTime 3600 epoch  -- 1 hour later

agent1, agent2, agent3 :: AgentId
agent1 = AgentId (UUID.fromWords 1 0 0 0)
agent2 = AgentId (UUID.fromWords 2 0 0 0)
agent3 = AgentId (UUID.fromWords 3 0 0 0)

mkUnanimousVerdict :: Verdict
mkUnanimousVerdict = Verdict
  { verdictOutcome = Unanimous
  , verdictAgreementCount = 3
  , verdictMajorityResult = Just "the-result"
  , verdictDecidedAt = epoch
  }

mkMajorityVerdict :: Verdict
mkMajorityVerdict = Verdict
  { verdictOutcome = MajorityAgree [agent3]
  , verdictAgreementCount = 2
  , verdictMajorityResult = Just "majority-result"
  , verdictDecidedAt = epoch
  }

mkInconclusiveVerdict :: Verdict
mkInconclusiveVerdict = Verdict
  { verdictOutcome = Inconclusive
  , verdictAgreementCount = 1
  , verdictMajorityResult = Nothing
  , verdictDecidedAt = epoch
  }

-- === Specs ===

spec :: Spec
spec = do
  describe "VerifiedCache" $ do
    describe "emptyCache" $ do
      it "starts with no entries" $ do
        cacheSize emptyCache `shouldBe` 0

    describe "cacheVerifiedResult" $ do
      it "caches a unanimous verdict" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "the-result" mkUnanimousVerdict Nothing
        cacheSize cache `shouldBe` 1

      it "caches a majority verdict" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "majority-result" mkMajorityVerdict Nothing
        cacheSize cache `shouldBe` 1

      it "does not cache inconclusive verdict" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkInconclusiveVerdict Nothing
        cacheSize cache `shouldBe` 0

      it "does not overwrite existing entry (immutability)" $ do
        let cache1 = cacheVerifiedResult emptyCache "fp1" "first-result" mkUnanimousVerdict Nothing
            cache2 = cacheVerifiedResult cache1 "fp1" "second-result" mkUnanimousVerdict Nothing
        case lookupCache cache2 "fp1" of
          Just entry -> ceResult entry `shouldBe` "first-result"
          Nothing -> expectationFailure "Expected cache entry"

      it "stores multiple entries under different fingerprints" $ do
        let cache = cacheVerifiedResult
                      (cacheVerifiedResult emptyCache "fp1" "result1" mkUnanimousVerdict Nothing)
                      "fp2" "result2" mkMajorityVerdict Nothing
        cacheSize cache `shouldBe` 2

    describe "lookupCache" $ do
      it "returns entry for known fingerprint" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "the-result" mkUnanimousVerdict Nothing
        case lookupCache cache "fp1" of
          Just entry -> do
            ceResult entry `shouldBe` "the-result"
            ceFingerprint entry `shouldBe` "fp1"
          Nothing -> expectationFailure "Expected cache entry"

      it "returns Nothing for unknown fingerprint" $ do
        lookupCache emptyCache "unknown" `shouldBe` Nothing

      it "returns provenance with verdict details" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "the-result" mkUnanimousVerdict Nothing
        case lookupCache cache "fp1" of
          Just entry -> do
            ceAgreementCount (ceProvenance entry) `shouldBe` 3
            ceVerdictOutcome (ceProvenance entry) `shouldBe` Unanimous
          Nothing -> expectationFailure "Expected cache entry"

    describe "expireCache" $ do
      it "removes entries past their TTL" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkUnanimousVerdict (Just 1800)
            -- Expire at later (1 hour), TTL was 30 minutes
            expired = expireCache cache later
        lookupCache expired "fp1" `shouldBe` Nothing

      it "keeps entries within their TTL" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkUnanimousVerdict (Just 7200)
            -- Check at later (1 hour), TTL is 2 hours
            checked = expireCache cache later
        lookupCache checked "fp1" `shouldNotBe` Nothing

      it "keeps entries with no TTL" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkUnanimousVerdict Nothing
            checked = expireCache cache later
        lookupCache checked "fp1" `shouldNotBe` Nothing

    describe "removeEntry" $ do
      it "removes a specific entry" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkUnanimousVerdict Nothing
            cache' = removeEntry cache "fp1"
        lookupCache cache' "fp1" `shouldBe` Nothing

      it "does nothing for unknown fingerprint" $ do
        let cache = cacheVerifiedResult emptyCache "fp1" "result" mkUnanimousVerdict Nothing
            cache' = removeEntry cache "fp2"
        cacheSize cache' `shouldBe` 1
