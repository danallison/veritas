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
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      pid <- UUID4.nextRandom
      -- First commit succeeds
      resp1 <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)
      statusCode (simpleStatus resp1) `shouldBe` 200

      -- Duplicate commit returns 400
      resp2 <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "commit after ceremony leaves Pending returns 400" $ \env -> do
      -- Create and finalize a 1-party VRF ceremony
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      pid1 <- UUID4.nextRandom
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid1)

      -- Ceremony is now Finalized; trying to commit should fail
      pid2 <- UUID4.nextRandom
      resp2 <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid2)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "reveal with wrong entropy returns 400" $ \env -> do
      req <- mkParticipantRevealCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      pid1 <- UUID4.nextRandom
      pid2 <- UUID4.nextRandom

      -- Commit both
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid1 1)
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid2 2)

      -- Reveal with wrong entropy (idx=99 instead of 1)
      resp2 <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest pid1 99)
      statusCode (simpleStatus resp2) `shouldBe` 400

    it "outcome on non-finalized ceremony returns 400" $ \env -> do
      req <- mkVRFCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cidPath = "/ceremonies/" <> uuidToPath (crspId ceremony)

      -- Ceremony is still Pending (needs 2 commits)
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

      pid1 <- UUID4.nextRandom
      pid2 <- UUID4.nextRandom

      -- Commit both to transition to AwaitingReveals
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid1 1)
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid2 2)

      -- Try to reveal with an uncommitted participant
      unknownPid <- UUID4.nextRandom
      resp2 <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest unknownPid 3)
      statusCode (simpleStatus resp2) `shouldBe` 400

cleanDB :: IntegrationEnv -> IO IntegrationEnv
cleanDB env = do
  withConnection (iePool env) truncateAllTables
  pure env
