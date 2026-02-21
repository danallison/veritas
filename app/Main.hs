module Main (main) where

import Control.Concurrent.Async (withAsync)
import Control.Exception (bracket)
import Network.Wai (Middleware)
import Network.Wai.Handler.Warp (run, defaultSettings, setPort)
import Network.Wai.Middleware.RequestLogger (logStdout)
import Network.Wai.Middleware.Cors (cors, simpleCorsResourcePolicy, CorsResourcePolicy(..))
import Servant (serve)

import Veritas.API.Types (fullApi)
import Veritas.API.Handlers (fullServer, AppEnv(..))
import Veritas.API.RateLimit (newRateLimiter, RateLimitConfig(..))
import Veritas.Config (loadConfig, Config(..), WorkerConfig(..), DrandConfig(..))
import Veritas.Crypto.Signatures (loadOrGenerateKeyPair)
import Veritas.DB.Pool (createPool, withConnection)
import Veritas.DB.Migrations (runMigrations)
import Veritas.Logging (initLogEnv, closeLogEnv, runKatipT, logMsg, Severity(..), ls)
import Veritas.Workers.ExpiryChecker (runExpiryChecker)
import Veritas.Workers.AutoResolver (runAutoResolver)
import Veritas.Workers.RevealDeadlineChecker (runRevealDeadlineChecker)
import Veritas.Workers.BeaconFetcher (runBeaconFetcher)
import Veritas.External.Drand (fetchChainInfo, ChainInfo(..))

import qualified Network.Wai.Handler.WarpTLS as TLS

main :: IO ()
main = bracket initLogEnv closeLogEnv $ \logEnv -> do
  runKatipT logEnv $ logMsg "main" InfoS "Veritas - Verifiable Social Randomness Service"

  -- Load config
  config <- loadConfig
  runKatipT logEnv $ logMsg "main" InfoS (ls ("Starting on port " <> show (configPort config)))

  -- Create DB pool and run migrations
  pool <- createPool (configDBConnStr config) (configDBPoolSize config)
  withConnection pool runMigrations
  runKatipT logEnv $ logMsg "main" InfoS "Database migrations complete"

  -- Generate or load server key pair
  keyPair <- loadOrGenerateKeyPair (configServerKeyPath config)
  case configServerKeyPath config of
    Just path -> runKatipT logEnv $ logMsg "main" InfoS (ls ("Server key loaded/generated at " <> path))
    Nothing   -> runKatipT logEnv $ logMsg "main" InfoS "Using ephemeral server key pair"

  -- Resolve drand public key: use configured key or fetch from /info
  drandCfg <- case drandPublicKey (configDrand config) of
    Just _pk -> do
      runKatipT logEnv $ logMsg "main" InfoS "Using configured drand public key"
      pure (configDrand config)
    Nothing -> do
      runKatipT logEnv $ logMsg "main" InfoS "Fetching drand chain info for BLS verification..."
      chainResult <- fetchChainInfo (configDrand config) (drandChainHash (configDrand config))
      case chainResult of
        Right ci -> do
          runKatipT logEnv $ logMsg "main" InfoS
            (ls ("drand public key fetched (scheme: " <> show (ciSchemeID ci) <> ")"))
          pure (configDrand config) { drandPublicKey = Just (ciPublicKey ci) }
        Left err -> do
          runKatipT logEnv $ logMsg "main" WarningS
            (ls ("Failed to fetch drand chain info: " <> show err <> ". Beacon verification disabled."))
          pure (configDrand config)

  let env = AppEnv
        { envPool = pool
        , envKeyPair = keyPair
        , envLogEnv = logEnv
        , envDrandConfig = drandCfg
        }

  let workerCfg = configWorkers config

  -- Build middleware pipeline
  rateLimiter <- newRateLimiter RateLimitConfig
    { rlMaxRequests = configRateLimit config
    , rlWindowSeconds = configRateWindow config
    }
  let corsPolicy = const $ Just simpleCorsResourcePolicy
        { corsRequestHeaders = ["Content-Type"]
        , corsMethods = ["GET", "POST", "OPTIONS"]
        }
  let middleware :: Middleware
      middleware = logStdout . rateLimiter . cors corsPolicy

  let app = middleware (serve fullApi (fullServer env))

  -- Start background workers
  withAsync (runExpiryChecker logEnv pool (workerExpiryInterval workerCfg)) $ \_ ->
    withAsync (runAutoResolver logEnv pool keyPair (workerResolveInterval workerCfg)) $ \_ ->
      withAsync (runRevealDeadlineChecker logEnv pool (workerRevealInterval workerCfg)) $ \_ ->
        withAsync (runBeaconFetcher logEnv pool drandCfg (workerBeaconInterval workerCfg)) $ \_ -> do
          runKatipT logEnv $ logMsg "main" InfoS "Background workers started"
          case (configTLSCert config, configTLSKey config) of
            (Just certPath, Just keyPath) -> do
              runKatipT logEnv $ logMsg "main" InfoS (ls ("TLS enabled, listening on port " <> show (configPort config)))
              let tlsSettings = TLS.tlsSettings certPath keyPath
                  warpSettings = setPort (configPort config) defaultSettings
              TLS.runTLS tlsSettings warpSettings app
            (Just _, Nothing) -> do
              runKatipT logEnv $ logMsg "main" WarningS "VERITAS_TLS_CERT set but VERITAS_TLS_KEY missing; starting without TLS"
              run (configPort config) app
            (Nothing, Just _) -> do
              runKatipT logEnv $ logMsg "main" WarningS "VERITAS_TLS_KEY set but VERITAS_TLS_CERT missing; starting without TLS"
              run (configPort config) app
            _ -> do
              runKatipT logEnv $ logMsg "main" InfoS (ls ("Listening on port " <> show (configPort config)))
              run (configPort config) app
