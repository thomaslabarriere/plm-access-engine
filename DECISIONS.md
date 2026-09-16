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

`decide` returns deny unless a rule grants, and conflicts resolve by, in order: rule
priority, then specificity (an exact resource beats a subtree; a deeper subtree beats a
shallower one; a principal beats a group), then **deny-overrides** at a true tie.

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

## 6. A simulated store, not Postgres (yet)

Rules and the tree live in memory / JSON. Aletiq uses PostgreSQL; the pure core is written
so a Postgres adapter slots in behind it without touching `decide`.

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

## 8. The tests are mutation-checked

A green suite means something only if it fails when the code breaks. Proof: flipping the
deny-overrides tie-breaker in `PLM.Engine.pick` (preferring the allow on an equal key)
makes the "deny overrides allow at an identical key" spec fail; reverting restores green.
The property is guarding the invariant, not padding a number.
