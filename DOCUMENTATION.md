# QA-Toolkit — Full Documentation

> A complete reference for **humans and AI agents** working with the `qa` plugin.
> Read this to understand *what the plugin is*, *how its pieces fit together*, and
> *how to use it end-to-end*. For the design rationale (the *why*) see
> [`qa/reference/DESIGN.md`](qa/reference/DESIGN.md); for a live, project-aware
> "what do I do next" answer run **`/qa:help`**.
>
> **This file is canonical.** There is no second, prettier copy to keep in step: the
> hand-authored `DOCUMENTATION.html` one-pager was deleted in 0.3.0 after sitting a full
> release cycle out of date (it never mentioned the verifier split, `lock:`/`fault:`/`clock:`
> or Playwright 1.63.0) with no generator to replay it. Docs land here.
>
> **New here? Don't start with this file — it's the reference.** Do the
> [**tutorial**](qa/reference/tutorial-first-test.md) (author one test end to end), keep the
> [**glossary**](qa/reference/glossary.md) open, and for a specific goal use a how-to recipe
> (e.g. [import your existing manual cases](qa/reference/how-to-import-manual-cases.md)). If
> you sign off on tests but don't read code, see
> [**reviewing without code**](qa/reference/reviewing-without-code.md). Come back *here* once
> you know the shape and need to look something up. (Goal-oriented recipes live in
> [`qa/reference/how-to.md`](qa/reference/how-to.md).)

---

## Table of contents

**Reading guide — this file is the *reference*.** New here? Start with the
[tutorial](qa/reference/tutorial-first-test.md), not this file. Within, sections group by need:
**Concepts (the *why*)** — §2, §4, §11–14, §18 · **Reference (facts to look up)** — §7–10, §16–17,
§19 · **Recipes & setup (tasks)** — §5–6, §15–16.1 (goal-titled recipes also in
[how-to.md](qa/reference/how-to.md)).

