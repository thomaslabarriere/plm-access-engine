# Design decisions

The point of this repo is judgment. Here is the reasoning, the alternatives rejected, and
what it does not prove.

## 1. Haskell, because they build in Haskell, and because the domain suits it

Aletiq's backend is Haskell, so the core is Haskell. It also happens to be the right tool:
the domain is naturally a set of sum types (subjects, targets, effects), the engine is a
pure total function, and the guarantees are exactly the kind of thing property-based
testing proves. **I am upfront that this is my first substantial Haskell project** (see
§7). What is here is idiomatic: newtypes over stringly-typed ids, total functions (no
`head`/`fromJust`, a cycle-guarded `ancestors`), `-Wall` and `hlint` clean.

## 2. The verdict is default-deny, and conflicts resolve deterministically

`decide` returns deny unless a rule grants, and conflicts resolve by comparing a ranking
key `(priority, target-specificity, subject-specificity, effect, ruleId)`, in that order:
rule priority first; then **target** specificity (an exact resource beats a subtree, a
deeper subtree beats a shallower one) which outranks **subject** specificity (a principal
beats a group); then **deny-overrides** at an otherwise-true tie (`Deny > Allow`); then
`ruleId` purely so the reported deciding rule is deterministic (never affects `granted`).

- **Why target before subject:** a rule written about one specific artifact is a more
  deliberate statement than a rule written about a person, so it wins. This precedence is
  a decision, not an accident of tuple order.

- **Why default-deny:** for a system holding aerospace/nuclear IP, the safe default when
  the policy is silent is "no". Granting-by-omission is the failure that leaks IP.
- **Why this order:** priority lets an explicit exception win; specificity makes a rule
  about one part beat a rule about the whole tree; deny-overrides is the last-resort tie
  breaker that fails closed.

## 3. Guarantees as properties, not prose

The invariants (default-deny, deny-overrides, "adding a deny never grants",
order-independence of the decision) are QuickCheck properties over generated rule sets.

- **Why:** these are the promises an access engine lives or dies by; a comment claiming
  them is worthless, a property that survives hundreds of adversarial rule sets is
  evidence. Order-independence in particular is non-obvious and worth pinning.

## 4. The harness measures over-permission, from state

`evaluate` scores the engine against a gold set (the policy's intended spec). `newlyGranted`
takes an old and a new rule set and returns every (principal, resource) that flips from
denied to granted, a rule change silently widening access.

- **Why:** accuracy against a spec is table stakes; the failure that actually costs you is
  a well-meaning rule change that widens access without anyone noticing. That is the check
  that would run in CI on every policy change.

## 5. Two processes, one JSON contract

The React cockpit does not import or re-implement the engine; the Haskell CLI computes
decisions/eval/diff and emits JSON, and the cockpit renders it.

- **Why:** the engine must be the single source of truth for a decision. Re-implementing
  the logic in TypeScript to make a prettier UI would be the exact drift this design
  refuses. The cockpit's decision explorer is a pure key lookup into precomputed output.
- **Enforced, not asserted:** `scripts/regen-cockpit-data.sh` pipes the single
  `dataset.json` through the engine (`decisions`/`eval`/`diff`) to produce all three
  cockpit data files, and CI runs it and `git diff --exit-code`s the result. So the
  committed data cannot drift from what the engine actually decides: if it did, CI fails.
  The claim above is a build gate, not a promise.

## 6. Fail closed, everywhere, through one resolver

An access request naming a principal absent from the roster is default-denied, not
fabricated into a group-less principal. `resolvePrincipal`/`decideFor` are the single
path the CLI and the eval harness both use, so `decide`, `evaluate` and `diff` cannot
disagree about an unknown id.

- **Why:** the earlier version fabricated `Principal id mempty` on a miss, which failed
  *open* (a principal-scoped allow still fired, group denies were skipped) — the exact
  over-permission this engine exists to stop, and it disagreed with the eval harness.
  Now a missing principal is a first-class deny, property-tested.

## 7. `newlyGranted` derives its own universe

The widening check does not trust caller-supplied resource/permission lists: it takes the
resources from the tree and iterates every permission, so a widening onto a resource or
permission a caller forgot to enumerate cannot slip past.

## 8. A simulated store, not Postgres (yet)

Rules and the tree live in memory / JSON. Aletiq uses PostgreSQL; the pure core is written
so a Postgres adapter slots in behind it without touching `decide`.

## 9. Scaling to millions of records (design sketch, not built)

Today `decide` is `O(rules × tree-depth)` per query and recomputes each rule's key on
every call — fine at the demo's 500 rules × 1000 nodes (~298 µs), not at Aletiq's stated
"hundreds of rules over millions of records". The shape that scales, behind the same pure
interface: index rules by their subtree root so a query only considers rules whose target
covers the resource's ancestor path; precompute each resource's ancestor set once
(`Map ResourceId (Set ResourceId)`); memoize rule ranking keys; and push the whole
evaluation into the PostgreSQL adapter as an indexed query for the hot path, keeping the
in-memory engine as the reference oracle the eval harness checks against. None of this is
implemented here; the point is that the domain model does not have to change to get there.

## A footgun worth stating: priority outranks specificity

Conflict resolution ranks priority first, then specificity, then deny-overrides. So a
broad high-priority `allow` beats a narrow low-priority classified `deny` — by design
("priority lets an explicit exception win"), but it means a classified deny must be pinned
in the top priority band, or the model must be changed to let deny win across priority
tiers. A real deployment should lint for classified denies that a higher-priority allow
can punch through.

## 7. What this does NOT prove

- It is my first substantial Haskell project. The core is idiomatic and property-tested,
  but a Haskell veteran would refactor things I have not seen yet.
- It is not a real PLM: no 3D/CAD viewer (Aletiq's other hard problem), no real-time
  collaboration, no persistence layer wired up.
- The benchmark is a single-process `getMonotonicTime` harness, not `criterion` with
  confidence intervals (criterion resolves on GHC 9.14 but drags in a heavy stack; the
  lightweight timer keeps the build lean). The number is indicative, not rigorous.
- The product tree and rule sets are demonstration-sized.

I would rather state these than have a reviewer find them.

## 10. The tests are mutation-checked

A green suite means something only if it fails when the code breaks. Proof: flipping
`Effect`'s ordering in `PLM.Types` (`data Effect = Allow | Deny` → `Deny | Allow`), which
removes deny-overrides from the ranking key, reddens exactly the two specs that guard it
("deny overrides allow at an identical key" and the generated-tree property "at an equal
key a deny always beats an allow"); reverting restores green. The properties guard the
invariant, not a coverage number.
