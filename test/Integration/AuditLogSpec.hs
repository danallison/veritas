module Integration.AuditLogSpec (spec) where

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

      -- Join, ack, commit (triggers finalization for 1-party VRF)
      tp <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)

      -- Get audit log
      logResp <- testGet (ieApp env) (cidPath <> "/log")
      statusCode (simpleStatus logResp) `shouldBe` 200
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let entries = alrEntries auditLog
          eventTypes = map alerEventType entries

      -- Expected event order for self-certified VRF ceremony
      eventTypes `shouldBe`
        [ "ceremony_created"
        , "participant_joined"
        , "roster_finalized"
        , "roster_acknowledged"
        , "participant_committed"
        , "vrf_generated"
        , "ceremony_resolved"
        , "ceremony_finalized"
        ]

    it "sequence numbers are strictly increasing starting at 0" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Join, ack, commit
      tp <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)

      logResp <- testGet (ieApp env) (cidPath <> "/log")
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let seqNums = map alerSequenceNum (alrEntries auditLog)
      seqNums `shouldBe` [0 .. fromIntegral (length seqNums - 1)]

    it "prev_hash chain is valid (each entry links to the previous)" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Join, ack, commit
      tp <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)

      logResp <- testGet (ieApp env) (cidPath <> "/log")
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let entries = alrEntries auditLog
      -- Each entry's prev_hash should match the preceding entry's entry_hash
      verifyChain entries

    it "/verify endpoint returns valid=True for finalized ceremony" $ \env -> do
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Join, ack, commit
      tp <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)

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

      -- Join two participants
      tp1 <- mkTestParticipant
      tp2 <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp1)
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp2)

      -- Ack roster
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp1)
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp2)

      -- Commit both with seals
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp1 1)
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp2 2)

      -- Two reveals
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest (tpId tp1) 1)
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest (tpId tp2) 2)

      -- Resolve using test helper
      resolveTestCeremony (iePool env) (ieKeyPair env) (CeremonyId cid)

      -- Get audit log
      logResp <- testGet (ieApp env) (cidPath <> "/log")
      statusCode (simpleStatus logResp) `shouldBe` 200
      auditLog <- decodeBody logResp :: IO AuditLogResponse

      let eventTypes = map alerEventType (alrEntries auditLog)

      eventTypes `shouldBe`
        [ "ceremony_created"
        , "participant_joined"
        , "participant_joined"
        , "roster_finalized"
        , "roster_acknowledged"
        , "roster_acknowledged"
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
