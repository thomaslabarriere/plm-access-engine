{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Property-based and example specs for the access engine.
--
-- The QuickCheck properties are the point: they state invariants a PLM access
-- system must never violate (default-deny, deny-overrides, "adding a deny can
-- never grant", order-independence of the decision), and generate hundreds of
-- rule sets over generated product trees — including cyclic and dangling ones —
-- to try to break them. The 'Arbitrary' instances live in "PLM.Arbitrary".
module PLM.EngineSpec (spec) where

import Data.Maybe (isNothing)
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Map.Strict (fromList)
import Test.Hspec
import Test.QuickCheck

import PLM.Arbitrary ()
import PLM.Engine
import PLM.Types

-- A small fixed universe for the examples.
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

-- Helpers to build applicable rules in the examples.
mkRule :: String -> Subject -> Target -> Permission -> Effect -> Int -> Rule
mkRule rid = Rule (RuleId (T.pack rid))

p1 :: Principal
p1 = Principal (PrincipalId "p1") (Set.fromList [GroupId "g1"])

spec :: Spec
spec = do
  describe "decide (properties over generated trees)" $ do
    it "default-deny: no rules means no access" $
      property $ \tree prin res perm ->
        not (granted (decide (tree :: ProductTree) prin res perm []))

    it "adding a deny rule can never turn a denial into a grant" $
      property $ \tree prin res perm rs (d0 :: Rule) ->
        let d = d0 {ruleEffect = Deny}
            withDeny = granted (decide (tree :: ProductTree) prin res perm (d : rs))
            without  = granted (decide tree prin res perm rs)
        -- No discards: state the implication directly as (withDeny <= without)
        -- over 'Bool''s ordering. 'classify' keeps the interesting case visible.
        in classify withDeny "deny-still-granted" (withDeny <= without)

    it "the decision (grant AND deciding rule) is independent of rule order" $
      property $ \tree prin res perm rs ->
        -- Both the outcome and the audited \"why\" must be order-independent: the
        -- ruleId tie-break in 'RuleKey' means an exact key tie no longer resolves
        -- to whichever equal rule came last in the list.
        let d  = decide (tree :: ProductTree) prin res perm rs
            d' = decide tree prin res perm (reverse rs)
        in (granted d === granted d') .&&. (decidingRule d === decidingRule d')

    it "every rule in the trace genuinely applies to the request" $
      property $ \tree prin res perm rs0 ->
        -- Re-id so ids are unique (the generator may repeat them), otherwise
        -- filtering the trace by id is ambiguous.
        let rs = zipWith (\i r -> r {ruleId = RuleId (T.pack (show (i :: Int)))}) [0 ..] rs0
            d = decide (tree :: ProductTree) prin res perm rs
            applied = filter ((`elem` applicable d) . ruleId) rs
        in all (applies tree prin res perm) applied

    it "at an equal key a deny always beats an allow (deny-overrides)" $
      property $ \prin res perm (Positive prio) ->
        -- Both rules share priority, TAll and the same principal subject, so
        -- their (priority, target-spec, subject-spec) keys are identical; only
        -- the effect differs. Both always apply, so no discards.
        let subj   = SubjPrincipal (principalId prin)
            allowR = Rule (RuleId "a") subj TAll perm Allow prio
            denyR  = Rule (RuleId "d") subj TAll perm Deny prio
        in not (granted (decide testTree prin res perm [allowR, denyR]))

    it "an unknown principal id is denied (fail closed) via decideFor" $
      property $ \res perm rs ->
        let ghost = PrincipalId "nobody"
            d = decideFor testTree [p1] ghost res perm rs
        in not (granted d) && isNothing (decidingRule d) && null (applicable d)

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

    it "a principal-scoped allow beats a group-scoped deny at an equal key" $ do
      -- Only the subject specificity separates them: principal > group, so the
      -- principal's allow wins over the group's deny.
      let grpDeny   = mkRule "g" (SubjGroup (GroupId "g1")) (TResource nodeA) Read Deny 1
          prinAllow = mkRule "p" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Allow 1
      granted (decide testTree p1 nodeA Read [grpDeny, prinAllow]) `shouldBe` True

    it "a non-empty rule set where nothing applies still denies" $ do
      let other = mkRule "o" (SubjPrincipal (PrincipalId "p2")) (TResource nodeB) Read Allow 9
          d = decide testTree p1 nodeA Write [other]
      granted d `shouldBe` False
      applicable d `shouldBe` []

  describe "unknownTargets (ingestion validation)" $ do
    it "reports a rule that targets a resource absent from the tree" $ do
      let ghostRes = ResourceId "ghost"
          bad  = mkRule "b" (SubjPrincipal (PrincipalId "p1")) (TResource ghostRes) Read Allow 1
          good = mkRule "g" (SubjPrincipal (PrincipalId "p1")) (TResource nodeA) Read Allow 1
      unknownTargets testTree [good, bad] `shouldBe` [ghostRes]

    it "accepts rules whose targets are all in the tree (TAll included)" $ do
      let sub = mkRule "s" (SubjGroup (GroupId "g1")) (TSubtree root) Read Allow 1
          allR = mkRule "a" (SubjPrincipal (PrincipalId "p1")) TAll Read Allow 1
      unknownTargets testTree [sub, allR] `shouldBe` []
