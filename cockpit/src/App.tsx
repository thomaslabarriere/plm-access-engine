import { useMemo, useState } from "react";
import datasetJson from "./data/dataset.json";
import decisionsJson from "./data/decisions.json";
import evalJson from "./data/eval.json";
import diffJson from "./data/diff.json";
import type {
  Dataset,
  Decisions,
  Diff,
  EvalResult,
  NestedNode,
  Permission,
  Rule,
} from "./types";
import {
  buildTree,
  describeSubject,
  describeTarget,
  diffIncludesResource,
  groupDiffByPrincipal,
  lookup,
} from "./lib";

const dataset = datasetJson as Dataset;
const decisions = decisionsJson as Decisions;
const evalResult = evalJson as EvalResult;
const diff = diffJson as Diff;

const CLASSIFIED_RESOURCE = "cpu";

function TreeView({ nodes }: { nodes: NestedNode[] }) {
  return (
    <ul>
      {nodes.map((n) => (
        <li key={n.resource}>
          <span className={"node" + (n.resource === CLASSIFIED_RESOURCE ? " classified" : "")}>
            {n.resource}
            {n.resource === CLASSIFIED_RESOURCE ? " • classified" : ""}
          </span>
          {n.children.length > 0 && <TreeView nodes={n.children} />}
        </li>
      ))}
    </ul>
  );
}

function RuleRows({ rules }: { rules: Rule[] }) {
  return (
    <>
      {rules.map((r) => (
        <tr key={r.id}>
          <td className="mono">{r.id}</td>
          <td className="mono">{describeSubject(r.subject.kind, r.subject.id)}</td>
          <td className="mono">{describeTarget(r.target.kind, r.target.id)}</td>
          <td className="mono">{r.permission}</td>
          <td className={r.effect === "allow" ? "eff-allow" : "eff-deny"}>{r.effect}</td>
          <td className="mono">{r.priority}</td>
        </tr>
      ))}
    </>
  );
}

