<!--
TEST BASIS template — written by /qa:intake, structured as an Example Map (Wynne).
This captures the *understanding* of a feature, NOT test cases. /qa:ideate reads it.
🟡 story · 🔵 rules = THE ORACLE ("what correct means") · 🟢 examples = case seeds ·
🔴 open questions (blocking ones gate /qa:ideate).
Keep it tight; the oracle (rules) is the one mandatory section. Delete this comment.
-->

# basis: <area>/<feature>

```yaml
feature: <area>/<feature>
kind: feature                 # feature | enhancement | bug | refactor | characterization  (exploratory is roadmap — see reference/test-case-ideation.md §4; /qa:ideate returns "unsupported" for it today, so don't select it yet)
site: app                     # MUST match a sites[].id in specs/_context/app.context.md
interview: <n questions across <m> rounds | none — fully observable>   # F-016 attestation: how much HUMAN intent-interview actually happened. /qa:intake stamps the real count (e.g. "7 questions across 2 rounds"); "none" is only legitimate when EVERY rule is [grounded:]/[imported:]/[pinned:] (no [human-answered]). A basis with [human-answered] rules but interview: none is a red flag — the human grounding is unattested (doctor WARNs).

# 🟡 yellow — the story (plain English; a non-engineer must understand it)
story: >
  <who> does <what> to achieve <why>.

# 🔵 blue — rules = THE ORACLE. condition → outcome. This is the mandatory section.
# One plain string per rule, "<condition> → <outcome>" (matches reference/test-case-ideation.md §7).
# PROVENANCE (recommended when `business_sources:` are declared in app.context.md) — suffix each rule
# with WHERE it was grounded + the verdict, so a reader can audit why the oracle says what it says.
# /qa:intake stamps these during its source-consult:
#   # [grounded: <source name>]   — a declared business_source states this rule (cite which)
#   # [human-answered]            — no source had it; the operator answered in the interview
#   # [not-in-source]             — the sources are silent → ALSO log it under open_questions until confirmed
#   # [contradicted: <source>]    — a source DISAGREES with the app / another source → resolve, do NOT ship
#   # [imported: <source> <ext-id>] — rule arrived via the manual-cases-import recipe (reference/how-to-import-manual-cases.md): derived from an external case's
#                                     expected result, NOT interviewed intent
#   # [pinned: observed <YYYY-MM-DD> — provisional] — characterization: behavior pinned, intent NOT
#                                     confirmed. NEVER [grounded:]/[human-answered] for a pin; a pin older
#                                     than the area's staleness tier is a re-verify prompt
rules:
  - "<condition> → <expected outcome>   # [grounded: <source> | human-answered | not-in-source | contradicted: <source>]"
  - "<condition> → <expected outcome (incl. the negative path)>"

# 🔵 must_not — ABSENCE / negative invariants the test must PROVE stay false.
# These are the ones generators fumble (they read as "nothing to assert"): "no order
# created", "cart count unchanged", "no token written on an invalid path". Naming them
# first-class here (not buried in a rules string) makes the handoff to ideate/generator
# machine-readable → each maps to a failable oracle (no_order_created, count_equals on a
# baseline, storage_state:<null>), NOT a skipped assertion. Omit if none.
must_not:
  - "<state that must NOT occur> — proven via <which surface: orders-API count / UI scan / storage key>"

# 🔵 integrity_invariants — RELATIONAL / equality oracles: two things that must match.
# The closed vocab has no single relational key, so capture the invariant here and the
# generator reifies it (exact equality assertion / same-literal-both-branches + a note).
# e.g. "created order total EQUALS the cart's computed total", "refusal message on branch
# A is byte-identical to branch B (anti-enumeration)". Omit if none.
# holds_when — the precondition domain over which the equality holds — an unscoped equality is
# green on the pinned row but wrong as an invariant (reviewer Check 2e WARNs); "always" only if genuinely universal.
integrity_invariants:
  - invariant: "<value/output A> == <value/output B>"   # why this equality IS the assertion
    holds_when: "<precondition domain — e.g. 'single-unit order'; 'always' if truly universal>"

# NOTE — where must_fail_when comes from. The spec contract (CLAUDE.md) has a first-class
# `must_fail_when:` block that the generator's step-8b fault injection and reviewer Check 2b
# ENFORCE. The basis tier does not repeat that key: `must_not` (above) + `integrity_invariants`
# ARE its source — the planner compiles each into the spec's `must_fail_when:` items. So name every
# defect the test must catch here (as a must_not absence or an integrity == invariant); do NOT leave
# it in prose. A defect named only in `story:`/`risks:` prose is NOT carried into `must_fail_when` and
# silently escapes step-8b. If a defect fits neither must_not nor an equality, add it as a `must_not`
# string phrased as the bad outcome ("<X> must NOT happen").

# 🟢 green — concrete examples (become test-case seeds / scenarios)
examples:
  - "<concrete input> → <concrete observable result>"

# inputs — drive equivalence partitioning + boundary value analysis
inputs:
  - name: <field>
    type: <string|number|enum|...>
    valid: [<...>]
    invalid: [<...>]            # the easy-to-miss half
    bounds: { min: <n>, max: <n> }   # if ordered/length-bounded

# states & transitions — drive state-transition cases (incl. invalid transitions)
states: [<state>, <state>, ...]

# actors / roles — drive permission cases
actors: [<role>, <role>]

# dependencies — drive interface / failure-injection cases
dependencies: [<service>, ...]

# couples_with — OTHER product areas whose STATE or BUSINESS RULES this feature's ORACLE must
# account for (inbound coupling — the forward change-impact / interdependency view). DISTINCT from
# `dependencies:` (services this feature calls at runtime): a coupling is another area whose
# rule can silently INVALIDATE an oracle here. Canonical misses this closes: a "totals are
# equal across surfaces" oracle broken by a multi-unit feature owned elsewhere; an "on-call
# count" rule that depends on the scheduling area's roster. /qa:intake traces these outward
# from the feature + whatever docs you point it at (source-agnostic — wiki, PRD, ticket, or the
# live app), records the couplings the area context declares, and turns UNKNOWN couplings into
# 🔴 open questions instead of silent gaps. /qa:ideate then enumerates a case per coupling.
# This is an HTSM-style completeness REMINDER (a recognized but heuristic aid), not a proof —
# it is advisory, never a gate. Omit if none known.
# `channel:` names WHICH coupling angle this is — a reconciled heuristic subset — the five channels:
#   shared-data              — another area reads/writes the same entity/record
#   cross-surface-aggregate  — this value sums/derives from another area's data (multi-unit totals)
#   state-gate               — a publish/approval/permission/lifecycle state owned elsewhere gates this
#   cross-actor              — another actor's action (admin, 2nd user, a job) changes what this asserts
#   config-flag              — behavior toggled by config/feature-flags owned by another area
couples_with:
  - area: "<other-area>"
    channel: "<shared-data | cross-surface-aggregate | state-gate | cross-actor | config-flag>"
    coupling: "<the rule/state there this feature's oracle must account for>"

# test_data / mutation — carry the data-lifecycle directive forward as a MACHINE-READABLE
# block, not prose in risks:. A mutating flow (checkout, refund, create/delete) needs a
# worker-scoped seed + teardown so parallel runs don't collide or accumulate — this is the
# record the generator reads when wiring the test-data-seed skill, and `/qa:doctor` Check 13
# verifies (declared-mutation ↔ isolation-marker pairing). Reviewer Check 13 independently
# detects mutation from the test code — this block is the *declared* half. (Seed is consumed
# as a Playwright fixture via mergeTests, NOT a `data:` block.) Omit for read-only flows.
test_data:
  mutates_server_state: false        # true → the flow creates/updates/deletes persistent state
  seed: "<none | worker-scoped fixture: which entity, seeded how>"
  teardown: "<none | by-tag / reset endpoint / per-worker cleanup>"

# the lenses LLMs silently drop — null = explicitly N/A (logged, not forgotten)
nonfunctional:
  a11y: <required|null>
  i18n: [<locales>]            # or null; RTL locales create real edge cases
  concurrency: "<scenario>"    # or null
  performance: <expectation|null>

risks: ["<known risk / past P1 / chronic area>"]   # → RCRCRC weighting
priority: P2                   # P1|P2|P3 — feature criticality, default P2. P1/critical drives the smoke-lane rule (planner auto-tags the governed happy-path @smoke) and the P1 must_fail_when floor (see planner.md).
covered_by:                    # legacy coverage — characterization/brownfield only
  - legacy: "tests-legacy/<path>"   # an existing suite already exercises this rule (coverage reports LEGACY-with-caveat)
compliance_relevant: false     # true for PCI/HIPAA/SOX → cross-vendor reviewer
out_of_scope: ["<explicit non-goal>"]

# 🔴 red — open questions. Mark blocking:true for ones that gate /qa:ideate.
open_questions:
  - q: "<unresolved intent question>"
    blocking: true
```

<!-- For kind: bug, replace inputs/rules/examples with:
repro: ["step", "step"]
expected: "<what should happen>"
actual: "<what happens>"
environment: "<site / browser / data>"
regression_scope: "<which paths this defect class could touch>"
-->
