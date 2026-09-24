---
description: Interactively capture the "test basis" for a feature/enhancement/bug — auto-gather observable context, then interview only for non-observable intent (the oracle) — and write specs/_context/<site>/<area>/<feature>.basis.md. First step of the authoring chain (intake → ideate → approve → new-spec); PRECONDITION — the area's context (app.context.md + <site>/<area>.md) MUST exist; intake hard-stops and tells you to run /qa-warden:explore first if it doesn't.
argument-hint: "<area/feature> [kind=feature|enhancement|bug|refactor|characterization] [site=<id>]"
disable-model-invocation: true
---

Capture the **test basis** for `$ARGUMENTS` — the information from which test cases are
derived. This runs **in the main session** (it is interactive — it interviews you);
it does NOT delegate to an autonomous subagent. Output: one Example-Map-structured
file at `specs/_context/<site>/<area>/<feature>.basis.md`.

**No argument given?** If `$ARGUMENTS` is empty, do **NOT** proceed — print the block below
verbatim and stop:

```
Usage:  /qa-warden:intake <area/feature> [kind=feature|enhancement|bug|refactor|characterization] [site=<id>]
Capture what "correct" means for ONE feature (first step of the rigor lane). For example:

  /qa-warden:intake auth/login                 what should sign-in guarantee?
  /qa-warden:intake tasks/update-task          what should editing a task guarantee?
  /qa-warden:intake checkout/coupon kind=bug   pin a known bug's expected behavior

First time? Follow ${CLAUDE_PLUGIN_ROOT}/reference/tutorial-first-test.md — or skip to the fast lane: /qa-warden:new-spec <area/feature>.
```

**Interactivity contract (F-16).** The interview uses `AskUserQuestion`, which exists **only in the
main-session toolset — it is NOT available to subagents.**
This includes **forks** (`context: fork`): a fork inherits the parent's history, model and
tools, but `AskUserQuestion` is filtered out of it like the other main-session-only tools —
so `context: fork` is NOT an escape hatch for an interactive skill, and a forked skill that
prompts dead-calls it.

So (1) run this in the main session, never dispatched to an autonomous subagent (an
orchestrator delegating the authoring chain keeps intake in the main loop); and (2) if
`AskUserQuestion` is unavailable, do NOT dead-call it or silently skip the interview — ask
the same batched questions as plain in-chat prose and read the typed reply.
Degrading to zero questions produces a hollow basis.

**Attest the interview (F-016).** Stamp the basis `interview:` field with the ACTUAL question and
round count (e.g. `interview: 7 questions across 2 rounds`) — without it, a fully-automated run that
invents rules and stamps them `[human-answered]` is indistinguishable from a real interview. A basis
with `[human-answered]` rules and no declared business source must carry a non-`none` count;
`interview: none` is legitimate only when every rule is `[grounded:]`/`[imported:]`/`[pinned:]`.
`/qa-warden:doctor` WARNs on `[human-answered]` rules with `interview: none`/absent.

