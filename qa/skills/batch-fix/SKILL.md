---
description: Apply a single healer pattern fix across every failing test matching a path-or-substring filter.
argument-hint: <path-or-filter (a dir or substring Playwright filters on, e.g. tests/checkout)>
disable-model-invocation: true
---

Apply a single healer pattern fix across every test matching `$ARGUMENTS`
(e.g. `/qa:batch-fix tests/checkout` — a path prefix or substring Playwright
filters on, **not** a shell glob; see the note below).

**Session boundary (F-38):** this command runs in the **main session** and owns the
in-chat propose/confirm gate at step 3 — a non-interactive subagent has no channel to
receive an in-chat confirmation, so the gate must NOT be delegated — and that includes a
**fork** (`context: fork`), which inherits the parent's tools but has `AskUserQuestion`
filtered out, so forking buys interactivity back no more than a plain subagent does. The `healer` subagent
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
   be stale (a `/qa:run mode=single` or `/qa:run mode=repeat` since, or an edit after the last smoke)
   and may not include these specs at all, so aborting on "zero matches in last-run" can
   skip a genuinely-red batch. Run the filter fresh, then work from THAT result:
   ```bash
   # zsh (this host's default Bash-tool shell) doesn't word-split unquoted vars and
   # doesn't glob-expand `**` in a variable — Playwright's filter is a path
   # substring/regex, NOT a shell glob, so prefer a directory or substring
   # (`/qa:batch-fix tests/checkout`). Force word-splitting; no-op in bash.
   [ -n "${ZSH_VERSION:-}" ] && setopt shwordsplit 2>/dev/null
   set -- $ARGUMENTS
   ARG="${1:?usage: /qa:batch-fix <path-or-substring>}"  # required; fail loudly — an empty
   # invocation would run the WHOLE suite and step 2 would "diagnose a pattern" across
   # every unrelated failure in the project (maximum blast radius for a batch tool).
   mkdir -p artifacts  # guard: the redirect target dir MUST exist first (F-S05) — sibling /qa:run mode=repeat
   # does the same. Without it, on a fresh project the `> artifacts/…json` write fails, `2>/dev/null` eats
   # the error, jq reads an absent file → MATCHED=0 → a FALSE "nothing matched" abort on a genuinely-red batch.
   npx playwright test "$ARG" --retries=0 --reporter=json > artifacts/batch-fix-precheck.json 2>/dev/null || true
   # Existence / corrupt / zero-test discrimination — single-sourced in
   # scripts/check-last-run.sh (F-37/F-39 class: `.stats.expected` counts only PASSED
   # tests; the script's total is expected+unexpected+skipped+flaky, and corrupt/statless
   # JSON reads as rc 4 / total=-1, NEVER as 0 — the old inline `${EXPECTED:-0}` arithmetic
   # turned corrupt JSON into a FALSE "nothing matched" abort on a genuinely-red batch).
   # 900s max_age only needs to accept the just-written file.
   LR=$(bash scripts/check-last-run.sh artifacts/batch-fix-precheck.json 900); lr_rc=$?
   MATCHED=${LR##*total=}; MATCHED=${MATCHED%% *}   # parse total=N off the canonical `last-run:` line
   case "$lr_rc" in
     3|4)
       # PW never started (bad globalSetup / prod-guard throw / no valid JSON).
       echo "precheck produced no valid JSON — Playwright failed to start (globalSetup/prod-guard/config?). Fix that first; do NOT read this as 'nothing matched' and do NOT proceed to step 2." >&2
       # STOP here — error state, not a zero-match. The stats arm below is skipped entirely.
       ;;
     5)
       echo "filter matched 0 tests — the pattern resolved to nothing; stop." ;;
     0|6)   # 6 (stale) is unreachable for a just-written file; keep it in the proceed arm
       # Only FAILED still needs a direct jq read — the script has no per-bucket output;
       # `${FAILED:-0}` is safe HERE because the corrupt case was already excluded by rc.
       FAILED=$(jq '.stats.unexpected // 0' artifacts/batch-fix-precheck.json 2>/dev/null); FAILED=${FAILED:-0}
       echo "filter matched ${MATCHED} test(s); ${FAILED} failing"
       # Cluster hint from heal telemetry (healer.md §"Heal telemetry"). Tolerant of an absent
       # log; top-5 signatures = the pattern this batch likely shares.
       [ -f artifacts/heal-log.jsonl ] && jq -s 'group_by(.classification + "|" + .root_cause) | map({signature: (.[0].classification + " | " + .[0].root_cause), count: length, specs: (map(.spec) | unique)}) | sort_by(-.count) | .[:5]' artifacts/heal-log.jsonl 2>/dev/null || true
       ;;
   esac
   ```
   If the filter matched **zero tests** (`MATCHED == 0`, i.e. expected+unexpected+skipped+flaky == 0),
   say the pattern resolved to nothing and stop. **Do NOT gate this on `stats.expected == 0`** — an
   all-failing batch (every matched test red) has `expected == 0` but `unexpected > 0`, and gating on
   `expected` would abort on the exact all-red batch this command exists to fix (F-39), which bites
   hardest at the recommended narrow scope (`/qa:batch-fix tests/<area>`). If it matched tests but
   **none are failing** (`FAILED == 0 && MATCHED > 0`), report "nothing to fix" — do not invent a
   patch. Only proceed to step 2 when `FAILED > 0` (≥1 real current failure).
