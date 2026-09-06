# Agent turn-budget pattern (the *why*, once)

Every agent in `agents/*.md` declares two different numbers. They are not
interchangeable, and mixing them up reintroduces the exact silent-failure
class this toolkit exists to prevent.

- **The prose budget** (stated in the agent's own `## Budget / escalation`
  section as `**Turn budget: N` or, for the healer, `**Hard budget: N turns`)
  is the agent's own fail-safe. Hitting it ends in a *behavior*: the healer
  files a bug and reverts its patch, the reviewer emits a `PARTIAL REVIEW` +
  `FAIL (inconclusive-partial)` verdict, exploration/ideation write what they
  have under an incompleteness banner. This is the number that actually
  protects the pipeline.
- **`maxTurns`** (frontmatter) is a **harness hard-stop**, not a budget. It
  returns PARTIAL output and runs **none** of the agent's own fallback. It
  exists only to bound a genuine runaway.

**The invariant: `maxTurns` MUST sit strictly above the prose budget** — with
a few turns of headroom, not the bare minimum. If `maxTurns` is pinned at or
below the prose number, the harness hard-stop preempts the agent's own
fail-safe: a healer stopped by `maxTurns` before it reaches its "file a bug
and revert" step ships a half-applied patch and no bug — worse than either
number alone. `doctor` Check 9bc enforces this ordering by reading both
numbers directly out of each agent file, so **the numbers in each file's own
`## Budget / escalation` section (and its `maxTurns:` frontmatter line) are
the source of truth Check 9bc parses — never move those numbers here.**

Per-agent specifics — why each agent's gap is what it is — stay in that
agent's own file, since they depend on what that agent's fallback actually
does (e.g. reviewer's whole-tree fallback is a full alternate execution mode
designed to exceed its budget, so it carries the widest gap; healer's
`HEALER_TURN_BUDGET` env var can raise its prose budget at runtime, so its
`maxTurns` reserves headroom for that too). See `reference/DESIGN.md`
§"Turn budgets are a fail-safe" for the cross-agent rationale and the full
table of current numbers.
