module Veritas.Workers.BeaconFetcherSpec (spec) where

import Test.Hspec

import Veritas.Config (DrandConfig(..))
import Veritas.Workers.BeaconFetcher (resolveChainHash)

testConfig :: DrandConfig
testConfig = DrandConfig
  { drandRelayUrl  = "https://api.drand.sh"
  , drandChainHash = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"
  , drandPublicKey = Nothing
  }

spec :: Spec
spec = do
  describe "resolveChainHash" $ do
    it "maps 'default' to the config chain hash" $
      resolveChainHash testConfig "default"
        `shouldBe` drandChainHash testConfig

    it "maps 'drand-quicknet' to the config chain hash" $
      resolveChainHash testConfig "drand-quicknet"
        `shouldBe` drandChainHash testConfig

    it "passes through an arbitrary hex string as-is" $
      resolveChainHash testConfig "abcdef1234567890"
        `shouldBe` "abcdef1234567890"

    it "passes through an empty string as-is" $
      resolveChainHash testConfig ""
        `shouldBe` ""
