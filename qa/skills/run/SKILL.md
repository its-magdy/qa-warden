---
description: Execute Playwright tests in one of four ways — run a single spec headless/CI-shaped (mode=single), run the @smoke-tagged suite (mode=smoke), repeat-probe a spec N times to check flakiness/repeatability/stability (mode=repeat), or run only the tests a git change touches (mode=changed). Deterministic, JSON-only, no LLM in the loop. Do not hand-roll a bare `npx playwright test` for any of these — this skill owns the resolver, freshness/zero-test guards, and report paths every downstream consumer (`/qa:report`, `/qa:heal`) depends on.
argument-hint: mode=single|smoke|repeat|changed [<spec-path-or-test-path>|<git-ref>] [N]
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/run.sh *)
---

One entry point, four selection scopes — all deterministic, no LLM in the
loop (plain `npx playwright test`, no MCP/LLM). Pick the mode from the ask:

| Natural phrasing | Mode | What runs | Output |
|---|---|---|---|
| "run this spec headless", "CI-shaped run of X", "just run X once, no interaction" | `single` | one spec, one shot | `reports/headless-<name>.json` (+ `.log`) |
| "run the smoke suite", "run smoke", "is the suite green" | `smoke` | `@smoke`-tagged tests | `artifacts/last-run.json` (config json sink) |
| "is this test flaky", "check repeatability", "run this N times" | `repeat` | same spec × N (default 10), back-to-back | `artifacts/flake-<name>.json` |
| "run what I changed", "run the tests this PR touches", "quick check before I push" | `changed` | tests git says the change touches | `reports/changed.json` (+ `.log`) |

**Argument shape:** `mode=single <spec-path-or-test-path>` · `mode=smoke` (no
further args) · `mode=repeat <spec-path-or-test-path> [N]` · `mode=changed [<git-ref>]`.

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh`
first — STOP and ask the user to confirm in-chat if it exits non-zero. For
`mode=repeat` this matters more than the other two: a repeat-each run drives
the live target N times, multiplying blast radius rather than reducing it —
flake probes run against **staging only**.

Run exactly this one command — the script parses `mode=` itself, so there is nothing to bind
first (and an inline binding block would not match this skill's pre-approved `run.sh` call):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh $ARGUMENTS
```

All four modes' run/guard/aggregate logic is bundled in one script
(`scripts/run.sh`) — a bash-shebang script keeps run+guard sequencing in one
process, avoiding the empty-`$RUN_START` hazard a split invocation would hit
(the Bash tool starts a fresh shell per call). The script owns the shell
recipes; this skill owns the mode-selection, caveats, and output format below
— do not re-derive or re-implement any of it inline.

**Exit codes (every mode):** `0` = completed cleanly — read the named JSON and
summarize per the mode section below. `2` = do NOT report a pass; the script
already printed why (missing/stale/corrupt/zero-test JSON, a non-zero
Playwright exit masked by a 0-failure JSON — F-04 — or bad args). Stop and
relay that message rather than summarizing.

## mode=single (formerly `/qa:headless`)

CI-shaped single-shot run of one spec — no interactive session, JSON output
only.

**Do NOT pass `--output`.** Let failure traces land under the config
`outputDir` (`artifacts/test-results/<id>/`) — that is exactly where `/qa:heal`
looks. Overriding `--output` strands the trace where the healer won't find it.

**Never `2>&1` into the `.json` file** (the script already splits stdout/stderr
correctly — do not reintroduce a fold if you re-run anything by hand).

Because `--reporter=json` overrides the config reporters, this run does **not**
refresh `artifacts/last-run.json` — that is intentional (each single run owns
its `reports/headless-<name>.json`). `/qa:report` reads the per-command file,
not `last-run.json`, for `mode=single` runs.

Then print a one-paragraph summary of the JSON output to chat (pass/fail,
spec path, duration, top-level error if any, pointer to artifacts). The script
already ran the open-bugs scan (`post-run-checks.sh --only bugs`) — fold any
hit into the summary (F-17: Playwright folds conditional `test.fail` xfails
into `expected`, so "N expected" can hide a scenario parked against a
confirmed-live defect).

## mode=smoke (formerly `/qa:run-smoke`)

Runs the `@smoke`-tagged suite deterministically. Then print a compact summary
to chat, reading counts from `artifacts/last-run.json` (the config `json`
sink; `dotenv({quiet:true})` keeps it valid JSON):

- **Lead with a one-line roll-up (F-025)** so a glance yields the verdict.
  Fold in the counts from the script's `post-run:` trailer (do not recount)
  and any parked (`test.fail`/`test.fixme`) scenarios, e.g.:
  `SMOKE: PASS (2/2) · 1 open bug · 2 parked xfail → NOT all-clear; see /qa:report`
  or `SMOKE: FAIL (1/2) → /qa:heal`. This roll-up is a **smoke-lane signal, not
  the go/no-go** — `/qa:report` remains the real quality verdict; say so on the
  same line.
