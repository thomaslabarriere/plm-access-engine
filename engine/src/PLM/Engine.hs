-- | Evaluation of PLM access rules.
--
-- 'decide' is a pure, total function: given the product tree, a principal, a
-- resource, a requested permission and a rule set, it returns a 'Decision'.
-- The policy is /default-deny/, with conflicts resolved by, in order:
-- rule priority, then specificity (an exact resource beats a subtree; a deeper
-- subtree beats a shallower one; a principal beats a group), then
-- /deny-overrides/ at a genuine tie.
module PLM.Engine
  ( Decision (..)
  , decide
  , applies
  , permits
  ) where

import PLM.Types

-- | The outcome of an access request, with the deciding rule and the full set
-- of rules that applied (the \"why\", for an audit trail).
data Decision = Decision
  { granted      :: Bool
  , decidingRule :: Maybe RuleId
  , applicable   :: [RuleId]
  } deriving (Eq, Show)

-- | Does a rule's permission cover the requested one? 'Admin' subsumes all.
permits :: Permission -> Permission -> Bool
permits rulePerm requested = rulePerm == requested || rulePerm == Admin

-- | Does a rule apply to this (principal, resource, permission) request?
applies :: ProductTree -> Principal -> ResourceId -> Permission -> Rule -> Bool
applies tree prin res requested rule =
  subjectMatches (ruleSubject rule)
    && targetMatches (ruleTarget rule)
    && permits (rulePermission rule) requested
  where
    subjectMatches (SubjPrincipal pid) = pid == principalId prin
    subjectMatches (SubjGroup gid)     = gid `elem` principalGroups prin
    targetMatches (TResource r) = r == res
    targetMatches (TSubtree r)  = isDescendantOf tree res r
    targetMatches TAll          = True

-- | Ranking key for conflict resolution: higher wins.
-- (priority, target specificity, subject specificity).
type RuleKey = (Int, Int, Int)

ruleKey :: ProductTree -> Rule -> RuleKey
ruleKey tree rule =
  (rulePriority rule, targetSpecificity (ruleTarget rule), subjectSpecificity (ruleSubject rule))
  where
    -- An exact resource is the most specific; a deeper subtree root beats a
    -- shallower one; TAll is the least specific.
    targetSpecificity (TResource _) = maxBound
    targetSpecificity (TSubtree r)  = length (ancestors tree r)
    targetSpecificity TAll          = minBound
    subjectSpecificity (SubjPrincipal _) = 1
    subjectSpecificity (SubjGroup _)     = 0

-- | Pick the winner between the current best and a candidate. On a strictly
-- higher key the candidate wins; on a strictly lower one the best is kept; on
-- an exact tie a 'Deny' wins over an 'Allow' (deny-overrides).
pick :: ProductTree -> Rule -> Rule -> Rule
pick tree best cand =
  case compare (ruleKey tree cand) (ruleKey tree best) of
    GT -> cand
    LT -> best
    EQ -> if ruleEffect cand == Deny then cand else best

decide :: ProductTree -> Principal -> ResourceId -> Permission -> [Rule] -> Decision
decide tree prin res requested rules =
  case filter (applies tree prin res requested) rules of
    [] -> Decision {granted = False, decidingRule = Nothing, applicable = []}
    (r : rs) ->
      let winner = foldl (pick tree) r rs
      in Decision
           { granted = ruleEffect winner == Allow
           , decidingRule = Just (ruleId winner)
           , applicable = map ruleId (r : rs)
           }