export default function App() {
  const tree = useMemo(() => buildTree(dataset.tree), []);
  const grouped = useMemo(() => groupDiffByPrincipal(diff), []);

  const [principal, setPrincipal] = useState("bob");
  const [resource, setResource] = useState("cpu");
  const [permission, setPermission] = useState<Permission>("read");

  const decision = lookup(decisions, principal, resource, permission);
  const cpuInDiff = diffIncludesResource(diff, CLASSIFIED_RESOURCE);

  return (
    <div className="app">
      <div className="masthead">
        <div>
          <h1>PLM Access Engine — Cockpit</h1>
          <div className="sub">
            Viewer over precomputed Haskell engine output. No access logic runs in this client.
          </div>
        </div>
        <div className="bench">
          benchmark: ~298 &micro;s / decision &middot; 500 rules &times; 1000 resources
        </div>
      </div>

      <div className="grid">
        {/* Decision explorer — centerpiece */}
        <section className="panel span-2">
          <h2>Decision explorer</h2>
          <div className="selectors">
            <label>
              Principal
              <select value={principal} onChange={(e) => setPrincipal(e.target.value)}>
                {dataset.principals.map((p) => (
                  <option key={p.id} value={p.id}>{p.id}</option>
                ))}
              </select>
            </label>
            <label>
              Resource
              <select value={resource} onChange={(e) => setResource(e.target.value)}>
                {dataset.resources.map((r) => (
                  <option key={r} value={r}>{r}</option>
                ))}
              </select>
            </label>
            <label>
              Permission
              <select
                value={permission}
                onChange={(e) => setPermission(e.target.value as Permission)}
              >
                {dataset.permissions.map((p) => (
                  <option key={p} value={p}>{p}</option>
                ))}
              </select>
            </label>
          </div>

          {decision ? (
            <>
              <div className="verdict">
                <span className={"badge " + (decision.granted ? "granted" : "denied")}>
                  {decision.granted ? "GRANTED" : "DENIED"}
                </span>
                <span className="deciding">
                  deciding rule:{" "}
                  {decision.decidingRule ? <b>{decision.decidingRule}</b> : <i>none (default deny)</i>}
                </span>
              </div>
              <div className="deciding" style={{ marginBottom: 6 }}>
                Applicable rules ("why"):
              </div>
              {decision.applicable.length === 0 ? (
                <p className="empty">No rules applied — default deny.</p>
              ) : (
                <ul className="trace">
                  {decision.applicable.map((rid) => (
                    <li key={rid} className={rid === decision.decidingRule ? "is-deciding" : ""}>
                      {rid === decision.decidingRule && <span className="marker">&rarr; </span>}
                      {rid}
                      {rid === decision.decidingRule ? "  (deciding)" : ""}
                    </li>
                  ))}
                </ul>
              )}
            </>
          ) : (
            <p className="empty">No precomputed decision for this combination.</p>
          )}
        </section>

        {/* Product tree */}
        <section className="panel tree">
          <h2>Product tree</h2>
          <TreeView nodes={tree} />
        </section>

        {/* Reliability */}
        <section className="panel">
          <h2>Reliability — policy meets spec</h2>
          <div className="acc">
            <span className="big">
              {evalResult.correct}/{evalResult.total}
            </span>
            <span className={"big " + (evalResult.accuracy === 1 ? "pass" : "")}>
              {Math.round(evalResult.accuracy * 100)}%
            </span>
          </div>
          <div className="spec-note">
            {evalResult.mismatches.length === 0
              ? "All gold cases pass — the policy behaves exactly as its intended spec requires."
              : `${evalResult.mismatches.length} mismatch(es) vs the intended spec:`}
          </div>
          {evalResult.mismatches.length > 0 && (
            <table style={{ marginTop: 8 }}>
              <thead>
                <tr>
                  <th>principal</th><th>resource</th><th>perm</th><th>expected</th>
                </tr>
              </thead>
              <tbody>
                {evalResult.mismatches.map((m, i) => (
                  <tr key={i}>
                    <td className="mono">{m.principal}</td>
                    <td className="mono">{m.resource}</td>
                    <td className="mono">{m.permission}</td>
                    <td className="mono">{String(m.expected)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>

        {/* Principals & rules */}
        <section className="panel span-2">
          <h2>Principals &amp; active rules</h2>
          <div style={{ marginBottom: 10 }}>
            {dataset.principals.map((p) => (
              <span key={p.id} style={{ marginRight: 16 }}>
                <b className="mono">{p.id}</b>{" "}
                {p.groups.map((g) => (
                  <span key={g} className="tag">{g}</span>
                ))}
              </span>
            ))}
          </div>
          <table>
            <thead>
              <tr>
                <th>rule id</th><th>subject</th><th>target</th>
                <th>permission</th><th>effect</th><th>priority</th>
              </tr>
            </thead>
            <tbody>
              <RuleRows rules={dataset.rules} />
            </tbody>
          </table>
        </section>

        {/* Unintended-grant alert — money panel */}
        <section className="panel alert span-2">
          <h2>&#9888; Unintended-grant alert</h2>
          <p className="lead">
            A proposed rule change silently widened access — the eval harness flagged it before it shipped.
          </p>
          <div className="deciding" style={{ marginBottom: 4 }}>
            Proposed rule <code>contractor-write-NEW</code> (allow WRITE on subtree(sat)) newly grants
            WRITE to {diff.length} (principal, resource) pair{diff.length === 1 ? "" : "s"}:
          </div>
          {grouped.map((g) => (
            <div key={g.principal} style={{ margin: "6px 0" }}>
              <b className="mono">{g.principal}</b>
              <span className="pairs" style={{ display: "inline-flex", marginLeft: 8 }}>
                {g.resources.map((r) => (
                  <span key={r} className={"pair" + (r === CLASSIFIED_RESOURCE ? " cpu" : "")}>
                    {r}
                    {r === CLASSIFIED_RESOURCE ? " • classified" : ""}
                  </span>
                ))}
              </span>
            </div>
          ))}
          {cpuInDiff && (
            <p className="caught">
              &#9888; This widening includes <code>cpu</code>, the classified resource that
              <code> cpu-classified</code> was written to protect. An over-broad rule punched through
              a security boundary — caught by the harness, not in production.
            </p>
          )}
        </section>
      </div>
    </div>
  );
}
