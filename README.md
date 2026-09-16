# plm-access-engine

A rule-based **access engine for PLM product trees**, written in **Haskell**, with a
**reliability harness** and a **React cockpit**. It mirrors the hardest problem in
Aletiq's own product: *calculating an access right from hundreds of rules over a deep
product hierarchy, at speed, without ever silently granting more than intended.*

- **`engine/`** (Haskell): a pure, total `decide` function over a product tree, with
  hierarchical inheritance and conflict resolution (priority, then specificity, then
  deny-overrides), plus an evaluation harness and a JSON CLI. The invariants are
  **property-tested** with QuickCheck.
- **`cockpit/`** (React + TypeScript): a viewer of the engine's output. It runs **no
  decision logic**; it reads precomputed JSON from the CLI and shows the product tree, a
  decision explorer with the "why" trace, the reliability report, and the unintended-grant
  alert.

## Why this shape

The verdict an access system gives is only worth what its *worst* silent failure costs.
For a PLM holding aerospace and nuclear IP, that failure is **over-permission**: a rule
change that quietly widens access. So the engine is `default-deny` and total, its
guarantees are stated as machine-checked properties, and the harness's headline check is
"did a rule change newly grant access it shouldn't?"

## The money shot: a widening caught before it ships

A proposed rule change (`contractor-write-NEW`) looks harmless. The harness's `diff` shows
it silently grants **write** to a contractor across the whole satellite tree, **including
the classified `cpu`**:

```
$ plm-access diff  < change.json
[["bob","sat"],["bob","power"],["bob","avionics"],["bob","cpu"],["bob","radio"]]
```

That is the exact IP-leak an access engine must never wave through, surfaced from the
engine's own decisions, not from anyone's assertion that the change was "safe."

## Correctness stated as properties

The engine's guarantees are QuickCheck properties (100s of generated rule sets each), not
prose (`engine/test/PLM/EngineSpec.hs`):

- **default-deny**: no rule means no access.
- **deny-overrides**: at an equal priority and specificity, a deny beats an allow.
- **adding a deny can never turn a denial into a grant**.
- **the decision is independent of rule order**.

Plus examples: higher priority wins, an exact-resource deny beats a broad subtree allow, a
subtree allow reaches descendants, `Admin` subsumes every permission.

## Quickstart

```bash
# Engine (Haskell): build, property tests, hlint
cd engine && cabal build all && cabal test && hlint src test app

# The CLI speaks JSON (decide / eval / diff)
echo '{"tree":[...],"rules":[...],"principals":[...],"request":{...}}' | cabal run plm-access -- decide

# Cockpit (React): a live view of the engine's output
cd ../cockpit && npm install && npm run dev

# One reproducible toolchain (Aletiq runs on NixOS)
nix develop      # ghc + cabal + hlint + node
```

## Performance

The engine evaluates **500 rules over a 1000-node product tree at ~298 µs per decision**
(`engine/bench/Bench.hs`, a `getMonotonicTime` harness, no heavy deps). Their stated
challenge is keeping this fast at scale; the pure core makes the cost measurable.

## Layout

```
engine/                     # Haskell
  src/PLM/Types.hs          # domain: principals, groups, product tree, rules
  src/PLM/Engine.hs         # decide: hierarchy + conflict resolution (pure, total)
  src/PLM/Eval.hs           # gold-set accuracy + newlyGranted (the widening check)
  src/PLM/Json.hs           # aeson wire format
  app/Main.hs               # plm-access CLI: decide / eval / diff (JSON in, JSON out)
  test/                     # QuickCheck properties + hspec examples
  bench/                    # latency benchmark
cockpit/                    # React + TypeScript viewer of the CLI's JSON output
```

The two sides meet only through the JSON envelopes the CLI reads and writes; the cockpit
never imports the engine.

See [DECISIONS.md](DECISIONS.md) for the trade-offs and what this does **not** prove
(including, honestly, that this is my first substantial Haskell project).
