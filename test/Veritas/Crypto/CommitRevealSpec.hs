module Veritas.Crypto.CommitRevealSpec (spec) where

import qualified Data.ByteString as BS
import Data.UUID as UUID
import Test.Hspec

import Veritas.Core.Types (CeremonyId(..), ParticipantId(..))
import Veritas.Crypto.CommitReveal

spec :: Spec
spec = do
  describe "CommitReveal" $ do
    let testCid = CeremonyId UUID.nil
        testPid = ParticipantId (UUID.fromWords 1 0 0 0)
        testEntropy = "my-secret-entropy-value"

    describe "createSeal" $ do
      it "produces a 32-byte seal" $ do
        BS.length (createSeal testCid testPid testEntropy) `shouldBe` 32

      it "is deterministic" $ do
        createSeal testCid testPid testEntropy
          `shouldBe` createSeal testCid testPid testEntropy

      it "different entropy produces different seals" $ do
        createSeal testCid testPid "entropy1"
          `shouldNotBe` createSeal testCid testPid "entropy2"

      it "different participants produce different seals" $ do
        let pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
        createSeal testCid testPid testEntropy
          `shouldNotBe` createSeal testCid pid2 testEntropy

    describe "verifySeal" $ do
      it "verifies a correct seal" $ do
        let seal = createSeal testCid testPid testEntropy
        verifySeal testCid testPid testEntropy seal `shouldBe` True

      it "rejects wrong entropy value" $ do
        let seal = createSeal testCid testPid testEntropy
        verifySeal testCid testPid "wrong-entropy" seal `shouldBe` False

      it "rejects wrong participant" $ do
        let seal = createSeal testCid testPid testEntropy
            wrongPid = ParticipantId (UUID.fromWords 99 0 0 0)
        verifySeal testCid wrongPid testEntropy seal `shouldBe` False

    describe "defaultEntropyValue" $ do
      it "produces a 32-byte value" $ do
        BS.length (defaultEntropyValue testCid testPid) `shouldBe` 32

      it "is deterministic" $ do
        defaultEntropyValue testCid testPid
          `shouldBe` defaultEntropyValue testCid testPid

      it "different participants get different defaults" $ do
        let pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
        defaultEntropyValue testCid testPid
          `shouldNotBe` defaultEntropyValue testCid pid2
