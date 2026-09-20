---
description: "Honest test-coverage report — 9 dimensions (0–6, plus 1b and 5b): route-footprint, requirement, spec-without-test, assertion, lens, flow, case, waiver-destination, and declared-a11y-need→oracle coverage, computed statically from basis, specs, cases, and route manifests. No test run, no line coverage. WARN-only, never a gate; names the GAPS, not a single gameable %."
argument-hint: "[area=<name>] [site=<id>]"
context: fork
background: false
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/coverage.sh *)
---

Report **honest** test coverage for this suite — *flow / requirement coverage, never line
coverage*. This is a **read-only static analysis**: it reads the files the authoring chain
already produces (`*.basis.md`, `specs/**/*.md`, `*.cases.md`, `artifacts/route-manifests/`)
and needs **no `npx playwright test` run**, no `.env`, and no browser — so there is **no
prod-guard step** (nothing is driven).

**Design contract (do not violate — these are the whole point):**
- **Never emit a single "X% covered" headline as the answer.** A lone percentage is the
  line-coverage lie one level up: it gets gamed, it hides what's missing. **Lead with the
  named GAPS** (which features have no spec, which lenses are empty) — the gap list is
  what's actionable and un-gameable. Sub-metrics may carry a ratio *next to their named
  gaps*, never a rolled-up score.
- **WARN, never FAIL.** This skill blocks nothing and gates nothing. Completeness is
  undecidable and humans own *what* to test (CLAUDE.md §Test-case ideation); a coverage
  gate would contradict that and breed vacuous specs written to hit a number. Surface gaps;
  let a human decide.
- **Deterministic extraction, not LLM-summarized.** Extract counts/paths with the shell
  recipes in the bundled script; the model only *formats* the result. Do not paraphrase or estimate numbers.
- **Degrade gracefully.** The `intake`→`ideate` chain is optional, so `*.basis.md` /
  `*.cases.md` may not exist. Compute only the dimensions whose inputs are present; for an
  absent input print `— (no <file> files; <dimension> unavailable)`, never `0%`.
- **State the limits inline.** The 🔵-rule→oracle-key mapping is *approximate* (semantic, not
  grep-able), so requirement coverage is reported at the deterministic **feature level**;
  rule-level counts are a **signal, not a guarantee**. Say so in the output.

## Arguments
Parse `$ARGUMENTS` for optional `area=<name>` and/or `site=<id>` (must match a
`sites[].id` in `specs/_context/app.context.md`). No args → whole suite.

**How the filter is applied (be honest about scope):** `area=`/`site=` narrow the
**feature-level** dimensions (1 requirement-coverage and 2 assertion-presence) by path —
the bundled script derives a `COV_FILTER` regex from the arguments and pipes each `find`
through it, so this stays *deterministic extraction*, not LLM post-filtering. Dimensions 3
(lens gaps) and 4 (flow footprint) are computed **suite-wide** (they aggregate cross-feature
signal); when a filter is set, report those two for the whole suite and **highlight** the
requested `area`/`site` rows rather than dropping the rest.

## What to compute (9 dimensions — 0–6 plus 1b and 5b)

All nine dimensions are computed by ONE bundled script. Run it from the **project root**
(every path it reads is project-relative) and pass `$ARGUMENTS` through verbatim:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/coverage.sh "$ARGUMENTS"
```

The script is the single source of the extraction recipes and their rationale — **do not
re-derive, re-implement, or "improve" any dimension inline here.** It is pre-approved by this
skill's `allowed-tools`, so it runs without a permission prompt; run it exactly as written
above (a rewritten invocation loses the grant and prompts).

**Exit codes:** `2` = filter resolution error (a bogus `area=`) — report it as a RESOLUTION
ERROR and STOP; it is *not* a gap-free result. Any other non-zero, or absent optional inputs,
degrade gracefully: format whatever dimensions produced output.

Your job from here is **formatting only** — take the script's output and render it in the
shape below. Do not paraphrase, recompute, or estimate any number it emitted.

**Per-dimension reporting:**
0. **Route plan vs footprint** — both directions are WARN-only review prompts, not defect
   lists: a declared-but-untested route is *planned, untested*; a tested-but-undeclared
   route means either the area file needs an `/qa:explore mode=area site=<id> area=<name>` refresh or it is an
   API/login route area files legitimately don't list.
1. **Requirement coverage** — features with a basis but **no spec** (uncovered — name them,
   lead with these); features with a spec but **fewer assertions than 🔵 rules**
   (under-asserted *signal* — name them, mark "approximate"). Ratio:
   `covered-features / total-basis-features`, printed beside the uncovered list — never alone.
   **`LEGACY(n)`** = covered by an unmanaged legacy suite — outside the assertion contract
   (no reviewer gate, no closed vocab); a caveat, not coverage parity.
1b. **Spec-without-test** — an authored `specs/<area>/<feature>.md` with no compiled
   `tests/<area>/<feature>.spec.ts`. **Lead with any row carrying the `← @smoke` marker:** a
   `@smoke`-tagged spec that was never generated means the smoke GATE is blind to it — `--grep
   @smoke` cannot run a test that does not exist, so a fully-broken P1 feature hides behind "no
   test to fail" and the gate still reports green. This dimension exists because the gap is
   invisible everywhere else: dim 1 is basis-DRIVEN (a spec authored without a basis is never
   enumerated there, and the basis is optional), doctor Check 15 `continue`s past test-less specs,
   and `/qa:impact` reads manifests, which an ungenerated spec never emitted. Name every row; the
   fix is `/qa:gen <spec>`.
2. **Assertion presence** — mean assertions/spec, and **any spec with 0 oracle keys** (name
   it — this echoes reviewer Check 1; the reviewer is the enforcing gate, this is visibility).
3. **Lens gaps (self-reported)** — a lens marked `0` (or `✗`, or absent) instead of `✓` is an
   empty lens for that feature. **This line is the ideate agent's own self-report, echoed — NOT
   recomputed here** (RUN-18); present it as "ideate reported", not as coverage-verified, so a ✓
   is never laundered into a computed guarantee. **Cross-check the basis `nonfunctional:` block**
   (`concurrency:`, `i18n:`, `a11y:`, `performance:`): a lens that is *empty in cases* **and**
   *declared-needed in the basis* is the strongest gap — surface it first (the ideation critic
   FAILs this per-feature; here it's the suite-level roll-up). Report per-lens: which features
   leave it empty.
4. **Flow footprint** — the route/area counts. (Manifests are verifier-emitted, so a spec
   not yet compiled contributes nothing — note that, same caveat as `/qa:impact`.)
5. **Case coverage (approved cases → scenarios)** — per feature, `<basis>_cases≈N (of T ideated)` vs
   `spec_scenarios≈M`, where the count is the **☑-approved** subset (not every ideated row — deferred/
   pruned rows are deliberate non-builds); the `<basis>` label is `approved` when the file uses ☑ boxes,
   or `all-ideated(no ☑)` when approval lives only in the banner prose (then the count is best-effort all-
   ideated — say so). Lead with any feature whose `.cases.md` exists but **spec=NO** (approved plan,
   nothing authored). Where `cases` **materially exceeds** `scenarios`, name the feature and prompt:
   *"K approved cases vs ~M scenarios — diff the `.cases.md` against the spec's `scenarios:` for
   silently-dropped approved cases; a deliberate drop should carry a `# waived:` note."* Both counts are
   **approximate** (data-driven `scenarios:` collapse several cases) — say so, never render as a percentage.
