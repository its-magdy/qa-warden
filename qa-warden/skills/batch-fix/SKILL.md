---
description: Apply a single healer pattern fix across every failing test matching a path-or-substring filter.
argument-hint: <path-or-filter (a dir or substring Playwright filters on, e.g. tests/checkout)>
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/../run/scripts/run.sh" *)
---

Apply a single healer pattern fix across every test matching `$ARGUMENTS`
(e.g. `/qa-warden:batch-fix tests/checkout` — a path prefix or substring Playwright
filters on, **not** a shell glob; see the note below).

**Session boundary (F-38):** this command runs in the **main session** and owns the
in-chat propose/confirm gate at step 3 — a non-interactive subagent has no channel to
receive an in-chat confirmation, so the gate must NOT be delegated — and that includes a
**fork** (`context: fork`), which runs as a fresh subagent without the conversation history and
has `AskUserQuestion` filtered out, so forking buys interactivity back no more than a plain subagent does. The `healer` subagent
is invoked only for the bounded **step-2 triage** of the ONE representative failure; the
mechanical N-file application (step 4) happens in the main session *after* confirmation.

Use case: a single selector change broke 10+ specs — diagnose once, patch
everywhere, verify once.

**Guard first (prod-safety).** Run `bash scripts/prod-guard.sh` and **STOP if it exits
non-zero** before any step below. Step 1's `npx playwright test` does fire the `globalSetup`
backstop, but the step-2 healer triage can drive a live browser via MCP first — so the guard
must run up front, same discipline as every other browser-driving command.

Workflow:

1. Establish the **current** failing set by RE-RUNNING the filter, not by trusting
   `artifacts/last-run.json`. `last-run.json` records only the last run — it can
   be stale (a `/qa-warden:run mode=single` or `/qa-warden:run mode=repeat` since, or an edit after the last smoke)
   and may not include these specs at all, so aborting on "zero matches in last-run" can
   skip a genuinely-red batch. Run the filter fresh and in the foreground — a backgrounded
   run is lost when a headless turn ends, and the healer then starts from nothing (run-01,
   O-64) — then work from THAT result. Run exactly this one command, as its own Bash call (the
   `allowed-tools` rule above pre-approves exactly this form; an inline shell block would not
   match it and is denied headless):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/../run/scripts/run.sh" precheck $ARGUMENTS
   ```
   The `precheck` mode of `/qa-warden:run`'s script runs the filter (`--retries=0`, JSON to
   `artifacts/batch-fix-precheck.json`, stderr to `.log`, never touching `last-run.json`), reads
   Playwright's exit code AND the JSON as one verdict, and prints a `run(precheck): … (verdict=<word>)`
   line plus what to do. Act on its exit code:
   - **`0` — verdict `red`:** `filter matched N test(s); M failing — proceed to step 2`, followed by
     the top heal-log signatures (`artifacts/heal-log.jsonl`) when that log exists — the pattern
     this batch likely shares. Only this proceeds.
   - **`1` — verdict `green` or `zero-test`:** matched tests but none failing → report "nothing to
     fix" and do not invent a patch; or the filter resolved to nothing → say so and stop. The match
     count is every resolved test (expected+unexpected+skipped+flaky), so an all-red batch never
     reads as "matched nothing" (F-39).
   - **`2` — anything else** (`incomplete`: Playwright exited non-zero with 0 failures recorded — a
     timeout or worker crash; `missing`/`corrupt`: it never started — globalSetup/prod-guard/config;
     a missing filter): relay the printed reason and stop. This is NOT "nothing to fix" and NOT
     "nothing matched" — do NOT proceed to step 2.

   The filter is a path prefix or substring Playwright matches, NOT a shell glob — prefer a
   directory (`/qa-warden:batch-fix tests/checkout`).
2. **Delegate to the `healer` subagent** to triage ONE representative failure
   end-to-end (trace, MCP replay, root cause) and extract the minimal
   selector/wait patch — do NOT triage inline; the bounded healer sandbox/turn-budget is the point. **If the healer returns a
   sentinel instead of a patch** (`artifacts/.healer-needs-*` — the representative
   failure classified as stale-context / auth-stale / data-drift / contract-change),
   close the loop per the sentinel→action table in `${CLAUDE_PLUGIN_ROOT}/reference/sentinel-actions.md` before
   re-invoking — never leave the sentinel orphaned (`/qa-warden:doctor` check 4 flags it).
3. Propose the pattern (before/after snippet) to the user IN CHAT and wait
   for explicit confirmation before editing N files — batch fixes are
   high-blast-radius.
   **When the pattern re-points a LOCATOR, split the N specs first.** The healer ran its
   lookalike guard (`agents/healer.md` §HEAL02) on the ONE representative only, and step 5's
   green proves the new locator *matched something*, not the *right* thing — so the guard
   has to be re-established per file, not inherited. For each matching spec, read what is
   asserted downstream of the patched step:
   - a **side-effect oracle** on a different surface (`url_matches`,
     `network_response_status`/`response_body_contains`, `storage_state`, a
     `count_equals`/`text_visible` on the post-action view) → green will be self-confirming;
     **batch-eligible**.
   - only a presence/state check on or beside the patched element → green would be
     unconfirmed; **exclude it from the batch** and list it for an individual
     `/qa-warden:heal <test-id>`, where HEAL02 actually runs.
   Show both lists in the proposal. A wait-only pattern (no locator change) cannot land on a
   lookalike — skip the split.
4. Once confirmed, apply the patch across every **batch-eligible** spec (never touch
   assertions or the oracle contract — CLAUDE.md §Assertion style).
5. Re-run the full batch. **Re-derive the filter from `$ARGUMENTS` in THIS block — do NOT reuse `$ARG` from step 1 (F-S03):** the Bash tool starts a fresh shell per call (see §Environment in CLAUDE.md), so `$ARG` set in the step-1 block is EMPTY here, and `npx playwright test ""` silently runs the WHOLE suite — the exact max-blast-radius this command warns against. Re-bind first, then run:
   ```bash
   [ -n "${ZSH_VERSION:-}" ] && setopt shwordsplit 2>/dev/null
   set -- $ARGUMENTS
   ARG="${1:?usage: /qa-warden:batch-fix <path-or-substring>}"   # re-derive; fail loudly rather than run everything
   npx playwright test "$ARG" --retries=0 --reporter=line
   ```
   **The `--reporter=line` override is load-bearing:** in a run-of-record context (CI, or
   `QA_RUN_OF_RECORD=1` in the environment) a bare re-run fires the config's gated
   `json` reporter, rewriting `artifacts/last-run.json` with ONLY this batch's
   subset — a later `/qa-warden:report` then reads the subset as the whole suite and hides real
   failures elsewhere. An inline `--reporter` replaces the config array, so `last-run.json`
   (the run-of-record) is left intact. You care only about exit code / red-green here.
6. Report: how many went green, how many still red, bugs filed for any that
   don't respond to the pattern (those are likely independent product bugs), **and the
   specs step 3 excluded**, each with its ready-to-paste `/qa-warden:heal <test-id>` — an excluded
   spec is still red, and one left off the report reads as fixed.

**Hard turn budget: 5** for the representative triage, then pure mechanical
application.
