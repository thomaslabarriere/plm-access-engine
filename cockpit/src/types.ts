export type Permission = "read" | "write" | "delete" | "admin";
export type Effect = "allow" | "deny";

export interface TreeNode {
  resource: string;
  parent: string | null;
}

export interface Principal {
  id: string;
  groups: string[];
}

export interface RuleSubject {
  kind: "principal" | "group" | "all";
  id?: string;
}

export interface RuleTarget {
  kind: "resource" | "subtree" | "all";
  id?: string;
}

export interface Rule {
  id: string;
  subject: RuleSubject;
  target: RuleTarget;
  permission: Permission;
  effect: Effect;
  priority: number;
}

export interface GoldCase {
  principal: string;
  resource: string;
  permission: Permission;
  expected: boolean;
}

export interface Dataset {
  tree: TreeNode[];
  principals: Principal[];
  rules: Rule[];
  newRules: Rule[];
  gold: GoldCase[];
  resources: string[];
  permissions: Permission[];
}

export interface Decision {
  granted: boolean;
  decidingRule: string | null;
  applicable: string[];
}

export type Decisions = Record<string, Decision>;

export interface EvalResult {
  total: number;
  correct: number;
  accuracy: number;
  mismatches: GoldCase[];
}

/** Each entry is a [principalId, resourceId] pair newly granted WRITE. */
export type Diff = [string, string][];

/** Nested tree node built from the flat TreeNode list. */
export interface NestedNode {
  resource: string;
  children: NestedNode[];
}
