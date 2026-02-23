module Veritas.Crypto.CeremonyParamsSpec (spec) where

import Data.List.NonEmpty (NonEmpty(..))
import Data.UUID as UUID
import qualified Data.Text as T
import Test.Hspec

import Veritas.Core.Types
import Veritas.Crypto.CeremonyParams

-- Helper: build a base ceremony for tests
baseCeremony :: Ceremony
baseCeremony = Ceremony
  { ceremonyId = CeremonyId UUID.nil
  , question = "Who goes first?"
  , ceremonyType = CoinFlip "Heads" "Tails"
  , entropyMethod = OfficiantVRF
  , requiredParties = 2
  , commitmentMode = Immediate
  , commitDeadline = read "2026-06-01 12:00:00 UTC"
  , revealDeadline = Nothing
  , nonParticipationPolicy = Nothing
  , beaconSpec = Nothing
  , identityMode = Anonymous
  , phase = Pending
  , createdBy = ParticipantId UUID.nil
  , createdAt = read "2026-01-01 00:00:00 UTC"
  }

spec :: Spec
spec = do
  describe "CeremonyParams" $ do
    describe "computeParamsHash" $ do
      it "is deterministic (same ceremony -> same hash)" $ do
        computeParamsHash baseCeremony `shouldBe` computeParamsHash baseCeremony

      it "different questions -> different hashes" $ do
        let c1 = baseCeremony { question = "Question A" }
            c2 = baseCeremony { question = "Question B" }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "different ceremony types -> different hashes" $ do
        let c1 = baseCeremony { ceremonyType = CoinFlip "Heads" "Tails" }
            c2 = baseCeremony { ceremonyType = UniformChoice ("A" :| ["B", "C"]) }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "different entropy methods -> different hashes" $ do
        let c1 = baseCeremony { entropyMethod = OfficiantVRF }
            c2 = baseCeremony { entropyMethod = ExternalBeacon
                              , beaconSpec = Just (BeaconSpec "default" Nothing CancelCeremony) }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "different required parties -> different hashes" $ do
        let c1 = baseCeremony { requiredParties = 2 }
            c2 = baseCeremony { requiredParties = 3 }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "different coin flip labels -> different hashes" $ do
        let c1 = baseCeremony { ceremonyType = CoinFlip "Heads" "Tails" }
            c2 = baseCeremony { ceremonyType = CoinFlip "Alice wins" "Bob wins" }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "different identity modes -> different hashes" $ do
        let c1 = baseCeremony { identityMode = Anonymous }
            c2 = baseCeremony { identityMode = SelfCertified }
        computeParamsHash c1 `shouldNotBe` computeParamsHash c2

      it "does not depend on mutable fields (phase, ceremonyId, createdBy, createdAt)" $ do
        let c1 = baseCeremony
            c2 = baseCeremony
                  { ceremonyId = CeremonyId (UUID.fromWords 1 2 3 4)
                  , phase = Finalized
                  , createdBy = ParticipantId (UUID.fromWords 5 6 7 8)
                  , createdAt = read "2026-06-15 00:00:00 UTC"
                  }
        computeParamsHash c1 `shouldBe` computeParamsHash c2

    describe "paramsHashHex" $ do
      it "returns a 64-character hex string" $ do
        let hex = paramsHashHex baseCeremony
        length (show hex) - 2 `shouldBe` 64  -- show adds quotes

      -- Golden test vector: this hash must match the TypeScript implementation
      -- in web/src/crypto/ceremonyParams.test.ts
      it "produces the expected golden hash for baseCeremony" $ do
        let hex = paramsHashHex baseCeremony
        T.unpack hex `shouldBe` "c22d9d86ddcbd47e28a8071cfbf796757b2b5e3c80665843a42f61f6a0949a46"
