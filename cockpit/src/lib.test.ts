import { describe, it, expect } from "vitest";
import {
  key,
  lookup,
  buildTree,
  groupDiffByPrincipal,
  formatDiff,
  diffIncludesResource,
  describeSubject,
  describeTarget,
} from "./lib";
import type { Decisions, Diff, TreeNode } from "./types";

describe("key", () => {
  it("joins triple with pipes", () => {
    expect(key("bob", "cpu", "read")).toBe("bob|cpu|read");
  });
});

describe("lookup", () => {
  const decisions: Decisions = {
    "bob|cpu|read": { granted: false, decidingRule: "cpu-classified", applicable: ["contractor-read", "cpu-classified"] },
  };
  it("returns the decision for a present key", () => {
    expect(lookup(decisions, "bob", "cpu", "read")?.granted).toBe(false);
    expect(lookup(decisions, "bob", "cpu", "read")?.decidingRule).toBe("cpu-classified");
  });
  it("returns null for an absent key", () => {
    expect(lookup(decisions, "bob", "cpu", "write")).toBeNull();
  });
});

describe("buildTree", () => {
  const flat: TreeNode[] = [
    { resource: "sat", parent: null },
    { resource: "power", parent: "sat" },
    { resource: "avionics", parent: "sat" },
    { resource: "cpu", parent: "avionics" },
    { resource: "radio", parent: "avionics" },
  ];
  it("nests children under parents from a flat list", () => {
    const roots = buildTree(flat);
    expect(roots).toHaveLength(1);
    expect(roots[0].resource).toBe("sat");
    const childNames = roots[0].children.map((c) => c.resource).sort();
    expect(childNames).toEqual(["avionics", "power"]);
    const avionics = roots[0].children.find((c) => c.resource === "avionics")!;
    expect(avionics.children.map((c) => c.resource).sort()).toEqual(["cpu", "radio"]);
  });
  it("handles empty input", () => {
    expect(buildTree([])).toEqual([]);
  });
});

describe("groupDiffByPrincipal", () => {
  it("groups grants under each principal", () => {
    const diff: Diff = [
      { principal: "bob", resource: "sat", permission: "write" },
      { principal: "bob", resource: "cpu", permission: "write" },
      { principal: "ann", resource: "radio", permission: "read" },
    ];
    const grouped = groupDiffByPrincipal(diff);
    expect(grouped).toEqual([
      {
        principal: "bob",
        grants: [
          { resource: "sat", permission: "write" },
          { resource: "cpu", permission: "write" },
        ],
      },
      { principal: "ann", grants: [{ resource: "radio", permission: "read" }] },
    ]);
  });
});

describe("formatDiff", () => {
  it("summarises multiple cells", () => {
    const diff: Diff = [
      { principal: "bob", resource: "sat", permission: "write" },
      { principal: "bob", resource: "cpu", permission: "write" },
    ];
    expect(formatDiff(diff)).toBe(
      "2 newly granted cells: bob→sat (write), bob→cpu (write)"
    );
  });
  it("handles empty diff", () => {
    expect(formatDiff([])).toBe("No newly granted access.");
  });
  it("uses singular for one grant", () => {
    expect(formatDiff([{ principal: "bob", resource: "cpu", permission: "write" }])).toBe(
      "1 newly granted cell: bob→cpu (write)"
    );
  });
});

describe("diffIncludesResource", () => {
  const diff: Diff = [
    { principal: "bob", resource: "sat", permission: "write" },
    { principal: "bob", resource: "cpu", permission: "write" },
  ];
  it("detects a present resource", () => {
    expect(diffIncludesResource(diff, "cpu")).toBe(true);
  });
  it("detects an absent resource", () => {
    expect(diffIncludesResource(diff, "radio")).toBe(false);
  });
});

describe("describeSubject / describeTarget", () => {
  it("describes subjects", () => {
    expect(describeSubject("group", "eng")).toBe("group:eng");
    expect(describeSubject("all")).toBe("everyone");
  });
  it("describes targets", () => {
    expect(describeTarget("all")).toBe("all resources");
    expect(describeTarget("subtree", "sat")).toBe("subtree(sat)");
    expect(describeTarget("resource", "cpu")).toBe("cpu");
  });
});
