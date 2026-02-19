module Main (main) where

import Test.Hspec

import qualified Veritas.Core.StateMachineSpec
import qualified Veritas.Core.ResolutionSpec
import qualified Veritas.Core.AuditLogSpec
import qualified Veritas.Core.RevealSpec
import qualified Veritas.Crypto.HashSpec
import qualified Veritas.Crypto.CommitRevealSpec
import qualified Veritas.External.DrandSpec
import qualified Properties.StateMachineProperties
import qualified Properties.ResolutionProperties
import qualified Properties.AuditLogProperties
import qualified Properties.CommitRevealProperties
import qualified Properties.StatisticalProperties

main :: IO ()
main = hspec $ do
  describe "Core.StateMachine" Veritas.Core.StateMachineSpec.spec
  describe "Core.Resolution" Veritas.Core.ResolutionSpec.spec
  describe "Core.AuditLog" Veritas.Core.AuditLogSpec.spec
  describe "Core.Reveal" Veritas.Core.RevealSpec.spec
  describe "Crypto.Hash" Veritas.Crypto.HashSpec.spec
  describe "Crypto.CommitReveal" Veritas.Crypto.CommitRevealSpec.spec
  describe "External.Drand" Veritas.External.DrandSpec.spec
  describe "Properties.StateMachine" Properties.StateMachineProperties.spec
  describe "Properties.Resolution" Properties.ResolutionProperties.spec
  describe "Properties.AuditLog" Properties.AuditLogProperties.spec
  describe "Properties.CommitReveal" Properties.CommitRevealProperties.spec
  describe "Properties.Statistical" Properties.StatisticalProperties.spec