2. **Delegate to the `healer` subagent** to triage ONE representative failure
   end-to-end (trace, MCP replay, root cause) and extract the minimal
   selector/wait patch — do NOT triage inline; the bounded healer sandbox/turn-budget is the point. **If the healer returns a
   sentinel instead of a patch** (`artifacts/.healer-needs-*` — the representative
   failure classified as stale-context / auth-stale / data-drift / contract-change),
   close the loop per the sentinel→action table in `${CLAUDE_PLUGIN_ROOT}/reference/sentinel-actions.md` before
   re-invoking — never leave the sentinel orphaned (`/qa:doctor` check 4 flags it).
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
     `/qa:heal <test-id>`, where HEAL02 actually runs.
   Show both lists in the proposal. A wait-only pattern (no locator change) cannot land on a
   lookalike — skip the split.
4. Once confirmed, apply the patch across every **batch-eligible** spec (never touch
   assertions or the oracle contract — CLAUDE.md §Assertion style).
5. Re-run the full batch. **Re-derive the filter from `$ARGUMENTS` in THIS block — do NOT reuse `$ARG` from step 1 (F-S03):** the Bash tool starts a fresh shell per call (see §Environment in CLAUDE.md), so `$ARG` set in the step-1 block is EMPTY here, and `npx playwright test ""` silently runs the WHOLE suite — the exact max-blast-radius this command warns against. Re-bind first, then run:
   ```bash
   [ -n "${ZSH_VERSION:-}" ] && setopt shwordsplit 2>/dev/null
   set -- $ARGUMENTS
   ARG="${1:?usage: /qa:batch-fix <path-or-substring>}"   # re-derive; fail loudly rather than run everything
   npx playwright test "$ARG" --retries=0 --reporter=line
   ```
   **The `--reporter=line` override is load-bearing:** in a run-of-record context (CI, or
   `QA_RUN_OF_RECORD=1` in the environment) a bare re-run fires the config's gated
   `json` reporter, rewriting `artifacts/last-run.json` with ONLY this batch's
   subset — a later `/qa:report` then reads the subset as the whole suite and hides real
   failures elsewhere. An inline `--reporter` replaces the config array, so `last-run.json`
   (the run-of-record) is left intact. You care only about exit code / red-green here.
6. Report: how many went green, how many still red, bugs filed for any that
   don't respond to the pattern (those are likely independent product bugs), **and the
   specs step 3 excluded**, each with its ready-to-paste `/qa:heal <test-id>` — an excluded
   spec is still red, and one left off the report reads as fixed.

**Hard turn budget: 5** for the representative triage, then pure mechanical
application.
