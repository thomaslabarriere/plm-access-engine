{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | JSON round-trip properties: @decode . encode == Right@ for the wire types
-- the cockpit exchanges. Reuses the engine's 'Arbitrary' instances.
module PLM.JsonSpec (spec) where

import Data.Aeson (FromJSON, ToJSON, decode, encode)
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Map.Strict (fromList)
import Test.Hspec
import Test.QuickCheck

import PLM.Engine
import PLM.Eval
import PLM.Json ()
import PLM.Types

resources :: [ResourceId]
resources = map (ResourceId . T.pack) ["root", "a", "b", "c"]

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

instance Arbitrary Rule where
  arbitrary = Rule . RuleId . T.pack . show
    <$> (arbitrary :: Gen Int)
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> choose (0, 3)

instance Arbitrary RuleId where
  arbitrary = RuleId . T.pack . show <$> (arbitrary :: Gen Int)

instance Arbitrary Decision where
  arbitrary = Decision <$> arbitrary <*> arbitrary <*> listOf arbitrary

instance Arbitrary GoldCase where
  arbitrary = GoldCase <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary EvalReport where
  arbitrary = EvalReport <$> arbitrary <*> arbitrary <*> arbitrary <*> listOf arbitrary

roundTrips :: (Eq a, Show a, ToJSON a, FromJSON a) => a -> Property
roundTrips x = decode (encode x) === Just x

spec :: Spec
spec = describe "JSON round-trips (decode . encode == id)" $ do
  it "Rule" $ property (roundTrips :: Rule -> Property)
  it "Decision" $ property (roundTrips :: Decision -> Property)
  it "GoldCase" $ property (roundTrips :: GoldCase -> Property)
  it "EvalReport" $ property (roundTrips :: EvalReport -> Property)
  it "ProductTree" $
    let tree = ProductTree (fromList
          [ (ResourceId "root", Nothing)
          , (ResourceId "a", Just (ResourceId "root"))
          ])
    in decode (encode tree) `shouldBe` Just tree
  it "Principal" $
    let p = Principal (PrincipalId "p1") (Set.fromList [GroupId "g1", GroupId "g2"])
    in decode (encode p) `shouldBe` Just p
