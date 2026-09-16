{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Aeson instances for the domain, the 'Decision', and the reliability
-- reports, so the engine can speak JSON to the CLI (and thence the cockpit).
--
-- The instances live here, deliberately out of the pure core, as orphans. The
-- wire shapes are hand-written rather than derived so they are stable, explicit
-- and pleasant for a JavaScript client to consume:
--
-- > Permission  "read" | "write" | "delete" | "admin"
-- > Effect      "allow" | "deny"
-- > Subject     {"kind":"principal","id":"p1"} | {"kind":"group","id":"g1"}
-- > Target      {"kind":"resource","id":"a"} | {"kind":"subtree","id":"root"}
-- >           | {"kind":"all"}
-- > Rule        {"id","subject","target","permission","effect","priority"}
-- > Principal   {"id":"p1","groups":["g1","g2"]}
-- > ProductTree [{"resource":"root","parent":null},{"resource":"a","parent":"root"}]
-- > Decision    {"granted":true,"decidingRule":"r1"|null,"applicable":["r1"]}
-- > GoldCase    {"principal","resource","permission","expected"}
-- > EvalReport  {"total","correct","accuracy","mismatches":[GoldCase]}
module PLM.Json () where

import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Value (String)
  , object
  , withObject
  , withText
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Foldable (toList)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import PLM.Engine (Decision (..))
import PLM.Eval (EvalReport (..), GoldCase (..))
import PLM.Types

-- Identifier newtypes: bare JSON strings.
instance ToJSON PrincipalId where toJSON (PrincipalId t) = toJSON t
instance FromJSON PrincipalId where parseJSON = fmap PrincipalId . parseJSON

instance ToJSON GroupId where toJSON (GroupId t) = toJSON t
instance FromJSON GroupId where parseJSON = fmap GroupId . parseJSON

instance ToJSON ResourceId where toJSON (ResourceId t) = toJSON t
instance FromJSON ResourceId where parseJSON = fmap ResourceId . parseJSON

instance ToJSON RuleId where toJSON (RuleId t) = toJSON t
instance FromJSON RuleId where parseJSON = fmap RuleId . parseJSON

instance ToJSON Permission where
  toJSON = String . \case
    Read   -> "read"
    Write  -> "write"
    Delete -> "delete"
    Admin  -> "admin"

instance FromJSON Permission where
  parseJSON = withText "Permission" $ \case
    "read"   -> pure Read
    "write"  -> pure Write
    "delete" -> pure Delete
    "admin"  -> pure Admin
    other    -> fail ("unknown permission: " <> show other)

instance ToJSON Effect where
  toJSON = String . \case
    Allow -> "allow"
    Deny  -> "deny"

instance FromJSON Effect where
  parseJSON = withText "Effect" $ \case
    "allow" -> pure Allow
    "deny"  -> pure Deny
    other   -> fail ("unknown effect: " <> show other)

instance ToJSON Subject where
  toJSON = \case
    SubjPrincipal pid -> object ["kind" .= String "principal", "id" .= pid]
    SubjGroup gid     -> object ["kind" .= String "group", "id" .= gid]

instance FromJSON Subject where
  parseJSON = withObject "Subject" $ \o -> do
    kind <- o .: "kind"
    case kind :: String of
      "principal" -> SubjPrincipal <$> o .: "id"
      "group"     -> SubjGroup <$> o .: "id"
      other       -> fail ("unknown subject kind: " <> other)

instance ToJSON Target where
  toJSON = \case
    TResource r -> object ["kind" .= String "resource", "id" .= r]
    TSubtree r  -> object ["kind" .= String "subtree", "id" .= r]
    TAll        -> object ["kind" .= String "all"]

instance FromJSON Target where
  parseJSON = withObject "Target" $ \o -> do
    kind <- o .: "kind"
    case kind :: String of
      "resource" -> TResource <$> o .: "id"
      "subtree"  -> TSubtree <$> o .: "id"
      "all"      -> pure TAll
      other      -> fail ("unknown target kind: " <> other)

instance ToJSON Rule where
  toJSON r = object
    [ "id"         .= ruleId r
    , "subject"    .= ruleSubject r
    , "target"     .= ruleTarget r
    , "permission" .= rulePermission r
    , "effect"     .= ruleEffect r
    , "priority"   .= rulePriority r
    ]

instance FromJSON Rule where
  parseJSON = withObject "Rule" $ \o ->
    Rule
      <$> o .: "id"
      <*> o .: "subject"
      <*> o .: "target"
      <*> o .: "permission"
      <*> o .: "effect"
      <*> o .: "priority"

instance ToJSON Principal where
  toJSON p = object
    [ "id"     .= principalId p
    , "groups" .= toList (principalGroups p)
    ]

instance FromJSON Principal where
  parseJSON = withObject "Principal" $ \o ->
    Principal <$> o .: "id" <*> (Set.fromList <$> o .: "groups")

instance ToJSON ProductTree where
  toJSON (ProductTree m) =
    toJSON [object ["resource" .= res, "parent" .= parent] | (res, parent) <- Map.toList m]

instance FromJSON ProductTree where
  parseJSON v = ProductTree . Map.fromList <$> (parseJSON v >>= mapM parseNode)
    where
      parseNode = withObject "TreeNode" $ \o ->
        (,) <$> o .: "resource" <*> o .:? "parent"

instance ToJSON Decision where
  toJSON d = object
    [ "granted"      .= granted d
    , "decidingRule" .= decidingRule d
    , "applicable"   .= applicable d
    ]

instance FromJSON Decision where
  parseJSON = withObject "Decision" $ \o ->
    Decision <$> o .: "granted" <*> o .: "decidingRule" <*> o .: "applicable"

instance ToJSON GoldCase where
  toJSON gc = object
    [ "principal"  .= gcPrincipal gc
    , "resource"   .= gcResource gc
    , "permission" .= gcPermission gc
    , "expected"   .= gcExpected gc
    ]

instance FromJSON GoldCase where
  parseJSON = withObject "GoldCase" $ \o ->
    GoldCase
      <$> o .: "principal"
      <*> o .: "resource"
      <*> o .: "permission"
      <*> o .: "expected"

instance ToJSON EvalReport where
  toJSON r = object
    [ "total"      .= erTotal r
    , "correct"    .= erCorrect r
    , "accuracy"   .= erAccuracy r
    , "mismatches" .= erMismatches r
    ]

instance FromJSON EvalReport where
  parseJSON = withObject "EvalReport" $ \o ->
    EvalReport
      <$> o .: "total"
      <*> o .: "correct"
      <*> o .: "accuracy"
      <*> o .: "mismatches"
