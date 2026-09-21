# `/qa:help` knowledge map

The catalog half of the `/qa:help` skill. Split out of `skills/help/SKILL.md` because that
body exceeded the ~5,000-token skill ceiling — past which Claude Code re-attaches only the
first 5k after a compaction, silently truncating everything below. The behavioral half
(how to answer, First 60 seconds, State read) stays in SKILL.md and must always be in
context; THIS file is read on demand for catalog / workflow-order / "what does X do" questions.

**Maintenance:** the `/qa:<name>` rows below must stay in sync with the directories under
`skills/`. `bin/qa-selfcheck` Check 9e enforces exactly that — add a row when you add a skill.

## The workflow (happy path)

```
/qa:init                         once per project — stamp runtime substrate, then edit .env
   ↓
/qa:explore                      hot tier  → specs/_context/app.context.md   (sites, auth, env, naming)
/qa:explore mode=area …          area tier → specs/_context/<site>/<area>.md  (REQUIRED before intake — intake hard-stops without it; new-spec/planner also STOPs on a missing/stale area file and has /qa:new-spec run /qa:explore mode=area … then re-invoke — the planner never drafts from the hot tier alone)
   ↓   ── "what to test" sub-chain (optional but intended) ──
/qa:intake  <area/feature>       interview → <feature>.basis.md   (pins the ORACLE — what "correct" means; needs the area file above)
                                 ↳ if app.context.md declares business_sources:, CONSULTS them to ground each rule + stamp provenance, and runs a multi-channel COUPLING SWEEP; asks you on any source-vs-app conflict
/qa:ideate  <area/feature>       SFDIPOT checklist → <feature>.cases.md   ← HUMAN approves/prunes via /qa:approve (gate)
   ↓   ── core pipeline ──
/qa:new-spec <area/feature>      planner   → specs/<area>/<feature>.md   (Markdown + YAML oracle block)
/qa:gen      specs/<area>/<f>.md generator → tests/<area>/<feature>.spec.ts, then verifier → twins + fault injection + route manifest; leaves a confirmation .webm on a new spec (QA_KEEP_VIDEO), caller commits after review
   ↓
/qa:review   [spec-or-diff]      reviewer  → BLOCKS green-but-empty/-wrong/-under-asserted + WARNs green-but-incomplete (approved case never generated) before merge (the load-bearing gate — run on every PR touching tests/specs)
   ↓
/qa:run mode=smoke                    run @smoke suite (no LLM)   ·   /qa:run mode=single <spec> = one spec, CI-shaped
   ↓   on failure
/qa:heal <test-id>               single fix   ·   /qa:batch-fix <path-or-substring> = one pattern across many failures
   ↓
/qa:report                       aggregate run + audits → PR/Slack-ready summary
```

**Side branches (quality probes, not in the build line):** `/qa:review url=<url>` (a11y + visual + closed-vocab audit of a live URL — a mode of `/qa:review`, not a separate command), `/qa:run mode=repeat <spec> [N]` (repeatability), `/qa:impact route=… | field=… | factory=… | area=… | operation=… | source=…` (which specs a change touches — all 6 keys), `/qa:doctor` (read-only health check — freshness / zero-test / vocab-drift / smoke-tag (vacuous gate + smoke-tagged-spec-with-no-test) / bug-Status + durable-evidence + parked-marker↔bug-lifecycle (Check 11c: a live `test.fail`/`test.fixme` on a fixed bug) / sentinel / context-staleness / pin+lockfile / prod-guard-lockstep / substrate-drift guards; `--verify-invariants` proves each `must_fail_when` is executable), `/qa:coverage [area=… | site=…]` (honest coverage across 9 dimensions, 0–6 plus 1b and 5b — route-footprint, requirement, spec-without-test, assertion, lens, flow, case, waiver-destination, declared-a11y-need→oracle — static, WARN-only, names gaps not a %).

