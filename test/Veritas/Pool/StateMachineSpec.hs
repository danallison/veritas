module Veritas.Pool.StateMachineSpec (spec) where

import qualified Data.ByteString as BS
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import Test.Hspec

import Veritas.Crypto.Signatures (generateKeyPair, signMsg, publicKeyBytes, KeyPair(..))
import Veritas.Pool.Types
import Veritas.Pool.Seal (computeFingerprint, createSeal, computeEvidenceHash)
import Veritas.Pool.StateMachine

-- | Helper to create a test validation round in the given phase
mkRound :: ValidationPhase -> [(AgentId, SealRecord)] -> ValidationRound
mkRound phase seals = ValidationRound
  { vrId = RoundId UUID.nil
  , vrPoolId = PoolId UUID.nil
  , vrFingerprint = testFingerprint
  , vrComputationSpec = testSpec
  , vrComparisonMethod = Exact
  , vrPhase = phase
  , vrRequester = requester
  , vrValidators = [validator1, validator2]
  , vrSeals = seals
  , vrBeaconRound = Nothing
  , vrSelectionProof = Nothing
  , vrCreatedAt = epoch
  , vrDeadline = Nothing
  }

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

requester, validator1, validator2 :: AgentId
requester = AgentId UUID.nil
validator1 = AgentId (UUID.fromWords 1 0 0 0)
validator2 = AgentId (UUID.fromWords 2 0 0 0)

testSpec :: ComputationSpec
testSpec = ComputationSpec "claude" "claude-3.5-sonnet" 0 Nothing Nothing "sys" "user" Nothing []

testFingerprint :: Fingerprint
testFingerprint = computeFingerprint testSpec

testResult :: BS.ByteString
testResult = "test-result-bytes"

testNonce :: BS.ByteString
testNonce = "test-nonce-1234"

testEvidence :: ExecutionEvidence
testEvidence = ExecutionEvidence Nothing Nothing Nothing Nothing Nothing

mkSealRecordSigned :: KeyPair -> Fingerprint -> AgentId -> BS.ByteString -> BS.ByteString -> SealRecord
mkSealRecordSigned kp fp aid result nonce =
  let evidenceHash = computeEvidenceHash testEvidence
      sealHash = createSeal fp aid result evidenceHash nonce
      sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
  in SealRecord
    { srSealHash = sealHash
    , srSealSig = sig
    , srRevealedResult = Nothing
    , srRevealedEvidence = Nothing
    , srRevealedNonce = Nothing
    , srPhase = Sealed
    }

mkSealRecordBadSig :: Fingerprint -> AgentId -> BS.ByteString -> BS.ByteString -> SealRecord
mkSealRecordBadSig fp aid result nonce =
  let evidenceHash = computeEvidenceHash testEvidence
      sealHash = createSeal fp aid result evidenceHash nonce
  in SealRecord
    { srSealHash = sealHash
    , srSealSig = BS.replicate 64 0  -- invalid signature
    , srRevealedResult = Nothing
    , srRevealedEvidence = Nothing
    , srRevealedNonce = Nothing
    , srPhase = Sealed
    }

