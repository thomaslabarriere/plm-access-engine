{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A dependency-free latency benchmark for 'decide'.
--
-- Criterion resolves on GHC 9.14 but drags in a heavy statistics stack; to keep
-- the build robust we measure with 'getMonotonicTime' from @base@ instead. A
-- workload of 500 rules over a 1000-node product tree is evaluated for every
-- resource, and the mean per-decision latency is printed.
module Main (main) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import GHC.Clock (getMonotonicTime)
import Text.Printf (printf)

import PLM.Engine (decide, granted)
import PLM.Types

nNodes :: Int
nNodes = 1000

nRules :: Int
nRules = 500

resourceAt :: Int -> ResourceId
resourceAt i = ResourceId (T.pack ('n' : show i))

-- A near-balanced binary tree: node i's parent is node (i-1) `div` 2.
workloadTree :: ProductTree
workloadTree = ProductTree (Map.fromList (root : rest))
  where
    root = (resourceAt 0, Nothing)
    rest = [(resourceAt i, Just (resourceAt ((i - 1) `div` 2))) | i <- [1 .. nNodes - 1]]

workloadRules :: [Rule]
workloadRules =
  [ Rule
      { ruleId         = RuleId (T.pack ('r' : show i))
      , ruleSubject    = SubjGroup (GroupId "engineers")
      , ruleTarget     = TSubtree (resourceAt (i `mod` nNodes))
      , rulePermission = Read
      , ruleEffect     = if even i then Allow else Deny
      , rulePriority   = i `mod` 8
      }
  | i <- [0 .. nRules - 1]
  ]

engineer :: Principal
engineer = Principal (PrincipalId "p1") (Set.fromList [GroupId "engineers"])

-- | Count how many of the resources the engineer is granted @Read@ on.
-- Strict, so evaluating the result forces the whole workload.
countGrants :: [ResourceId] -> Int
countGrants =
  foldl'
    (\ !acc res ->
       if granted (decide workloadTree engineer res Read workloadRules)
         then acc + 1
         else acc)
    0

main :: IO ()
main = do
  let resources = map resourceAt [0 .. nNodes - 1]
      count     = length resources
  -- Warm up (force thunks / caches) then measure a second, timed pass.
  let !warm = countGrants resources
  start <- warm `seq` getMonotonicTime
  let !grants = countGrants resources
  end <- grants `seq` getMonotonicTime
  let meanUs = (end - start) / fromIntegral count * 1e6
  printf "workload: %d rules x %d resources (tree of %d nodes)\n" nRules count nNodes
  printf "grants:   %d / %d\n" grants count
  printf "total:    %.3f ms\n" ((end - start) * 1000)
  printf "mean:     %.2f us / decision\n" meanUs
