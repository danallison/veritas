module Properties.CommitRevealProperties (spec) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.UUID as UUID
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

import TestHelpers ()
import Veritas.Core.Types
import Veritas.Crypto.CommitReveal

spec :: Spec
spec = do
  describe "CommitReveal Properties" $ do
    prop "correct revealed value always verifies against its seal" $
      \(val :: ByteString) ->
        not (BS.null val) ==>
          let cid = CeremonyId UUID.nil
              pid = ParticipantId (UUID.fromWords 1 0 0 0)
              seal = createSeal cid pid val
          in verifySeal cid pid val seal

    prop "wrong revealed value never verifies against seal" $
      \(val :: ByteString) (wrong :: ByteString) ->
        not (BS.null val) && not (BS.null wrong) && val /= wrong ==>
          let cid = CeremonyId UUID.nil
              pid = ParticipantId (UUID.fromWords 1 0 0 0)
              seal = createSeal cid pid val
          in not (verifySeal cid pid wrong seal)

    prop "seal is different for different participants" $
      \(val :: ByteString) ->
        not (BS.null val) ==>
          let cid = CeremonyId UUID.nil
              pid1 = ParticipantId (UUID.fromWords 1 0 0 0)
              pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
          in createSeal cid pid1 val /= createSeal cid pid2 val

    prop "seal is different for different ceremonies" $
      \(val :: ByteString) ->
        not (BS.null val) ==>
          let cid1 = CeremonyId UUID.nil
              cid2 = CeremonyId (UUID.fromWords 1 0 0 0)
              pid = ParticipantId (UUID.fromWords 1 0 0 0)
          in createSeal cid1 pid val /= createSeal cid2 pid val

    prop "defaultEntropyValue is deterministic" $
      let cid = CeremonyId UUID.nil
          pid = ParticipantId (UUID.fromWords 1 0 0 0)
      in defaultEntropyValue cid pid == defaultEntropyValue cid pid

    prop "defaultEntropyValue is distinct per participant" $
      let cid = CeremonyId UUID.nil
          pid1 = ParticipantId (UUID.fromWords 1 0 0 0)
          pid2 = ParticipantId (UUID.fromWords 2 0 0 0)
      in defaultEntropyValue cid pid1 /= defaultEntropyValue cid pid2

    prop "defaultEntropyValue is distinct per ceremony" $
      let cid1 = CeremonyId UUID.nil
          cid2 = CeremonyId (UUID.fromWords 1 0 0 0)
          pid = ParticipantId (UUID.fromWords 1 0 0 0)
      in defaultEntropyValue cid1 pid /= defaultEntropyValue cid2 pid