**Start here when red:**
- ONE test failing → `/qa:heal <id>` (the artifacts/test-results/<dir> name from the failure output)
- MANY failures, same shape (one selector/copy change) → `/qa:batch-fix <path-or-substring>` — diagnose once, patch everywhere
- Fails SOMETIMES / passes on retry → `/qa:run mode=repeat <spec> [N]` — repeatability probe; @quarantine if the worst per-test rate <95%
- Red right after an app change/deploy → `/qa:impact route=…|field=…|factory=…|area=…|operation=…|source=…` to scope the blast radius; `/qa:explore mode=area …` if the area context is stale
- EVERYTHING red / won't even start → check `.env` + host reachability (VPN?), then `/qa:doctor` — don't heal tests when the harness is the problem
- After fixing → `/qa:run mode=smoke`, then `/qa:report` for the shareable summary

**Which checker do I want?**

| Checker | Looks at | Answers | Run it |
|---|---|---|---|
| `/qa:review` | the working diff / a named spec+test | "Is this test honest?" (assertion contract) | every PR touching tests/ or specs/ |
| `/qa:doctor` | project substrate + artifacts, static | "Is the harness healthy?" | when things look wrong; weekly; CI |
| `/qa:coverage` | basis/cases/specs/manifests, static | "What am I NOT testing?" (named gaps, no %) | after generating an area |
| `/qa:review url=<url>` | one live URL | "Is this page accessible / visually regressed?" | ad-hoc probe |

**Brownfield:** adopting on an existing app → explore all areas → risk-rank → P1 area first via the rigor lane; park the legacy suite at `tests-legacy/` (coverage shows LEGACY-with-caveat); pin unspecifiable behavior with `kind: characterization`.

## Slash commands (skills you invoke as `/qa:<name>` — all namespaced)

