-- | A reliability harness for the access engine.
--
-- Two pure, total facilities sit on top of 'decide':
--
--   * 'evaluate' scores a rule set against a labelled gold set and reports
--     accuracy plus the exact cases that were misclassified.
--   * 'newlyGranted' is the headline safety check: it diffs an old and a new
--     rule set and returns every (principal, resource) whose access silently
--     /widened/. In PLM a silent widening is an IP-leak risk, so a change that
--     grows this set is exactly what a reviewer must see.
module PLM.Eval
  ( GoldCase (..)
  , EvalReport (..)
  , evaluate
  , newlyGranted
  ) where

import qualified Data.Map.Strict as Map

import PLM.Engine
import PLM.Types

-- | A labelled expectation: the ground-truth answer to one access request.
data GoldCase = GoldCase
  { gcPrincipal  :: PrincipalId
  , gcResource   :: ResourceId
  , gcPermission :: Permission
  , gcExpected   :: Bool
  } deriving (Eq, Show)

-- | The outcome of scoring a rule set against a gold set.
data EvalReport = EvalReport
  { erTotal      :: Int
  , erCorrect    :: Int
  , erAccuracy   :: Double
  , erMismatches :: [GoldCase]
  } deriving (Eq, Show)

-- | Score @rules@ against a gold set. For each case the principal is looked up
-- by id and 'decide' is run; the @granted@ result is compared to the expected
-- label. A gold case naming a principal that is not present is treated as a
-- denial (and so counts as a mismatch whenever it was expected to be granted),
-- never as a crash.
evaluate :: ProductTree -> [Rule] -> [Principal] -> [GoldCase] -> EvalReport
evaluate tree rules principals gold =
  EvalReport
    { erTotal      = total
    , erCorrect    = correct
    , erAccuracy   = if total == 0 then 1 else fromIntegral correct / fromIntegral total
    , erMismatches = mismatches
    }
  where
    byId = Map.fromList [(principalId p, p) | p <- principals]

    actual gc =
      case Map.lookup (gcPrincipal gc) byId of
        Nothing  -> False
        Just prin -> granted (decide tree prin (gcResource gc) (gcPermission gc) rules)

    mismatches = [gc | gc <- gold, actual gc /= gcExpected gc]
    total      = length gold
    correct    = total - length mismatches

-- | Every (principal, resource) that was denied @perm@ under @oldRules@ but is
-- granted it under @newRules@ — the access that a rule change silently widened.
-- An empty result means the change granted nothing new.
newlyGranted
  :: ProductTree
  -> [Principal]
  -> Permission
  -> [ResourceId]
  -> [Rule]      -- ^ old rule set
  -> [Rule]      -- ^ new rule set
  -> [(PrincipalId, ResourceId)]
newlyGranted tree principals perm resources oldRules newRules =
  [ (principalId prin, res)
  | prin <- principals
  , res  <- resources
  , not (granted (decide tree prin res perm oldRules))
  , granted (decide tree prin res perm newRules)
  ]
