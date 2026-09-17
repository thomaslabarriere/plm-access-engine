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
  , decideFor
  , resolvePrincipal
  , applies
  , permits
  ) where

import Data.List (maximumBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)

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

-- | How specifically a rule's target names a resource. Ordered least-to-most
-- specific: every resource ('SpecAll') < a subtree < an exact resource, and a
-- deeper subtree (more ancestors) beats a shallower one. The derived 'Ord' is
-- exactly this ranking.
data TargetSpec = SpecAll | SpecSubtree Int | SpecExact
  deriving (Eq, Ord)

-- | How specifically a rule's subject names a principal: a whole group is less
-- specific than the individual principal. Derived 'Ord': group < principal.
data SubjectSpec = SpecGroupSubject | SpecPrincipalSubject
  deriving (Eq, Ord)

-- | Ranking key for conflict resolution: the largest key wins under 'Ord'.
-- Priority dominates, then target specificity, then subject specificity, and
-- finally the effect. 'Effect' derives @Allow < Deny@, so at an otherwise
-- identical key a 'Deny' outranks an 'Allow' — deny-overrides falls out of the
-- ordering for free, with no special-casing.
type RuleKey = (Int, TargetSpec, SubjectSpec, Effect)

ruleKey :: ProductTree -> Rule -> RuleKey
ruleKey tree rule =
  ( rulePriority rule
  , targetSpec (ruleTarget rule)
  , subjectSpec (ruleSubject rule)
  , ruleEffect rule
  )
  where
    targetSpec (TResource _) = SpecExact
    targetSpec (TSubtree r)  = SpecSubtree (length (ancestors tree r))
    targetSpec TAll          = SpecAll
    subjectSpec (SubjPrincipal _) = SpecPrincipalSubject
    subjectSpec (SubjGroup _)     = SpecGroupSubject

decide :: ProductTree -> Principal -> ResourceId -> Permission -> [Rule] -> Decision
decide tree prin res requested rules =
  case filter (applies tree prin res requested) rules of
    [] -> Decision {granted = False, decidingRule = Nothing, applicable = []}
    applicableRules ->
      -- Decorate each rule with its key once (so 'ancestors' is not re-walked
      -- inside a fold), then take the maximum key: deny-overrides is baked into
      -- 'RuleKey' via 'Effect''s ordering.
      let winner = snd (maximumBy (comparing fst) [(ruleKey tree r, r) | r <- applicableRules])
      in Decision
           { granted = ruleEffect winner == Allow
           , decidingRule = Just (ruleId winner)
           , applicable = map ruleId applicableRules
           }

-- | Resolve a principal id against the roster, then 'decide'. This is the
-- shared entry point for every id-based caller (the CLI and 'PLM.Eval'): a
-- principal id absent from the roster fails /closed/ — a default-deny
-- 'Decision', never a fabricated empty principal (which would silently fail
-- /open/ on a principal-scoped @allow@ and skip group rules).
decideFor :: ProductTree -> [Principal] -> PrincipalId -> ResourceId -> Permission -> [Rule] -> Decision
decideFor tree principals pid res requested rules =
  case resolvePrincipal principals pid of
    Nothing   -> Decision {granted = False, decidingRule = Nothing, applicable = []}
    Just prin -> decide tree prin res requested rules

-- | Look up a principal in the roster by its id. The single source of truth for
-- id resolution, so the CLI and the reliability harness cannot disagree.
resolvePrincipal :: [Principal] -> PrincipalId -> Maybe Principal
resolvePrincipal principals pid =
  Map.lookup pid (Map.fromList [(principalId p, p) | p <- principals])