- Total / passed / failed / flaky (`jq '.stats' artifacts/last-run.json`).
- For each failure: spec path + first error line + pointer to
  `artifacts/test-results/<dir>/trace.zip` (the config `outputDir`), and a
  ready-to-paste heal command per failure: `/qa:heal <dir>`.
- Exit cleanly — do NOT invoke the `healer` subagent from here. Use
  `/qa:heal <failing-test-id>` to triage a specific failure, or
  `/qa:batch-fix <pattern>` for a pattern fix across many. If failures look
  intermittent, run `/qa:run mode=repeat <spec>` before healing; if
  *everything* is red, run `/qa:doctor` and check `.env`/VPN first.

Do not retry past the default Playwright retry count. Do not add
`--retries=99` or similar cover-up flags. This is a **policy, not a hook** — the
`hooks/` layer matches `Edit|Write`, never `Bash`, so nothing stops a cover-up
flag on the command line (CLAUDE.md §Oracle defense); the reviewer is the backstop.

## mode=repeat (formerly `/qa:flake-check`)

Repeatability probe: run the same spec N times in a row and report the
pass/fail rate. A healthy test should stay above 95% over 10 runs; anything
flakier goes into the `@quarantine` lane (CLAUDE.md §Escalation rules).
`mode=repeat` does not refresh `artifacts/last-run.json`; its output is the per-command
`artifacts/flake-<name>.json`.

**Quarantined target?** The config's `grepInvert: /@quarantine/` excludes
`@quarantine` tests from this probe too — the run reports 0 executed (null
rate), which reads like a resolution error. To probe a quarantined test (the
primary use of this mode while fixing one), prefix the run:
`QA_RUN_QUARANTINE=1 npx playwright test "$TEST" --repeat-each=…` by hand, or
temporarily drop the tag.

If `pass_rate_pct` is `null` (0 executed tests), do **not** report stability —
report that the argument did not resolve to an executed test and stop.

Report:
- Pass rate as `X / <executed> (Y%)` (with `--repeat-each`, each test in the
  file runs N times, so `executed` = tests × N).
- **Also report the PER-TEST minimum pass rate, not just the suite aggregate
  (F-21).** Pointing this at a spec file runs `--repeat-each` over ALL its
  tests, so the suite aggregate DILUTES a localized flake: one test failing
  once in a 7-test × 5 = 35-run file is 34/35 ≈ 97% — *above* the 95% gate —
  while that single test is 4/5 = 80%. The script already computes the
  per-title breakdown (worst-first); gate on the **worst** test.
- Per-execution duration min / median / max (from the script's
  `durations_ms` array).
- **A fully-skipped title reports as `skipped (N/N)` and is EXCLUDED from the
  flake gate** — a parked `test.fixme` or a `test.skip(!BASE_URL)` guard is
  not a flake; never recommend `@quarantine` for it or fold its null rate
  into the worst-per-test gate.
- If any run red: per-failure first error line + trace pointer.
- Recommend `@quarantine` if the **worst per-test** pass rate < 95% (not just
  the aggregate).

Do NOT invoke the healer automatically — `mode=repeat` is diagnostic only.
Use `/qa:heal <id>` afterwards if you want to fix a specific failure.

## mode=changed

A PR-speed lane: Playwright's `--only-changed` runs the test files that changed **plus every
test file that imports a changed file**, so editing a page object re-runs its consumers. Bare
`mode=changed` compares against uncommitted work; `mode=changed main` (any ref) compares
against that branch. It never refreshes `artifacts/last-run.json` — it is **not the run of
record**; `mode=smoke` and the nightly still are.

What it cannot see, and the script says so rather than staying quiet:
- **An edited spec (`specs/**/*.md`) selects nothing** — no test imports Markdown. The script
  lists those specs; relay the list and say their tests are stale until `/qa:gen` recompiles
  them. A re-run cannot fix that.
- **App-side changes** are invisible to git-in-this-repo. `/qa:impact` is the tool for a
  requirement or route change.
- A repo with **no commit yet** or an **unresolvable ref** exits 2 with a reason — relay it; it
  is not a zero-match result.

Report: the selected/passed/failed counts from `reports/changed.json`, per-failure first error
line + `/qa:heal <dir>` command as in `mode=smoke`, and any listed stale specs. If the script
printed `NOTHING SELECTED`, report exactly that — **nothing ran, so it is not a pass** — and
suggest `mode=smoke` if the user wanted a health signal.
