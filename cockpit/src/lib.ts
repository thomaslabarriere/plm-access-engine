import type { Decision, Decisions, Diff, NestedNode, Permission, TreeNode } from "./types";

/** Build the decision-map key for a (principal, resource, permission) triple. */
export function key(principal: string, resource: string, permission: string): string {
  return `${principal}|${resource}|${permission}`;
}

/** Pure lookup into the precomputed decision map. Returns null if absent. */
export function lookup(
  decisions: Decisions,
  principal: string,
  resource: string,
  permission: Permission
): Decision | null {
  return decisions[key(principal, resource, permission)] ?? null;
}

/**
 * Transform the flat parent-pointer list into a nested tree.
 * Root nodes are those with parent === null.
 */
export function buildTree(flat: TreeNode[]): NestedNode[] {
  const nodes = new Map<string, NestedNode>();
  for (const n of flat) {
    nodes.set(n.resource, { resource: n.resource, children: [] });
  }
  const roots: NestedNode[] = [];
  for (const n of flat) {
    const node = nodes.get(n.resource)!;
    if (n.parent === null) {
      roots.push(node);
    } else {
      const parent = nodes.get(n.parent);
      if (parent) parent.children.push(node);
      else roots.push(node);
    }
  }
  return roots;
}

/** Group diff entries by principal into a readable structure. */
export function groupDiffByPrincipal(
  diff: Diff
): { principal: string; grants: { resource: string; permission: string }[] }[] {
  const map = new Map<string, { resource: string; permission: string }[]>();
  for (const { principal, resource, permission } of diff) {
    const list = map.get(principal) ?? [];
    list.push({ resource, permission });
    map.set(principal, list);
  }
  return [...map.entries()].map(([principal, grants]) => ({ principal, grants }));
}

/** Human-readable one-line summary of the diff. */
export function formatDiff(diff: Diff): string {
  if (diff.length === 0) return "No newly granted access.";
  const cells = diff.map((e) => `${e.principal}→${e.resource} (${e.permission})`).join(", ");
  return `${diff.length} newly granted cell${diff.length === 1 ? "" : "s"}: ${cells}`;
}

/** Whether the diff touches a given resource id. */
export function diffIncludesResource(diff: Diff, resource: string): boolean {
  return diff.some((e) => e.resource === resource);
}

/** Human phrasing of a subject/target rule descriptor. */
export function describeSubject(kind: string, id?: string): string {
  if (kind === "all") return "everyone";
  return `${kind}:${id ?? "?"}`;
}

export function describeTarget(kind: string, id?: string): string {
  if (kind === "all") return "all resources";
  if (kind === "subtree") return `subtree(${id})`;
  return `${id}`;
}
