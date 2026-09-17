{-# LANGUAGE OverloadedStrings #-}

-- | @plm-access@: a thin JSON front-end to the access engine, for the React
-- cockpit. Each subcommand reads one JSON envelope (from a file argument, or
-- stdin) and prints exactly one JSON object to stdout; anything diagnostic
-- goes to stderr, so stdout is always clean, parseable JSON.
--
-- > plm-access decide    < envelope.json  -> Decision
-- > plm-access eval      < envelope.json  -> EvalReport
-- > plm-access diff      < envelope.json  -> [{principal,resource,permission}]
-- > plm-access decisions < envelope.json  -> {"<pid>|<res>|<perm>": Decision}
module Main (main) where

import Data.Aeson (FromJSON (..), eitherDecode, encode, object, withObject, (.:), (.:?), (.=))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Function (on)
import Data.List (intercalate, nubBy)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import PLM.Engine (Decision, decide, decideFor, unknownTargets)
import PLM.Eval (GoldCase, evaluate, newlyGranted)
import PLM.Json ()
import PLM.Types

-- | A single access request inside the @decide@ envelope.
data Request = Request PrincipalId ResourceId Permission

instance FromJSON Request where
  parseJSON = withObject "request" $ \o ->
    Request <$> o .: "principal" <*> o .: "resource" <*> o .: "permission"

data DecideInput = DecideInput ProductTree [Rule] [Principal] Request

instance FromJSON DecideInput where
  parseJSON = withObject "decide input" $ \o ->
    DecideInput
      <$> o .: "tree"
      <*> o .: "rules"
      <*> o .: "principals"
      <*> o .: "request"

data EvalInput = EvalInput ProductTree [Rule] [Principal] [GoldCase]

instance FromJSON EvalInput where
  parseJSON = withObject "eval input" $ \o ->
    EvalInput
      <$> o .: "tree"
      <*> o .: "rules"
      <*> o .: "principals"
      <*> o .: "gold"

-- | The @diff@ envelope: two rule sets over one tree/roster. The resource and
-- permission universes are derived from the tree by 'newlyGranted', so the
-- caller supplies neither. The old set is read from @oldRules@ if present, else
-- from the shared dataset's @rules@ field — so the project's @dataset.json@
-- (which ships @rules@/@newRules@) diffs directly, with no hand rename. At
-- least one of the two must be present; @newRules@ is always required.
data DiffInput = DiffInput ProductTree [Principal] [Rule] [Rule]

instance FromJSON DiffInput where
  parseJSON = withObject "diff input" $ \o -> do
    tree       <- o .: "tree"
    principals <- o .: "principals"
    mOld       <- o .:? "oldRules"
    mRules     <- o .:? "rules"
    oldRules   <- case (mOld, mRules) of
      (Just rs, _)       -> pure rs
      (Nothing, Just rs) -> pure rs
      (Nothing, Nothing) -> fail "expected key \"oldRules\" or \"rules\" for the old rule set"
    newRules   <- o .: "newRules"
    pure (DiffInput tree principals oldRules newRules)

-- | The @decisions@ envelope: a dataset without a request. The batch is taken
-- over every principal x resource(from the tree) x permission.
data BatchInput = BatchInput ProductTree [Rule] [Principal]

instance FromJSON BatchInput where
  parseJSON = withObject "decisions input" $ \o ->
    BatchInput
      <$> o .: "tree"
      <*> o .: "rules"
      <*> o .: "principals"

main :: IO ()
main = do
  args <- getArgs
  case args of
    (cmd : rest) -> runCommand cmd rest
    []           -> usageError

runCommand :: String -> [String] -> IO ()
runCommand cmd rest = do
  raw <- readInput rest
  case cmd of
    "decide"    -> withDecoded raw runDecide
    "eval"      -> withDecoded raw runEval
    "diff"      -> withDecoded raw runDiff
    "decisions" -> withDecoded raw runDecisions
    _           -> usageError

-- | Read the JSON envelope: from the first path argument if given, else stdin.
readInput :: [String] -> IO BL.ByteString
readInput (path : _) = BL.readFile path
readInput []         = BL.getContents

-- | Decode into the expected envelope or fail loudly on stderr.
withDecoded :: FromJSON a => BL.ByteString -> (a -> IO ()) -> IO ()
withDecoded raw k =
  case eitherDecode raw of
    Left err  -> hPutStrLn stderr ("plm-access: invalid input: " <> err) >> exitFailure
    Right val -> k val

emit :: BL.ByteString -> IO ()
emit = BLC.putStrLn

-- | Resolve the request's principal through the shared 'decideFor', so an
-- unknown principal id fails closed (default-deny) exactly as it does in the
-- reliability harness — never fabricated into an empty principal that grants.
runDecide :: DecideInput -> IO ()
runDecide (DecideInput tree rules principals0 (Request pid res perm)) = do
  guardTargets tree rules
  let principals = dedupPrincipals principals0
  emit (encode (decideFor tree principals pid res perm rules))

runEval :: EvalInput -> IO ()
runEval (EvalInput tree rules principals0 gold) =
  emit (encode (evaluate tree rules (dedupPrincipals principals0) gold))

-- | Emit each silently-widened grant as a JSON object
-- @{"principal":..,"resource":..,"permission":..}@ (one entry per widened
-- (principal, resource, permission), covering every permission).
runDiff :: DiffInput -> IO ()
runDiff (DiffInput tree principals0 oldRules newRules) = do
  guardTargets tree (oldRules <> newRules)
  let principals = dedupPrincipals principals0
  emit (encode (map entry (newlyGranted tree principals oldRules newRules)))
  where
    entry (PrincipalId p, ResourceId r, perm) =
      object ["principal" .= p, "resource" .= r, "permission" .= perm]

-- | Emit the full decision matrix as a JSON object keyed by
-- @"<principal>|<resource>|<permission>"@, one 'Decision' per cell — the shape
-- the cockpit loads as @decisions.json@.
runDecisions :: BatchInput -> IO ()
runDecisions (BatchInput tree rules principals0) = do
  guardTargets tree rules
  emit (encode (Map.fromList entries))
  where
    principals = dedupPrincipals principals0

    entries :: [(Text, Decision)]
    entries =
      [ (cellKey (principalId prin) res perm, decide tree prin res perm rules)
      | prin <- principals
      , res  <- treeResources tree
      , perm <- [minBound .. maxBound]
      ]

    cellKey (PrincipalId p) (ResourceId r) perm =
      p <> "|" <> r <> "|" <> permToken perm

-- | The permission tokens the wire uses, as bare 'Text' for decision keys.
permToken :: Permission -> Text
permToken perm = case perm of
  Read   -> "read"
  Write  -> "write"
  Delete -> "delete"
  Admin  -> "admin"

-- | Collapse a roster to one 'Principal' per id, keeping the /last/ occurrence
-- and the original relative order. Without this a duplicated id would make
-- @decisions@ (which iterates the list) emit two rows while @decide@ resolves to
-- a single principal — the two views of the same dataset would disagree.
dedupPrincipals :: [Principal] -> [Principal]
dedupPrincipals =
  reverse . nubBy ((==) `on` principalId) . reverse

-- | Fail closed on a malformed policy: if any rule targets a resource absent
-- from the product tree, report it on stderr and exit non-zero rather than
-- silently evaluating a rule that can never match a real resource.
guardTargets :: ProductTree -> [Rule] -> IO ()
guardTargets tree rules =
  case unknownTargets tree rules of
    []  -> pure ()
    bad -> do
      hPutStrLn stderr
        ( "plm-access: policy targets resources absent from the tree: "
            <> intercalate ", " [T.unpack t | ResourceId t <- bad]
        )
      exitFailure

usageError :: IO ()
usageError = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " (decide|eval|diff|decisions) [FILE]")
  exitFailure