5b. **Waiver destinations exist** — every `# waived: … → specs/<path>.md` destination emitted by dim 5b
   that does **not** resolve to a file. A phantom destination means the approved case is unbuilt AND its
   stated home does not exist — coverage-looking, not coverage. Surface each under Gaps (deterministic
   companion to reviewer Check 14's waiver-to-phantom-spec WARN; the reviewer additionally judges bolded
   `**area/feature**` prose destinations this grep can't resolve).
6. **Nonfunctional need → oracle authored** — for each feature whose basis declares
   `a11y: required`, whether the spec actually carries an `a11y_violations_below` oracle. A
   ⚠️ here is a **declared-required a11y case that vanished between `.cases.md` and the spec** —
   a stronger, more specific gap than dim 3's lens ✓ (which only says ideate *listed* a candidate).
   Surface it alongside the dim-3 lens gaps. (i18n/performance/concurrency have no closed-vocab key,
   so they can't be checked at the oracle level — only at the lens level in dim 3.)

## Output format
This skill runs as a forked subagent, so the caller sees only what you return: emit the
full block below VERBATIM as your result — do not summarize it, and do not report "coverage
looks fine" in place of the named gaps.

Return ONE Markdown block as your result (and, if `reports/` exists, also write
`reports/coverage-<area-or-all>.md`). **Lead with gaps.** Shape:

```markdown
## Coverage — <area or "whole suite"> (flow/requirement, NOT line)

### Gaps (act on these)
- Uncovered requirements: <feature-a>, <feature-b>   (basis exists, no spec)
- Empty lenses: Time (no concurrency spec in <feat>), Platform (no i18n spec)   ← declared-needed in basis ⚠
- Zero-assertion specs: <none | name them>
- Dropped-case risk: <feat: ~K approved cases vs ~M scenarios — diff for silent drops | none flagged>
- Phantom waiver destinations: <specs/x.md, specs/y.md — waived-to but never authored | none>

### Numbers (context, not a grade)
- Requirements: <C>/<T> features with a basis have a spec  ·  assertions vs 🔵 rules is APPROXIMATE
- Assertion density: <mean> oracle keys/spec  ·  0 assertion-free ✓
- Lens coverage: <k>/8 lenses non-empty across <N> features   (self-reported by /qa:ideate, not recomputed)
- Case→scenario: <feat> ~<K> approved cases / ~<M> scenarios (approximate — data-driven collapse)
- Flow footprint: <R> routes · <A> areas

_Limits: feature-level requirement coverage is deterministic; rule→assertion mapping is a
signal, not proof. Route footprint counts only compiled specs (manifest-derived). This is a
report, not a gate — humans own what to test._
```

If a dimension's inputs are absent, print its line as `— (no <basis|cases|manifest> files)`
and continue; never fail the skill.

## When to use
- Before a release: "what did we decide to test, and what's still a gap?"
- After `/qa:ideate` approval: confirm every approved rule has a spec.
- In a PR: paste the Gaps block so reviewers see coverage direction (not a %).

## What this does NOT do
- **No line/statement coverage** — pointing an LLM at a line target manufactures the exact
  green-but-empty tests this toolkit exists to prevent (reference/DESIGN.md §"Honest limits").
- **No gate / no merge-block** — WARN only.
- **No test run** — static analysis of on-disk authoring artifacts only.
- It cannot prove a 🔵 rule's *oracle is correct* (that's the un-closeable wrong-spec gap);
  it reports whether a rule has *an* assertion, not whether the assertion is *right*.
  (`/qa:review url=<url>` + the reviewer + metamorphic twins + negative-control probes cover strength.)
