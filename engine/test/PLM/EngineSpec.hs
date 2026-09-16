{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Property-based and example specs for the access engine.
--
-- The QuickCheck properties are the point: they state invariants a PLM access
-- system must never violate (default-deny, deny-overrides, "adding a deny can
-- never grant", order-independence of the decision), and generate hundreds of
-- rule sets over a small product tree to try to break them.
module PLM.EngineSpec (spec) where

import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Map.Strict (fromList)
import Test.Hspec
import Test.QuickCheck

import PLM.Engine
import PLM.Types

-- A small fixed universe so generated rule sets are dense and meaningful.
-- Tree:  root -> a -> c ,  root -> b
root, nodeA, nodeB, nodeC :: ResourceId
root = ResourceId "root"
nodeA = ResourceId "a"
nodeB = ResourceId "b"
nodeC = ResourceId "c"

testTree :: ProductTree
testTree = ProductTree (fromList
  [ (root, Nothing)
  , (nodeA, Just root)
  , (nodeB, Just root)
  , (nodeC, Just nodeA)
  ])

resources :: [ResourceId]
resources = [root, nodeA, nodeB, nodeC]

instance Arbitrary Permission where arbitrary = arbitraryBoundedEnum
instance Arbitrary Effect where arbitrary = elements [Allow, Deny]

instance Arbitrary ResourceId where arbitrary = elements resources
instance Arbitrary PrincipalId where
  arbitrary = elements (map (PrincipalId . T.pack) ["p1", "p2", "p3"])
instance Arbitrary GroupId where
  arbitrary = elements (map (GroupId . T.pack) ["g1", "g2"])

instance Arbitrary Subject where
  arbitrary = oneof [SubjPrincipal <$> arbitrary, SubjGroup <$> arbitrary]

instance Arbitrary Target where
  arbitrary = oneof [TResource <$> arbitrary, TSubtree <$> arbitrary, pure TAll]

instance Arbitrary Principal where
  arbitrary = Principal <$> arbitrary <*> (Set.fromList <$> sublistOf allGroups)
    where allGroups = map (GroupId . T.pack) ["g1", "g2"]

instance Arbitrary Rule where
  arbitrary = Rule . RuleId . T.pack . show
    <$> (arbitrary :: Gen Int)
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> choose (0, 3)

-- Helpers to build applicable rules in the examples.
mkRule :: String -> Subject -> Target -> Permission -> Effect -> Int -> Rule
mkRule rid = Rule (RuleId (T.pack rid))

p1 :: Principal
p1 = Principal (PrincipalId "p1") (Set.fromList [GroupId "g1"])

spec :: Spec
spec = do
  describe "decide (properties)" $ do
    it "default-deny: no rules means no access" $
      property $ \prin res perm ->
        not (granted (decide testTree prin res perm []))

    it "adding a deny rule can never turn a denial into a grant" $
      property $ \prin res perm rs (d0 :: Rule) ->
        let d = d0 {ruleEffect = Deny}
            withDeny = decide testTree prin res perm (d : rs)
            without  = decide testTree prin res perm rs
        in granted withDeny ==> granted without

    it "the granted decision is independent of rule order" $
      property $ \prin res perm rs ->
        granted (decide testTree prin res perm rs)
          === granted (decide testTree prin res perm (reverse rs))

    it "every rule in the trace genuinely applies to the request" $
      property $ \prin res perm rs0 ->
        -- Re-id so ids are unique (the generator may repeat them), otherwise
        -- filtering the trace by id is ambiguous.
        let rs = zipWith (\i r -> r {ruleId = RuleId (T.pack (show (i :: Int)))}) [0 ..] rs0
            d = decide testTree prin res perm rs
            applied = filter ((`elem` applicable d) . ruleId) rs
        in all (applies testTree prin res perm) applied

  describe "decide (examples)" $ do
    it "deny overrides allow at an identical key" $ do
      let allowR = mkRule "al" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Allow 1
          denyR  = mkRule "de" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Deny 1
      granted (decide testTree p1 nodeA Read [allowR, denyR]) `shouldBe` False
      granted (decide testTree p1 nodeA Read [denyR, allowR]) `shouldBe` False

    it "a higher-priority allow beats a lower-priority deny" $ do
      let allowR = mkRule "al" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Allow 5
          denyR  = mkRule "de" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Deny 1
      granted (decide testTree p1 nodeA Read [denyR, allowR]) `shouldBe` True

    it "a subtree allow covers a descendant resource" $ do
      let r = mkRule "sub" (SubjPrincipal (PrincipalId "p1")) (TSubtree root) Read Allow 1
      granted (decide testTree p1 nodeC Read [r]) `shouldBe` True

    it "an exact-resource deny beats a broader subtree allow" $ do
      let allowSub = mkRule "al" (SubjPrincipal (PrincipalId "p1")) (TSubtree root) Read Allow 1
          denyEx   = mkRule "de" (SubjPrincipal (PrincipalId "p1")) (TResource nodeC) Read Deny 1
      granted (decide testTree p1 nodeC Read [allowSub, denyEx]) `shouldBe` False

    it "an Admin rule permits any requested permission" $ do
      let r = mkRule "adm" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Admin Allow 1
      granted (decide testTree p1 nodeA Delete [r]) `shouldBe` True

    it "a group rule applies to a principal in that group" $ do
      let r = mkRule "grp" (SubjGroup (GroupId "g1")) (TResource nodeA) Read Allow 1
      granted (decide testTree p1 nodeA Read [r]) `shouldBe` True
