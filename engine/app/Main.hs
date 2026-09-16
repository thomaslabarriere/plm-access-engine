{-# LANGUAGE OverloadedStrings #-}

-- | @plm-access@: a thin JSON front-end to the access engine, for the React
-- cockpit. Each subcommand reads one JSON envelope (from a file argument, or
-- stdin) and prints exactly one JSON object to stdout; anything diagnostic
-- goes to stderr, so stdout is always clean, parseable JSON.
--
-- > plm-access decide  < envelope.json   -> Decision
-- > plm-access eval    < envelope.json   -> EvalReport
-- > plm-access diff    < envelope.json   -> [[principal, resource]]
module Main (main) where

import Data.Aeson (FromJSON (..), eitherDecode, encode, withObject, (.:))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import PLM.Engine (decide)
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

data DiffInput = DiffInput ProductTree [Principal] Permission [ResourceId] [Rule] [Rule]

instance FromJSON DiffInput where
  parseJSON = withObject "diff input" $ \o ->
    DiffInput
      <$> o .: "tree"
      <*> o .: "principals"
      <*> o .: "permission"
      <*> o .: "resources"
      <*> o .: "oldRules"
      <*> o .: "newRules"

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
    "decide" -> withDecoded raw runDecide
    "eval"   -> withDecoded raw runEval
    "diff"   -> withDecoded raw runDiff
    _        -> usageError

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

runDecide :: DecideInput -> IO ()
runDecide (DecideInput tree rules principals (Request pid res perm)) =
  emit (encode (decide tree prin res perm rules))
  where
    prin = case Map.lookup pid byId of
      Just p  -> p
      Nothing -> Principal pid Set.empty
    byId = Map.fromList [(principalId p, p) | p <- principals]

runEval :: EvalInput -> IO ()
runEval (EvalInput tree rules principals gold) =
  emit (encode (evaluate tree rules principals gold))

runDiff :: DiffInput -> IO ()
runDiff (DiffInput tree principals perm resources oldRules newRules) =
  emit (encode (map pair (newlyGranted tree principals perm resources oldRules newRules)))
  where
    pair (PrincipalId p, ResourceId r) = [p, r]

usageError :: IO ()
usageError = do
  name <- getProgName
  hPutStrLn stderr ("usage: " <> name <> " (decide|eval|diff) [FILE]")
  exitFailure