1. [What this is (in one paragraph)](#1-what-this-is-in-one-paragraph)
2. [The core idea: AI authors, Playwright replays, AI triages on failure](#2-the-core-idea)
3. [What it can and cannot do](#3-what-it-can-and-cannot-do)
4. [Architecture: marketplace → plugin → brain + body](#4-architecture)
5. [Install & quickstart](#5-install--quickstart)
6. [The workflow, end to end](#6-the-workflow-end-to-end)
    - [6.1 Brownfield adoption](#61-brownfield-adoption)
7. [Command reference (21 user-invocable skills)](#7-command-reference)
8. [Agent reference (6 subagents)](#8-agent-reference)
9. [Skill reference (5 skills)](#9-skill-reference)
10. [Key concept — the closed oracle vocabulary (16 keys)](#10-the-closed-oracle-vocabulary)
11. [Key concept — the oracle defenses (why tests can't fake green)](#11-the-oracle-defenses)
12. [Key concept — three-tier context](#12-three-tier-context)
13. [Key concept — CLI vs MCP](#13-cli-vs-mcp)
14. [Key concept — the page-object reuse layer](#14-the-page-object-reuse-layer)
15. [Safety rails](#15-safety-rails)
    - [15.1 Privacy & data flow](#151-privacy--data-flow)
16. [The runtime substrate (`/qa:init`)](#16-the-runtime-substrate)
    - [16.1 Nightly in CI](#161-nightly-in-ci)
    - [16.2 Exporting results to your TCM](#162-exporting-results-to-your-tcm)
17. [Repository map](#17-repository-map)
18. [Honest limits](#18-honest-limits)
19. [Glossary](#19-glossary)
20. [For maintainers: where each fact lives](#20-for-maintainers-where-each-fact-lives)

---

## 1. What this is (in one paragraph)

**QA-Toolkit** is a private Claude Code **marketplace** that hosts a single plugin,
**`qa`**. The `qa` plugin turns plain-language feature descriptions into a
deterministic **Playwright** end-to-end (E2E) test suite. An AI (Claude, via a set of
specialized subagents) *authors* the specs and compiles them into runnable
TypeScript tests; **plain Playwright then replays those tests nightly at essentially
$0 in LLM cost**; and the AI is invoked again *only* when a test fails, to triage it.
Shared UI flows live in an AI-maintained **page-object** layer, so a UI change is a
one-file fix that heals every test using it.

---

## 2. The core idea

**AI authors → Playwright replays → AI triages only on failure.**

The expensive part of an AI-driven test is *running the LLM*. A naïve "agent drives
the browser live for every test, every night" design is expensive, flaky, and leaks
memory — a 100-test nightly suite that way costs on the order of **$3,000/month**.

So the toolkit runs an LLM **only** where it is genuinely irreplaceable:

- **Authoring** a spec and compiling it to a test (once), and
- **Triaging** a failure (only when something goes red).

The nightly regression run is plain `npx playwright test`: deterministic, no agent in
the loop, **~$0 LLM cost**. Generate once, replay forever. That single decision is
~90% of the cost win and takes the same suite to roughly **$5–50/month**.

The corollary is a hard rule enforced throughout the design: **never run an LLM on a
green build.** The healer is invoked *only* on a failing test.

Four terms of art you will meet throughout, glued to plain English once here:
the **oracle** — the definition of what "correct" means for a test (the term of art:
the *oracle*); the **closed vocabulary** — assertions from a fixed menu of 16
checkable kinds — an assertion that can't quietly assert nothing; **metamorphic
twins** — checks that don't need to know the right answer — they verify an invariant
instead (reorder the cart ⇒ same total); and the **healer** — on a red test, AI reads
the trace and fixes the locator, never the assertion.

> This "AI authors + deterministic replay" pattern is not unique to this toolkit —
> Meta (TestGen-LLM), Microsoft (Playwright Agents: Planner/Generator/Healer),
> Airbnb, Stripe, and Uber all converged on it independently.

---

## 3. What it can and cannot do

**It is for:** E2E / integration tests that drive a **real browser** against a
**staging/QA** deployment of a web application.

**It is NOT for:**

| Out of scope | Use instead |
|---|---|
| Unit / component / contract tests | Vitest / Pact (keep in the product repo) |
| Performance / load testing | k6 / Locust |
| Security DAST | ZAP / Burp |
| Native mobile (iOS/Android) | Playwright cannot drive native apps |

Two included checks are **partial** oracles by nature: automated accessibility
(`@axe-core`) catches ~20–30% of WCAG issues by success-criterion (~57% by issue volume), and self-hosted visual diffs catch
gross layout breakage only. A green a11y scan is **not** "accessible," and both need
a human for the long tail. See [Honest limits](#18-honest-limits).

---

## 4. Architecture

### 4.1 Two layers: the marketplace and the plugin

```
QA-Toolkit/                          ← the MARKETPLACE (a git repo)
├── .claude-plugin/marketplace.json  ← the catalog — lists the "qa" plugin
└── qa/                              ← the PLUGIN
    ├── .claude-plugin/plugin.json   ← the plugin manifest
    ├── agents/                      ← the "brain" (7 subagents)
    ├── skills/                      ← 23 SKILL.md: 19 /qa:* commands + 4 helpers
    ├── hooks/                       ← 2 PreToolUse gates (the only real-time enforcement)
    ├── reference/                   ← DESIGN.md + research notes
    ├── templates/                   ← the "body" stamped into each project
    └── bin/qa-scaffold              ← the deterministic substrate installer
```

### 4.2 The "brain vs body" split (important)

A Claude Code plugin can only ship **Claude configuration** (agents and skills —
upstream merged custom slash commands into skills, so every `/qa:*` is a skill). It **cannot** install a project's *runtime* files (a `package.json`,
Playwright config, etc.). So the toolkit is deliberately split:

| The "brain" — shipped **by the plugin** (live, auto-updates on upgrade) | The "body" — stamped **by `/qa:init`** (per-project, one-time) |
|---|---|
| agents, skills (incl. every `/qa:*`), `reference/DESIGN.md` | `package.json`, `playwright.config.ts`, `tsconfig.json` |
| | `CLAUDE.md` (the per-project policy / source-of-truth) |
| | `.claude/settings.json` permission rules (writable-path + deny-list) |
| | `.mcp.json` + `.mcp.explore.json` (the two-config MCP pattern) |
| | `scripts/`, `fixtures/`, `.env.example`, `.gitignore` |

**Why the body is stamped, not shipped:** a plugin's `settings.json` only honors a
couple of keys, a plugin `CLAUDE.md` is *not* loaded as project context, and a plugin
`.mcp.json` would auto-start Playwright MCP whenever the plugin is enabled — breaking
the token-cost discipline (MCP is wanted only in explore/heal sessions).

**Consequence — fixes don't auto-propagate to already-stamped files.** Upgrading the
plugin updates the brain instantly, but a fix to a *template* file (e.g.
`playwright.config.ts`) only reaches **new** projects. To pull a substrate fix into an
existing project, run **`/qa:init --resync`** (force-refreshes toolkit-owned files,
backing each up to `<file>.qa-bak`, never touching `.env`/`CLAUDE.md`/your files).
**`/qa:doctor`** flags when a project has drifted and needs it.

**The shared-ownership files are the catch, and `CLAUDE.md` is the one that costs a
feature.** `--resync` skips it on purpose — it is your project policy and you edit it —
but it is also where every new *authoring* feature is documented (`fault:`, `clock:`,
`lock:`, the `verifier` role), and the in-project agents read your copy rather than the
plugin. So a clean, green resync can leave you on the current runtime with a vocabulary a
release behind. Doctor's **CLAUDE.md vocabulary containment** sub-check (Check 9) now names
exactly which toolkit-owned symbols your copy is missing, and points at the shipped template
to diff against — it **warns** rather than fails, because the repair is a hand-merge rather
than a command.

The other two shared-ownership files used to cost you something as well, and no longer do —
both were fixed by making the resync do slightly more, rather than by detecting the shortfall.
`.claude/settings.json` is still never overwritten, but `--resync` now runs the same additive
`jq` permission merge the plain stamp runs (it previously did not, leaving a resync-only
upgrade short **37 rules** with an exit-0 banner). And `.gitignore` is still yours, but the
resync appends the single `*.qa-bak` pattern before writing any backup, so the command stops
generating untracked files its own output tells you to review.

### 4.3 How the pieces coordinate

- **Commands** are the entry points. Some run logic inline in the main session;
  most **delegate to a subagent**.
- **Agents** are the brain. Each has a narrow role, a fixed tool set, and a strict
  **writable-path** boundary. **No agent can spawn another agent** — handoffs route
  back through the orchestrator via STOP-and-return messages or sentinel files
  (`artifacts/.healer-needs-*`).
- **Skills** are capability helpers agents call (mostly auto-invoked via Bash).
- **Templates** are the runtime substrate the tests actually run on.

---

## 5. Install & quickstart

```bash
# 1. Register this marketplace (private git — SSH or HTTPS both work)
/plugin marketplace add git@your-host:org/qa-toolkit.git

# 2. Install the plugin at project scope
/plugin install qa@qa-toolkit --scope project

# 3. Stamp the runtime substrate into THIS project + install deps
/qa:init
```

Then **edit `.env`** — set `BASE_URL_APP` to a real **staging/QA** host (never a prod
host — a prod-guard fails *closed* until you replace the shipped `CHANGEME`
placeholder) and fill `QA_USER_*` credentials. Then:

**Fast lane** (a first test today):

```bash
/qa:explore                  # build specs/_context/app.context.md (first run: DRAFT — confirm it)
/qa:new-spec auth/login      # draft a spec
/qa:gen specs/auth/login.md  # compile spec → tests/auth/login.spec.ts, run it green
/qa:review                   # reviewer gates the assertion contract (every PR)
/qa:run mode=smoke                # run the @smoke suite (no LLM)
```

**Rigor lane** (P1 / money / compliance): insert `/qa:intake` → `/qa:ideate` →
`/qa:approve` between explore and new-spec — it pins *what correct means* before
anything is generated. **Right-sizing:** the fast lane skips no FAIL-level gate
(Check 14 / coverage only WARN), so use it for everything that isn't P1/money/compliance.

Running the suite = `npx playwright test` — plain Playwright, zero LLM.

**Local plugin development** (no marketplace): `claude --plugin-dir ./qa`, then
`/reload-plugins` after edits. **Validate before pushing:**
`claude plugin validate --strict ./qa` (passes clean in versioned mode — verified; the
former "drop `--strict`" advice applied only while `version` was omitted).

> **Versioning note.** The plugin ships in **versioned mode** — `plugin.json` carries an
> explicit `version`, which per the plugins reference *pins the plugin to that version
> string, so users only receive updates when you bump it.* **Bump it in the same commit as
> every user-visible change**: pushing without bumping ships nothing and reports no error.
> To switch to commit-SHA mode instead, delete the `version` key — Claude Code then falls
> back to the git SHA and every push counts as a new version. See README §Versioning.

---

## 6. The workflow, end to end

```
/qa:init                         once per project — stamp substrate, then edit .env
   │
   ▼
/qa:explore                      HOT tier  → specs/_context/app.context.md
/qa:explore mode=area …          AREA tier → specs/_context/<site>/<area>.md
   │                             (area file REQUIRED before /qa:intake)
   │   ── decide WHAT to test (optional but intended) ──
/qa:intake  <area/feature>       interview → <feature>.basis.md  (pins the ORACLE)
                                 ↳ consults business_sources: (if declared) to ground rules + stamp provenance; runs a multi-channel coupling sweep; asks you on source-vs-app conflict
/qa:ideate  <area/feature>       SFDIPOT checklist → <feature>.cases.md
/qa:approve <area/feature>       ↑ a HUMAN approves / prunes (mandatory gate);
   │                             /qa:approve records the verdict + mints stable row ids
   │   ── build the tests ──
/qa:new-spec <area/feature>      planner   → specs/<area>/<feature>.md (+ YAML oracle)
/qa:gen      specs/<area>/<f>.md generator → tests/<area>/<feature>.spec.ts, runs green
   │
   ▼
/qa:review   [spec-or-diff]      reviewer  → BLOCKS green-but-empty/-wrong tests
   │                             (the load-bearing gate — run on every PR)
   ▼
/qa:run mode=smoke                    run @smoke suite (no LLM)
   │   on failure
   ▼
/qa:heal <test-id>               triage from trace; patch selectors/waits, NOT assertions
   │
   ▼
/qa:report                       aggregate run + audits → PR/Slack-ready summary
```

**Side branches (quality probes, not in the build line):** `/qa:review url=<url>`,
`/qa:run mode=repeat <spec> [N]`, `/qa:impact route=…|field=…|factory=…|area=…|operation=…|source=…`,
`/qa:doctor`, `/qa:coverage`, `/qa:batch-fix <filter>`, `/qa:run mode=single <spec>`,
`/qa:import-cases`, `/qa:retire`.

**Two lanes through this chart.** The **fast lane** (explore → new-spec → gen →
review → run mode=smoke) gets a first test running today; the **rigor lane** inserts
`/qa:intake` → `/qa:ideate` → `/qa:approve` between explore and new-spec for
P1/money/compliance features — it pins *what correct means* before anything is
generated. The fast lane skips no FAIL-level gate (Check 14 / coverage only WARN).

**How an idea becomes a test (the lineage).** An **example** is a concrete
input→result seed captured in the feature's `.basis.md` at intake. `/qa:ideate` fans
examples (plus the SFDIPOT lenses) out into **cases** — checklist rows in `.cases.md`
that a human approves or prunes (`/qa:approve` records it). The planner scopes
approved cases into **scenarios** — entries inside one spec's YAML block, each
carrying its own oracle. The generator compiles the spec's scenarios into the runnable
**test**; reviewer Check 14 warns when an approved case reached no scenario and no
waiver.

**Start here when red:**

- **One test red** → `/qa:heal <test-id>` — triage from the trace; patches
  selectors/waits only, never assertions.
- **Many tests red with the same signature** → `/qa:report` to cluster by failure
  signature, then `/qa:batch-fix <filter>` for one shared pattern.
- **Red only sometimes** → `/qa:run mode=repeat <spec> [N]` — pass-rate over N repeats;
  quarantine below 95%.
- **Red right after an app change/deploy** → `/qa:impact route=…|field=…|…` to scope
  the blast radius; `/qa:explore mode=area …` if the area context is stale.
- **Everything red / infra-looking** → check `.env` and the prod-guard first, then
  `/qa:doctor` (env, pins, substrate drift).
- **After fixing** → `/qa:run mode=smoke` to re-establish the run-of-record, then `/qa:report`
  for the shareable summary.

---

## 6.1 Brownfield adoption

Adopting the toolkit on an app that already exists (and probably already has *some*
suite) is the common case. The playbook:

1. **Don't backfill everything** — coverage is triaged, not completed.
2. **`/qa:explore`** (hot) → enumerate areas.
3. **Risk-rank** (money / auth / the 2am-page flow); pick **ONE** P1 area.
4. **P1 area first, full rigor chain** (explore area → intake → ideate → approve →
   new-spec → gen), happy path `@smoke`.
5. **Park the legacy suite at `tests-legacy/`** (outside `testDir` — keeps running
   however it ran; a fallback, not a gate) and record `covered_by: legacy:` in each
   covered feature's basis so coverage shows LEGACY-with-caveat, not a false gap.
6. **Pin unspecifiable behavior with `kind: characterization`** — provisional pins
   with an upgrade path, not fake intent.
7. **Expand area-by-area in risk order**; `/qa:coverage` is the backlog, not a grade.
8. **Nightly from day one** — even 5 smoke tests replayed at $0 beat a plan.

---

## 7. Command reference

All commands are namespaced `/qa:`. "Delegates to" names the subagent or skill that
does the work; "—" means it runs inline in the main session.

Every one of these is a **skill** at `qa/skills/<name>/SKILL.md` — upstream merged custom
slash commands into skills, and this plugin uses the skill layout exclusively (a `commands/`
directory reappearing fails the toolkit's own `bin/qa-selfcheck`, Check 9d). You type them exactly as before;
nothing about the `/qa:` names changed.

What *is* new is that each skill declares **who may invoke it** — see
`reference/DESIGN.md` §"Why the invocation policy is what it is" for the reasoning:

- **You only** — anything with side effects (`init`, `gen`, `new-spec`, `heal`, `batch-fix`,
  `retire`, `approve`, `run`, `import-cases`, `intake`,
  `ideate`). Claude will not run these on its own. `/qa:approve` is the load-bearing case:
  it stamps the human-approval banner, so a model able to invoke it could rubber-stamp its
  own test plan.
- **You or Claude** — the read-only ones (`help`, `review`, `coverage`, `doctor`,
  `impact`, `report`, `explore`). `/qa:explore` in particular MUST stay reachable by Claude:
  the planner and healer stop on stale context and rely on the orchestrator re-running it.
  `metamorphic-relations` is also here even though it writes twin specs: the verifier
  applies it on every new spec during `/qa:gen`.
- **Runs in its own subagent** (`coverage`, `doctor`, `impact`, `report`) — the heavy
  read-only passes, so their working output stays out of your session.

| Command | Argument hint | Does | Delegates to |
|---|---|---|---|
| **`/qa:init`** | `[--no-install] \| [--resync]` | Bootstrap the runtime substrate (configs, scripts, fixtures, `CLAUDE.md`, permissions) + install deps. Idempotent, never clobbers. `--resync` force-refreshes toolkit-owned files (backing up to `.qa-bak`). **Run once, first.** | `bin/qa-scaffold` |
| **`/qa:explore`** | `[mode=hot \| mode=area site=<id> area=<name>]` | Build the context layer. `mode=hot` refreshes `app.context.md`; `mode=area` writes one `<site>/<area>.md`. Never caches selectors. | **exploration** |
| **`/qa:intake`** | `<area/feature> [kind=…] [site=<id>]` | Interactive interview capturing the **test basis** — auto-gathers observable context, asks only about non-observable intent (the oracle) → `.basis.md`. If `app.context.md` declares `business_sources:`, **consults them to ground each rule + stamp provenance** and runs a **multi-channel coupling sweep**; asks the operator on a source-vs-app conflict. | — (interactive) |
| **`/qa:ideate`** | `<area/feature> [site=<id>]` | Enumerate candidate test cases (SFDIPOT fan-out, de-dup, risk-rank, completeness critic) → `.cases.md` checklist. **Never writes specs/tests.** | **ideation** |
| **`/qa:approve`** | `<area/feature>` | Record the human verdict on a `.cases.md` checklist — approve/prune/defer per row, stamp the approval banner, mint stable row ids (the traceability anchor for Check 14 and TCM export). Closes by printing the **literal `/qa:new-spec` command per approved group** (slug derived from the group subject) rather than the naming rule — that hand-off is where the chain historically tripped people. | — (interactive) |
| **`/qa:import-cases`** | `<area/feature> [source=<name>] [<file>]` | Import an existing manual test-case suite (CSV/TCM export) as `.cases.md` rows with `[imported:]` provenance; import-once, the external id becomes the row id. | — |
| **`/qa:retire`** | `<area/feature>` | Retire a feature coherently — a dry-run plan of every linked artifact (spec, test, twins, route manifest, basis/cases), shared page-objects/fixtures deleted only when nothing else uses them, then `tsc` + `--list` verification. Git history is the archive. | — |
| **`/qa:new-spec`** | `<area/feature>` | Draft one feature's Markdown spec with a closed-vocab YAML oracle → `specs/<area>/<feature>.md`. **Never emits `.spec.ts`.** | **planner** |
| **`/qa:gen`** | `<spec-path or area/feature>` | Compile a spec → `tests/<area>/<feature>.spec.ts`; run it once and leave it green for the caller to commit. Keeps a confirmation `.webm` on new specs. | **generator** |
| **`/qa:review`** | `[spec-or-path — default: working diff]` | Run the **load-bearing reviewer** over the diff (or a named path). The shipped trigger for the full assertion-contract check suite. Any FAIL blocks the PR. Read-only. | **reviewer** |
| **`/qa:run mode=smoke`** | *(none)* | Run the `@smoke` suite, print a pass/fail summary. Sets `QA_RUN_OF_RECORD=1` so it refreshes `last-run.json`. No LLM, no auto-heal. | — |
| **`/qa:run mode=single`** | `<spec-path-or-test-path>` | CI-shaped single-shot run of one spec → `reports/headless-<name>.json`. Does **not** refresh `last-run.json`. | — |
| **`/qa:heal`** | `<failing-test-id>` | Triage one failing test from its trace; patch **selectors/waits only, never assertions**; file a `bugs/*.md` on a product defect. | **healer** |
| **`/qa:batch-fix`** | `<path-or-filter>` | Apply ONE healer pattern across every failing test matching a Playwright filter. **Proposes the pattern and waits for confirmation** (high blast radius). | **healer** |
| **`/qa:run mode=repeat`** | `<spec> [N]` | Repeat one spec N times (default 10) back-to-back → `artifacts/flake-<name>.json`; report pass rate; recommend `@quarantine` if <95%. Diagnostic only. | — |
| **`/qa:run mode=changed`** | `[<git-ref>]` | PR-speed lane via Playwright `--only-changed`: runs changed test files plus every test importing a changed file (bare = uncommitted work; a ref = diff against it). Lists edited `specs/*.md` it cannot select (stale until `/qa:gen`). Never refreshes `last-run.json`; `NOTHING SELECTED` is not a pass. | — |
| **`/qa:metamorphic-relations`** | `<parent-spec-path>` | Generate 2–3 metamorphic "twin" specs of a passing `.spec.ts` by hand. The verifier already does this for every new spec during `/qa:gen`; use this to harden an existing critical flow. | — |
| **`/qa:impact`** | `route=… \| field=… \| factory=… \| area=… \| source=… \| operation=…` | List every spec affected by a change to a route/field/factory/area — or, via `source=`/`operation=`, to a business source / seed operation. Reads `artifacts/route-manifests/`. Read-only. | — |
| **`/qa:review url=<url>`** | `url=<url> [site=<id>]` | Full a11y + visual + closed-vocab audit of a URL → `reports/audit-<ts>.md`. Direct snapshot, no exploration. Also drives the page's documented **error/failure states** (invalid-submit alert, opened menu/modal) before the axe scan — a state-dependent violation (a low-contrast error alert) never renders in the pristine default state. | **reviewer** + **axe-a11y** + **visual-regression** |
| **`/qa:report`** | *(none)* | Aggregate `last-run.json` + `reports/*.json` → PR/Slack summary → `reports/summary.md`. Pure aggregation, reruns nothing. Leads with the run **scope** read from the record (`--grep @smoke` → "N smoke tests"), so a green smoke subset is never presented as full-suite green — then a **qualified go/no-go verdict** that must stay qualified while any `bugs/*.md` is open, an audit reported violations, or the scope could not be established. Also surfaces passed-with-retries (flaky ≠ passing), a11y/visual audit headlines, and the running value ledger. | — (self-contained) |
| **`/qa:coverage`** | `[area=<name>] [site=<id>]` | Honest **requirement/assertion/lens/flow/case/a11y-need** coverage (NOT line coverage), computed statically across 9 dimensions (0–6 plus 1b and 5b) — incl. dim-0 (route plan vs actual footprint), **dim-1b spec-without-test** (an authored spec never compiled, invisible to the smoke gate/doctor/impact), **dim-5b waiver destinations** (an approved case fanned to a sibling spec that must exist), and dim-6 (declared-a11y-need → oracle). **WARN-only, names gaps, not a %** — but a bogus `area=` that matches nothing now errors (a `site=` typo warns and degrades — basis files are optional) instead of rendering a false gap-free report. | — |
| **`/qa:doctor`** | `[--verify-invariants specs/<f>.md]` | Read-only health check (script-extracted, checks 0–21): freshness / zero-test / vocab-drift / smoke-tag (vacuous gate **and** smoke-tagged-spec-with-no-test) / spec-with-no-compiled-test (any tag) / abandoned authoring chain (`.cases.md` with no spec) / unattested interview (`[human-answered]` basis with no `interview:` count) / bug Status + durable-evidence / staleness / pin+lockfile / prod-guard-lockstep / substrate-drift and more. `--verify-invariants` proves each `must_fail_when` is executable. | — |
| **`/qa:help`** | `["free-form question" \| <area/feature>]` | Ask anything about the plugin, or "what's next" — inspects your project state to give a situated answer with the exact next command. Pass an `<area>/<feature>` (e.g. `/qa:help checkout/coupon`) to scope the "what's next" read to **one feature** — it resolves that feature's basis → cases → spec → test and names the single next command with the path filled in, instead of walking project-wide state. Read-only. | — |

---

## 8. Agent reference

The seven subagents are the "brain." Each has a narrow role, a fixed tool set, and a
strict writable-path boundary. **None can spawn another** — handoffs route through the
orchestrator (which is why `/qa:gen` is two separate calls: `generator`, then `verifier`).
**Every agent pins an explicit `model:` in its frontmatter** — the tiers below are enforced,
not operator guidance; `CLAUDE.md`'s "Subagent roster" mirrors them.

| Agent | Suggested model | Role | Triggered by | Writes to |
|---|---|---|---|---|
| **exploration** | `model: sonnet` (pinned) + CLI | Build the context layer — hot tier (`app.context.md`) or one area file. Captures **domain vocabulary, never selectors**. | `/qa:explore`; healer sentinel | `specs/_context/**` |
| **ideation** | `model: opus` (pinned) | Enumerate candidate test cases via SFDIPOT lenses → a checklist. **The human is the gate.** | `/qa:ideate` | `specs/**` (`.cases.md`) |
| **planner** | `model: opus` (pinned — it authors the oracle, and nothing downstream compares an oracle to reality) + CLI | Translate a story/bug into one spec + YAML oracle. **Owns the assertion contract.** | `/qa:new-spec` | `specs/**` |
| **generator** | `model: sonnet` (pinned) + CLI | Compile spec → deterministic `.spec.ts`, run it once to green, hand off. **Does not grade its own output.** Runs **serially in the main working tree**. | `/qa:gen` (1st of 2) | `tests/**`, `page-objects/**`, `fixtures/**`, `bugs/**` |
| **verifier** | `model: opus` (pinned — a wrong CATCHES verdict produces no red test, only a `// verified:` comment Check 2b trusts) | Grade the generator's green, as an agent that did **not** write it: author the metamorphic twins, fault-inject each declared `must_fail_when` to prove the `expect` goes RED (CATCHES vs BLIND), rename scenarios that overclaim, keep the confirmation `.webm`, and emit the route manifest only once all of that is clear. **May not edit any `expect(...)`.** | `/qa:gen` (2nd of 2) | `tests/**` (twins + annotations), `bugs/**`, `artifacts/route-manifests/**` |
| **reviewer** | `model: opus` (pinned — Checks 2b/2c/2d/2e/14 are LLM judgment and this is the sole assertion-contract gate) | **Read-only PR gatekeeper.** Blocks green-but-empty / -under-asserted / -wrong tests via its full check suite. The sole *judgment* enforcement of the assertion contract; the two `PreToolUse` hooks are a floor, not a gate ([§11](#11-the-oracle-defenses)). | `/qa:review` (both modes) | *nothing (read-only)* |
| **healer** | `model: sonnet` (pinned) + MCP | Triage a failure into one of **10 buckets**; patch selectors/waits or file a bug. **Never touches assertions.** Logs every triage to `artifacts/heal-log.jsonl`. | `/qa:heal`, `/qa:batch-fix`, CI failure | `tests/**`, `page-objects/**`, `bugs/**`, `artifacts/heal-log.jsonl`, `artifacts/.healer-needs-*` |

### 8.1 planner — owns the assertion contract

Reads the user story + `app.context.md` (+ the area file, or **STOPs** and hands off
if it's missing/stale — it cannot spawn exploration itself). Emits **one** Markdown
spec with a fenced YAML **oracle** block drawn from the [16-key closed
vocabulary](#10-the-closed-oracle-vocabulary). Lifts "broken-when" prose into a
`must_fail_when:` list. Never writes `.spec.ts`, never writes password literals
(always `password_env`), never targets production. Tools: `Bash, Read, Write`.

### 8.2 generator + verifier — compiles, then proves the test

`/qa:gen` is two subagent calls. The **generator** reads the spec, resolves the site,
takes a **live AX snapshot for every route** (this is where selectors come from — never
from source), reuses existing page objects, and writes the `.spec.ts` in one pass. Then
it **runs the test once** and hands the green result to the verifier. It does not grade
its own output.

**8 hard rules** the reviewer enforces on the generator: only the 7 `getBy*` locator
factories (no XPath/CSS); auto-waiting assertions only (never `waitForTimeout` /
`networkidle`); ≥1 failable `expect()` per oracle item with no orphans; prefer
`toMatchAriaSnapshot()` for structural oracles; wrap each step in a real `test.step`;
no logging of secrets; STOP if the spec exceeds ~250 LOC; no `expect(true).toBe(true)`
and no unlinked `test.fixme/skip`. Tools: `Bash, Read, Write, Edit, Skill`.

The **verifier** did not write the test, and grades it:

- **8a** authors 2–3 metamorphic "twin" specs (new specs only),
- **8b** **fault-injects** each declared `must_fail_when:` to prove the oracle
  actually goes red on the defect (a BLIND oracle → STOP + escalate),
- **8c** renames a scenario for what its oracle can actually prove,
- **8d** keeps a confirmation `.webm` (`QA_KEEP_VIDEO=1`) for a human to watch,
- emits a route manifest (routes/fields/factories) for `/qa:impact`.

It **may not edit any `expect(...)`** in the parent spec — a `PreToolUse` hook denies it.
Tools: `Bash, Read, Write, Edit, Skill`.

### 8.3 healer — the only thing invoked on failure

Reads the trace under `artifacts/test-results/<id>/`, classifies the failure into
**one of 10 buckets**, and patches minimally *or* files a bug and reverts. When it files a
bug it **copies the trace/screenshot into a durable `bugs/<slug>/` folder** and cites that —
not the volatile `test-results/<id>/` paths, which the next green run overwrites (HEAL03) — and
when it finds an already-green test whose bug is still `open`, it **reconciles the bug to `fixed`**
(HEAL04). `/qa:doctor` Check 11b backstops both — and **Check 11c** cross-checks every parked `test.fail`/`test.fixme` marker in `tests/` against its linked bug's `Status`, flagging a live marker on a `fixed`/`reverted` bug (a resolved defect laundered green). This is what forces marker cleanup, since the P-14 conditional park self-neutralizes silently when the app is fixed:

| # | Bucket | Action |
|---|---|---|
| 1 | broken-locator | patch selector (behavior unchanged) |
| 2 | missing-wait | add a web-first assertion timeout (never a sleep) |
| 3 | changed-text | **oracle concern** → `.healer-needs-spec-update` sentinel, escalate to planner |
| 4 | stale-context | `.healer-needs-exploration` sentinel |
| 5 | auth-stale | `.healer-needs-seed` sentinel |
| 6 | data-drift | `.healer-needs-data` sentinel |
| 7 | env-infra | file `bugs/…-infra-….md`, revert |
| 8 | contract-change | `.healer-needs-migrate` sentinel |
| 9 | expected-failure | leave it red — do not patch/silence a live `must_fail_when` |
| 10 | product-bug | file `bugs/…` + park with a conditional `test.fail(<observed>===<buggy>, 'bugs/…')` (or `test.fixme(true, 'bugs/…')` if it can't execute) — P-14; keep the bug `Status: open` while the marker lives |

**Anti-drift rule (verbatim): "Never change the assertion contract — only
selectors/waits."** It is the only agent with Playwright **MCP** `browser_*` tools
(for interactive triage). Turn budget: 5. Tools: `Bash, Read, Write` + Playwright MCP.

### 8.4 reviewer — the load-bearing gate

Read-only. For each new/modified `.spec.ts` (plus its spec and every imported page
object) it runs a battery of deterministic checks. **Any FAIL blocks the PR**;
Checks 2c/2e/7/12/14/15 are WARN-level. Check numbering is frozen — new checks append
(14, 15, …) or sub-letter (2b–2e); existing numbers are never reused or renumbered.

| Check | Level | Catches |
|---|---|---|
| 1 — failable expect | FAIL | a test with no `expect()` that can fail |
| 2 — step→assertion coverage | FAIL | steps performed but nothing asserted (green-but-empty) |
| 2b — `must_fail_when` reified-or-waived | FAIL | a declared invariant that isn't an oracle key or an explicit waiver |
| 2c — oracle discriminating-power | WARN | a valid but non-discriminating key (`text_visible` where intent needs `count_equals`) |
| 2d — oracle **value fidelity** | FAIL | right key, wrong value (green-but-**wrong**) |
| 2e — equality-invariant **precondition scope** | WARN | an equality/relational oracle asserted with no `invariant_holds_when:` domain, or pinned `data:` outside it (green-but-**over-broad**) |
| 3 — no unlinked `test.fixme/skip/fail` | FAIL | a parked test with no `bugs/` link, **or a link to a non-`open` bug** (stale marker laundering a resolved defect); prefer the conditional `test.fail(<observed>===<buggy>)` park — WARN on an unconditional `test.fail(true)` lacking a `// park: unconditional` note (P-14) |
| 4 — closed oracle vocabulary | FAIL | an off-vocab key or wrong argument shape |
| 5 — no `waitForTimeout` / `networkidle` | FAIL | banned waits (in tests **and** page objects) |
| 6 — metamorphic twins exist + agree | FAIL | new spec with no twins, or a twin that disagrees (a fully-skipped twin run — no `BASE_URL` — is reported SKIPPED, never a vacuous PASS) |
| 7 — context freshness | WARN | a stale or `draft:`/`REVIEW:`-banner context file |
| 8 — site validity | FAIL | a `site:` that isn't a declared `sites[].id` |
| 9 — locator policy | FAIL | XPath/CSS or chained `.locator('css')` |
| 10 — factory enforcement | FAIL | an entity with a factory not using the `factory:` form |
| 11 — hygiene | FAIL | `.only()`, hardcoded creds, inline base URLs, missing smoke/regression tag |
| 12 — POM abstraction sanity | WARN | over- or under-abstraction of page objects |
| 13 — parallel-safety | FAIL | a state-mutating spec without worker isolation / `mode: 'serial'`; **also the cross-feature case** — one spec mutates a shared *seed* entity (deactivates/deletes a seeded user) that another spec depends on as a fixture/owner (per-feature-green, combined-`npx playwright test`-red) |
| 14 — approved-case traceability | WARN | an approved `.cases.md` case with no scenario and no waiver (green-but-**incomplete**) — **also** a `# waived: … → specs/x.md` whose destination spec does not exist (phantom coverage: the case is unbuilt AND its stated home is missing) |
| 15 — healed-locator drift | WARN | a heal that broadened a locator (`.first()`/`getByText` downgrade) — diff-aware; with no git baseline, falls back to a stale-testid full-scan (a spec/`_context` `getByTestId('X')` **used as an assertion/locator** whose `X` no POM/test uses — the healed-but-not-back-propagated case; testids that appear only inside a `stable_testids:` hint catalog are excluded — a deliberately-shunned hint is not drift) |

Fail-closed on inconclusive runs. Escape hatch: a `// reviewer-skip-check-<N>:
bugs/…` comment. Tools: `Read, Bash` (read-only by contract).

### 8.5 exploration — the context builder

Two modes, one artifact per run. **Hot mode** *verifies* the human-owned
`app.context.md` (sites, auth, env, naming) against a live snapshot and refreshes
`last_verified:`; it never invents authoritative `sites[]`. **Area mode**
authenticates, walks *only* that area's routes (depth-2 BFS, no full crawl), snapshots
the AX tree for **domain vocabulary** (not selectors), records stable `data-testid`s
as grey-box hints, and writes a dated `<site>/<area>.md` with a `volatility:` tier.
Discipline: an inaccurate-but-fresh file is worse than a stale one. Tools: `Bash,
Read, Write`.

### 8.6 ideation — enumerate what to test

Reads a feature's `.basis.md` and rotates through the full **SFDIPOT** lenses
(Structure / Function / Data / Interfaces / Platform / Operations / Time +
error-guessing), de-dups, risk-ranks (NIST interaction strength + RCRCRC
change-proximity), runs a completeness critic, and writes a **`.cases.md` checklist
for a human to approve or prune**. Routes on `kind:` (feature | enhancement | bug |
refactor). **Never writes specs or tests.** Tools: `Read, Bash, Write`.

---

## 9. Skill reference

Skills are capability helpers agents call (mostly auto-invoked via Bash). Only one is
directly slash-callable.

| Skill | Adds | Invoked by | Slash-callable? |
|---|---|---|---|
| **playwright-cli** | Token-predictable browser driving (`npx playwright-cli`) — the engine under the healer, generator, and suite runs. Adds the CLI-vs-MCP decision rules + session hygiene. | auto (healer, generator, runs) | no |
| **test-data-seed** | Worker-scoped, API-seeded, teardown-by-tag fixtures that stay parallel-safe at 10+ workers (keyed on `workerInfo.parallelIndex`), plus a pluggable seed adapter. | auto (generator authoring) | no |
| **axe-a11y** | Drop-in `@axe-core/playwright` WCAG scanning per UI **state** (not per page), plus an adversarial-pair pattern to prove the detector is live. | auto; `/qa:review url=` | no |
| **visual-regression** | `toHaveScreenshot()` layout/CSS/typography oracle with mandatory stable-state waits (`document.fonts.ready`, `reducedMotion`, masking). | `/qa:review url=`; otherwise on request in the main session. Not reachable from a spec — no oracle key requests a screenshot. | no |
| **metamorphic-relations** | Generate 2–3 invariant-preserving "twin" specs (`@metamorphic`+`@regression`, never `@smoke`) that catch spec drift plain assertions miss. **Authored by the verifier**; the reviewer only verifies they exist and agree. | verifier; reviewer; `/qa:review url=`; human | **yes** |

---

## 10. The closed oracle vocabulary

Every assertion in a spec must use one of **exactly 16 keys**. This is the primary
structural defense: an assertion cannot be free-form prose ("should look right" is
unfalsifiable), so every assertion means something a reviewer can mechanically check.
An agent **cannot invent a new key** — the reviewer's Check 4 FAILs an off-vocab key.

Two things a spec writes are **not** oracle keys and are not counted among the 16: the
`steps:` **situation forms** `fault:` (stub one network dependency) and `clock:` (control
fake time), which make the Interfaces/Operations and Time test-design lenses authorable.
They set up the situation; the 16 keys above still do all the asserting. A response-faking
`fault:` must be paired with a `network_response_status` oracle on the injected status —
that pairing is its *fired-proof*, because a stub whose URL glob matches nothing is silent
and would let every other assertion pass for the wrong reason.

| # | Key | Argument shape |
|---|---|---|
| 1 | `text_visible` | `"<string>"` |
| 2 | `url_matches` | `"<regex-or-literal>"` |
| 3 | `count_equals` | `{ locator, n }` |
| 4 | `value_between` | `{ locator, range: [min, max] }` |
| 5 | `error_shown` | `"<string>"` (exact) |
| 6 | `no_order_created` | `<bool>` |
| 7 | `attribute_equals` | `{ locator, attr, value }` |
| 8 | `element_state` | `{ locator, state }` |
| 9 | `network_response_status` | `{ url, status }` |
| 10 | `response_body_contains` | `{ url, text }` |
| 11 | `download_received` | `{ filename?, min_bytes? }` |
| 12 | `clipboard_contains` | `"<string>"` |
| 13 | `storage_state` | `{ cookies?, localStorage? }` (camelCase; `"<non-null>"`→truthy, `"<null>"`→falsy) |
| 14 | `upload_accepted` | `{ selector_role, name }` |
| 15 | `dialog_dismissed` | `{ type: 'confirm'\|'alert'\|'prompt', accept? }` |
| 16 | `a11y_violations_below` | `{ max_critical, max_serious }` |

> **Deliberate gap:** there is **no** relational / exact-equality key (`value_equals`).
> `value_between` only bounds one number against constants. This is intentional (a
> relational key the reviewer couldn't structurally validate would weaken the
> closed-vocab guarantee). Sanctioned workarounds and the recipe for adding a 17th key
> are documented in the stamped `templates/CLAUDE.md`.

**Maintenance:** this exact set is *mirrored* across `planner.md`, `generator.md`,
reviewer Check 4, `scripts/oracle-keys.txt`, and `/qa:coverage`'s `KEYS_RE`
(`/qa:new-spec` and `/qa:review url=` **defer** to the stamped CLAUDE.md and hold no list —
nothing to edit there). Adding or removing a key means editing **all** enumerating
mirrors in one commit (see [§20](#20-for-maintainers-where-each-fact-lives)).

---

## 11. The oracle defenses

The most dangerous failure is **not** a flaky test. It is a test that stays **green
while no longer testing what it claims** — the "green-but-empty" or silent false pass.
LLM-authored tests are especially prone to it (an agent will happily find a new UI path
that turns green, quietly weaken an assertion, or write `expect(true).toBe(true)`).
Every defense below answers *that* problem:

- **Closed oracle vocabulary** — assertions can't be free-form ([§10](#10-the-closed-oracle-vocabulary)).
- **Step→assertion coverage** — every step must carry a real, failable `expect()`;
  the cheapest way to fake a passing test is to perform steps and assert nothing.
- **Assert intent, not observed behavior** — the oracle encodes what *correct* means
  (captured at intake as the test basis), not what the app happens to do today.
  Encoding observed behavior bakes today's bug in as tomorrow's expected result. This
  is why the assertion contract is **owned by the planner and is sacred**: the healer
  may fix selectors and waits but must **never** touch assertions; a changed-text
  failure escalates back to the planner.
- **`must_fail_when:` + negative-control injection** — a declared "broken-when"
  invariant is fault-injected by the generator (step 8b) to prove the oracle *actually*
  goes red; a BLIND oracle blocks. Re-runnable via `/qa:doctor --verify-invariants`.
- **Metamorphic relations** — a check needing no ground-truth answer: instead of "is
  this output correct?" they ask "does an invariant-preserving transform of the input
  keep the output equal?" (reorder a cart → total unchanged). Well-suited to
  LLM-authored oracles, which can't be trusted to know the right answer but *can* be
  trusted to preserve an invariant.
- **Structured output schema** — `passed=true` must be backed by populated evidence
  fields (order id, observed total), so it isn't a word the agent can just emit.
  (Convention — not mechanically validated; see CLAUDE.md §"Oracle defense".)
- **The reviewer is still the backstop, by discipline** — but two of the contracts it
  backstops are now also enforced at write time. The `hooks/` layer (2026-09-20) denies
  the four *lexical* reviewer FAILs (assert-on-a-literal, `waitForTimeout`/`networkidle`,
  raw CSS/XPath, `.only`) and — the one that matters — denies the **healer** and the
  **verifier** any edit that removes or rewrites an existing assertion. A check earns a
  hook only if it is decidable from the proposed text alone; everything needing repository
  state or judgment stays with the reviewer, which is most of it. **Keep it on a capable
  model.** See `qa/hooks/README.md`.

---

## 12. Three-tier context

Selectors drift faster than any document can be regenerated, so a single long-lived
selector catalog becomes a "God Object" that is confidently wrong past ~100 routes.
Context is split by **volatility**, not stuffed into one file:

| Tier | File | Contents | Lifetime |
|---|---|---|---|
| **Hot** | `specs/_context/app.context.md` | Durable facts: sites, auth, env vars, naming. Always loaded. Human-owned; exploration only *verifies*. | Long-lived (~80 lines) |
| **Area** | `specs/_context/<site>/<area>.md` | Per-(site, area) domain vocabulary, routes, exact error/success strings, `stable_testids` hints, known-flaky surfaces. Dated, carries a `volatility:` tier. | Medium (~150 lines) |
| **Cold** | *(none — live AX tree)* | Selectors, pulled live at generate/heal time. **Never cached in a doc.** | Ephemeral |

**Staleness is volatility-tiered, not a flat interval** (critical 7 days / reference 30
/ stable 90). A single uniform threshold over-warns on stable surfaces and under-warns
on volatile ones (an auth/payments area would drift three weeks past when it should
re-warn under a flat 30-day rule).

**Optional business-source grounding (the gather phase).** The three tiers hold the app's
*observable structure*; **business truth** ("what correct means", why areas couple) is
grounded separately. `app.context.md` may declare an optional, **source-agnostic**
`business_sources:` block — a named `doc` / `url` / `api-spec` / `tracker` / `human` (deliberately
**not** wiki-locked). `/qa:intake` consults it to ground each 🔵 oracle rule, stamps each rule's
**provenance** (`grounded[src]` / `human-answered` / `not-in-source` / `contradicted` — pre-RS
source traceability), and runs a **multi-channel coupling sweep** (shared-data / cross-surface-aggregate
/ state-gate / cross-actor / config-flag — a reconciled-heuristic subset of coupling +
requirements-interdependency taxonomies) recorded as `couples_with:`. This is the RAG-grounding +
traceability defense against *grounded-but-incomplete* oracles and silent cross-area couplings.
On a **source-vs-app contradiction**, an unreachable/gated source, or a source silent on a needed
rule, intake **asks the operator** — it never guesses. Honest limits: it reads local files / fetches
reachable URLs / asks (it cannot crawl a gated wiki); grounding + coupling are aids, not completeness
guarantees; all of it is WARN/advisory. Omit `business_sources:` → grounding falls back to the
interview + live app (the default). Related: reviewer **Check 2e** (WARN) scopes equality/relational
invariants to a declared `invariant_holds_when:` precondition domain (Design-by-Contract).

---

## 13. CLI vs MCP

The toolkit uses **`@playwright/cli`** as the default transport for the healer,
generator, and nightly runs, and reaches for **Playwright MCP** (bundled with
Playwright 1.62+ via `npx playwright mcp`; the standalone `@playwright/mcp`
package is legacy) only for first-contact exploration and interactive healing. The reasoning is narrower than "CLI
is cheaper" (which is **not** true):

- **CLI wins on predictability and hygiene** — tiny tool-schema overhead (~68 tokens
  vs MCP's ~3,600–4,200 always-loaded), near-flat context across many steps, and no
  MCP-style idle memory growth / orphaned-process leaks. Across 100+ nightly tests
  that compounds.
- **MCP wins on wall-clock and, with prompt caching, on billed $/test** (the "~28% cheaper
  per test, ~2–3× faster per 10-step flow" figures are illustrative/unverified internal estimates,
  not a sourced benchmark — and cut against the published finding that the CLI is ~4–10× cheaper in
  tokens, so treat them as directional). "CLI always wins" is wrong on wall-clock.
- **MCP's live AX tree is genuinely better for first contact**, when the agent knows
  nothing about the app.

This is implemented with a **two-config pattern**: the default `.mcp.json` is empty
`{}` (so plain runs pay no MCP token cost), and `.mcp.explore.json` registers the
Playwright MCP server for the explore/heal sessions that actually need it.

---

## 14. The page-object reuse layer

Shared UI flows live in an AI-maintained **page-object (POM)** layer under
`page-objects/`, exposed to tests through the `fixtures/test.ts` barrel. Because a
flow lives in one place, a UI change is a **one-file fix** the healer applies once for
every test that uses it.

- Page objects use **semantic locators only** (the `getBy*` factories), live-validated
  before being centralized.
- The **generator** creates/updates page objects during authoring; the **healer** owns
  edits during maintenance (and re-runs every consumer on a POM edit).
- **Earn the abstraction:** promote on first write for inherently-reusable flows
  (login), otherwise after 2–3 appearances. The reviewer's Check 12 WARNs on both
  over-abstraction (single-use) and under-abstraction (a locator-set duplicated across
  ≥2 files that should be promoted).

---

## 15. Safety rails

- **Never point `BASE_URL_*` at a prod host.** Two guards enforce it:
  1. **`scripts/prod-guard.sh`** — an advisory, agent-run shell guard on every
     explore/audit/run command. Screens every `BASE_URL_*`, strips scheme/userinfo/port,
     word-boundary-matches `prod`/`production`.
  2. **`scripts/prod-guard.ts`** — an **enforced** Playwright `globalSetup` that
     **throws before any browser opens**, so even a bare `npx playwright test` is
     protected.
  Both **fail CLOSED** on an empty or placeholder host — the shipped `.env.example`
  ships `BASE_URL_APP=CHANGEME`, so the guard REFUSES until you set a real target (a
  green guard against a host you never chose is worse than a STOP). `QA_ALLOW_PROD=1`
  overrides the prod-marker check ONLY, in both layers — placeholder/empty-target
  refusals have no env escape (the fix is editing `.env`). Their marker regexes must
  stay in lockstep (`/qa:doctor` checks this).
- **Strict writable-path separation** (merged into `.claude/settings.json`): Write/Edit
  is **allowed** only under `tests/ specs/ steps/ bugs/ artifacts/ reports/ fixtures/
  page-objects/`. It is **denied** on `playwright.config.ts`, `package.json`, the
  lockfile, and both `prod-guard.*` — which is *why* substrate fixes need
  `/qa:init --resync` rather than an in-place agent patch. Dangerous Bash (`rm`,
  `git clean`, `git push --force`, `git reset --hard`, `curl | sh`) is denied too.
- **Credentials via env only** — agents cannot write `.env`; passwords are always
  referenced as `password_env`, never as literals; secrets are never logged.
- **`/qa:batch-fix` has high blast radius** — it proposes one pattern and waits for
  explicit confirmation before applying across many files.
- **The reviewer fails closed** (blocks the PR) on inconclusive runs.

---

## 15.1 Privacy & data flow

**What leaves your machine, and when.** LLM calls happen in exactly two phases:
**authoring** (explore/intake/ideate/plan/generate/review) and **failure triage**
(heal). In those phases the agents send Anthropic's API what they observe:
accessibility-tree snapshots of pages they visit on *your staging/QA app*, spec/test
file contents, and trace excerpts. The **nightly replay sends nothing** — plain
`npx playwright test`, no model in the loop, by design.

**What never leaves:** credentials stay in `.env` (gitignored, loaded locally);
generated code resolves passwords via `process.env` indirection;
`fixtures/auth.<site>.json` is a local file consumed by Playwright, not agent
context; agent flows read the AX tree, not screenshots, by default.

**Training & retention (verify against your own agreement — summarized as of
mid-2026):** for **commercial usage (API key / Claude for Work)** Anthropic's default
is inputs/outputs are **not used to train models**; for **consumer Claude accounts
(Free/Pro/Max) — including Claude Code signed in with one** — the account's own
privacy toggle decides whether sessions may be used for training; if your QA sessions
run on a consumer login, check Privacy Settings before pointing agents at anything
sensitive.

**Practical rules:** author against staging with synthetic data (prod-guard already
fails closed); prefer a commercial API key for org work; treat any page an agent
visits as content that transits the API during authoring/triage.

---

## 16. The runtime substrate

What `/qa:init` (via `bin/qa-scaffold`) stamps into a project. The scaffold is
idempotent and skip-if-exists — `templates/` *is* the manifest (it `find`-walks and
copies every file), so new templates never strand.

| File / dir | Purpose |
|---|---|
| **`CLAUDE.md`** | The stamped **source-of-truth policy** (~238 lines): mission, prod-guard, discovery rule, file layout, the **test-case format contract** (the 16 oracle keys + argument shapes), assertion style, oracle-defense layers, the page-object reuse rules, the subagent roster, MCP discipline, cost discipline, the bug-report schema, and escalation rules. |
| **`playwright.config.ts`** | `globalSetup: prod-guard.ts`; run-of-record-gated `json → artifacts/last-run.json` reporter; `outputDir: ./artifacts/test-results`; `trace: retain-on-failure`; `video` retain-on-failure (or `on` when `QA_KEEP_VIDEO=1`); `reducedMotion:'reduce'`; `locale:'en-US'`; `grepInvert: /@quarantine/`; `setup → app → (conditional) admin` projects, **tag-routed** (`@site:*`) not path-routed. |
| **`package.json`** | Pinned dev deps (see below) + `overrides` pinning `playwright`/`playwright-core` to one stable browser revision, and npm scripts (`test`, `test:smoke`, `test:regression`, `typecheck`, …). |
| **`.mcp.json`** / **`.mcp.explore.json`** | Empty `{}` default vs the Playwright-MCP-registered explore/heal config (the two-config pattern of [§13](#13-cli-vs-mcp)). |
| **`scripts/`** | `prod-guard.sh` (advisory), `prod-guard.ts` (enforced globalSetup), `resolve-spec-path.sh` (single `<arg>`→spec/test path mapper), `doctor.sh` (the `/qa:doctor` deterministic self-check, checks 0–21 + rollup), `check-last-run.sh` (canonical `last-run.json` freshness/zero-test gate, shared by doctor + `/qa:report`), `bug-status.sh` (canonical `bugs/*.md` Status parser **and** — via `--class` — the canonical resolved-vs-open classification, shared by doctor + `/qa:run mode=smoke`/`/qa:run mode=single`/`/qa:report`), `retire-delete.sh` (the sanctioned scoped-delete wrapper `/qa:retire` calls), `resync-set.txt` (the single manifest of toolkit-owned files, read by BOTH `qa-scaffold --resync` and doctor's substrate-drift check), `runtime-dirs.txt` (the single manifest of runtime directories, read by BOTH bootstrap entry points so `/qa:init` and `npm run init` stamp the same tree), `oracle-keys.txt` (the closed oracle vocabulary as data, read by doctor Checks 2/9b), `prod-guard-rails.txt` (the manifest of skills that must carry a prod-guard rail, read by Check 9bd), `claude-md-vocab.txt` (the manifest of toolkit-owned symbols that must survive in your `CLAUDE.md` — the delivery half of the upgrade path, since that file is shared-ownership and `--resync` cannot refresh it), `init.sh` (plugin-free bootstrap for a fresh clone), plus a `README.md` covering all of them. |
| **`.env.example`** | `BASE_URL_APP=CHANGEME` fail-closed sentinel, blank creds, documented toggles (`QA_KEEP_VIDEO`, `QA_RUN_QUARANTINE`, `QA_RUN_OF_RECORD`, `QA_ALLOW_PROD`). |
| **`fixtures/`** | `test.ts` (the `test`/`expect` barrel; the generator adds one fixture per promoted page object), plus `schemas/` + `factories/` `.ts.example` illustrations (real schemas/factories are generated **on demand, grounded in the real app**, on first `factory:` use). |
| **`specs/_context/_templates/`** | `app.context.md` (hot-tier skeleton), `area.md` (specialist skeleton), `basis.md` (the Example-Map test-basis template), `cases.md` (the SFDIPOT candidate-case checklist template). |
| **`.github/workflows/qa-nightly.yml.example`** | The **disarmed** nightly CI workflow — rename to `qa-nightly.yml` to arm it ([§16.1](#161-nightly-in-ci)). |
| **`.github/workflows/qa-review.yml.example`** | **Optional** — the local gate is `/qa:review` + doctor Check 15. The **disarmed** PR workflow that runs the `reviewer` on every PR touching `tests/`/`specs/`/`page-objects/`/`fixtures/` — rename to `qa-review.yml`, point `plugin_marketplaces` at a Git URL of the marketplace (the runner must install the plugin or the `reviewer` subagent does not exist there), then make the job a **required status check**. |
| **runtime dirs** | `artifacts/ bugs/ fixtures/ page-objects/ reports/ specs/_context/ steps/ tests/` |

**Pinned dependencies** (`package.json`, exact at time of writing):

| Package | Version | Note |
|---|---|---|
| `@playwright/test` | `1.63.0` | exact pin (no caret) + `overrides` pin `playwright`/`playwright-core` to `1.63.0`. These three **plus** the version-pinned npx arg in `.mcp.explore.json` are **FOUR sites that move in one change** — all four enforced by `/qa:doctor` Check 8b (the exact-pin arm matters: a caret floats the runner above the forced core while the equality arm still reads true). Bumped 1.62.1 → 1.63.0 on 2026-09-20 to enable `test lock:` (see below); the bump moves the **Chromium revision 1234 → 1243**, so run `npx playwright install` after pulling. `@playwright/cli` 0.1.17 and both MCP paths were re-verified driving a real browser on the forced-stable 1.63.0 core. |
| `@playwright/cli` | `0.1.17` | default transport; exact pin (pre-1.0, no float) — manual-bump |
| `@playwright/mcp` | `^0.0.78` | **legacy fallback only** — explore/heal now use the MCP server bundled with `playwright` (`npx playwright mcp`, 1.62+); `.mcp.explore.json` launches the bundled server, not this package |

**`test lock:` (Playwright 1.63+).** `lock?: string | string[]` on `TestDetails` — available on `test(title, details, body)` and `test.describe.parallel(title, details, body)` — is the only cross-file mutual-exclusion primitive the runner ships, and the reason for the 1.63.0 bump. Reviewer **Check 13** offers it for the cross-FEATURE *mutator/consumer* race (spec A mutates a shared seed entity that spec B merely reads), where the previous remedies were a throwaway entity or pinning a whole lane. The **generator** emits it into the compiled `.spec.ts` — it is not an oracle key, not a `steps:` form, and nothing in a spec's YAML authors it. Three ways it is *silently* wrong, all measured on 1.63.0 rather than read from a release note, and all enforced: a lock name declared at exactly **one** site is inert (`/qa:doctor` **Check 9l** FAILs it); **sharding voids it** entirely, because the shard filter splits by test count and never reads the locks (Check 9l FAILs the combination — fold the contention into ONE file's serial `describe` instead, which is shard-safe); and a lock on a hooked `describe.parallel` is held at **group** granularity, so it stalls unlocked neighbours.
| `@axe-core/playwright` | `^4.12.1` | a11y skill |
| `zod` | `~3.25.0` | pinned to Zod **3** — `zod-fixture 2.5.2` breaks on Zod 4; use `z.string().email()`, not `z.email()` |
| `zod-fixture` | `^2.5.2` | factory generation |
| `typescript` | `^5.9.0` | held on 5.x |
| `@types/node` | `^24.0.0` | held on 24 LTS |
| `dotenv` | `^17.4.2` | `{ quiet: true }` — v17 banner would corrupt JSON reporters |

---

## 16.1 Nightly in CI

The scaffold stamps `.github/workflows/qa-nightly.yml.example` — note the
`.yml.example` suffix: **arming the nightly is a deliberate act** (rename it to
`qa-nightly.yml`), never a side effect of `/qa:init`. Once armed, it fails safe:
`prod-guard.sh` **fails closed** on a missing or placeholder `BASE_URL`, so a
workflow armed before its secrets exist goes **red, never silently green**.

**Secrets** (Settings → Secrets → Actions) mirror your local `.env`:

| Secret | Mirrors |
|---|---|
| `QA_BASE_URL_APP` | `BASE_URL_APP` (staging/QA host — the guard rejects prod and `CHANGEME`) |
| `QA_USER_EMAIL` / `QA_USER_PASSWORD` | `QA_USER_*` creds |
| *(as needed)* `BASE_URL_ADMIN` / `QA_ADMIN_*` / seed-API vars | whatever else your suite reads |

**What a run produces:** `artifacts/last-run.json` (the run-of-record — the workflow
sets `QA_RUN_OF_RECORD=1`), an HTML report built from the blob report, and
`trace.zip` per failure — all uploaded as one `qa-nightly-<n>` artifact
(14-day retention).

**On failure:** download the artifact, then triage **locally** with
`/qa:heal <test-id>` from the trace. The workflow also carries a commented **opt-in
AI-heal step** for triage in CI itself — off by default because the nightly is **$0
LLM by design**; enabling it puts a model (and an `ANTHROPIC_API_KEY` secret) in the
failure path, so treat it as a cost decision, not a default.

**Sharding:** the single-job workflow needs no merge step. If you shard later, use
the matrix + `merge-reports` recipe in the stamped CLAUDE.md §Reporting pipeline.

---

## 16.2 Exporting results to your TCM

To feed TestRail / Xray / Zephyr Scale, export JUnit XML — no rerun needed if you
start from the nightly's blob report:

```bash
# from the nightly blob (no rerun):
npx playwright merge-reports --reporter junit ./blob-report > reports/junit-results.xml

# ad-hoc local run:
PLAYWRIGHT_JUNIT_OUTPUT_NAME=reports/junit-results.xml npx playwright test --reporter=junit,line
```

Note the ad-hoc form: an inline `--reporter` **replaces** the config's reporter array
— the gated json sink never fires, so it does **not** refresh `last-run.json`
(consistent with `/qa:run mode=single`).

**Import commands:** TestRail — `trcli parse_junit`; Xray —
`POST /api/v2/import/execution/junit`; Zephyr Scale —
`POST /automations/executions/junit?autoCreateTestCases=true`.

**Caveat:** test titles are the matching key — do **NOT** rename tests to please a
TCM; use auto-create on first import. Case-table (CSV) export is deferred until
stable row ids exist (`/qa:approve` mints them).

---

## 17. Repository map

```
QA-Toolkit/
├── README.md                       # how the plugin is packaged & installed (marketplace-level)
├── DOCUMENTATION.md                # ← this file (the CANONICAL reference)
├── MERGE-NOTES.md                  # design lineage (Test-Browser oracle-defense + POM reuse merge)
├── .claude-plugin/
│   └── marketplace.json            # the catalog (lists the qa plugin)
└── qa/                             # THE PLUGIN
    ├── README.md                   # plugin-level intro + authoring workflow
    ├── .claude-plugin/plugin.json  # manifest (name, description, keywords, version — bump to ship)
    ├── agents/                     # planner · generator · verifier · healer · reviewer · exploration · ideation
    ├── skills/                     # 23 SKILL.md — one dir each.
    │                               #   19 /qa:* commands (init · gen · heal · review · …)
    │                               #   + 4 helpers: playwright-cli · test-data-seed ·
    │                               #     axe-a11y · visual-regression
    ├── hooks/
    │   ├── hooks.json              # registers both PreToolUse gates on Edit|Write
    │   ├── assertion-contract.sh   # denies the healer/verifier any assertion rewrite
    │   ├── spec-lint.sh            # denies reviewer Checks 1/5/9/11 at write time
    │   └── README.md               # why the subset is what it is, + the fail-open rules
    ├── reference/
    │   ├── DESIGN.md               # the design rationale (the "why")
    │   ├── sentinel-actions.md     # sentinel → action contract (heal · batch-fix · doctor Check 4)
    │   └── test-case-ideation.md   # research grounding for intake/ideate
    ├── templates/                  # the runtime substrate /qa:init stamps (see §16)
    └── bin/qa-scaffold             # the deterministic substrate installer
```

---

## 18. Honest limits

These concessions are deliberate — do not let a future doc pass quietly delete them to
make the toolkit sound more complete than it is:

- **A green a11y gate ≠ accessible.** `@axe-core` catches ~20–30% of WCAG issues by
  success-criterion (16 of ~50 SC, per Deque; ~57% by issue volume — the volume figure is Deque-sourced and accurate). Worse, AI-generated a11y "fixes" routinely
  satisfy the scanner while making the screen-reader experience *worse*. A human with a
  screen reader must review a11y fixes; never auto-merge a scanner-pass diff.
- **No automated mutation gate for `.spec.ts`.** Mutation testing (Stryker) covers
  pure-TS units only. For browser tests, `must_fail_when:` + the generator's step-8b
  negative control is the substitute — but it only covers *declared* invariants;
  automated mutation coverage for browser tests is an open gap.
- **Ordinary (non-`must_fail_when`) oracles are not falsification-tested.** A plain
  happy-path oracle is *counted* (present, in-vocab, non-orphan) but never
  fault-injected, so a mis-chosen-but-valid key can ship green. Reviewer Check 2c
  *WARNs* on this by reasoning about intent-vs-oracle — it is LLM judgment, not a
  mechanical guarantee. Keep the reviewer on a capable model.
- **Visual regression needs a specialist past the obvious.** Self-hosted screenshot
  diffs catch gross breakage; the perceptual / cross-viewport / cross-browser long tail
  needs visual-AI (Applitools / Chromatic / Percy / Argos).
- **No relational / exact-equality oracle key** ([§10](#10-the-closed-oracle-vocabulary)).
- **Most of the reviewer cannot be a hook.** Two `PreToolUse` gates ship
  ([§11](#11-the-oracle-defenses)), but a hook sees one tool call's input — no paired spec,
  no `bugs/` tree, no diff, no test run — so only checks decidable from the proposed text
  alone are enforced at write time. Three more were examined and deliberately left with the
  reviewer (see `qa/hooks/README.md` §"What is NOT hooked"). The reviewer remains the
  backstop, by discipline.
- **No request-side oracle, and HAR replay is refused.** Specs can stub a dependency
  (`fault:`) and control time (`clock:`), and the vocabulary asserts what the server
  *answered* — but nothing expresses what the client *sent* ("the POST carried
  `coupon=QA20`"). Separately, `routeFromHAR` replay is banned rather than missing: a suite
  served from a recorded HAR asserts the frontend against a frozen backend and stays green
  through every server-side regression.
- **Single-vendor multi-agent review shares blind spots.** All-Claude agents converge
  on the same failure modes under adversarial pressure. For compliance-relevant specs a
  human *may* optionally re-run the reviewer through a non-Claude model (pilot-only).
- **Plugin fixes don't auto-propagate to already-stamped substrate.** The remedy is
  human-invoked (`/qa:doctor` detects, `/qa:init --resync` repairs) — never automatic
  ([§4.2](#42-the-brain-vs-body-split-important)).
- **The un-closeable gap: a wrong spec is un-automatable.** Every defense above guards
  against *drift inside a correct spec*. If the human writes a YAML that doesn't reflect
  the real business rule, no oracle defense fixes it. Completeness of *what* to test is
  undecidable — which is why the **human approval gate on the ideation checklist is
  mandatory and non-negotiable**.

---

## 19. Glossary

**Day-1 terms** (the six you need on the first afternoon): **site** — one deployed
app under test (`BASE_URL_<SITE>`) · **area** — a product area, the folder specs
group under · **spec** — the human-readable Markdown contract in `specs/` · **test**
— the compiled Playwright `.spec.ts` in `tests/` · **oracle** — the spec's definition
of "correct" (the assertions) · **smoke** — the `@smoke`-tagged fast gate
`/qa:run mode=smoke` runs.

> **Terminology rule:** *Spec* always means the Markdown file under `specs/`; the
> compiled artifact under `tests/` is always *the test* — even though Playwright
> names its files `.spec.ts`.

**The complete, canonical glossary is [`qa/reference/glossary.md`](qa/reference/glossary.md)** —
every term defined once (the single source of truth, so definitions can't drift between two
copies). It covers all of the above plus `assertion contract`, `closed vocabulary`,
`green-but-empty/-wrong`, `metamorphic twin`, `must_fail_when`, `route manifest`, `sentinel`,
`run-of-record`, `brain / body`, the three context tiers, and more.

---

## 20. For maintainers: where each fact lives

Every operational fact has exactly one authoritative home — do **not** duplicate them.

| Fact | Authoritative home |
|---|---|
| Oracle vocabulary (16 keys) + argument shapes | `templates/CLAUDE.md` (the stamped SoT). **Enumerated** (editable list — change all in one commit) in `agents/planner.md`, `agents/generator.md`, reviewer Check 4, `/qa:doctor` Check 2, `/qa:coverage`'s grep. `/qa:new-spec` and `/qa:review url=` **defer** (hold no list). |
| Reviewer checks (the full suite) | `agents/reviewer.md` |
| Sentinel → action contract (`.healer-needs-*`) | `reference/sentinel-actions.md` — single source; `/qa:heal`, `/qa:batch-fix` and doctor Check 4 all point at it |
| Command catalog + workflow order | skill frontmatter under `skills/**`; `skills/help/SKILL.md` (or run `/qa:help`) |
| Page-object reuse rules | `templates/CLAUDE.md` §"Page-object reuse layer" |
| Subagent roster (models, tools) | `templates/CLAUDE.md` §"Subagent roster" + `agents/**` |
| Prod-guard / env-loading / writable-path policy | `templates/CLAUDE.md` (policy) + `templates/scripts/prod-guard.{sh,ts}` (implementation — regexes must stay in lockstep) |
| Ideation mechanics (lenses, per-kind processes) | `skills/intake/SKILL.md` + `agents/ideation.md` + `templates/specs/_context/_templates/**` |
| The design rationale (the *why*) | `qa/reference/DESIGN.md` |

**Maintenance rule:** if you're about to document a *mechanic* (a key, a check, a
command) in `DESIGN.md`, stop — it belongs in one of the homes above. `DESIGN.md` holds
only reasoning that stays true if the mechanic changes. This file (`DOCUMENTATION.md`)
is the human/agent-facing *overview* — it may restate mechanics for orientation, but
when they change, the homes above are the source of truth to update first.
