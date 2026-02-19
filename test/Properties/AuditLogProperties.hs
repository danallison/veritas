module Properties.AuditLogProperties (spec) where

import Data.Time (UTCTime, getCurrentTime)
import Data.UUID as UUID
import Test.Hspec

import Veritas.Core.Types
import Veritas.Core.AuditLog
import Veritas.Crypto.Hash (genesisHash)

spec :: Spec
spec = do
  describe "AuditLog Properties" $ do
    it "any correctly constructed chain passes verification" $ do
      now <- getCurrentTime
      let cid = CeremonyId UUID.nil
          events = [CeremonyExpired, CeremonyFinalized, CeremonyDisputed "test"]
          chain = buildChain cid now events
      verifyChain chain `shouldBe` Nothing

    it "modifying any entry in a chain is detected" $ do
      now <- getCurrentTime
      let cid = CeremonyId UUID.nil
          entry1 = createLogEntry 0 cid CeremonyExpired now genesisHash
          entry2 = createLogEntry 1 cid CeremonyFinalized now (logEntryHash entry1)
          entry3 = createLogEntry 2 cid (CeremonyDisputed "test") now (logEntryHash entry2)
          -- Tamper with middle entry's event
          tampered2 = entry2 { logEvent = CeremonyExpired }
      verifyChain [entry1, tampered2, entry3] `shouldNotBe` Nothing

    it "inserting an entry breaks the chain" $ do
      now <- getCurrentTime
      let cid = CeremonyId UUID.nil
          entry1 = createLogEntry 0 cid CeremonyExpired now genesisHash
          entry2 = createLogEntry 1 cid CeremonyFinalized now (logEntryHash entry1)
          -- Create an extra entry that doesn't fit the chain
          extra = createLogEntry 1 cid (CeremonyDisputed "inserted") now genesisHash
      verifyChain [entry1, extra, entry2] `shouldNotBe` Nothing

    it "reordering entries breaks the chain" $ do
      now <- getCurrentTime
      let cid = CeremonyId UUID.nil
          entry1 = createLogEntry 0 cid CeremonyExpired now genesisHash
          entry2 = createLogEntry 1 cid CeremonyFinalized now (logEntryHash entry1)
      verifyChain [entry2, entry1] `shouldNotBe` Nothing

-- Build a correctly chained sequence of log entries
buildChain :: CeremonyId -> UTCTime -> [CeremonyEvent] -> [LogEntry]
buildChain _ _ [] = []
buildChain cid ts events = go 0 genesisHash events []
  where
    go _ _ [] acc = reverse acc
    go seqNum prevHash (e:es) acc =
      let entry = createLogEntry seqNum cid e ts prevHash
      in go (seqNum + 1) (logEntryHash entry) es (entry : acc)
