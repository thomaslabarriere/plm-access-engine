{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Shared QuickCheck generators for the domain and wire types.
--
-- These orphan 'Arbitrary' instances used to be duplicated across the engine
-- and JSON specs; keeping the single copy here means every property draws from
-- the same small, dense universe. 'shrink' is supplied for the compound types
-- ('Rule', 'Target', 'Subject') so a counterexample minimises to something
-- readable, and 'ProductTree' generates small forests that deliberately include
-- cycles and dangling parents, so the invariants are exercised on hostile trees
-- rather than only the fixed 4-node fixture.
module PLM.Arbitrary () where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import Test.QuickCheck

import PLM.Engine (Decision (..))
import PLM.Eval (EvalReport (..), GoldCase (..))
import PLM.Types

-- | The fixed resource universe generators draw from. Kept small so rule sets
-- are dense and subtree/ancestor relationships actually occur.
resourceNames :: [ResourceId]
resourceNames = map (ResourceId . T.pack) ["root", "a", "b", "c", "d"]

instance Arbitrary Permission where arbitrary = arbitraryBoundedEnum
instance Arbitrary Effect where arbitrary = elements [Allow, Deny]

instance Arbitrary ResourceId where arbitrary = elements resourceNames
instance Arbitrary PrincipalId where
  arbitrary = elements (map (PrincipalId . T.pack) ["p1", "p2", "p3"])
instance Arbitrary GroupId where
  arbitrary = elements (map (GroupId . T.pack) ["g1", "g2"])
instance Arbitrary RuleId where
  arbitrary = RuleId . T.pack . show <$> (arbitrary :: Gen Int)

instance Arbitrary Subject where
  arbitrary = oneof [SubjPrincipal <$> arbitrary, SubjGroup <$> arbitrary]
  -- Shrink a group subject towards the more specific single principal.
  shrink (SubjPrincipal _) = []
  shrink (SubjGroup _)     = [SubjPrincipal (PrincipalId (T.pack "p1"))]

instance Arbitrary Target where
  arbitrary = oneof [TResource <$> arbitrary, TSubtree <$> arbitrary, pure TAll]
  -- Shrink towards the least specific target.
  shrink TAll         = []
  shrink (TSubtree _) = [TAll]
  shrink (TResource r) = TAll : [TSubtree r]

instance Arbitrary Principal where
  arbitrary = Principal <$> arbitrary <*> (Set.fromList <$> sublistOf allGroups)
    where allGroups = map (GroupId . T.pack) ["g1", "g2"]

instance Arbitrary Rule where
  arbitrary =
    Rule
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> choose (0, 3)
  shrink r =
    [ r {ruleTarget = t}   | t <- shrink (ruleTarget r) ]
      ++ [ r {ruleSubject = s}  | s <- shrink (ruleSubject r) ]
      ++ [ r {rulePriority = p} | p <- shrink (rulePriority r) ]

-- | Small forests that INCLUDE cyclic and dangling parents on purpose: a parent
-- may be any name (so it can point outside the picked set, or back at an
-- ancestor forming a cycle). 'ancestors' is cycle-safe, so the invariants must
-- still hold — that is exactly what this stresses.
instance Arbitrary ProductTree where
  arbitrary = do
    picked <- sublistOf resourceNames
    let nodes = if null picked then take 1 resourceNames else picked
    parented <- mapM (\r -> (,) r <$> genParent) nodes
    pure (ProductTree (Map.fromList parented))
    where
      genParent =
        frequency
          [ (1, pure Nothing)
          , (3, Just <$> elements resourceNames)
          ]
  -- Shrink toward smaller, tamer forests: first by dropping a node entirely,
  -- then by cutting an edge (repointing a parented node to a root). This lets a
  -- failing tree counterexample minimise to the fewest nodes and edges that
  -- still reproduce the failure.
  shrink (ProductTree m) =
    [ ProductTree (Map.delete r m) | r <- Map.keys m ]
      ++ [ ProductTree (Map.insert r Nothing m) | (r, Just _) <- Map.toList m ]

instance Arbitrary Decision where
  arbitrary = Decision <$> arbitrary <*> arbitrary <*> listOf arbitrary

instance Arbitrary GoldCase where
  arbitrary = GoldCase <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary EvalReport where
  arbitrary = EvalReport <$> arbitrary <*> arbitrary <*> arbitrary <*> listOf arbitrary