spec :: Spec
spec = do
  describe "Pool StateMachine" $ do
    describe "submitRequesterSeal" $ do
      it "transitions Requested -> Selecting with valid signature" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Requested []
            seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
        case submitRequesterSeal round requester pk seal of
          Right r -> vrPhase r `shouldBe` Selecting
          Left e  -> expectationFailure (show e)

      it "rejects invalid signature" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Requested []
            seal = mkSealRecordBadSig testFingerprint requester testResult testNonce
        case submitRequesterSeal round requester pk seal of
          Left (SealSignatureInvalid _) -> pure ()
          other -> expectationFailure ("Expected SealSignatureInvalid, got " <> show other)

      it "rejects wrong phase" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Computing []
            seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
        submitRequesterSeal round requester pk seal `shouldBe`
          Left (InvalidRoundPhase Requested Computing)

      it "rejects non-requester agent" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Requested []
            seal = mkSealRecordSigned kp testFingerprint validator1 testResult testNonce
        submitRequesterSeal round validator1 pk seal `shouldBe`
          Left (AgentNotInRound validator1)

      it "rejects wrong key (different keypair than signed with)" $ do
        kpSign <- generateKeyPair
        kpWrong <- generateKeyPair
        let wrongPk = publicKeyBytes (kpPublic kpWrong)
            round = mkRound Requested []
            seal = mkSealRecordSigned kpSign testFingerprint requester testResult testNonce
        case submitRequesterSeal round requester wrongPk seal of
          Left (SealSignatureInvalid _) -> pure ()
          other -> expectationFailure ("Expected SealSignatureInvalid, got " <> show other)

    describe "recordValidatorSelection" $ do
      it "transitions Selecting -> Computing" $ do
        let round = mkRound Selecting []
            validators = [mkPoolMember validator1 "p1", mkPoolMember validator2 "p2"]
        case recordValidatorSelection round validators 12345 "proof" of
          Right r -> do
            vrPhase r `shouldBe` Computing
            vrBeaconRound r `shouldBe` Just 12345
            length (vrValidators r) `shouldBe` 2
          Left e -> expectationFailure (show e)

      it "rejects wrong phase" $ do
        let round = mkRound Requested []
            validators = [mkPoolMember validator1 "p1"]
        recordValidatorSelection round validators 1 "proof" `shouldBe`
          Left (InvalidRoundPhase Selecting Requested)

    describe "submitValidatorSeal" $ do
      it "accepts validator seals in Computing phase with valid signature" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        let pkV1 = publicKeyBytes (kpPublic kpV1)
            requesterSeal = mkSealRecordSigned kpReq testFingerprint requester testResult testNonce
            round = mkRound Computing [(requester, requesterSeal)]
            seal = mkSealRecordSigned kpV1 testFingerprint validator1 testResult "nonce-v1"
        case submitValidatorSeal round validator1 pkV1 seal of
          Right r -> length (vrSeals r) `shouldBe` 2
          Left e  -> expectationFailure (show e)

      it "transitions to Revealing when all seals are in" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        kpV2 <- generateKeyPair
        let pkV2 = publicKeyBytes (kpPublic kpV2)
            requesterSeal = mkSealRecordSigned kpReq testFingerprint requester testResult testNonce
            v1Seal = mkSealRecordSigned kpV1 testFingerprint validator1 testResult "nonce-v1"
            round = mkRound Sealing [(requester, requesterSeal), (validator1, v1Seal)]
            v2Seal = mkSealRecordSigned kpV2 testFingerprint validator2 testResult "nonce-v2"
        case submitValidatorSeal round validator2 pkV2 v2Seal of
          Right r -> vrPhase r `shouldBe` Revealing
          Left e  -> expectationFailure (show e)

      it "rejects invalid signature" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        let pkV1 = publicKeyBytes (kpPublic kpV1)
            requesterSeal = mkSealRecordSigned kpReq testFingerprint requester testResult testNonce
            round = mkRound Computing [(requester, requesterSeal)]
            badSeal = mkSealRecordBadSig testFingerprint validator1 testResult "nonce-v1"
        case submitValidatorSeal round validator1 pkV1 badSeal of
          Left (SealSignatureInvalid _) -> pure ()
          other -> expectationFailure ("Expected SealSignatureInvalid, got " <> show other)

      it "rejects duplicate seal from same agent" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        let pkV1 = publicKeyBytes (kpPublic kpV1)
            requesterSeal = mkSealRecordSigned kpReq testFingerprint requester testResult testNonce
            v1Seal = mkSealRecordSigned kpV1 testFingerprint validator1 testResult "nonce-v1"
            round = mkRound Computing [(requester, requesterSeal), (validator1, v1Seal)]
        submitValidatorSeal round validator1 pkV1 v1Seal `shouldBe`
          Left (SealAlreadySubmitted validator1)

      it "rejects non-validator" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Computing []
            nonValidator = AgentId (UUID.fromWords 99 0 0 0)
            seal = mkSealRecordSigned kp testFingerprint nonValidator testResult "nonce"
        submitValidatorSeal round nonValidator pk seal `shouldBe`
          Left (AgentNotValidator nonValidator)

    describe "submitReveal" $ do
      it "verifies seal and records revealed data" $ do
        kp <- generateKeyPair
        let seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
            round = mkRound Revealing [(requester, seal)]
        case submitReveal round requester testResult testEvidence testNonce of
          Right r -> case lookup requester (vrSeals r) of
            Just s -> srPhase s `shouldBe` Revealed
            Nothing -> expectationFailure "seal not found after reveal"
          Left e -> expectationFailure (show e)

      it "rejects reveal with wrong result (seal mismatch)" $ do
        kp <- generateKeyPair
        let seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
            round = mkRound Revealing [(requester, seal)]
        case submitReveal round requester "wrong-result" testEvidence testNonce of
          Left (RevealSealMismatch _) -> pure ()
          other -> expectationFailure ("Expected RevealSealMismatch, got " <> show other)

      it "rejects reveal with wrong nonce (seal mismatch)" $ do
        kp <- generateKeyPair
        let seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
            round = mkRound Revealing [(requester, seal)]
        case submitReveal round requester testResult testEvidence "wrong-nonce" of
          Left (RevealSealMismatch _) -> pure ()
          other -> expectationFailure ("Expected RevealSealMismatch, got " <> show other)

      it "rejects reveal for agent not in round" $ do
        let round = mkRound Revealing []
            unknown = AgentId (UUID.fromWords 99 0 0 0)
        case submitReveal round unknown testResult testEvidence testNonce of
          Left (AgentNotInRound _) -> pure ()
          other -> expectationFailure ("Expected AgentNotInRound, got " <> show other)

      it "rejects reveal in wrong phase" $ do
        kp <- generateKeyPair
        let seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
            round = mkRound Computing [(requester, seal)]
        submitReveal round requester testResult testEvidence testNonce `shouldBe`
          Left (InvalidRoundPhase Revealing Computing)

    describe "finalizeRound" $ do
      it "returns Validated + CacheEntry when all agree" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        kpV2 <- generateKeyPair
        let mkRevealedSeal kp aid result nonce =
              let evidenceHash = computeEvidenceHash testEvidence
                  sealHash = createSeal testFingerprint aid result evidenceHash nonce
                  sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
              in SealRecord sealHash sig
                   (Just result) (Just testEvidence) (Just nonce) Revealed

            seals =
              [ (requester, mkRevealedSeal kpReq requester testResult "n1")
              , (validator1, mkRevealedSeal kpV1 validator1 testResult "n2")
              , (validator2, mkRevealedSeal kpV2 validator2 testResult "n3")
              ]
            round = mkRound Revealing seals
        case finalizeRound round of
          Right (r, Just cache) -> do
            vrPhase r `shouldBe` Validated
            ceResult cache `shouldBe` testResult
            rpOutcome (ceProvenance cache) `shouldBe` Unanimous
            rpAgreementCount (ceProvenance cache) `shouldBe` 3
          Right (_, Nothing) -> expectationFailure "Expected cache entry"
          Left e -> expectationFailure (show e)

      it "returns Validated + Majority when 2/3 agree" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        kpV2 <- generateKeyPair
        let mkRevealedSeal kp aid result nonce =
              let evidenceHash = computeEvidenceHash testEvidence
                  sealHash = createSeal testFingerprint aid result evidenceHash nonce
                  sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
              in SealRecord sealHash sig
                   (Just result) (Just testEvidence) (Just nonce) Revealed

            seals =
              [ (requester, mkRevealedSeal kpReq requester testResult "n1")
              , (validator1, mkRevealedSeal kpV1 validator1 testResult "n2")
              , (validator2, mkRevealedSeal kpV2 validator2 "bad-result" "n3")
              ]
            round = mkRound Revealing seals
        case finalizeRound round of
          Right (r, Just cache) -> do
            vrPhase r `shouldBe` Validated
            rpOutcome (ceProvenance cache) `shouldBe` Majority validator2
            rpAgreementCount (ceProvenance cache) `shouldBe` 2
            ceResult cache `shouldBe` testResult  -- majority result, not dissenter's
          Right (_, Nothing) -> expectationFailure "Expected cache entry"
          Left e -> expectationFailure (show e)

      it "returns Failed when no majority (all different)" $ do
        kpReq <- generateKeyPair
        kpV1 <- generateKeyPair
        kpV2 <- generateKeyPair
        let mkRevealedSeal kp aid result nonce =
              let evidenceHash = computeEvidenceHash testEvidence
                  sealHash = createSeal testFingerprint aid result evidenceHash nonce
                  sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
              in SealRecord sealHash sig
                   (Just result) (Just testEvidence) (Just nonce) Revealed

            seals =
              [ (requester, mkRevealedSeal kpReq requester "result-1" "n1")
              , (validator1, mkRevealedSeal kpV1 validator1 "result-2" "n2")
              , (validator2, mkRevealedSeal kpV2 validator2 "result-3" "n3")
              ]
            round = mkRound Revealing seals
        case finalizeRound round of
          Right (r, Nothing) -> vrPhase r `shouldBe` Failed
          other -> expectationFailure ("Expected Failed, got " <> show other)

      it "rejects finalize when not all revealed" $ do
        kp <- generateKeyPair
        let seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
            round = mkRound Revealing [(requester, seal)]
        case finalizeRound round of
          Left NotAllRevealed -> pure ()
          other -> expectationFailure ("Expected NotAllRevealed, got " <> show other)

      it "rejects finalize in wrong phase" $ do
        let round = mkRound Computing []
        case finalizeRound round of
          Left (InvalidRoundPhase Revealing Computing) -> pure ()
          other -> expectationFailure ("Expected InvalidRoundPhase, got " <> show other)

    describe "Terminal state enforcement" $ do
      it "cannot submit seal to Validated round" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Validated []
            seal = mkSealRecordSigned kp testFingerprint requester testResult testNonce
        case submitRequesterSeal round requester pk seal of
          Left (InvalidRoundPhase Requested Validated) -> pure ()
          other -> expectationFailure ("Expected InvalidRoundPhase, got " <> show other)

      it "cannot submit validator seal to Failed round" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            round = mkRound Failed []
            seal = mkSealRecordSigned kp testFingerprint validator1 testResult "nonce"
        case submitValidatorSeal round validator1 pk seal of
          Left (InvalidRoundPhase Computing Failed) -> pure ()
          other -> expectationFailure ("Expected InvalidRoundPhase, got " <> show other)

      it "cannot reveal in Cancelled round" $ do
        let round = mkRound Cancelled []
        case submitReveal round requester testResult testEvidence testNonce of
          Left (InvalidRoundPhase Revealing Cancelled) -> pure ()
          other -> expectationFailure ("Expected InvalidRoundPhase, got " <> show other)

mkPoolMember :: AgentId -> String -> PoolMember
mkPoolMember aid principal = PoolMember
  { pmAgentId = aid
  , pmPublicKey = BS.replicate 32 0
  , pmPrincipalId = PrincipalId (read ("\"" ++ principal ++ "\""))
  , pmJoinedAt = epoch
  }
