-- | Database connection pool management.
module Veritas.DB.Pool
  ( DBPool
  , createPool
  , withConnection
  , withSerializableTransaction
  ) where

import Control.Exception (SomeException, catch, throwIO)
import Data.ByteString (ByteString)
import Data.Pool (Pool, newPool, defaultPoolConfig, withResource)
import Database.PostgreSQL.Simple
  ( Connection, connectPostgreSQL, close, commit, execute_
  )

type DBPool = Pool Connection

-- | Create a new connection pool
createPool :: ByteString  -- ^ connection string
           -> Int          -- ^ max connections
           -> IO DBPool
createPool connStr maxConns =
  newPool $ defaultPoolConfig
    (connectPostgreSQL connStr)
    close
    60   -- unused resource TTL (seconds)
    maxConns

-- | Run an action with a connection from the pool
withConnection :: DBPool -> (Connection -> IO a) -> IO a
withConnection = withResource

-- | Run an action within a SERIALIZABLE transaction.
-- Retries on serialization failures (up to 3 attempts).
withSerializableTransaction :: Connection -> (Connection -> IO a) -> IO a
withSerializableTransaction conn action = go (3 :: Int)
  where
    go 0 = error "withSerializableTransaction: max retries exceeded"
    go retriesLeft = do
      execute_ conn "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE"
      result <- (action conn >>= \r -> commit conn >> pure (Right r))
        `catch` (\(e :: SomeException) -> do
          execute_ conn "ROLLBACK"
          if retriesLeft > 1
            then pure (Left e)
            else throwIO e)
      case result of
        Right r -> pure r
        Left _  -> go (retriesLeft - 1)