**Who can invoke what** (ask about this if a user wonders why Claude did or didn't run something):
every `/qa:*` is a skill under `skills/`. The side-effecting ones — `init` `gen` `new-spec`
`heal` `batch-fix` `retire` `approve` `run`
`intake` `ideate` `import-cases` — are **user-only**: Claude never triggers them by itself, so it will
recommend a command rather than run it. The read-only ones (`help` `review`
`coverage` `doctor` `impact` `report` `explore` `metamorphic-relations`) Claude may also invoke on its own, and
`coverage`/`doctor`/`impact`/`report` run in their own subagent. Reasoning:
`${CLAUDE_PLUGIN_ROOT}/reference/DESIGN.md` §"Why the invocation policy is what it is".
(`reference/how-to-import-manual-cases.md` has a narrative walkthrough of the same
`/qa:import-cases` workflow, for reading end-to-end rather than as agent steps.)

| Command | Does | Delegates to |
|---|---|---|
| `/qa:init` | Bootstrap runtime substrate (configs, scripts, fixtures, CLAUDE.md, permissions) + install deps. Idempotent, never clobbers. **Run once, first.** `--resync` force-refreshes the toolkit-owned substrate (`package.json`, `playwright.config.ts`, `prod-guard.*`, pinned deps, …) in an ALREADY-scaffolded project — the fix-propagation path for when a plugin fix must reach a project the skip-if-exists scaffold won't rewrite; backs up each changed file to `.qa-bak`, never touches `.env`/`CLAUDE.md`/user files. It also runs the additive `.claude/settings.json` permission merge and appends `*.qa-bak` to `.gitignore`, so an upgrade is ONE call. | — (scaffold script) |
| `/qa:explore` | `mode=hot` refresh `app.context.md`; `mode=area` write `<site>/<area>.md`. Never caches selectors. | **exploration** agent |
| `/qa:intake` | Interactive interview to capture the test basis — auto-gathers observable context, asks only about non-observable intent (the oracle) → `.basis.md`. **If `app.context.md` declares `business_sources:`, consults them to ground each 🔵 rule and stamp its provenance** (`grounded[src]`/`human-answered`/`not-in-source`/`contradicted`), and runs a **multi-channel coupling sweep** (shared-data / aggregate / state-gate / cross-actor / config-flag) → `couples_with:`. Asks you on a source-vs-app conflict or an unreachable/silent source — never guesses. Runs in main session. | — (interactive) |
| `/qa:ideate` | Enumerate candidate test cases (SFDIPOT fan-out, de-dup, risk-rank, completeness critic) → `.cases.md` checklist. Never writes specs/tests. | **ideation** agent |
| `/qa:approve` | Record human approval of an ideated checklist — mint stable row ids, write the `> HUMAN APPROVAL` banner reviewer Check 14 reads. Structured approve/prune/defer round; writes only the `.cases.md`. Runs in main session. Closes by printing the literal `/qa:new-spec` command per approved group, not the naming rule. | — (interactive) |
| `/qa:import-cases` | Bring existing manual test cases in (TestRail/Excel/wiki) → `.cases.md` rows + a minimal basis, provenance-stamped (`[imported/<source> <id>]`) and deduped. Import ≠ approval — `/qa:approve` is still the gate. | — (interactive) |
| `/qa:new-spec` | Draft one feature's Markdown spec with a closed-vocab YAML oracle → `specs/<area>/<feature>.md`. Never emits `.spec.ts`. | **planner** agent |
| `/qa:gen` | Compile a spec → `tests/<area>/<feature>.spec.ts` (generator), then grade it — twins, fault injection, route manifest (verifier, a separate call); leaves the green, verified test for the caller to commit. Runs serially in the main working tree (multiple specs one at a time). On a **new** spec's final run it keeps a confirmation `.webm` (`QA_KEEP_VIDEO=1`) so a human can watch the actual run and confirm intent before committing, then delete `artifacts/`; pass `keep-video` to force one on a re-run. | **generator** agent |
| `/qa:metamorphic-relations <parent-spec>` | Generate 2-3 invariant-preserving **twin** specs of a passing `.spec.ts` (reorder-invariance, round-trip identity, returning-sequence, inverse-operation) — a twin that DISAGREES with its parent on first run means the oracle is drifting. Normally you never call this by hand: the **verifier** invokes it automatically post-green on a new spec (its step 8a), and reviewer Check 6 only verifies the twins exist and agree. Run it directly to add twins to a spec that predates the step, or after widening an invariant. | **verifier** authors; **reviewer** verifies |
| `/qa:review` | Run the **load-bearing reviewer** over the working diff (or a named spec/path) — the shipped trigger for the full assertion-contract suite (failable-expect, step→assertion, `must_fail_when` reified, value fidelity, closed vocab, locator policy, twin/parallel-safety, approved-case traceability WARN). Any FAIL blocks the PR. Read-only; emits one PR comment. Run on every PR touching `tests/`/`specs/`; CI snippet inside. | **reviewer** agent |
| `/qa:run mode=smoke` | Run the `@smoke` suite, print pass/fail summary. No LLM in loop, no auto-heal. | — |
| `/qa:run mode=single` | CI-shaped single-shot run of one spec → `reports/headless-<name>.json`. | — |
| `/qa:run mode=repeat` | Repeat one spec N times back-to-back (default 10, one `--repeat-each` run → `artifacts/flake-<name>.json`), report pass rate; recommends `@quarantine` if <95%. Diagnostic only. The tag is enforced, not advisory: `playwright.config.ts` ships `grepInvert: /@quarantine/`, so tagged tests are excluded from every run with no CLI flag. | — |
| `/qa:run mode=changed` | Run only the tests git says a change touches (Playwright `--only-changed [ref]` — changed test files + every test importing a changed page-object/fixture) → `reports/changed.json`. PR-speed lane, never the run of record; lists edited specs it cannot select; refuses an unborn HEAD or an unresolvable ref (both silently select 0). | — |
| `/qa:heal` | Triage one failing test from its trace; patch **selectors/waits only, never assertions**; file a bug if it's a product defect. | **healer** agent |
| `/qa:batch-fix` | Apply ONE healer pattern across every failing test matching a path-or-substring filter (Playwright's own test filter — NOT a shell glob). Proposes the pattern and waits for confirmation (high blast radius). | **healer** agent |
| `/qa:impact` | List every spec affected by a change to a route/field/factory/area — plus `source=<name>` (which specs stand on a business source) and `operation=` (GraphQL). Reads `artifacts/route-manifests/`. Read-only. | — |
| `/qa:retire` | Coherent feature deletion, consumer-checked: dry-run inventory of every linked artifact (spec, test, twin, shared `*.oracle.ts` module, manifest, basis/cases), STOP for confirmation, delete only unshared files, then `tsc` + `--list` verify. | — |
| `/qa:review url=<url>` | Full a11y + visual + closed-vocab audit of a URL → `reports/audit-<ts>.md`. A mode of `/qa:review` (not a separate command). Direct snapshot, no exploration. Scans the page's documented **error/failure states** (invalid-submit alert, opened menu/modal), not only the pristine default — a low-contrast error alert only renders after the interaction. | **reviewer** agent, **axe-a11y** + **visual-regression** skills |
| `/qa:report` | Aggregate `last-run.json` + `reports/*.json` → PR/Slack summary. Pure aggregation, reruns nothing. Leads with the run **scope** (`--grep @smoke` → "N smoke tests"), so a green smoke subset is never reported as full-suite green. Then a qualified go/no-go verdict — it stays qualified while any `bugs/*.md` is open, an audit found violations, or the scope could not be established. Surfaces passed-with-retries (flaky is not passing), audit headlines, and the value ledger. | — (self-contained) |
| `/qa:doctor` | Read-only health check: scripts every freshness / zero-test / closed-vocab / smoke-tag / sentinel / context-staleness / pin+lockfile / prod-guard-lockstep / **substrate-drift** guard the toolkit otherwise leaves to prose. Smoke-tag is now two-sided (Check 3 vacuous gate + Check 16 a smoke-tagged spec with no compiled test — a P1 flow the gate is blind to), and **Check 17** extends that to a spec with no compiled test on ANY tag (a `@regression`-only spec authored but never generated); **Check 18** flags an abandoned authoring chain (a `.cases.md` with no downstream spec); **Check 19** flags an unattested interview (a `[human-answered]` basis with no `interview:` count). Check 11b flags an open bug still citing volatile `artifacts/test-results/…` evidence (copy it into `bugs/<slug>/`); Check 11c flags a parked `test.fail`/`test.fixme` marker whose linked bug is already `fixed`/`reverted` (stale marker laundering a resolved defect green — remove it or reopen the bug). The substrate-drift check flags a `package.json`/`config`/`prod-guard`/MCP-config that no longer matches the shipped template and names `/qa:init --resync` as the fix. `--verify-invariants` fault-injects each `must_fail_when` to prove it's executable. | — |
| `/qa:coverage` | Honest **flow/requirement** coverage (NOT line): 🔵-rule→spec gaps, **spec-without-test** (an authored spec never compiled — invisible to the smoke gate/doctor/impact), assertion density, empty SFDIPOT lenses, route footprint, approved-cases→scenarios drift (dim-5 counts ☑-approved, not every ideated row), phantom waiver destinations (dim-5b — a `→ specs/x.md` waiver target that was never authored), declared-a11y-need→oracle-authored. Static analysis of basis/specs/cases/manifests — no test run. **WARN-only, names gaps not a %.** A bogus `area=` that matches nothing now errors; a `site=` typo warns and degrades (feature dimensions still computed — basis files are optional), not a false clean report. | — |
| `/qa:help` | This guide: command catalog, workflow order, and "what's next" read from project state. Pass an `<area>/<feature>` to scope that read to ONE feature (basis → cases → spec → test) instead of walking the project. Read-only. | — |

## Agents (the "brain" — triggered by a skill or an event; can't spawn each other)

| Agent | Role | Triggered by | Writes |
|---|---|---|---|
| **exploration** | Build the context layer: hot tier (app.context.md) or one area file. Captures domain vocab, never selectors. | `/qa:explore`; sentinel from healer | `specs/_context/**` |
| **ideation** | Enumerate candidate test cases via SFDIPOT lenses → checklist. Human is the gate. | `/qa:ideate` | `specs/**` (`.cases.md`) |
| **planner** | Translate a story/bug into one spec + YAML oracle. Owns the **assertion contract**. | `/qa:new-spec` | `specs/**` |
| **generator** | Compile spec → deterministic `.spec.ts`, run it once to green, hand off. **Does not grade its own output.** Runs serially in the main working tree. | `/qa:gen` (first of two agents) | `tests/**`, `page-objects/**` (create + update), `fixtures/test.ts`, `fixtures/schemas/**` + `fixtures/factories/**` (created on demand, grounded in the real app, on first `factory:` use), `bugs/**` (fixme-legitimizing defect files) |
| **verifier** | Grade the generator's green, as an agent that did **not** write it. Authors the metamorphic twins, **negative-control-verifies every declared `must_fail_when` invariant is executable** (step 8b — fault-injects each defect, blocks on a BLIND oracle), renames scenarios that overclaim (8c), keeps a confirmation `.webm` on a **new** spec (8d, `QA_KEEP_VIDEO=1`), and emits the route manifest only once all of that is clear. **Forbidden from editing any `expect(...)`** — a mis-compile goes back to the generator, a decorative oracle to the planner. | `/qa:gen` (second of two agents) | `tests/**` (twins + `// verified:`/rename/`test.fixme` edits), `bugs/**` (BLIND + unverified records), `artifacts/route-manifests/**` |
| **reviewer** | Read-only PR gatekeeper. Blocks **green-but-empty**, **green-but-under-asserted**, AND **green-but-wrong** tests via its full check suite; the keystones are step→assertion coverage (Check 2), **must_fail_when/fail_if reified-as-oracle-or-waived (Check 2b — the intent→oracle half)**, **oracle value fidelity (Check 2d — the compiled `expect` must assert the oracle's *actual* literal/number, catching a right-key/wrong-value mis-compile)**, and failable-expect (Check 1), with a **Check 2c WARN on oracle discriminating-power** (a valid-but-non-discriminating key, e.g. `text_visible` where the intent needs `count_equals`) and a **Check 14 WARN on green-but-incomplete** (an approved `.cases.md` case with no scenario and no waiver — including a waiver that fans the case to a `→ specs/x.md` sibling spec that doesn't exist: phantom coverage). Two `PreToolUse` hooks ship (`hooks/`) covering the four lexical FAILs and the healer/verifier assertion prohibition, but nothing a hook cannot decide from a single write — so the reviewer is still the backstop; invoke it via **`/qa:review`**. | **`/qa:review`** (run on every PR touching `tests/`/`specs/`) | nothing (read-only) |
| **healer** | Triage a failure: classify into one of **10 buckets** (broken-locator, missing-wait, changed-text, stale-context, auth-stale, data-drift, env-infra, contract-change, expected-failure, product-bug); patch selectors/waits or file a bug. **Never touches assertions.** Logs every triage to `artifacts/heal-log.jsonl` (cluster-detection for `/qa:batch-fix` + drift visibility). | `/qa:heal`, `/qa:batch-fix`, CI failure | `tests/**`, `page-objects/**`, `bugs/**`, `artifacts/heal-log.jsonl`, `artifacts/.healer-needs-*` sentinels |

## Capability skills (same SKILL.md format; Claude auto-triggers these, most aren't slash-callable)

| Skill | Adds | Invoked by | Slash-callable? |
|---|---|---|---|
| **playwright-cli** | Deterministic, token-predictable browser driving (the engine under healer/generator/suite runs). | auto (healer, generator, suite runs) | no |
| **test-data-seed** | Parallel-safe, API-seeded, teardown-by-tag fixtures (survives 10+ workers). | auto (generator authoring) | no |
| **axe-a11y** | WCAG accessibility assertions per UI state. Catches ~30–40% by success-criterion (~57% by issue volume); rest needs a human. | auto; `/qa:review url=` | no |
| **visual-regression** | `toHaveScreenshot()` layout/CSS oracle that text assertions miss. | `/qa:review url=`; otherwise only when you ask for a screenshot check in the main session. **Not reachable from a spec** — no oracle key requests a screenshot, so planner/generator/verifier never invoke it. | no |
| **metamorphic-relations** | Generate 2–3 invariant-preserving "twin" specs that catch spec drift plain assertions can't. **Authored by the verifier** post-green (it has Write, and did not write the parent); reviewer Check 6 only *verifies* they exist and agree. Twins are tagged `@metamorphic` + `@regression`, never `@smoke`. | verifier (post-green, authors); reviewer (verifies, Check 6); `/qa:review url=`; human | **yes** |

## Mental model (the load-bearing "why"s)

- **The assertion contract is sacred and owned by the planner.** Generator maps it 1:1 to `expect()`; the verifier grades whether that mapping actually fires but may never edit it; healer must never weaken it (changed-text → escalate to planner); reviewer enforces it. This is the central defense against the **silent false pass** (green-but-empty test).
- **Three-tier context:** hot (`app.context.md`) → area (`<site>/<area>.md`) → cold (live selectors, pulled at generate time, **never cached**). Staleness is volatility-tiered (critical/reference/stable), not a flat 30 days.
- **Oracle grounding (the gather phase, optional).** The tiers above hold the app's *observable structure*; **business truth** ("what correct means", why areas couple) is grounded separately. Declare an optional, source-agnostic `business_sources:` block in `app.context.md` (a doc/url/api-spec/tracker/`human` — **not** wiki-locked) and `/qa:intake` consults it to ground each 🔵 rule, stamps its **provenance** (pre-RS/source traceability), and runs a **coupling sweep** across a reconciled channel taxonomy → `couples_with:`. This is the RAG-grounding + traceability defense against *grounded-but-incomplete* oracles (a rule the source has but the interview missed) and silent cross-area couplings. Honest limits: can't crawl a gated wiki (reads/fetches/asks); it's an aid, not a completeness proof; all WARN/advisory; on source-vs-app conflict intake asks *you*.
- **Cost discipline:** AI authors once; Playwright replays with **zero LLM**; AI triages only on failure. That's why MCP/Playwright stays project-side and the replay path is plain `npx playwright test` (run on demand or on your own CI schedule).
- **No subagent spawns another subagent.** Handoffs route through the orchestrator via STOP-and-return messages or sentinel files (`artifacts/.healer-needs-*`). Skills are called via Bash, not as agent handoffs.
- **Strict writable-path separation** enforces the contract: planner/ideation/exploration → `specs/**`; generator → `tests/**` + `page-objects/**` + `fixtures/schemas|factories/**` (create + update; schema/factory generated on demand from the real app); verifier → `tests/**` (twins + annotations, **never an `expect(...)`**) + `bugs/**` + `artifacts/route-manifests/**`; healer → `tests/**` + `page-objects/**` + `bugs/**` + append-only `artifacts/heal-log.jsonl` + `artifacts/.healer-needs-*` sentinels; reviewer → read-only.
- **"Is this oracle real?"** `metamorphic-relations` generates invariant-preserving "twin" specs — if a twin disagrees with the parent on first run, the oracle is drifting and the reviewer fails Check 6. `must_fail_when:` is advisory by contract (the *author* isn't forced to make it executable), but it is **no longer allowed to silently vanish OR silently fail to fire**: reviewer **Check 2b** fails a spec whose declared `must_fail_when`/`fail_if` invariant isn't reified as an oracle key or explicitly waived, the **verifier's step 8b** fault-injects each declared defect at authoring time and blocks a BLIND (never-goes-red) oracle — run by an agent that did *not* author the assertion it is grading, so its cheapest path is no longer to claim the oracle catches, and `/qa:doctor --verify-invariants` re-runs the same injection on demand / in CI. For *ordinary* happy-path oracles (which get no step-8b injection), reviewer **Check 2c** WARNs when a valid key can't actually discriminate the stated intent — the "filter to exactly one result" scenario asserted with `text_visible` (true on the unfiltered page) instead of `count_equals{n:1}`. This is LLM-judgment, not a mechanical guarantee — keep the reviewer on a capable model and lift prose "broken if…" statements into `must_fail_when:` so injection covers them. For an **equality/relational** oracle, reviewer **Check 2e** (WARN) additionally catches the *over-broad invariant* — an equality asserted with no `invariant_holds_when:` precondition domain (e.g. "order-total == cart-total" is only true single-unit), the Design-by-Contract `require true` default: green on the pinned row, false as a stated invariant.

## Safety rails to remind users of
- **Never point `BASE_URL_*` at a prod host.** Two guards: explore/review/run commands run the canonical `bash scripts/prod-guard.sh` (advisory, agent-run — screens every `BASE_URL_*`, stops on a word-boundary `prod`/`production` host marker), AND `playwright.config.ts` ships an enforced `globalSetup` prod-guard (`scripts/prod-guard.ts`) that throws before any browser opens — so even a bare `npx playwright test` is protected. Both also **fail-CLOSED on an empty or placeholder host** (the shipped `.env.example` ships `BASE_URL_APP=CHANGEME`), so the first guard run REFUSES until you set a real target — a green guard against a host you never chose is worse than a STOP. `QA_ALLOW_PROD=1` overrides the prod-marker check ONLY (in both layers); placeholder/empty-target refusals have no env escape — the fix is editing `.env`.
- `/qa:batch-fix` has high blast radius — it proposes one pattern and waits for explicit confirmation.
- The reviewer **fails closed** (blocks the PR) on inconclusive runs.
