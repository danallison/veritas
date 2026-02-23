{-# LANGUAGE OverloadedStrings #-}
-- | Generate test vectors for cross-language verification.
--
-- This program runs the actual resolution functions and outputs JSON
-- test vectors that the TypeScript verification tests can compare against.
module Main where

import Data.Aeson ((.=), encode, object, toJSON, Value)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.UUID as UUID
import Numeric (showHex)

import Veritas.Core.Types
import Veritas.Core.Resolution
import Veritas.Crypto.Hash

-- | Hex-encode a ByteString
toHex :: BS.ByteString -> String
toHex = concatMap (\w -> let h = showHex w "" in (if length h < 2 then "0" else "") ++ h) . BS.unpack

main :: IO ()
main = LC8.putStrLn $ encode $ object
  [ "hkdf"           .= hkdfVectors
  , "combine"        .= combineVector
  , "coinFlip"       .= coinFlipVector
  , "uniformChoice"  .= uniformChoiceVector
  , "intRange"       .= intRangeVector
  , "weightedChoice" .= weightedChoiceVector
  , "shuffle"        .= shuffleVector
  , "fullPipeline"   .= fullPipelineVector
  , "mixedSources"   .= mixedSourcesVector
  ]

-- Two fixed 32-byte entropy values (SHA-256 hashes of known strings)
entropy1, entropy2, entropy3, entropy4 :: BS.ByteString
entropy1 = sha256 "test-entropy-1"
entropy2 = sha256 "test-entropy-2"
entropy3 = sha256 "test-entropy-3"
entropy4 = sha256 "test-entropy-4"

-- | HKDF test vectors: verify that hkdfSHA256 produces the expected output
hkdfVectors :: Value
hkdfVectors = object
  [ "input"  .= toHex entropy1
  , "uniform_output" .= toHex (hkdfSHA256 "veritas-uniform" entropy1 32)
  , "shuffle_0_output" .= toHex (hkdfSHA256 "veritas-shuffle-0" entropy1 32)
  , "shuffle_1_output" .= toHex (hkdfSHA256 "veritas-shuffle-1" entropy1 32)
  , "shuffle_10_output" .= toHex (hkdfSHA256 "veritas-shuffle-10" entropy1 32)
  ]

-- | Entropy combination: concatenate and SHA-256
combineVector :: Value
combineVector = object
  [ "inputs"   .= [toHex entropy1, toHex entropy2]
  , "combined" .= toHex (sha256 (BS.concat [entropy1, entropy2]))
  ]

-- Combined entropy for use in derivation tests
combined :: BS.ByteString
combined = sha256 (BS.concat [entropy1, entropy2])

-- | CoinFlip derivation
coinFlipVector :: Value
coinFlipVector = object
  [ "entropy" .= toHex combined
  , "result"  .= deriveCoinFlip combined
  ]

-- | UniformChoice derivation
uniformChoiceVector :: Value
uniformChoiceVector = object
  [ "entropy" .= toHex combined
  , "choices" .= (["alpha", "beta", "gamma", "delta"] :: [String])
  , "result"  .= deriveChoice combined ("alpha" :| ["beta", "gamma", "delta"])
  ]

-- | IntRange derivation
intRangeVector :: Value
intRangeVector = object
  [ "entropy" .= toHex combined
  , "lo"      .= (1 :: Int)
  , "hi"      .= (100 :: Int)
  , "result"  .= deriveIntRange combined 1 100
  ]

-- | WeightedChoice derivation
weightedChoiceVector :: Value
weightedChoiceVector = object
  [ "entropy" .= toHex combined
  , "choices" .= [object ["label" .= ("red" :: String), "weight" .= (1 :: Int)]
                 ,object ["label" .= ("green" :: String), "weight" .= (2 :: Int)]
                 ,object ["label" .= ("blue" :: String), "weight" .= (3 :: Int)]
                 ]
  , "result"  .= deriveWeightedChoice combined (("red", 1) :| [("green", 2), ("blue", 3)])
  ]

-- | Shuffle derivation
shuffleVector :: Value
shuffleVector = object
  [ "entropy" .= toHex combined
  , "items"   .= (["alice", "bob", "carol", "dave"] :: [String])
  , "result"  .= deriveShuffle combined ("alice" :| ["bob", "carol", "dave"])
  ]

-- | Full pipeline: from raw entropy contributions through combineEntropy + resolve
-- This tests canonical sorting and the full resolve function.
fullPipelineVector :: Value
fullPipelineVector =
  let pid1 = ParticipantId (UUID.fromWords 0x550e8400 0xe29b41d4 0xa7164466 0x55440000)
      pid2 = ParticipantId (UUID.fromWords 0x660e8400 0xe29b41d4 0xa7164466 0x55440000)
      c1 = EntropyContribution
        { ecCeremony = CeremonyId UUID.nil
        , ecSource = ParticipantEntropy pid1
        , ecValue = entropy1
        }
      c2 = EntropyContribution
        { ecCeremony = CeremonyId UUID.nil
        , ecSource = ParticipantEntropy pid2
        , ecValue = entropy2
        }
      -- Provide them in reverse order to test sorting
      contributions = [c2, c1]
      combinedFull = combineEntropy contributions
      outcome = resolve (CoinFlip "Heads" "Tails") contributions
  in object
    [ "contributions" .=
        [ object [ "source" .= ("ParticipantEntropy" :: String)
                 , "participant_id" .= UUID.toString (let ParticipantId u = pid1 in u)
                 , "value" .= toHex entropy1
                 ]
        , object [ "source" .= ("ParticipantEntropy" :: String)
                 , "participant_id" .= UUID.toString (let ParticipantId u = pid2 in u)
                 , "value" .= toHex entropy2
                 ]
        ]
    , "combined_entropy" .= toHex combinedFull
    , "coin_flip_result" .= case outcomeValue outcome of
        CoinFlipResult label -> toJSON label
        _ -> toJSON ("" :: String)
    ]

-- | Mixed source types: tests that cross-type priority sorting works correctly.
-- Includes ParticipantEntropy, DefaultEntropy, BeaconEntropy, and VRFEntropy
-- deliberately provided out of canonical order.
mixedSourcesVector :: Value
mixedSourcesVector =
  let pid1 = ParticipantId (UUID.fromWords 0xaaaa0000 0x00000000 0x00000000 0x00000001)
      pid2 = ParticipantId (UUID.fromWords 0xbbbb0000 0x00000000 0x00000000 0x00000002)
      beaconAnchor = BeaconAnchor
        { baNetwork = "test-chain"
        , baRound = 99
        , baValue = entropy3
        , baSignature = "sig"
        , baFetchedAt = read "2026-01-01 00:00:00 UTC"
        }
      vrfOut = VRFOutput
        { vrfValue = entropy4
        , vrfProof = "proof"
        , vrfPublicKey = "pk"
        }
      -- Contributions in deliberately wrong order:
      -- VRF (priority 3), Beacon (2), Default (1), Participant (0)
      contributions =
        [ EntropyContribution (CeremonyId UUID.nil) (VRFEntropy vrfOut) entropy4
        , EntropyContribution (CeremonyId UUID.nil) (BeaconEntropy beaconAnchor) entropy3
        , EntropyContribution (CeremonyId UUID.nil) (DefaultEntropy pid2) entropy2
        , EntropyContribution (CeremonyId UUID.nil) (ParticipantEntropy pid1) entropy1
        ]
      combinedMixed = combineEntropy contributions
      outcome = resolve (UniformChoice ("x" :| ["y", "z"])) contributions
  in object
    [ "contributions" .=
        [ object [ "source" .= ("VRFEntropy" :: String)
                 , "source_id" .= ("vrf" :: String)
                 , "value" .= toHex entropy4
                 ]
        , object [ "source" .= ("BeaconEntropy" :: String)
                 , "source_id" .= ("beacon" :: String)
                 , "value" .= toHex entropy3
                 ]
        , object [ "source" .= ("DefaultEntropy" :: String)
                 , "source_id" .= UUID.toString (let ParticipantId u = pid2 in u)
                 , "value" .= toHex entropy2
                 ]
        , object [ "source" .= ("ParticipantEntropy" :: String)
                 , "source_id" .= UUID.toString (let ParticipantId u = pid1 in u)
                 , "value" .= toHex entropy1
                 ]
        ]
    , "canonical_order" .= (["ParticipantEntropy", "DefaultEntropy", "BeaconEntropy", "VRFEntropy"] :: [String])
    , "combined_entropy" .= toHex combinedMixed
    , "ceremony_type" .= ("UniformChoice" :: String)
    , "choices" .= (["x", "y", "z"] :: [String])
    , "result" .= case outcomeValue outcome of
        ChoiceResult t -> toJSON t
        _ -> toJSON ("" :: String)
    ]
