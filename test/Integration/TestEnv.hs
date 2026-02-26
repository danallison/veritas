-- | Test environment for integration tests.
-- Sets up a WAI application backed by a real PostgreSQL database.
module Integration.TestEnv
  ( IntegrationEnv(..)
  , withTestApp
  , testGet
  , testPost
  , decodeBody
  , uuidToPath
  ) where

import Control.Exception (bracket)
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Database.PostgreSQL.Simple (connectPostgreSQL, close)
import Network.HTTP.Types (methodPost)
import Network.Wai (Application, defaultRequest, Request(..))
import Network.Wai.Test (SResponse(..), Session, runSession, setPath, request, srequest, SRequest(..))
import Servant (serve, (:<|>)((:<|>)))
import System.Environment (lookupEnv)
import Test.Hspec (expectationFailure)

import Veritas.API.Handlers (AppEnv(..), server, docsHandler)
import Veritas.API.PoolHandlers (poolServer)
import Veritas.API.Types (fullApi)
import Veritas.Config (DrandConfig(..))
import Veritas.Crypto.Signatures (KeyPair, generateKeyPair)
import Veritas.DB.Migrations (runMigrations)
import Veritas.DB.Pool (DBPool, createPool)
import Veritas.Logging (initLogEnv, LogEnv)

data IntegrationEnv = IntegrationEnv
  { ieApp     :: Application
  , iePool    :: DBPool
  , ieKeyPair :: KeyPair
  , ieLogEnv  :: LogEnv
  }

-- | Create a test environment: DB pool, migrations, ephemeral keypair, WAI app.
-- The VERITAS_DB env var must point to the test database.
withTestApp :: (IntegrationEnv -> IO a) -> IO a
withTestApp action = do
  connStr <- maybe "host=db port=5432 dbname=veritas user=veritas password=veritas"
                   BS8.pack
             <$> lookupEnv "VERITAS_DB"

  -- Run migrations using a direct connection
  bracket (connectPostgreSQL connStr) close runMigrations

  pool <- createPool connStr 4
  keyPair <- generateKeyPair
  logEnv <- initLogEnv

  let drandCfg = DrandConfig
        { drandRelayUrl  = "https://api.drand.sh"
        , drandChainHash = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"
        , drandPublicKey = Nothing
        }
      env = AppEnv
        { envPool        = pool
        , envKeyPair     = keyPair
        , envLogEnv      = logEnv
        , envDrandConfig = drandCfg
        }
      app = serve fullApi (server env :<|> poolServer env :<|> docsHandler)
      ienv = IntegrationEnv
        { ieApp     = app
        , iePool    = pool
        , ieKeyPair = keyPair
        , ieLogEnv  = logEnv
        }

  action ienv

-- | Run a GET request against the WAI app.
testGet :: Application -> ByteString -> IO SResponse
testGet app path = runSession (doGet path) app

-- | Run a POST request with a JSON body against the WAI app.
testPost :: ToJSON a => Application -> ByteString -> a -> IO SResponse
testPost app path body = runSession (doPost path body) app

-- | Decode a response body as JSON, failing the test on parse error.
decodeBody :: FromJSON a => SResponse -> IO a
decodeBody resp = case eitherDecode (simpleBody resp) of
  Left err  -> expectationFailure ("Failed to decode response: " <> err) >> error "unreachable"
  Right val -> pure val

-- | Convert a UUID to a path segment.
uuidToPath :: UUID -> ByteString
uuidToPath = BS8.pack . UUID.toString

-- Internal helpers

doGet :: ByteString -> Session SResponse
doGet path = request (setPath defaultRequest path)

doPost :: ToJSON a => ByteString -> a -> Session SResponse
doPost path body =
  let req = (setPath defaultRequest path)
              { requestMethod = methodPost
              , requestHeaders = [("Content-Type", "application/json")]
              }
  in srequest (SRequest req (encode body))
