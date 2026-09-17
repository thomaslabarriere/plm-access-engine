{-# LANGUAGE ScopedTypeVariables #-}

-- | JSON round-trip properties: @decode . encode == Just@ for the wire types
-- the cockpit exchanges. The 'Arbitrary' instances live in "PLM.Arbitrary".
module PLM.JsonSpec (spec) where

import Data.Aeson (FromJSON, ToJSON, decode, encode)
import Test.Hspec
import Test.QuickCheck

import PLM.Arbitrary ()
import PLM.Engine
import PLM.Eval
import PLM.Json ()
import PLM.Types

roundTrips :: (Eq a, Show a, ToJSON a, FromJSON a) => a -> Property
roundTrips x = decode (encode x) === Just x

spec :: Spec
spec = describe "JSON round-trips (decode . encode == id)" $ do
  it "Rule" $ property (roundTrips :: Rule -> Property)
  it "Decision" $ property (roundTrips :: Decision -> Property)
  it "GoldCase" $ property (roundTrips :: GoldCase -> Property)
  it "EvalReport" $ property (roundTrips :: EvalReport -> Property)
  it "ProductTree" $ property (roundTrips :: ProductTree -> Property)
  it "Principal" $ property (roundTrips :: Principal -> Property)
