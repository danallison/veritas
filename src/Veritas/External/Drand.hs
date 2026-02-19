-- | drand HTTP client for fetching external randomness beacon values.
--
-- Stub implementation for Phase 1. Full implementation in Phase 3.
module Veritas.External.Drand
  ( fetchBeaconRound
  , DrandError(..)
  ) where

import Data.Text (Text)
import GHC.Natural (Natural)

import Veritas.Core.Types (BeaconAnchor(..))

data DrandError
  = DrandNetworkError Text
  | DrandRoundNotAvailable Natural
  | DrandVerificationFailed
  deriving stock (Show)

-- | Fetch a specific round from a drand network.
-- Stub for Phase 1 — returns an error indicating drand is not yet implemented.
fetchBeaconRound :: Text       -- ^ network identifier
                 -> Natural    -- ^ round number
                 -> IO (Either DrandError BeaconAnchor)
fetchBeaconRound _network _round =
  pure (Left (DrandNetworkError "drand integration not yet implemented (Phase 3)"))
