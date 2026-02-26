module Veritas.Pool.SelectionSpec (spec) where

import qualified Data.ByteString as BS
import Data.List (nub)
import Data.Time (UTCTime(..), fromGregorian, secondsToDiffTime)
import Data.UUID as UUID
import Test.Hspec

import Veritas.Pool.Types
import Veritas.Pool.Selection

-- | Create a test pool member
mkMember :: Int -> String -> PoolMember
mkMember n principal = PoolMember
  { pmAgentId = AgentId (UUID.fromWords (fromIntegral n) 0 0 0)
  , pmPublicKey = BS.replicate 32 (fromIntegral n)
  , pmPrincipalId = PrincipalId (fromString principal)
  , pmJoinedAt = epoch
  }
  where
    fromString = \s -> let _ = s :: String in read ("\"" ++ s ++ "\"")

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

mkMember' :: Int -> Int -> PoolMember
mkMember' n principalNum = PoolMember
  { pmAgentId = AgentId (UUID.fromWords (fromIntegral n) 0 0 0)
  , pmPublicKey = BS.replicate 32 (fromIntegral n)
  , pmPrincipalId = PrincipalId (showT principalNum)
  , pmJoinedAt = epoch
  }
  where showT x = read ("\"principal-" ++ show x ++ "\"")

spec :: Spec
spec = do
  describe "Selection" $ do
    let seed = BS.replicate 48 0x42  -- simulated drand signature
        requesterPrincipal = PrincipalId "principal-1"
        -- 6 members across 4 principals
        members =
          [ mkMember' 1 1  -- requester's principal
          , mkMember' 2 2
          , mkMember' 3 3
          , mkMember' 4 4
          , mkMember' 5 2  -- same principal as agent 2
          , mkMember' 6 3  -- same principal as agent 3
          ]

    it "never selects from the requester's principal" $ do
      case stratifiedSelect members requesterPrincipal seed 2 of
        Right selected ->
          all (\m -> pmPrincipalId m /= requesterPrincipal) selected `shouldBe` True
        Left e -> expectationFailure (show e)

    it "selects exactly N validators" $ do
      case stratifiedSelect members requesterPrincipal seed 2 of
        Right selected -> length selected `shouldBe` 2
        Left e -> expectationFailure (show e)

    it "never selects two validators from the same principal" $ do
      case stratifiedSelect members requesterPrincipal seed 2 of
        Right selected -> do
          let principals = map pmPrincipalId selected
          nub principals `shouldBe` principals
        Left e -> expectationFailure (show e)

    it "is deterministic given the same seed" $ do
      let s1 = stratifiedSelect members requesterPrincipal seed 2
          s2 = stratifiedSelect members requesterPrincipal seed 2
      case (s1, s2) of
        (Right r1, Right r2) ->
          map (unAgentId . pmAgentId) r1 `shouldBe` map (unAgentId . pmAgentId) r2
        _ -> expectationFailure "Expected Right for both"

    it "different seeds produce different selections" $ do
      let seed2 = BS.replicate 48 0x99
          s1 = stratifiedSelect members requesterPrincipal seed 2
          s2 = stratifiedSelect members requesterPrincipal seed2 2
      case (s1, s2) of
        (Right r1, Right r2) ->
          -- With high probability, different seeds produce different orders
          map (unAgentId . pmAgentId) r1 `shouldNotBe` map (unAgentId . pmAgentId) r2
        _ -> expectationFailure "Expected Right for both"

    it "fails when not enough eligible principals" $ do
      let smallPool =
            [ mkMember' 1 1   -- requester's principal
            , mkMember' 2 2
            ]
      case stratifiedSelect smallPool requesterPrincipal seed 2 of
        Left (NotEnoughPrincipals required available) -> do
          required `shouldBe` 3   -- need 3 principals (1 requester + 2 validators)
          available `shouldBe` 2  -- only have 2 (principal-1 and principal-2)
        Right _ -> expectationFailure "Expected Left NotEnoughPrincipals"

    it "fails when all members share requester's principal" $ do
      let samePool =
            [ mkMember' 1 1
            , mkMember' 2 1
            , mkMember' 3 1
            ]
      case stratifiedSelect samePool requesterPrincipal seed 2 of
        Left (NotEnoughPrincipals _ available) ->
          available `shouldBe` 1  -- only requester's principal
        Right _ -> expectationFailure "Expected Left NotEnoughPrincipals"

    it "succeeds with exactly N+1 principals" $ do
      -- 3 principals: 1 requester + 2 validators
      let exactPool =
            [ mkMember' 1 1  -- requester
            , mkMember' 2 2  -- validator candidate
            , mkMember' 3 3  -- validator candidate
            ]
      case stratifiedSelect exactPool requesterPrincipal seed 2 of
        Right selected -> length selected `shouldBe` 2
        Left e -> expectationFailure (show e)

  describe "deterministicShuffle" $ do
    it "preserves all elements" $ do
      let xs = [1..10 :: Int]
          seed = BS.replicate 32 0xab
          shuffled = deterministicShuffle xs seed
      length shuffled `shouldBe` length xs
      all (`elem` shuffled) xs `shouldBe` True

    it "is deterministic" $ do
      let xs = [1..10 :: Int]
          seed = BS.replicate 32 0xab
      deterministicShuffle xs seed `shouldBe` deterministicShuffle xs seed

    it "handles empty list" $ do
      let xs = [] :: [Int]
          seed = BS.replicate 32 0xab
      deterministicShuffle xs seed `shouldBe` []

    it "handles single element" $ do
      let xs = [42 :: Int]
          seed = BS.replicate 32 0xab
      deterministicShuffle xs seed `shouldBe` [42]

    it "actually shuffles (not identity)" $ do
      let xs = [1..20 :: Int]
          seed = BS.replicate 32 0xab
          shuffled = deterministicShuffle xs seed
      -- With 20 elements, probability of identity permutation is 1/20! ≈ 0
      shuffled `shouldNotBe` xs
