-- | Core domain for a PLM access engine.
--
-- Everything here is data: identifiers, the product tree, and the access
-- rules. The evaluation lives in "PLM.Engine". Modelling the domain with sum
-- types and no partial functions is what lets the engine be total and the
-- properties in the test-suite be meaningful.
module PLM.Types
  ( PrincipalId (..)
  , GroupId (..)
  , ResourceId (..)
  , Permission (..)
  , Effect (..)
  , Subject (..)
  , Target (..)
  , Rule (..)
  , RuleId (..)
  , Principal (..)
  , ProductTree (..)
  , emptyTree
  , ancestors
  , isDescendantOf
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import Data.Text (Text)

newtype PrincipalId = PrincipalId Text deriving (Eq, Ord, Show)
newtype GroupId = GroupId Text deriving (Eq, Ord, Show)
newtype ResourceId = ResourceId Text deriving (Eq, Ord, Show)
newtype RuleId = RuleId Text deriving (Eq, Ord, Show)

-- | The access rights a rule can speak about. 'Admin' subsumes the others
-- (see 'PLM.Engine.permits').
data Permission = Read | Write | Delete | Admin
  deriving (Eq, Ord, Show, Enum, Bounded)

data Effect = Allow | Deny
  deriving (Eq, Ord, Show)

-- | Who a rule is about: a single principal or a whole group.
data Subject
  = SubjPrincipal PrincipalId
  | SubjGroup GroupId
  deriving (Eq, Ord, Show)

-- | What a rule covers: one resource, a resource and everything beneath it in
-- the product tree, or every resource.
data Target
  = TResource ResourceId
  | TSubtree ResourceId
  | TAll
  deriving (Eq, Ord, Show)

data Rule = Rule
  { ruleId     :: RuleId
  , ruleSubject    :: Subject
  , ruleTarget     :: Target
  , rulePermission :: Permission
  , ruleEffect     :: Effect
  , rulePriority   :: Int
  } deriving (Eq, Ord, Show)

-- | A principal and the groups it belongs to.
data Principal = Principal
  { principalId :: PrincipalId
  , principalGroups :: Set GroupId
  } deriving (Eq, Ord, Show)

-- | The product hierarchy as a child -> parent map (a forest; roots map to
-- 'Nothing'). Kept as a newtype so the invariants live behind smart helpers.
newtype ProductTree = ProductTree (Map ResourceId (Maybe ResourceId))
  deriving (Eq, Show)

emptyTree :: ProductTree
emptyTree = ProductTree Map.empty

-- | The ancestors of a resource, nearest first, excluding the resource itself.
-- Cycles or unknown parents terminate the walk safely (total function).
ancestors :: ProductTree -> ResourceId -> [ResourceId]
ancestors (ProductTree parents) = go []
  where
    go seen rid =
      case Map.lookup rid parents of
        Just (Just parent)
          | parent `notElem` seen -> parent : go (rid : seen) parent
        _ -> []

-- | Is @child@ equal to or beneath @ancestor@ in the tree?
isDescendantOf :: ProductTree -> ResourceId -> ResourceId -> Bool
isDescendantOf tree child ancestor =
  child == ancestor || ancestor `elem` ancestors tree child
