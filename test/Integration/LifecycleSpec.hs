module Integration.LifecycleSpec (spec) where

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

    it "VRF 1-party: create -> join -> ack -> commit -> finalized -> outcome -> verify" $ \env -> do
      -- Create ceremony (starts in Gathering)
      req <- mkVRFCeremonyReq 1
      resp <- testPost (ieApp env) "/ceremonies" req
      statusCode (simpleStatus resp) `shouldBe` 200
      ceremony <- decodeBody resp :: IO CeremonyResponse
      crspPhase ceremony `shouldBe` Gathering

      let cid = crspId ceremony
          cidPath = "/ceremonies/" <> uuidToPath cid

      -- Join with Ed25519 keypair
      tp <- mkTestParticipant
      joinResp <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp)
      statusCode (simpleStatus joinResp) `shouldBe` 200

      -- GET ceremony to get roster for ack signing
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      crspPhase cerState1 `shouldBe` AwaitingRosterAcks

      -- Ack roster
      ackResp <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp)
      statusCode (simpleStatus ackResp) `shouldBe` 200

      -- GET ceremony — should be in Pending after all acks
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      crspPhase cerState2 `shouldBe` Pending

      -- Commit with signature (VRF resolves inline)
      commitResp <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp)
      statusCode (simpleStatus commitResp) `shouldBe` 200
      commit <- decodeBody commitResp :: IO CommitResponse
      cmrPhase commit `shouldBe` Resolving

      -- GET ceremony — DB phase should be Finalized
      cerResp3 <- testGet (ieApp env) cidPath
      cerState3 <- decodeBody cerResp3 :: IO CeremonyResponse
      crspPhase cerState3 `shouldBe` Finalized

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

      -- Join two participants
      tp1 <- mkTestParticipant
      tp2 <- mkTestParticipant
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp1)
      _ <- testPost (ieApp env) (cidPath <> "/join") (mkJoinRequest tp2)

      -- GET ceremony for roster
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse
      crspPhase cerState1 `shouldBe` AwaitingRosterAcks

      -- Both ack roster
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp1)
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp2)

      -- GET ceremony — should be Pending
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      crspPhase cerState2 `shouldBe` Pending

      -- First commit: should stay Pending
      commit1Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp1)
      statusCode (simpleStatus commit1Resp) `shouldBe` 200
      commit1 <- decodeBody commit1Resp :: IO CommitResponse
      cmrPhase commit1 `shouldBe` Pending

      -- Second commit: quorum met, VRF resolves inline
      commit2Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequest cid cerState2 tp2)
      statusCode (simpleStatus commit2Resp) `shouldBe` 200
      commit2 <- decodeBody commit2Resp :: IO CommitResponse
      cmrPhase commit2 `shouldBe` Resolving

      -- GET ceremony — DB phase should be Finalized
      cerResp3 <- testGet (ieApp env) cidPath
      cerState3 <- decodeBody cerResp3 :: IO CeremonyResponse
      crspPhase cerState3 `shouldBe` Finalized

      -- Outcome exists
      outcomeResp <- testGet (ieApp env) (cidPath <> "/outcome")
      statusCode (simpleStatus outcomeResp) `shouldBe` 200

      -- Verify valid
      verifyResp <- testGet (ieApp env) (cidPath <> "/verify")
      verify <- decodeBody verifyResp :: IO VerifyResponse
      vrValid verify `shouldBe` True

    it "ParticipantReveal 2-party: join -> ack -> commit -> reveal -> resolve -> finalized" $ \env -> do
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

      -- GET ceremony for roster
      cerResp1 <- testGet (ieApp env) cidPath
      cerState1 <- decodeBody cerResp1 :: IO CeremonyResponse

      -- Both ack roster
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp1)
      _ <- testPost (ieApp env) (cidPath <> "/ack-roster") (mkAckRosterRequest cid cerState1 tp2)

      -- GET ceremony for commit signing
      cerResp2 <- testGet (ieApp env) cidPath
      cerState2 <- decodeBody cerResp2 :: IO CeremonyResponse
      crspPhase cerState2 `shouldBe` Pending

      -- Two participants commit with seals
      _ <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp1 1)
      commit2Resp <- testPost (ieApp env) (cidPath <> "/commit") (mkSignedCommitRequestWithSeal cid cerState2 tp2 2)
      commit2 <- decodeBody commit2Resp :: IO CommitResponse
      cmrPhase commit2 `shouldBe` AwaitingReveals

      -- Two reveals
      _ <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest (tpId tp1) 1)
      reveal2Resp <- testPost (ieApp env) (cidPath <> "/reveal") (mkRevealRequest (tpId tp2) 2)
      statusCode (simpleStatus reveal2Resp) `shouldBe` 200

      -- Check ceremony is in Resolving phase
      cerResp3 <- testGet (ieApp env) cidPath
      cerState3 <- decodeBody cerResp3 :: IO CeremonyResponse
      crspPhase cerState3 `shouldBe` Resolving

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

-- | Truncate tables before each test.
-- Used via hspec's 'before' combinator.
cleanDB :: IntegrationEnv -> IO IntegrationEnv
cleanDB env = do
  withConnection (iePool env) truncateAllTables
  pure env
