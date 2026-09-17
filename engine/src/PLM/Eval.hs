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
    -- Route through the shared resolver so an unknown principal fails closed
    -- exactly as it does at the CLI, never as a crash.
    actual gc =
      granted (decideFor tree principals (gcPrincipal gc) (gcResource gc) (gcPermission gc) rules)

    mismatches = [gc | gc <- gold, actual gc /= gcExpected gc]
    total      = length gold
    correct    = total - length mismatches

-- | Every (principal, resource, permission) that was denied under @oldRules@
-- but is granted under @newRules@ — the access a rule change silently widened.
-- An empty result means the change granted nothing new.
--
-- The scan is /complete/ by construction: it never trusts a caller-supplied
-- shortlist. The resource universe is the whole product tree ('treeResources'),
-- the principals are the roster, and every permission is checked
-- (@[minBound .. maxBound]@). Each entry carries the permission it widened, so a
-- reviewer sees exactly which right leaked, on which resource, for whom.
newlyGranted
  :: ProductTree
  -> [Principal]
  -> [Rule]      -- ^ old rule set
  -> [Rule]      -- ^ new rule set
  -> [(PrincipalId, ResourceId, Permission)]
newlyGranted tree principals oldRules newRules =
  [ (principalId prin, res, perm)
  | prin <- principals
  , res  <- treeResources tree
  , perm <- [minBound .. maxBound]
  , not (granted (decide tree prin res perm oldRules))
  , granted (decide tree prin res perm newRules)
  ]
