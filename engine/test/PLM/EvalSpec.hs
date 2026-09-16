{-# LANGUAGE OverloadedStrings #-}

-- | Specs for the reliability harness: gold-set scoring and the
-- unintended-grant (\"widening\") safety check.
module PLM.EvalSpec (spec) where

import qualified Data.Set as Set
import Data.Map.Strict (fromList)
import Test.Hspec

import PLM.Eval
import PLM.Types

root, nodeA, nodeC :: ResourceId
root = ResourceId "root"
nodeA = ResourceId "a"
nodeC = ResourceId "c"

testTree :: ProductTree
testTree = ProductTree (fromList
  [ (root, Nothing)
  , (nodeA, Just root)
  , (nodeC, Just nodeA)
  ])

p1 :: Principal
p1 = Principal (PrincipalId "p1") (Set.fromList [GroupId "g1"])

mkRule :: RuleId -> Subject -> Target -> Permission -> Effect -> Int -> Rule
mkRule = Rule

allowReadA :: Rule
allowReadA = mkRule (RuleId "allowA") (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Allow 1

spec :: Spec
spec = do
  describe "evaluate" $ do
    it "reports full accuracy when every gold case matches" $ do
      let gold =
            [ GoldCase (PrincipalId "p1") nodeA Read True    -- allowed
            , GoldCase (PrincipalId "p1") nodeC Read False   -- default-deny
            ]
          report = evaluate testTree [allowReadA] [p1] gold
      erTotal report `shouldBe` 2
      erCorrect report `shouldBe` 2
      erAccuracy report `shouldBe` 1.0
      erMismatches report `shouldBe` []

    it "reports the exact mismatched case when a label is wrong" $ do
      -- We wrongly expect a grant on nodeC (which is default-denied).
      let wrong = GoldCase (PrincipalId "p1") nodeC Read True
          gold  = [GoldCase (PrincipalId "p1") nodeA Read True, wrong]
          report = evaluate testTree [allowReadA] [p1] gold
      erCorrect report `shouldBe` 1
      erMismatches report `shouldBe` [wrong]

    it "treats a gold case for an unknown principal as a denial, not a crash" $ do
      let ghost = GoldCase (PrincipalId "ghost") nodeA Read True
          report = evaluate testTree [allowReadA] [p1] [ghost]
      erCorrect report `shouldBe` 0
      erMismatches report `shouldBe` [ghost]

  describe "newlyGranted" $ do
    it "flags a rule change that silently widens access" $ do
      -- Old: nothing. New: a subtree allow reaching every resource under root.
      let widen = mkRule (RuleId "wide") (SubjGroup (GroupId "g1")) (TSubtree root) Read Allow 1
          leaks = newlyGranted testTree [p1] Read [root, nodeA, nodeC] [] [widen]
      leaks `shouldMatchList`
        [ (PrincipalId "p1", root)
        , (PrincipalId "p1", nodeA)
        , (PrincipalId "p1", nodeC)
        ]

    it "is empty when the change only narrows access" $ do
      let wideAllow = mkRule (RuleId "wide") (SubjGroup (GroupId "g1")) (TSubtree root) Read Allow 1
          denyC     = mkRule (RuleId "denyC") (SubjPrincipal (PrincipalId "p1")) (TResource nodeC) Read Deny 5
          -- old grants everything under root; new adds a deny on nodeC (narrows).
          leaks = newlyGranted testTree [p1] Read [root, nodeA, nodeC] [wideAllow] [wideAllow, denyC]
      leaks `shouldBe` []
