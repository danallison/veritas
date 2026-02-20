-- | Application configuration.
module Veritas.Config
  ( Config(..)
  , WorkerConfig(..)
  , DrandConfig(..)
  , loadConfig
  , defaultConfig
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Environment (lookupEnv)

-- | Top-level application config
data Config = Config
  { configPort        :: Int
  , configDBConnStr   :: ByteString
  , configDBPoolSize  :: Int
  , configServerKeyPath :: Maybe FilePath
  , configWorkers     :: WorkerConfig
  , configDrand       :: DrandConfig
  , configRateLimit   :: Int            -- ^ Max requests per window (from VERITAS_RATE_LIMIT)
  , configRateWindow  :: Int            -- ^ Rate limit window in seconds (from VERITAS_RATE_WINDOW)
  , configTLSCert     :: Maybe FilePath -- ^ TLS certificate path (from VERITAS_TLS_CERT)
  , configTLSKey      :: Maybe FilePath -- ^ TLS key path (from VERITAS_TLS_KEY)
  } deriving stock (Show, Generic)

-- | Configuration for the drand external randomness beacon
data DrandConfig = DrandConfig
  { drandRelayUrl  :: Text    -- ^ Base URL of the drand relay (e.g. "https://api.drand.sh")
  , drandChainHash :: Text    -- ^ Default chain hash for the drand network
  } deriving stock (Show, Generic)

-- | Configuration for background worker polling intervals (in seconds)
data WorkerConfig = WorkerConfig
  { workerExpiryInterval  :: Int
  , workerResolveInterval :: Int
  , workerBeaconInterval  :: Int
  , workerRevealInterval  :: Int
  } deriving stock (Show, Generic)

-- | Load config from environment variables (simple approach for Phase 1;
-- dhall integration deferred to Phase 4)
loadConfig :: IO Config
loadConfig = do
  port <- maybe 8080 read <$> lookupEnv "VERITAS_PORT"
  dbStr <- maybe defaultDBStr BS8.pack <$> lookupEnv "VERITAS_DB"
  poolSize <- maybe 10 read <$> lookupEnv "VERITAS_DB_POOL_SIZE"
  keyPath <- lookupEnv "VERITAS_SERVER_KEY"
  relayUrl <- maybe defaultDrandRelay T.pack <$> lookupEnv "VERITAS_DRAND_RELAY_URL"
  chainHash <- maybe defaultDrandChainHash T.pack <$> lookupEnv "VERITAS_DRAND_CHAIN_HASH"
  rateLimit <- maybe 60 read <$> lookupEnv "VERITAS_RATE_LIMIT"
  rateWindow <- maybe 60 read <$> lookupEnv "VERITAS_RATE_WINDOW"
  tlsCert <- lookupEnv "VERITAS_TLS_CERT"
  tlsKey <- lookupEnv "VERITAS_TLS_KEY"
  pure Config
    { configPort = port
    , configDBConnStr = dbStr
    , configDBPoolSize = poolSize
    , configServerKeyPath = keyPath
    , configWorkers = defaultWorkerConfig
    , configDrand = DrandConfig
        { drandRelayUrl = relayUrl
        , drandChainHash = chainHash
        }
    , configRateLimit = rateLimit
    , configRateWindow = rateWindow
    , configTLSCert = tlsCert
    , configTLSKey = tlsKey
    }

defaultDBStr :: ByteString
defaultDBStr = "host=localhost port=5432 dbname=veritas"

-- | Default drand mainnet relay URL
defaultDrandRelay :: Text
defaultDrandRelay = "https://api.drand.sh"

-- | Default drand mainnet (quicknet) chain hash
defaultDrandChainHash :: Text
defaultDrandChainHash = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"

defaultWorkerConfig :: WorkerConfig
defaultWorkerConfig = WorkerConfig
  { workerExpiryInterval  = 10
  , workerResolveInterval = 5
  , workerBeaconInterval  = 15
  , workerRevealInterval  = 10
  }

-- | Default config (for testing)
defaultConfig :: Config
defaultConfig = Config
  { configPort = 8080
  , configDBConnStr = defaultDBStr
  , configDBPoolSize = 10
  , configServerKeyPath = Nothing
  , configWorkers = defaultWorkerConfig
  , configDrand = DrandConfig
      { drandRelayUrl = defaultDrandRelay
      , drandChainHash = defaultDrandChainHash
      }
  , configRateLimit = 60
  , configRateWindow = 60
  , configTLSCert = Nothing
  , configTLSKey = Nothing
  }