The method is defined inline below. Design rationale (maintainers, not required to run):
the plugin's `reference/test-case-ideation.md` §5.

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh` first — STOP and ask the user to confirm in-chat if it exits non-zero. The live-snapshot steps below need `$BASE_URL_*` in their own shell — load `.env` in that same invocation (CLAUDE.md §Environment).

Parse `$ARGUMENTS` for the `<area/feature>` path, optional `kind=` (default `feature`),
and optional `site=` (default `app`; must match a `sites[].id` in
`specs/_context/app.context.md`).

**Validate `<area>` against `naming.area_dirs` before writing anything (F-18).** After
parsing, confirm the `<area>` segment is one of the `naming.area_dirs` declared in
`specs/_context/app.context.md`. A typo (`authentication` vs the declared `auth`) would
otherwise silently create a mismatched `specs/_context/<site>/<area>/` path/dir that no
downstream command resolves. On a mismatch, list the valid `area_dirs` and stop — do not
write a basis under an unrecognized area.

## What to do

1. **Auto-gather observable context — do NOT ask the human what you can see.**
   - Read `specs/_context/app.context.md` (sites/auth) and
     `specs/_context/<site>/<area>.md` (area context). If the area file is missing or
     stale (past its `volatility:`-tier threshold in `staleness_tiers:`), tell the user to run
     `/qa-warden:explore mode=area site=<id> area=<area>` first, and stop.
   - Take a live snapshot of the feature's routes to pre-fill fields, states, and
     on-screen vocabulary — open the browser first, then navigate to each resolved route:
     ```bash
     # Load .env in THIS shell first — dotenv in playwright.config.ts only reaches
     # `playwright test`, not this playwright-cli shell, so ${BASE_URL_APP} is EMPTY
     # without it and the goto below hits a bare relative path (RD-02). Same invocation,
     # per CLAUDE.md §Environment (a split load in a separate Bash call is already gone).
     set -a; [ -f "${CLAUDE_PROJECT_DIR:-.}/.env" ] && . "${CLAUDE_PROJECT_DIR:-.}/.env"; set +a
     # <feature-slug> = the feature BASENAME only — a session id with a slash is treated as a path
     # segment by many session stores, so `/qa-warden:intake auth/login` uses -s=intake-login.
     # <SITE> = the resolved site: BASE_URL_<SITE> (BASE_URL_ADMIN for site=admin), never a
     # hardcoded BASE_URL_APP.
     npx playwright-cli -s=intake-<feature-slug> open
     npx playwright-cli -s=intake-<feature-slug> goto "${BASE_URL_<SITE>}/<route>"   # substitute the real route
     npx playwright-cli -s=intake-<feature-slug> snapshot
     # …repeat goto+snapshot per route, then ALWAYS close — orphan sessions leak, and the
     # shared `default` session (no -s=) can be mutated by a concurrent run mid-interview:
     npx playwright-cli close -s=intake-<feature-slug>
     ```
   - **(Optional) ingest docs** the user points at (ticket/Figma/API spec) as an extra
     pre-fill source — not a substitute for the interview.
   - **Consult the declared business sources — ground each rule, stamp its provenance.**
     If `specs/_context/app.context.md` declares a `business_sources:` block, consult it to ground the
     🔵 oracle rules in the authoritative source of "what correct MEANS" — not just what the app happens
     to do. For each source you can REACH — read a `doc` file/folder, `WebFetch` a `url`, read an
     `api-spec` file — search for the feature's rules. Stamp EACH rule you record with its provenance
     (the basis rules-suffix convention): `[grounded: <source>]` (a source states it), `[human-answered]`
     (only the operator knew), `[not-in-source]` (sources silent → ALSO log an open question), or
     `[contradicted: <source>]` (a source disagrees — resolve, do NOT ship). Two more registered
     stamp values: `[imported: <source> <ext-id>]` (rule arrived via the manual-cases-import recipe (reference/how-to-import-manual-cases.md) — derived
     from an external case's expected result, not interviewed intent) and
     `[pinned: observed <YYYY-MM-DD> — provisional]` (characterization only — behavior pinned,
     intent NOT confirmed; never use `[grounded:]`/`[human-answered]` for a pin).
     **Reachability + fallback (human-in-the-loop):** you read local files, fetch a
     reachable URL, or ASK — you CANNOT crawl a gated wiki/tracker. For a `human`-typed source, an
     unreachable/gated source, or a source SILENT on a rule you need, do NOT guess — ask (step 3's
     interview) and stamp `[human-answered]`. Grounding is an AID, not a guarantee: a source can be stale
     or wrong — the source-vs-app contradiction rule in step 3 handles that. No `business_sources:`
     declared → skip this and ground on the interview + live app (today's behavior).
   - **Coupling sweep — work each channel, don't free-associate (forward change-impact).**
     Enumerate the OTHER product areas whose state/rules an oracle here must account for, working EACH
     channel below and logging a result for each (`✓ <coupling>` or `0 — none`) — same "log every angle,
     don't trust your sense of done" discipline as the SFDIPOT lens rotation, so an un-examined channel
     is visible rather than silently skipped. A heuristic aid, not a canonical list
     (`reference/test-case-ideation.md` §5 has the taxonomy it reconciles and the honest limits):
       1. **shared-data** — another area reads/writes the same entity/record this feature does.
       2. **cross-surface-aggregate** — this value sums/derives from another area's data (the classic
          "totals match across surfaces" oracle broken by a multi-unit feature owned elsewhere).
       3. **state-gate** — a publish/approval/permission/lifecycle state OWNED elsewhere gates behavior here.
       4. **cross-actor** — another actor's action (admin, a 2nd user, a background job) changes what this oracle asserts.
       5. **config-flag** — behavior toggled by config/feature-flags owned by another area.
     Sources for the sweep: the area file's `couples_with:` (`/qa-warden:explore mode=area …` step 9 records the
     ones it OBSERVED — the block is omitted when it saw none, so an absent block means "none observed",
     not "not yet swept"; it is the only cross-area source, the other two below being feature-scoped), the declared
     `business_sources:`, and the live app. Record each coupling found under `couples_with:` with its
     `channel:`; a coupling you SUSPECT but can't confirm → a 🔴 open question (blocking if an oracle
     depends on it). A channel-silent rule treated as settled is the "grounded-but-incomplete" miss this catches.

2. **Detect ambiguity to know WHAT to ask** — run the Requirements-Smells checklist
   over the user's story/brief: subjective language, ambiguous adverbs/adjectives,
   loopholes, open-ended/non-verifiable terms, superlatives, vague pronouns, incomplete
   references [Femmer JSS 2017 / ISO 29148]. Each smell is a *candidate question*, not
   an auto-reject.

3. **Interview by information value — and STOP early.** Ask only what you cannot observe,
   highest-value first, and stop when further answers would not change the case set:
   - Ask the **highest-value** questions first — the ones that most change the test set
     (the oracle / "what is correct", business rules, boundaries, risks, declared
     non-functional needs). Skip anything already known from step 1.
   - Use `AskUserQuestion` and **batch** up to 4 related questions per round to cut
     round-trips.
   - **Stop** when remaining questions wouldn't materially change the case set, or after
     ~2-3 rounds. Do not interrogate exhaustively.
   - The MANDATORY thing to pin down is the **oracle** (the 🔵 rules). Everything else
     has a smart default or an explicit "N/A (logged)".
   - Also pin `priority:` (P1/P2/P3; smart default P2 — spend a question on it only when
     the area smells critical: money, auth, compliance, or the story says "core flow").
   - **Observed-behavior ≠ oracle (mandatory disambiguation).** When the auto-gathered
     context (step 1) or a `bugs/*.md` file describes behavior that looks *wrong* — a stale
     counter, an error the app never surfaces, a value that disagrees with another surface —
     do NOT silently lift that observed value into the 🔵 rule. Ask the human explicitly
     (via `AskUserQuestion`): "the app currently does X here — is X the correct behavior, or
     a defect the test should catch?" Record the answer: correct → the oracle asserts X; defect
     → the oracle asserts the *intended* value and the case carries `must_fail_when:` /
     `must_not:` so it goes RED against the live build (detection, not accommodation). This is
     the guardrail against baking a bug into the oracle (the toolkit's core failure mode).
   - **Source-vs-app contradiction (mandatory) — escalate, don't pick silently.** When a declared
     `business_source` and the live app DISAGREE (the source says X, the app does Y), do NOT silently
     bake either into the oracle. The literature does not settle whether spec or as-built wins, and
     guessing hides a real discrepancy — so ASK (via `AskUserQuestion`): "the `<source>` says X but the
     app does Y — which is correct?" Then record: source right → oracle asserts X, stamp `[grounded:
     <source>]`; app right / source stale → stamp `[human-answered]` and note the stale source; app is a
     DEFECT → the oracle asserts the intended value with a `must_fail_when:` so it goes red against the
     live build. Same guardrail as observed-behavior-≠-oracle, one level up (the source is a third input).

4. **Per kind:**
   - `feature` — full Example Map from scratch.
   - `enhancement` / `refactor` — load the existing `.basis.md`; ask ONLY the delta
     (what changed); record the change so `/qa-warden:ideate` can run `/qa-warden:impact`.
   - `bug` — if a `bugs/<date>-<slug>.md` exists (often written by the healer), read it
     and structure it; otherwise capture repro / expected / actual / environment /
     regression_scope. No broad interview.
   - **`characterization` — the sanctioned exception to "assert intent, not observed
     behavior".** There is no intent source: the app IS the spec, temporarily. Get ONE
     blanket confirmation up front ("I am pinning current behavior as a provisional
     baseline — a green characterization test means *unchanged*, not *correct*") instead
     of the per-value observed-vs-intent interrogation — EXCEPT when an observed value
     looks defective (contradicts another surface, a `bugs/*.md`, or common sense): those
     still get the mandatory per-value ask, and a "defect" answer produces a normal intent
     rule + `must_fail_when:`, not a pin. Inputs: legacy test assertions (reading
     `tests-legacy/**` is sanctioned here as ORACLE evidence — asserted values/behaviors
     only; locators still never copied) + live snapshots. Every pinned rule is stamped
     `[pinned: observed <date> — provisional]` and doubles as a standing open question; a
     pin older than the area's staleness tier is a re-verify prompt, not a trusted oracle.

5. **Write `specs/_context/<site>/<area>/<feature>.basis.md`** using the template at
   `specs/_context/_templates/basis.md`. Log every unresolved item as a 🔴 open question
   (mark blocking ones) — capturing a question turns an unknown unknown into a known
   unknown. Print a one-line summary and the next step:
   `→ review the basis, then run /qa-warden:ideate <area/feature>`.

## Hard rules
- Write ONLY under `specs/_context/**`. Never write `tests/**` or `specs/<area>/<feature>.md`.
- Never write a password/secret literal — use `_env` indirection. **Emails and usernames MAY be
  literals** (e.g. `email: "customer@shopqa.test"`); only *secrets* (passwords, tokens, API keys)
  require `_env` (F-17). Do not `_env`-indirect a non-secret identifier — it just obscures the basis.
- Never invent the oracle. If you cannot get "what correct means" from the human, log it
  as a blocking red card and stop — `/qa-warden:ideate` will refuse until it's resolved.
- The oracle (🔵 rules) is the one mandatory output; a basis without it is incomplete.
