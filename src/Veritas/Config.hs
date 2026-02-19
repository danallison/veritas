-- | Application configuration.
module Veritas.Config
  ( Config(..)
  , WorkerConfig(..)
  , loadConfig
  , defaultConfig
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import GHC.Generics (Generic)
import System.Environment (lookupEnv)

-- | Top-level application config
data Config = Config
  { configPort        :: Int
  , configDBConnStr   :: ByteString
  , configDBPoolSize  :: Int
  , configServerKeyPath :: Maybe FilePath
  , configWorkers     :: WorkerConfig
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
  pure Config
    { configPort = port
    , configDBConnStr = dbStr
    , configDBPoolSize = poolSize
    , configServerKeyPath = keyPath
    , configWorkers = defaultWorkerConfig
    }

defaultDBStr :: ByteString
defaultDBStr = "host=localhost port=5432 dbname=veritas"

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
  }
