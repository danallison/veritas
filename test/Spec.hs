module Main (main) where

import Test.Hspec

import qualified Veritas.Core.StateMachineSpec
import qualified Veritas.Core.ResolutionSpec
import qualified Veritas.Core.AuditLogSpec
import qualified Veritas.Core.RevealSpec
import qualified Veritas.Crypto.HashSpec
import qualified Veritas.Crypto.CommitRevealSpec
import qualified Veritas.Crypto.BLSSpec
import qualified Veritas.Crypto.RosterSpec
import qualified Veritas.Crypto.CeremonyParamsSpec
import qualified Veritas.External.DrandSpec
import qualified Properties.StateMachineProperties
import qualified Properties.ResolutionProperties
import qualified Properties.AuditLogProperties
import qualified Properties.CommitRevealProperties
import qualified Properties.StatisticalProperties
import qualified Properties.PoolProperties
import qualified Veritas.API.HandlersSpec
import qualified Veritas.DB.QueriesSpec
import qualified Veritas.Workers.BeaconFetcherSpec
import qualified Integration.LifecycleSpec
import qualified Integration.ErrorSpec
import qualified Integration.AuditLogSpec
import qualified Integration.StandaloneSpec
import qualified Veritas.Core.PoolSpec
import qualified Veritas.Core.TaskAssignmentSpec
import qualified Veritas.Core.VerificationSpec
import qualified Veritas.Core.VerifiedCacheSpec
import qualified Veritas.Core.VerificationFlowSpec
import qualified Veritas.Pool.SealSpec
import qualified Veritas.Pool.SelectionSpec
import qualified Veritas.Pool.ComparisonSpec
import qualified Veritas.Pool.StateMachineSpec

main :: IO ()
main = hspec $ do
  describe "Core.StateMachine" Veritas.Core.StateMachineSpec.spec
  describe "Core.Resolution" Veritas.Core.ResolutionSpec.spec
  describe "Core.AuditLog" Veritas.Core.AuditLogSpec.spec
  describe "Core.Reveal" Veritas.Core.RevealSpec.spec
  describe "Crypto.Hash" Veritas.Crypto.HashSpec.spec
  describe "Crypto.CommitReveal" Veritas.Crypto.CommitRevealSpec.spec
  describe "Crypto.BLS" Veritas.Crypto.BLSSpec.spec
  describe "Crypto.Roster" Veritas.Crypto.RosterSpec.spec
  describe "Crypto.CeremonyParams" Veritas.Crypto.CeremonyParamsSpec.spec
  describe "External.Drand" Veritas.External.DrandSpec.spec
  describe "Properties.StateMachine" Properties.StateMachineProperties.spec
  describe "Properties.Resolution" Properties.ResolutionProperties.spec
  describe "Properties.AuditLog" Properties.AuditLogProperties.spec
  describe "Properties.CommitReveal" Properties.CommitRevealProperties.spec
  describe "Properties.Statistical" Properties.StatisticalProperties.spec
  describe "Properties.Pool" Properties.PoolProperties.spec
  describe "API.Handlers" Veritas.API.HandlersSpec.spec
  describe "DB.Queries" Veritas.DB.QueriesSpec.spec
  describe "Workers.BeaconFetcher" Veritas.Workers.BeaconFetcherSpec.spec
  describe "Integration.Lifecycle" Integration.LifecycleSpec.spec
  describe "Integration.ErrorCases" Integration.ErrorSpec.spec
  describe "Integration.AuditLog" Integration.AuditLogSpec.spec
  describe "Integration.Standalone" Integration.StandaloneSpec.spec
  describe "Core.Pool" Veritas.Core.PoolSpec.spec
  describe "Core.TaskAssignment" Veritas.Core.TaskAssignmentSpec.spec
  describe "Core.Verification" Veritas.Core.VerificationSpec.spec
  describe "Core.VerifiedCache" Veritas.Core.VerifiedCacheSpec.spec
  describe "Core.VerificationFlow" Veritas.Core.VerificationFlowSpec.spec
  describe "Pool.Seal" Veritas.Pool.SealSpec.spec
  describe "Pool.Selection" Veritas.Pool.SelectionSpec.spec
  describe "Pool.Comparison" Veritas.Pool.ComparisonSpec.spec
  describe "Pool.StateMachine" Veritas.Pool.StateMachineSpec.spec
