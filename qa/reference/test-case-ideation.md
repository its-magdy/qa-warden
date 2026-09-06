# Test-Case Ideation — design reference

The design + research grounding for two **new** commands that fill the toolkit's one
missing lifecycle stage: **deciding *what* to test**. Companion to
[DESIGN.md](./DESIGN.md).

Last updated: 2026-07-18. Synthesizes **three** adversarially-verified deep-research
passes (≈6M tokens, ~425 subagents): (1) classical test-design + coverage theory +
heuristics + AI test-gen; (2) LLM elicitation + prioritization + human-in-the-loop
review; (3) bug/enhancement best-practice validation. Each cited claim survived a
3-vote refutation gate (≥2/3 to kill). Where a claim is *inference* or *unvalidated*,
it is marked as such — see §9.

---

## Table of contents
1. [The gap this fills](#1-the-gap-this-fills)
2. [Why test-case generation is hard (and why a human stays in the loop)](#2-why-test-case-generation-is-hard)
3. [Architecture: two new commands, two artifacts](#3-architecture)
4. [The `kind:` router](#4-the-kind-router)
5. [`/qa:intake` — capture the test basis](#5-qaintake)
6. [`/qa:ideate` — enumerate candidate cases](#6-qaideate)
7. [Artifacts: `.basis.md` and `.cases.md`](#7-artifacts)
8. [Reuse of existing toolkit machinery](#8-reuse-of-existing-machinery)
9. [Validated flows, refinements & honest open questions](#9-validated-flows)
10. [References](#10-references)

---

## 1. The gap this fills

The toolkit is strong on **run / heal / analyze / report** but has no step for
**"decide what to test."** Today a human writes a plain-English story for *one flow*;
`planner`→`generator`→`reviewer` do the rest. Nothing *enumerates the set of cases* a
feature needs, and — critically — **no downstream gate can detect an omitted
category** (a missing case is invisible to mutation testing, metamorphic twins, and
the reviewer alike). This is the open risk the intake→ideate front-end (`/qa:intake` → `/qa:ideate`) exists to close.

**Two new commands close the gap, before `/qa:new-spec`:**

```
/qa:explore  area=checkout   → app-observed area context              (exists)
/qa:intake   checkout/coupon → the "test basis" (understanding)       NEW
   ⟵ human reviews the basis (GIGO checkpoint)
/qa:ideate   checkout/coupon → candidate-case CHECKLIST               NEW
   ⟵ human approves / prunes
/qa:new-spec checkout/<case> → one rule → one spec, examples → scenarios (exists)
/qa:gen      …               → runnable .spec.ts                      (exists)
```

`intake` writes *understanding*; `ideate` writes *a plan of what to test*; only
`gen` writes a runnable test. The split exists so a human can catch a wrong
assumption at the **cheapest** point — the checklist — before it is baked into code.

---

## 2. Why test-case generation is hard

This is not merely difficult; **complete** case generation is structurally
unattainable, and the industry's own standards say so. This is *why* a human must
own case selection and *why* the defenses are structural, not metric-based.

- **Exhaustive testing is impossible.** ISTQB CTFL v4.0.1 principle #2 (verbatim):
  *"Exhaustive testing is impossible… test techniques, test case prioritization, and
  risk-based testing should be used to focus test efforts."* [ISTQB]
- **No coverage metric can certify completeness.** Code coverage *ignores oracles
  entirely* — a suite with zero assertions can hit 100% [arXiv:2212.06118]. Even
  exhaustive 1024-input enumeration reached only 77–93% MC/DC depending on tool, and
  tools disagree on what partial MC/DC *means* [NIST/IEEE QRS-C 2017].
- **The bound that *is* actionable — the NIST Interaction Rule.** Across domains, all
  observed failures were triggered by ≤4–6 variable interactions; for one NASA app,
  single values triggered 67% of failures, 2-way 93%, 3-way 98% [NIST SP 800-142].
  → ranking by single-factor + pairwise interaction is principled, not arbitrary.
- **LLMs silently drop categories.** From thin stories LLMs hit ~98% of *stated*
  acceptance criteria but omit non-functional/security/edge cases *"without explicit
  prompting"* [ThoughtWorks]. → forced perspective rotation, not one prompt.
- **LLMs under-ask by default.** Clarification rates <5% (Claude-Haiku ~4.9%,
  Sonnet 2.3%, GPT 0.2–0.7%); models *"overwhelmingly default to direct answers"*
  [arXiv:2502.13069, CLAMBER ACL 2024]. Yet interactive clarification recovers up to
  74% of performance lost to underspecification [Ambig-SWE, ICLR 2026]. → the intake
  agent must be *engineered to ask*; silence is the real failure mode, not over-asking
  (the "LLMs over-interrogate" hypothesis was **refuted 0-3** in research pass 2).
- **Garbage-in survives examples.** *"Subtle ambiguities can lead LLMs to generate
  incorrect code even when clarifying I/O examples are present"* — in one case all 20
  generated programs took the wrong interpretation [SpecFix, ASE 2025]. → elicit
  intent up front; you cannot patch a thin basis with examples downstream.

**Consequence for the design:** safety comes from *structure* (forced lens presence,
logged skips, human approval gates), **not** from trusting the model's completeness
judgment — because that judgment is provably unreliable and unverifiable.

---

## 3. Architecture

Two commands, two execution modes, two artifacts (`<feature>.basis.md`, `<feature>.cases.md`).

| Command | Mode | Reads | Writes |
|---|---|---|---|
| `/qa:intake` | **interactive** (main session) | area context + live snapshot + (optional) docs | `<feature>.basis.md` |
| `/qa:ideate` | **autonomous** (subagent fan-out / Workflow) | `<feature>.basis.md` | `<feature>.cases.md` |

Why separate (not one command): intake is *interactive* (human-in-the-loop interview),
ideate is *autonomous* (parallel lens agents). The two don't compose inside one
background run, and the `.basis.md` deserves its own human review gate (the GIGO
chokepoint). The split also matches the toolkit's grain — one command, one agent, one
artifact — and the **guard-and-handoff** pattern already exists (`planner` tells you
to run `/qa:explore` first when context is stale). `/qa:ideate` likewise refuses if
`.basis.md` is missing or has unresolved blocking questions.

---

## 4. The `kind:` router

Intake/ideate route on `kind:`. Six kinds; **five are implemented** (feature,
enhancement, bug, refactor, characterization — the shipped `basis.md` template
offers all five), and `kind:` stays extensible for the rest.

| Kind | Intake | Ideate | Output | Coverage |
|---|---|---|---|---|
| **feature** (new) | full Example Map from scratch | broad SFDIPOT fan-out | many specs | ✅ pass 1 |
| **enhancement** (change existing) | **delta only** — ask what changed | new-behavior cases **+** impact-selected regression set | few new specs + flagged existing | ✅ validated |
| **bug** | read bug record / healer's `bugs/*.md` | **narrow** — regression case + MR twins + bug-class scan | 1 regression spec + twins | ✅ validated |
| **refactor** (behavior-preserving) | delta; oracle = "same as before" | *no* new cases; lean on regression + MR "output unchanged" | regression + invariance twins | ✅ pass 3 (regression+MR) |
| **characterization** (existing untested code) | reverse-engineer oracle from observed behavior | pin current behavior (golden-master) | characterization specs | ✅ implemented (⚠️ established practice, not adversarially verified — Feathers) |
| **exploratory** (charter-driven discovery) | time-boxed charter, not a story | HICCUPPS/SFDIPOT charter, find unknowns | bug records → bug kind | ✅ heuristics, pass 1 |

---

## 5. `/qa:intake`

> **Rationale only — not the runtime definition.** The operational process lives in
> `skills/intake/SKILL.md`; the artifact shape in `templates/specs/_context/_templates/basis.md`.
> If this section and those files disagree, the shipped files win — fix this doc, not them.

**Interactive elicitation of the "test basis"** (ISTQB term: the information you
derive tests from). It captures the *non-observable intent* the agent cannot get
from the app itself — chiefly **the oracle: what "correct" means**. (Reading product
source can disambiguate a route, field, or API shape, but not the intended business
rule; locators still come only from the live AX tree.)

### Process
1. **Auto-gather observable context** — read `specs/_context/<site>/<area>.md`
   (`/qa:explore` output) + a live `playwright-cli snapshot`. Pre-fill everything the
   agent can see (routes, fields, states, vocabulary). *Never ask what it can observe.*
2. **(Optional) ingest docs** the human points at (ticket / Figma / API spec) — a
   pre-fill source, **not** a separate mode (a doc inherits whatever it omits).
3. **Run the Requirements-Smells checklist** on the story to know *what to ask about*
   — subjective language, ambiguous adverbs/adjectives, loopholes, open-ended terms,
   vague pronouns, incomplete references [Femmer et al., JSS 2017, operationalizing
   ISO/IEC/IEEE 29148]. A smell triggers a *question*, never an auto-reject. (Don't
   rely on the base model to detect ambiguity — that ability is model-version-specific.)
4. **Interview by information value, not "ask everything":** ask the single
   highest-value question per turn (EVPI-style), penalize redundant questions, and
   **stop** when no question's net value clears a threshold *or* a question budget is
   exhausted [SAGE-Agent; "Modeling Future Conversation Turns," ICLR 2025]. Naive
   "just ask clarifying questions" backfires — redundant, fatiguing, can degrade
   output [SpecFix, ASE 2025]. Batch questions (the `AskUserQuestion` tool takes up
   to 4) to cut round-trips.
5. **Coupling sweep** — enumerate the other product areas an oracle here must account for, one
   result logged per channel (shared-data, cross-surface-aggregate, state-gate, cross-actor,
   config-flag). The five channels are a **reconciled subset** of recognized taxonomies —
   Constantine/Yourdon module coupling, Dahlstedt-Persson/ReInTa requirements interdependencies,
   and the feature-interaction literature — chosen so the angles are explicit rather than
   free-associated. **Honest limit:** they are a heuristic aid, NOT a canonical list, and there is
   no evidence that forced enumeration finds *more* couplings than careful review; the value is
   that an un-examined channel is visible instead of silently skipped, the same discipline as the
   SFDIPOT lens rotation. A coupling suspected but unconfirmed becomes a 🔴 open question.
6. **Ground each rule in a declared `business_source`, and stamp its provenance** — this is
   RAG-style grounding plus pre-RS (source/origin) traceability: it reduces unfounded rules and
   makes the oracle auditable. The stamp vocabulary (`[grounded:]`, `[human-answered]`,
   `[not-in-source]`, `[contradicted:]`, `[imported:]`, `[pinned:]`) is operative and lives in
   `skills/intake/SKILL.md`. Grounding is an AID, not a guarantee: a source can be stale or wrong,
   which is why a source-vs-app disagreement escalates to the human rather than being resolved
   silently — the literature does not settle whether spec or as-built wins.
7. **Write `<feature>.basis.md`** structured as an **Example Map** [Matt Wynne].
   Unresolved questions are logged as 🔴 red cards — *"turning an unknown unknown into
   a known unknown."* Blocking red cards **gate** `/qa:ideate`.

### Per-kind intake
- **feature** — full map from scratch.
- **enhancement / refactor** — load existing basis, **ask only the delta**.
- **bug** — usually read an existing `bugs/<date>-<slug>.md` (often already written by
  the healer); intake just structures it (repro / expected / actual / env / scope).
- **characterization** — no story to elicit; reverse-engineer the oracle from observed
  behavior and pin it.

---

## 6. `/qa:ideate`

> **Rationale only — not the runtime definition.** The operational lens definitions and
> per-kind processes live in `agents/ideation.md`; the artifact shape in
> `templates/specs/_context/_templates/cases.md`. If this section and those files disagree,
> the shipped files win — fix this doc, not them.

**Autonomous multi-perspective fan-out** that turns the basis into a candidate-case
**checklist** for human approval. Never auto-generates specs.

### Process (feature kind — the broad path)
1. **SFDIPOT lens fan-out** — one agent per lens, each blind to the others, each
   *forced* to emit cases only through its lens [Bach HTSM / SFDIPOT]:
   - **Structure** → route/DOM integrity, error pages (404/500), deep-link + page-reload
     state preservation, SPA history/back-button (the "S" of SFDIPOT, as reachable
     black-box structure) · **Function** → happy paths · **Data** → EP valid/invalid,
     BVA edges, cardinality (0/1/many/max), lifecycle · **Operations** →
     disfavored/malicious use, permissions/roles · **Time** → concurrency, idempotency,
     retry · **Platform** → i18n/RTL, viewport, a11y · **Interfaces** →
     dependency-failure injection, API error codes · plus an **Error-guessing**
     (experience-based) agent.
   - An empty lens must report *"0 candidates"* explicitly — a logged decision, never
     an invisible gap. (Note: that fan-out beats a single rich prompt is a reasonable
     *hypothesis*, supported by multi-agent consensus evidence [CANDOR, TOSEM 2025]
     but **not directly verified** for this lens decomposition — see §9.)
2. **Embedding-similarity de-dup** — cluster near-duplicate candidates and drop
   redundant ones [LTM, IEEE TSE 2024: 0.84 fault-detection, 41.72% time saved].
3. **Risk-rank** — NIST interaction strength (single-factor + pairwise first) + RCRCRC
   change-proximity. Trims to top-N *without dropping a category*.
4. **Completeness critic** — check the merged list against the full SFDIPOT taxonomy
   and the basis's declared non-functional fields. **WARN** on thin lenses (the
   judgment is unvalidated — §9); **FAIL** only on a *deterministic contradiction*
   (basis declares `concurrency: required` but zero `@concurrency` candidates exist).
5. **Write `<feature>.cases.md`** — grouped by rule, each row tagged with lens +
   technique + risk + an oracle hint, with approve/prune checkboxes.

### Per-kind ideate
- **bug** → narrow: (a) **the regression case** (reproduces the bug, asserts the fix,
  tagged `@regression`, **carrying a `must_fail_when:` entry** — an advisory record of
  the defect the assertion must catch, documented intent, not an auto-verified mutation
  run); (b) **metamorphic twins + boundary siblings** via the
  `metamorphic-relations` skill; (c) a **bug-class scan** (WARN-level — see §9).
- **enhancement** → two fronts: **new-behavior** cases + a **regression set** chosen
  by `/qa:impact`. *Impact selection is an optimization on top of periodic full
  regression — never a replacement* (§9, safety caveat).
- **refactor** → no new-behavior cases; regression + metamorphic "output unchanged."

---

## 7. Artifacts

> The examples below are **illustrative**; the shipped templates under `templates/specs/_context/_templates/` are authoritative — they carry additional required slots (`must_not:`, `integrity_invariants:`, `test_data:`, and the `Lens coverage:` line that `/qa:coverage` greps) that these condensed examples omit.

### `<feature>.basis.md` (Example Map)
```markdown
# basis: checkout/coupon
kind: feature                 # feature | enhancement | bug | refactor | characterization  (exploratory: roadmap only — §4 below; /qa:ideate returns "unsupported" for it today)
site: app
story: >                      # 🟡 yellow card
  A logged-in user applies a coupon to get a discount.
rules:                        # 🔵 blue cards = THE ORACLE ("what correct means")
  - valid coupon + cart ≥ min spend → discount applies
  - valid coupon + cart < min spend → error, no discount
  - expired coupon → rejected
examples:                     # 🟢 green cards = test-case seeds
  - QA20 on a $50 cart → $40 total, "Coupon applied"
open_questions:               # 🔴 red cards — blocking ones gate /qa:ideate
  - "Can two coupons stack?"  # unresolved
nonfunctional:                # the lenses LLMs drop — null = explicitly N/A, logged
  a11y: required
  i18n: [en, ar]              # RTL → real edge cases
  concurrency: "two tabs applying coupons at once"
  performance: null
risks: ["coupon stacking caused a P1 last quarter"]   # → RCRCRC weight
compliance_relevant: false
out_of_scope: ["gift cards (separate feature)"]
```
For `kind: bug`, swap `rules/examples` for `repro / expected / actual / environment /
regression_scope`.

### `<feature>.cases.md` (checklist)
```markdown
# cases: checkout/coupon   (☐ approve · group = one spec, examples = scenarios)
Rule: valid coupon + cart ≥ min spend
  ☐ [Function/happy]    QA20 on $50 cart → discount applies       risk: high
  ☐ [Data/boundary]     cart exactly = min spend                  risk: high
  ☐ [Data/invalid]      expired coupon → rejected                 risk: med
  ☐ [Operations/abuse]  already-used coupon reused                risk: high
  ☐ [Time/concurrency]  two tabs apply coupon at once             risk: med
  ☐ [Platform/a11y]     coupon error announced to screen reader   risk: med
⚠ critic: "i18n=[en,ar] declared but no RTL case — gap?"
✗ critic FAIL: basis declares concurrency:required — covered ✓
```
**Cases flow to specs** via Example Mapping structure: each 🔵 **rule → one spec**;
its 🟢 **examples → that spec's `scenarios:`** array (matches the planner's existing
multi-scenario support). Distinct rules → separate specs.

---

## 8. Reuse of existing machinery

The new commands **feed** the toolkit, they don't replace it. Both validated
refinements turned out to be already-solvable with parts you have:

| Need | Existing piece it reuses |
|---|---|
| Observable context for intake | `/qa:explore` + `playwright-cli snapshot` |
| Bug regression "strong assertions" requirement | `must_fail_when:` (advisory intent record) |
| Bug "stays dead via nearby paths" | `metamorphic-relations` skill |
| Enhancement impact selection | `/qa:impact` (route/field/factory/area) |
| Enhancement **safe fallback** (full regression) | `npx playwright test` |
| Spec compilation from approved cases | `/qa:new-spec` → `/qa:gen` |
| Checklist quality gate | the `reviewer` agent (WARN/FAIL tiers) |
| Approved-case → test traceability | reviewer **Check 14** (WARN) + `/qa:coverage` dim-5 (coarse count) |
| Existing manual cases | `/qa:import-cases` (see `reference/how-to-import-manual-cases.md`; import-once, `[imported:]` provenance, external id = row id) |
| Stale-context handoff pattern | mirrors `planner` → `/qa:explore` |

### Traceability (approved case → scenario)

The human approval gate on `.cases.md` is only load-bearing if an approved case that never becomes a
test is *caught*. Two signals do this today:

- **reviewer Check 14 (WARN, per-case)** — reads the `.cases.md` `> HUMAN APPROVAL` banner + rows,
  derives the in-approved-scope set (named approved in the banner, row not `~~struck~~`, group
  approved), and judges each against the spec's `scenarios:`. WARNs on any approved case with no
  covering scenario and no waiver. A conscious drop is waived by naming the case under
  "Deferred"/"pruned" in the banner, or a `# waived: <case> — <reason>` note in the spec.
- **`/qa:coverage` dim-5 (coarse, suite-wide)** — the approved-case COUNT vs the scenario COUNT per
  feature; a dashboard prompt, not a per-case match.

**Why WARN, not a deterministic FAIL (and the Phase-2 upgrade).** Approval is free-text prose today
(the `.cases.md` rows are a human-review checklist, not a lintable schema — see the template's FORMAT
NOTE F-20), so Check 14 is an LLM prose→scenario judgment; a hard-FAIL built on a fuzzy "was this
approved?" read would false-block merges. To make it a deterministic, CI-runnable FAIL:

1. ~~`/qa:ideate` stamps each candidate row a **stable id**~~ **SHIPPED (differently): `/qa:approve` mints the stable ids** (`R1.a`, `NF.sql`, `C.<slug>`) at the human-approval step — the right owner, since the id set should freeze at approval, not at enumeration.
2. The **planner** (`/qa:new-spec`) and **generator** carry a `covers: [<id>, …]` field on each
   `scenario:` it authors from an approved case.
3. Check 14 becomes a mechanical **id set-diff**: `approved_ids − covered_ids − waived_ids == ∅` else
   FAIL — deterministic enough to run in `/qa:doctor` / CI with no model in the loop.

This is the same incremental path the `response_body_contains` oracle key took (proven as a WARN/soft
signal first, then hardened). Step 1 shipped 2026-07-18 via `/qa:approve`; the remaining `covers:`
change touches two mirrors (planner, generator), so the FAIL flip is deferred until the WARN has
demonstrated its value in practice.

---

## 9. Validated flows, refinements & honest open questions

### Validated (research pass 3, 24/25 claims confirmed)
- **Bug route — confirmed canonical.** Failing-test-before-fix, retained as
  `@regression`, is endorsed by Fowler, Kent Beck (TDD red-green), Google (*SWE at
  Google*), and empirical study [arXiv:2602.02965, AST 2026]. MR twins for regression
  are recognized; *diverse* MRs raise fault detection [Chen MT survey; Srinivasan &
  Kanewala, STVR 2022].
- **Enhancement route — confirmed canonical.** Delta-driven selection of impacted
  tests *is* the textbook definition of Regression Test Selection [Yoo & Harman, STVR
  2012] and how Microsoft/Google TIA operate. Two-front split = ISTQB
  confirmation-vs-regression.

### Refinements forced by the research (folded into §5–6)
1. **Bug tests need STRONG assertions.** Validated anti-pattern: bug-reproducing tests
   skew toward weak assertions / try-except, *"missing the opportunity to validate
   expected output"* [arXiv:2602.02965]. → bug route **requires `must_fail_when:`**.
2. **Enhancement needs a SAFE FALLBACK.** Impact/delta selection is provably "safe"
   only under conditions that *often fail*; a change can break *unrelated* areas; the
   problem is *"largely open"* even at Google [Rothermel & Harrold; Google ICSE-SEIP
   2019]. Canonical mitigation: fall back to **full regression** for changes the
   analyzer can't reason about [Microsoft TIA]. → `/qa:impact` per-change is an
   optimization *on top of* full regression (`npx playwright test`), never a replacement.

### Honest open questions / unvalidated assumptions
These failed verification or rest on inference — they are **best-effort heuristics,
not proven**, and the design must not depend on their correctness:
1. **Does SFDIPOT fan-out beat a single rich prompt?** Unconfirmed. Supported by
   multi-agent consensus evidence by analogy [CANDOR], not by a direct test of
   per-lens decomposition. Treat as a hypothesis; the empty-lens-logging makes it safe
   either way.
2. **Completeness-critic / missing-category detection — no surviving claim.** Its own
   recall is unvalidated. Hence WARN-only for fuzzy judgment; FAIL only on
   deterministic contradiction.
3. **Human-in-the-loop trust / automation bias for AI test review — no surviving
   claim.** The approve/prune UX rests on intuition; watch for rubber-stamping.
4. **Bug-class scan** is grounded in ODC/defect-classification *theory* by inference,
   not a prescribed workflow [Chillarege ODC] — ship as a **WARN-level suggestion**.
5. **Characterization kind** is described from established practice (Feathers,
   golden-master/approval testing), **not** adversarially verified here.

### Domain-transfer caveat (applies throughout)
The strongest AI-test-gen evidence is from **Java unit-test** benchmarks
(HumanEvalJava, Defects4J) and tool-calling agents — it transfers as *design
patterns/mechanisms*, not as effectiveness *guarantees* for E2E Playwright. Specific
figures (74% boost, ≥21.1pp, 0.84 FDR) are directional, not promises.

---

## 10. References

**Standards / canon:** ISTQB CTFL v4.0.1 · ISO/IEC/IEEE 29148 · NIST SP 800-142
(interaction rule) · NIST/IEEE QRS-C 2017 (MC/DC limits) · Myers, *Art of Software
Testing* · Kent Beck, *TDD* · Fowler, *Self-Testing Code* · Google, *SWE at Google*
ch.14 · Feathers, *Working Effectively with Legacy Code* (characterization).

**Heuristics:** Bach, Heuristic Test Strategy Model / SFDIPOT (satisfice.com) ·
Bolton, FEW HICCUPPS (developsense.com) · Wynne, Example Mapping · Hendrickson,
*Explore It!* · RCRCRC (Ministry of Testing).

**Papers:** CANDOR multi-agent oracles (arXiv:2506.02943) · oracle-adequacy &
oracle-gap surveys (arXiv:2212.06118, 2309.02395) · SpecFix (ASE 2025,
arXiv:2505.07270) · Ambig-SWE (arXiv:2502.13069) · SAGE-Agent (arXiv:2511.08798) ·
Modeling Future Conversation Turns (ICLR 2025, arXiv:2410.13788) · Requirements Smells
(Femmer, JSS 2017, arXiv:1611.08847) · bug-reproducing tests (arXiv:2602.02965, AST
2026) · Yoo & Harman RTS survey (STVR 2012) · Rothermel & Harrold safe RTS · Google
transition-based selection (ICSE-SEIP 2019) · Microsoft Azure DevOps TIA · Chillarege
ODC (IEEE TSE 1992) · Chen MT survey (ACM CSUR 2018) · LTM test minimization (IEEE TSE
2024, arXiv:2304.01397).

**Internal:** [DESIGN.md](./DESIGN.md) (the design rationale — oracle-defense
philosophy, the no-hooks decision, honest limits). Operational facts — the subagent
roster, oracle vocabulary, and reviewer checks — live in `templates/CLAUDE.md` and
`agents/**`.
