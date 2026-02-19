module Main (main) where

import Control.Concurrent.Async (withAsync)
import Network.Wai.Handler.Warp (run)
import Servant (serve)
import System.IO (hSetBuffering, stdout, BufferMode(..))

import Veritas.API.Types (api)
import Veritas.API.Handlers (server, AppEnv(..))
import Veritas.Config (loadConfig, Config(..), WorkerConfig(..))
import Veritas.Crypto.Signatures (generateKeyPair)
import Veritas.DB.Pool (createPool, withConnection)
import Veritas.DB.Migrations (runMigrations)
import Veritas.Workers.ExpiryChecker (runExpiryChecker)
import Veritas.Workers.AutoResolver (runAutoResolver)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  putStrLn "Veritas - Verifiable Social Randomness Service"
  putStrLn "============================================="

  -- Load config
  config <- loadConfig
  putStrLn $ "Starting on port " ++ show (configPort config)

  -- Create DB pool and run migrations
  pool <- createPool (configDBConnStr config) (configDBPoolSize config)
  withConnection pool runMigrations
  putStrLn "Database migrations complete"

  -- Generate or load server key pair
  keyPair <- generateKeyPair
  putStrLn "Server key pair generated"

  let env = AppEnv
        { envPool = pool
        , envKeyPair = keyPair
        }

  let workerCfg = configWorkers config

  -- Start background workers
  withAsync (runExpiryChecker pool (workerExpiryInterval workerCfg)) $ \_ ->
    withAsync (runAutoResolver pool keyPair (workerResolveInterval workerCfg)) $ \_ -> do
      putStrLn "Background workers started"
      putStrLn $ "Listening on port " ++ show (configPort config)
      run (configPort config) (serve api (server env))
