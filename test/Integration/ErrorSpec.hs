module Integration.ErrorSpec (spec) where

import qualified Data.UUID.V4 as UUID4
import Network.HTTP.Types (statusCode)
import Network.Wai.Test (simpleStatus)
import Test.Hspec

import Veritas.API.Types
import Veritas.Core.Types (EntropyMethod(..))
import Veritas.DB.Pool (withConnection)
import Integration.CeremonyFixtures
import Integration.DbHelpers (truncateAllTables)
import Integration.TestEnv

spec :: Spec
spec = aroundAll withTestApp $ beforeWith cleanDB $ do

    it "GET non-existent ceremony returns 404" $ \env -> do
      fakeId <- UUID4.nextRandom
      resp <- testGet (ieApp env) ("/ceremonies/" <> uuidToPath fakeId)
      statusCode (simpleStatus resp) `shouldBe` 404

    it "commit to non-existent ceremony returns 404" $ \env -> do
      fakeId <- UUID4.nextRandom
      pid <- UUID4.nextRandom
      resp <- testPost (ieApp env)
        ("/ceremonies/" <> uuidToPath fakeId <> "/commit")
        (mkCommitRequest pid)
      statusCode (simpleStatus resp) `shouldBe` 404

    it "duplicate commit is rejected" $ \env -> do
      req <- mkVRFCeremonyReq 2
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

      -- GET ceremony for commit signing
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse

      -- First commit succeeds
      resp1 <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp1)
      statusCode (simpleStatus resp1) `shouldBe` 200

      -- Duplicate commit returns 400
      resp2 <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp1)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "commit after ceremony leaves Pending returns 400" $ \env -> do
      -- Create and finalize a 1-party VRF ceremony
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Join, ack, commit to finalize
      tp <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)

      -- Ceremony is now Finalized; trying to commit with unsigned request should fail
      pid2 <- UUID4.nextRandom
      resp2 <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid2)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "reveal with wrong entropy returns 400" $ \env -> do
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

      -- Reveal with wrong entropy (idx=99 instead of 1)
      resp2 <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest (tpId tp1) 99)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "outcome on non-finalized ceremony returns 400" $ \env -> do
      req <- mkVRFCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      -- Ceremony is in Gathering (needs 2 participants)
      outcomeResp <- testGet (ieApp env) (cidPath <> "/outcome")
      statusCode (simpleStatus outcomeResp) `shouldBe` 400

    it "audit log for nonexistent ceremony returns empty entries" $ \env -> do
      fakeId <- UUID4.nextRandom
      resp <- testGet (ieApp env) ("/ceremonies/" <> uuidToPath fakeId <> "/log")
      statusCode (simpleStatus resp) `shouldBe` 200
      auditLog <- decodeBody resp :: IO AuditLogResponse
      alrEntries auditLog `shouldBe` []

    it "creating ParticipantReveal ceremony without reveal_deadline returns 400" $ \env -> do
      req <- mkVRFCeremonyReq 1  -- VRF ceremony (no reveal_deadline)
      -- Patch it to ParticipantReveal but keep no reveal_deadline
      let badReq = req { crqEntropyMethod = ParticipantReveal }
      resp <- testPost (ieApp env) "/ceremonies" badReq
      statusCode (simpleStatus resp) `shouldBe` 400

    it "reveal from uncommitted participant returns 400" $ \env -> do
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

      -- Commit both to transition to AwaitingReveals
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp1 1)
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp2 2)

      -- Try to reveal with an uncommitted participant
      unknownPid <- UUID4.nextRandom
      resp2 <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest unknownPid 3)
      statusCode (simpleStatus resp2) `shouldBe` 400

cleanDB :: IntegrationEnv -> IO IntegrationEnv
cleanDB env = do
  withConnection (iePool env) truncateAllTables
  pure env
