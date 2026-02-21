module Integration.AuditLogSpec (spec) where

import qualified Data.UUID.V4 as UUID4
import Network.HTTP.Types (statusCode)
import Network.Wai.Test (simpleStatus)
import Test.Hspec

import Veritas.API.Types
import Veritas.Core.Types (CeremonyId(..))
import Veritas.DB.Pool (withConnection)
import Integration.CeremonyFixtures
import Integration.DbHelpers (truncateAllTables, resolveTestCeremony)
import Integration.TestEnv

spec :: Spec
spec = aroundAll withTestApp $ beforeWith cleanDB $ do

    it "VRF ceremony audit log has correct event types in order" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Commit (triggers finalization for 1-party VRF)
      pid <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)

      -- Get audit log
      logResp <- testGet (ieApp env) (cidPath <> "/log")
      statusCode (simpleStatus logResp) `shouldBe` 200
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let entries = alrEntries auditLog
          eventTypes = map alerEventType entries

      -- Expected event order for VRF
      eventTypes `shouldBe`
        [ "ceremony_created"
        , "participant_committed"
        , "vrf_generated"
        , "ceremony_resolved"
        , "ceremony_finalized"
        ]

    it "sequence numbers are strictly increasing starting at 0" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      pid <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)

      logResp <- testGet (ieApp env) (cidPath <> "/log")
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let seqNums = map alerSequenceNum (alrEntries auditLog)
      seqNums `shouldBe` [0, 1, 2, 3, 4]

    it "prev_hash chain is valid (each entry links to the previous)" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      pid <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)

      logResp <- testGet (ieApp env) (cidPath <> "/log")
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let entries = alrEntries auditLog
      -- Each entry's prev_hash should match the preceding entry's entry_hash
      verifyChain entries

    it "/verify endpoint returns valid=True for finalized ceremony" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      pid <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)

      verifyResp <- testGet (ieApp env) (cidPath <> "/verify")
      statusCode (simpleStatus verifyResp) `shouldBe` 200
      verify <- decodeBody verifyResp :: IO VerifyResponse
      vrErrors verify `shouldBe` []
      vrValid verify `shouldBe` True

    it "ParticipantReveal ceremony audit log has correct event types" $ \env -> do
      req <- mkParticipantRevealCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Two participants commit with seals
      pid1 <- UUID4.nextRandom
      pid2 <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid1 1)
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid2 2)

      -- Two reveals
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest pid1 1)
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest pid2 2)

      -- Resolve using test helper
      resolveTestCeremony (iePool env) (ieKeyPair env) (CeremonyId cid)

      -- Get audit log
      logResp <- testGet (ieApp env) (cidPath <> "/log")
      statusCode (simpleStatus logResp) `shouldBe` 200
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let eventTypes = map alerEventType (alrEntries auditLog)

      eventTypes `shouldBe`
        [ "ceremony_created"
        , "participant_committed"
        , "participant_committed"
        , "reveals_published"
        , "ceremony_resolved"
        , "ceremony_finalized"
        ]

-- | Verify the hash chain: each entry's prev_hash should match the previous entry's entry_hash.
verifyChain :: [AuditLogEntryResponse] -> IO ()
verifyChain [] = pure ()
verifyChain [_] = pure ()
verifyChain (e1:e2:rest) = do
  alerEntryHash e1 `shouldBe` alerPrevHash e2
  verifyChain (e2:rest)

cleanDB :: IntegrationEnv -> IO IntegrationEnv
cleanDB env = do
  withConnection (iePool env) truncateAllTables
  pure env
