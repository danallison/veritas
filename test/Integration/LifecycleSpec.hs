module Integration.LifecycleSpec (spec) where

import qualified Data.UUID.V4 as UUID4
import Network.HTTP.Types (statusCode)
import Network.Wai.Test (simpleStatus)
import Test.Hspec

import Veritas.API.Types
import Veritas.Core.Types (CeremonyId(..), Phase(..))
import Veritas.DB.Pool (withConnection)
import Integration.CeremonyFixtures
import Integration.DbHelpers (truncateAllTables, resolveTestCeremony)
import Integration.TestEnv

spec :: Spec
spec = aroundAll withTestApp $ beforeWith cleanDB $ do

    it "VRF 1-party: create -> commit -> finalized -> outcome -> verify" $ \env -> do
      -- Create ceremony
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      statusCode (simpleStatus resp) `shouldBe` 200
      ceremony <- decodeBody resp :: IO CeremonyResponse
      crspPhase ceremony `shouldBe` Pending

      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Commit (VRF resolves inline; response shows Resolving but DB is Finalized)
      pid <- UUID4.nextRandom
      commitResp <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid)
      statusCode (simpleStatus commitResp) `shouldBe` 200
      commit <- decodeBody commitResp :: IO CommitResponse
      cmrPhase commit `shouldBe` Resolving

      -- GET ceremony — DB phase should be Finalized
      cerResp <- testGet (ieApp env) cidPath
      cerState <- decodeBody cerResp :: IO CeremonyResponse
      crspPhase cerState `shouldBe` Finalized

      -- GET outcome
      outcomeResp <- testGet (ieApp env) (cidPath <> "/outcome")
      statusCode (simpleStatus outcomeResp) `shouldBe` 200
      _outcome <- decodeBody outcomeResp :: IO OutcomeResponse

      -- GET verify
      verifyResp <- testGet (ieApp env) (cidPath <> "/verify")
      statusCode (simpleStatus verifyResp) `shouldBe` 200
      verify <- decodeBody verifyResp :: IO VerifyResponse
      vrValid verify `shouldBe` True

    it "VRF 2-party: first commit stays pending, second finalizes" $ \env -> do
      req <- mkVRFCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- First commit: should stay Pending
      pid1 <- UUID4.nextRandom
      commit1Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid1)
      statusCode (simpleStatus commit1Resp) `shouldBe` 200
      commit1 <- decodeBody commit1Resp :: IO CommitResponse
      cmrPhase commit1 `shouldBe` Pending

      -- Second commit: quorum met, VRF resolves inline
      -- Response shows Resolving but DB goes to Finalized
      pid2 <- UUID4.nextRandom
      commit2Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequest pid2)
      statusCode (simpleStatus commit2Resp) `shouldBe` 200
      commit2 <- decodeBody commit2Resp :: IO CommitResponse
      cmrPhase commit2 `shouldBe` Resolving

      -- GET ceremony — DB phase should be Finalized
      cerResp <- testGet (ieApp env) cidPath
      cerState <- decodeBody cerResp :: IO CeremonyResponse
      crspPhase cerState `shouldBe` Finalized

      -- Outcome exists
      outcomeResp <- testGet (ieApp env) (cidPath <> "/outcome")
      statusCode (simpleStatus outcomeResp) `shouldBe` 200

      -- Verify valid
      verifyResp <- testGet (ieApp env) (cidPath <> "/verify")
      verify <- decodeBody verifyResp :: IO VerifyResponse
      vrValid verify `shouldBe` True

    it "ParticipantReveal 2-party: commit -> reveal -> resolve -> finalized" $ \env -> do
      req <- mkParticipantRevealCeremonyReq 2
      resp <- testPost (ieApp env) "/ceremonies" req
      ceremony <- decodeBody resp :: IO CeremonyResponse
      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Two participants commit with seals
      pid1 <- UUID4.nextRandom
      pid2 <- UUID4.nextRandom

      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid1 1)
      commit2Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkCommitRequestWithSeal cid pid2 2)
      commit2 <- decodeBody commit2Resp :: IO CommitResponse
      cmrPhase commit2 `shouldBe` AwaitingReveals

      -- Two reveals
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest pid1 1)
      reveal2Resp <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest pid2 2)
      statusCode (simpleStatus reveal2Resp) `shouldBe` 200

      -- Check ceremony is in Resolving phase
      cerResp <- testGet (ieApp env) cidPath
      cerState <- decodeBody cerResp :: IO CeremonyResponse
      crspPhase cerState `shouldBe` Resolving

      -- Resolve using test helper (replicates AutoResolver)
      resolveTestCeremony (iePool env) (ieKeyPair env) (CeremonyId cid)

      -- Should be finalized now
      finalResp <- testGet (ieApp env) cidPath
      finalState <- decodeBody finalResp :: IO CeremonyResponse
      crspPhase finalState `shouldBe` Finalized

      -- Outcome exists
      outcomeResp <- testGet (ieApp env) (cidPath <> "/outcome")
      statusCode (simpleStatus outcomeResp) `shouldBe` 200

      -- Verify valid
      verifyResp <- testGet (ieApp env) (cidPath <> "/verify")
      verify <- decodeBody verifyResp :: IO VerifyResponse
      vrValid verify `shouldBe` True

    it "list ceremonies with phase filter" $ \env -> do
      -- Create two VRF ceremonies, finalize one
      req1 <- mkVRFCeremonyReq 1
      resp1 <- testPost (ieApp env) "/ceremonies" req1
      c1 <- decodeBody resp1 :: IO CeremonyResponse
      let c1Path = "/ceremonies/" <> uuidToPath (crspId c1)

      req2 <- mkVRFCeremonyReq 2
      _ <- testPost (ieApp env) "/ceremonies" req2

      -- Finalize the first by committing
      pid <- UUID4.nextRandom
      _ <- testPost (ieApp env) (c1Path <> "/commit") (mkCommitRequest pid)

      -- List all
      allResp <- testGet (ieApp env) "/ceremonies"
      statusCode (simpleStatus allResp) `shouldBe` 200
      allCeremonies <- decodeBody allResp :: IO [CeremonyResponse]
      length allCeremonies `shouldBe` 2

      -- Filter by pending
      pendingResp <- testGet (ieApp env) "/ceremonies?phase=pending"
      pendingList <- decodeBody pendingResp :: IO [CeremonyResponse]
      length pendingList `shouldBe` 1

      -- Filter by finalized
      finalizedResp <- testGet (ieApp env) "/ceremonies?phase=finalized"
      finalized <- decodeBody finalizedResp :: IO [CeremonyResponse]
      length finalized `shouldBe` 1

-- | Truncate tables before each test.
-- Used via hspec's 'before' combinator.
cleanDB :: IntegrationEnv -> IO IntegrationEnv
cleanDB env = do
  withConnection (iePool env) truncateAllTables
  pure env
