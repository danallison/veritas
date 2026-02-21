module Integration.StandaloneSpec (spec) where

import qualified Data.Text as T
import qualified Data.UUID as UUID
import Network.HTTP.Types (statusCode)
import Network.Wai.Test (simpleStatus)
import Test.Hspec

import Veritas.API.Types
import Integration.TestEnv

spec :: Spec
spec = aroundAll withTestApp $ do

    it "GET /health returns status=ok" $ \env -> do
      resp <- testGet (ieApp env) "/health"
      statusCode (simpleStatus resp) `shouldBe` 200
      health <- decodeBody resp :: IO HealthResponse
      hrStatus health `shouldBe` "ok"

    it "GET /random/coin returns a valid boolean" $ \env -> do
      resp <- testGet (ieApp env) "/random/coin"
      statusCode (simpleStatus resp) `shouldBe` 200
      _coin <- decodeBody resp :: IO RandomCoinResponse
      -- Parsing as RandomCoinResponse is the assertion (rcrResult is Bool)
      pure ()

    it "GET /random/integer returns value within default range" $ \env -> do
      resp <- testGet (ieApp env) "/random/integer"
      statusCode (simpleStatus resp) `shouldBe` 200
      randInt <- decodeBody resp :: IO RandomIntResponse
      rirMin randInt `shouldBe` 0
      rirMax randInt `shouldBe` 100
      rirResult randInt `shouldSatisfy` (\n -> n >= 0 && n <= 100)

    it "GET /random/integer?min=1&max=6 returns value within [1,6]" $ \env -> do
      resp <- testGet (ieApp env) "/random/integer?min=1&max=6"
      statusCode (simpleStatus resp) `shouldBe` 200
      randInt <- decodeBody resp :: IO RandomIntResponse
      rirMin randInt `shouldBe` 1
      rirMax randInt `shouldBe` 6
      rirResult randInt `shouldSatisfy` (\n -> n >= 1 && n <= 6)

    it "GET /random/integer?min=6&max=1 handles inverted range" $ \env -> do
      resp <- testGet (ieApp env) "/random/integer?min=6&max=1"
      statusCode (simpleStatus resp) `shouldBe` 200
      randInt <- decodeBody resp :: IO RandomIntResponse
      rirResult randInt `shouldSatisfy` (\n -> n >= 1 && n <= 6)

    it "GET /random/uuid returns a parseable UUID" $ \env -> do
      resp <- testGet (ieApp env) "/random/uuid"
      statusCode (simpleStatus resp) `shouldBe` 200
      randUuid <- decodeBody resp :: IO RandomUUIDResponse
      -- rurResult is a UUID type, so parsing success means it's valid
      UUID.toString (rurResult randUuid) `shouldSatisfy` (not . null)

    it "GET /server/pubkey returns a non-empty hex string" $ \env -> do
      resp <- testGet (ieApp env) "/server/pubkey"
      statusCode (simpleStatus resp) `shouldBe` 200
      pubkey <- decodeBody resp :: IO ServerPubKeyResponse
      spkPublicKey pubkey `shouldSatisfy` (not . T.null)
