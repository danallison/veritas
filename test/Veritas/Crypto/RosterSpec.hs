module Veritas.Crypto.RosterSpec (spec) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.UUID as UUID
import Test.Hspec

import Veritas.Core.Types
import Veritas.Crypto.Roster
import Veritas.Crypto.Signatures (generateKeyPair, signMsg, publicKeyBytes, KeyPair(..))

testCeremonyId :: CeremonyId
testCeremonyId = CeremonyId UUID.nil

testParticipant1 :: ParticipantId
testParticipant1 = ParticipantId (UUID.fromWords 1 0 0 0)

testParticipant2 :: ParticipantId
testParticipant2 = ParticipantId (UUID.fromWords 2 0 0 0)

-- A fixed 32-byte params hash for testing
testParamsHash :: ByteString
testParamsHash = BS.replicate 32 0xAB

-- A different params hash for mismatch tests
differentParamsHash :: ByteString
differentParamsHash = BS.replicate 32 0xCD

spec :: Spec
spec = do
  describe "Roster Crypto" $ do
    describe "buildRosterPayload" $ do
      it "is deterministic (same inputs -> same bytes)" $ do
        kp1 <- generateKeyPair
        kp2 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            pk2 = publicKeyBytes (kpPublic kp2)
            roster = [(testParticipant1, pk1), (testParticipant2, pk2)]
            payload1 = buildRosterPayload testCeremonyId testParamsHash roster
            payload2 = buildRosterPayload testCeremonyId testParamsHash roster
        payload1 `shouldBe` payload2

      it "changes when participants differ" $ do
        kp1 <- generateKeyPair
        kp2 <- generateKeyPair
        kp3 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            pk2 = publicKeyBytes (kpPublic kp2)
            pk3 = publicKeyBytes (kpPublic kp3)
            roster1 = [(testParticipant1, pk1), (testParticipant2, pk2)]
            roster2 = [(testParticipant1, pk1), (testParticipant2, pk3)]
            payload1 = buildRosterPayload testCeremonyId testParamsHash roster1
            payload2 = buildRosterPayload testCeremonyId testParamsHash roster2
        payload1 `shouldNotBe` payload2

      it "produces same payload regardless of input order" $ do
        kp1 <- generateKeyPair
        kp2 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            pk2 = publicKeyBytes (kpPublic kp2)
            roster1 = [(testParticipant1, pk1), (testParticipant2, pk2)]
            roster2 = [(testParticipant2, pk2), (testParticipant1, pk1)]
            payload1 = buildRosterPayload testCeremonyId testParamsHash roster1
            payload2 = buildRosterPayload testCeremonyId testParamsHash roster2
        payload1 `shouldBe` payload2

      it "different paramsHash -> different payload" $ do
        kp1 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            roster = [(testParticipant1, pk1)]
            payload1 = buildRosterPayload testCeremonyId testParamsHash roster
            payload2 = buildRosterPayload testCeremonyId differentParamsHash roster
        payload1 `shouldNotBe` payload2

    describe "verifyRosterSignature" $ do
      it "verifies a valid roster signature" $ do
        kp1 <- generateKeyPair
        kp2 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            pk2 = publicKeyBytes (kpPublic kp2)
            roster = [(testParticipant1, pk1), (testParticipant2, pk2)]
            payload = buildRosterPayload testCeremonyId testParamsHash roster
            sig = signMsg (kpSecret kp1) (kpPublic kp1) payload
        verifyRosterSignature testCeremonyId testParamsHash roster testParticipant1 sig `shouldBe` True

      it "rejects signature from wrong participant" $ do
        kp1 <- generateKeyPair
        kp2 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            pk2 = publicKeyBytes (kpPublic kp2)
            roster = [(testParticipant1, pk1), (testParticipant2, pk2)]
            payload = buildRosterPayload testCeremonyId testParamsHash roster
            sig = signMsg (kpSecret kp1) (kpPublic kp1) payload
        verifyRosterSignature testCeremonyId testParamsHash roster testParticipant2 sig `shouldBe` False

      it "rejects signature for non-roster participant" $ do
        kp1 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            roster = [(testParticipant1, pk1)]
            payload = buildRosterPayload testCeremonyId testParamsHash roster
            sig = signMsg (kpSecret kp1) (kpPublic kp1) payload
        verifyRosterSignature testCeremonyId testParamsHash roster testParticipant2 sig `shouldBe` False

      it "rejects signature when paramsHash differs" $ do
        kp1 <- generateKeyPair
        let pk1 = publicKeyBytes (kpPublic kp1)
            roster = [(testParticipant1, pk1)]
            payload = buildRosterPayload testCeremonyId testParamsHash roster
            sig = signMsg (kpSecret kp1) (kpPublic kp1) payload
        -- Verify with different paramsHash
        verifyRosterSignature testCeremonyId differentParamsHash roster testParticipant1 sig `shouldBe` False

    describe "verifyCommitSignature" $ do
      it "verifies a valid commit signature (without seal)" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            payload = buildCommitPayload testCeremonyId testParticipant1 testParamsHash Nothing
            sig = signMsg (kpSecret kp) (kpPublic kp) payload
        verifyCommitSignature pk sig testCeremonyId testParticipant1 testParamsHash Nothing `shouldBe` True

      it "verifies a valid commit signature (with seal)" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            seal = "abcdef0123456789" :: ByteString
            payload = buildCommitPayload testCeremonyId testParticipant1 testParamsHash (Just seal)
            sig = signMsg (kpSecret kp) (kpPublic kp) payload
        verifyCommitSignature pk sig testCeremonyId testParticipant1 testParamsHash (Just seal) `shouldBe` True

      it "rejects signature with wrong seal" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            seal1 = "abcdef0123456789" :: ByteString
            seal2 = "9876543210fedcba" :: ByteString
            payload = buildCommitPayload testCeremonyId testParticipant1 testParamsHash (Just seal1)
            sig = signMsg (kpSecret kp) (kpPublic kp) payload
        verifyCommitSignature pk sig testCeremonyId testParticipant1 testParamsHash (Just seal2) `shouldBe` False

      it "rejects signature when paramsHash differs" $ do
        kp <- generateKeyPair
        let pk = publicKeyBytes (kpPublic kp)
            payload = buildCommitPayload testCeremonyId testParticipant1 testParamsHash Nothing
            sig = signMsg (kpSecret kp) (kpPublic kp) payload
        verifyCommitSignature pk sig testCeremonyId testParticipant1 differentParamsHash Nothing `shouldBe` False
