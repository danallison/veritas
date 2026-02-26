module Veritas.Pool.SealSpec (spec) where

import qualified Data.ByteString as BS
import Data.UUID as UUID
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

import TestHelpers ()
import Veritas.Crypto.Signatures (generateKeyPair, signMsg, publicKeyBytes, KeyPair(..))
import Veritas.Pool.Types
import Veritas.Pool.Seal

spec :: Spec
spec = do
  describe "Seal Properties" $ do
    let fp = Fingerprint (BS.replicate 32 0xaa)
        aid = AgentId UUID.nil
        result = "test-result"
        nonce = "test-nonce"
        evidence = ExecutionEvidence Nothing Nothing Nothing Nothing Nothing
        evidenceHash = computeEvidenceHash evidence

    it "correct values verify against their seal" $ do
      let seal = createSeal fp aid result evidenceHash nonce
      verifySeal fp aid result evidenceHash nonce seal `shouldBe` True

    it "wrong result does not verify" $ do
      let seal = createSeal fp aid result evidenceHash nonce
      verifySeal fp aid "wrong-result" evidenceHash nonce seal `shouldBe` False

    it "wrong nonce does not verify" $ do
      let seal = createSeal fp aid result evidenceHash nonce
      verifySeal fp aid result evidenceHash "wrong-nonce" seal `shouldBe` False

    it "wrong evidence hash does not verify" $ do
      let seal = createSeal fp aid result evidenceHash nonce
      verifySeal fp aid result "wrong-evidence-hash" nonce seal `shouldBe` False

    it "different agents produce different seals" $ do
      let aid2 = AgentId (UUID.fromWords 1 0 0 0)
          seal1 = createSeal fp aid result evidenceHash nonce
          seal2 = createSeal fp aid2 result evidenceHash nonce
      seal1 `shouldNotBe` seal2

    it "different fingerprints produce different seals" $ do
      let fp2 = Fingerprint (BS.replicate 32 0xbb)
          seal1 = createSeal fp aid result evidenceHash nonce
          seal2 = createSeal fp2 aid result evidenceHash nonce
      seal1 `shouldNotBe` seal2

    it "computeFingerprint is deterministic" $ do
      let spec1 = ComputationSpec "claude" "claude-3.5-sonnet" 0 Nothing Nothing "sys" "user" Nothing []
      computeFingerprint spec1 `shouldBe` computeFingerprint spec1

    it "different specs produce different fingerprints" $ do
      let spec1 = ComputationSpec "claude" "claude-3.5-sonnet" 0 Nothing Nothing "sys" "user1" Nothing []
          spec2 = ComputationSpec "claude" "claude-3.5-sonnet" 0 Nothing Nothing "sys" "user2" Nothing []
      computeFingerprint spec1 `shouldNotBe` computeFingerprint spec2

    prop "seal is always 32 bytes" $
      \(bs :: BS.ByteString) ->
        not (BS.null bs) ==>
          let seal = createSeal fp aid bs evidenceHash nonce
          in BS.length seal == 32

  describe "Ed25519 Signature Verification" $ do
    it "valid signature verifies" $ do
      kp <- generateKeyPair
      let sealHash = BS.replicate 32 0xcc
          sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
          pk = publicKeyBytes (kpPublic kp)
      verifySealSignature pk sealHash sig `shouldBe` True

    it "wrong message does not verify" $ do
      kp <- generateKeyPair
      let sealHash = BS.replicate 32 0xcc
          sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
          pk = publicKeyBytes (kpPublic kp)
      verifySealSignature pk "wrong-message" sig `shouldBe` False

    it "wrong public key does not verify" $ do
      kp1 <- generateKeyPair
      kp2 <- generateKeyPair
      let sealHash = BS.replicate 32 0xcc
          sig = signMsg (kpSecret kp1) (kpPublic kp1) sealHash
          pk2 = publicKeyBytes (kpPublic kp2)
      verifySealSignature pk2 sealHash sig `shouldBe` False

    it "end-to-end: create seal, sign it, verify signature" $ do
      kp <- generateKeyPair
      let fp = Fingerprint (BS.replicate 32 0xaa)
          aid = AgentId UUID.nil
          result = "test-result"
          nonce = "test-nonce"
          evidence = ExecutionEvidence Nothing Nothing Nothing Nothing Nothing
          evidenceHash = computeEvidenceHash evidence
          sealHash = createSeal fp aid result evidenceHash nonce
          sig = signMsg (kpSecret kp) (kpPublic kp) sealHash
          pk = publicKeyBytes (kpPublic kp)
      -- Seal hash verification
      verifySeal fp aid result evidenceHash nonce sealHash `shouldBe` True
      -- Signature verification
      verifySealSignature pk sealHash sig `shouldBe` True

  describe "Evidence Hash" $ do
    it "is deterministic for same evidence" $ do
      let evidence = ExecutionEvidence (Just "req-123") (Just "model-1") Nothing Nothing Nothing
      computeEvidenceHash evidence `shouldBe` computeEvidenceHash evidence

    it "different evidence produces different hashes" $ do
      let e1 = ExecutionEvidence (Just "req-123") Nothing Nothing Nothing Nothing
          e2 = ExecutionEvidence (Just "req-456") Nothing Nothing Nothing Nothing
      computeEvidenceHash e1 `shouldNotBe` computeEvidenceHash e2

    it "empty evidence produces a valid hash" $ do
      let evidence = ExecutionEvidence Nothing Nothing Nothing Nothing Nothing
      BS.length (computeEvidenceHash evidence) `shouldBe` 32
