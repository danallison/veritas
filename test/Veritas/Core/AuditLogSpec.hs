module Veritas.Core.AuditLogSpec (spec) where

import Data.UUID as UUID
import Data.Time (getCurrentTime)
import Test.Hspec

import Veritas.Core.Types
import Veritas.Core.AuditLog
import Veritas.Crypto.Hash (genesisHash)

spec :: Spec
spec = do
  describe "AuditLog" $ do
    let testCid = CeremonyId UUID.nil

    describe "createLogEntry" $ do
      it "creates an entry with valid hash" $ do
        now <- getCurrentTime
        let entry = createLogEntry 0 testCid CeremonyFinalized now genesisHash
        verifyEntry entry `shouldBe` True

      it "chains entries correctly" $ do
        now <- getCurrentTime
        let entry1 = createLogEntry 0 testCid CeremonyExpired now genesisHash
            entry2 = createLogEntry 1 testCid CeremonyFinalized now (logEntryHash entry1)
        logPrevHash entry2 `shouldBe` logEntryHash entry1
        verifyEntry entry2 `shouldBe` True

    describe "verifyChain" $ do
      it "validates an empty chain" $ do
        verifyChain [] `shouldBe` Nothing

      it "validates a single entry" $ do
        now <- getCurrentTime
        let entry = createLogEntry 0 testCid CeremonyExpired now genesisHash
        verifyChain [entry] `shouldBe` Nothing

      it "validates a multi-entry chain" $ do
        now <- getCurrentTime
        let entry1 = createLogEntry 0 testCid CeremonyExpired now genesisHash
            entry2 = createLogEntry 1 testCid CeremonyFinalized now (logEntryHash entry1)
            entry3 = createLogEntry 2 testCid (CeremonyDisputed "test") now (logEntryHash entry2)
        verifyChain [entry1, entry2, entry3] `shouldBe` Nothing

      it "detects a broken chain (wrong prevHash)" $ do
        now <- getCurrentTime
        let entry1 = createLogEntry 0 testCid CeremonyExpired now genesisHash
            entry2 = createLogEntry 1 testCid CeremonyFinalized now "wrong-prev-hash"
        verifyChain [entry1, entry2] `shouldBe` Just (LogSequence 1)

      it "detects a tampered entry (modified event)" $ do
        now <- getCurrentTime
        let entry1 = createLogEntry 0 testCid CeremonyExpired now genesisHash
            entry2 = createLogEntry 1 testCid CeremonyFinalized now (logEntryHash entry1)
            tampered = entry2 { logEvent = CeremonyExpired }  -- tamper event
        verifyChain [entry1, tampered] `shouldBe` Just (LogSequence 1)

    describe "verifyEntry" $ do
      it "verifies a correctly constructed entry" $ do
        now <- getCurrentTime
        let entry = createLogEntry 0 testCid CeremonyFinalized now genesisHash
        verifyEntry entry `shouldBe` True

      it "rejects a tampered entry" $ do
        now <- getCurrentTime
        let entry = createLogEntry 0 testCid CeremonyFinalized now genesisHash
            tampered = entry { logEvent = CeremonyExpired }
        verifyEntry tampered `shouldBe` False
