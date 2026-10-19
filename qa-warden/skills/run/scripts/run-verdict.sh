#!/usr/bin/env bash
# run-verdict.sh — sourced by run.sh (not executed): turns ONE Playwright run into ONE word.
#
# A run has two witnesses and neither is enough alone:
#   - the JSON report: was it written, does it parse, did it resolve any tests, is it this run's?
#     That half is the project's scripts/check-last-run.sh (the same gate doctor Check 1 and
#     /qa-warden:report call) — this file calls it, never re-derives it.
#   - Playwright's exit code: a timeout, a worker crash or --max-failures exits non-zero while the
#     JSON can still show 0 failures (F-04). Read alone, that JSON is a vacuous green.
#     Playwright itself exits 0 (passed), 1 (failed / timed out / --max-failures / no tests) or
#     130 (interrupted) — `status === "interrupted" ? 130 : status === "passed" ? 0 : 1` in
#     playwright/lib/cli/testActions.js (read in 1.62.1). Anything but 0 or 1 — its own 130, or a shell
#     128+N when a signal (137 SIGKILL, 143 SIGTERM) or a crash took the process down — means the
#     run stopped early, and the failures it recorded are a partial count, not a completed red.
# Every run.sh mode used to combine the two by hand (four case tables, two copies of the
# crash guard, and batch-fix's inline precheck ignored the exit code entirely). Now each mode
# calls run_verdict and only words its own message per verdict.
#
# run_verdict <pw_exit> <json> <max_age_seconds>
#   Always returns 0. Sets:
#     VERDICT  one word, decided in this order (the JSON first: a missing or zero-test report
#              outranks the exit code, which is what every mode did before; then the exit code,
#              then the failure count):
#                missing     no JSON file — the run aborted before Playwright wrote it
#                corrupt     the file is not a usable report (bad JSON, no .stats)
#                zero-test   the report resolved no tests
#                stale       the file is older than max_age — a previous run's report
#                unchecked   check-last-run.sh itself failed (missing script on an old stamp, any
#                            other exit) — never a pass
#                incomplete  the run did not complete: an exit other than 0 or 1 (interrupted,
#                            killed by a signal, crashed) whatever the failure count, OR exit 1
#                            with 0 failures recorded — timeout / --max-failures / worker crash
#                red         exit 0 or 1 and ≥1 test failed — the run completed with failures
#                green       exit 0 and 0 failures
#     LR       check-last-run.sh's one line (`last-run: <status> total=<n> …`), for the caller to echo
#     TOTAL    resolved tests (expected+unexpected+skipped+flaky), from that line; -1 when unknown
#     FAILED   .stats.unexpected; 0 unless the JSON is usable
#
# Like every plugin script, this calls the STAMPED helper (reference/DESIGN.md: "Plugin scripts
# call the project's STAMPED helpers"), so it relies only on check-last-run.sh's long-stable CLI:
# the one line, exit codes 0/3/4/5/6. Run from the PROJECT root, like run.sh. Bash 3.2 safe.

# shellcheck disable=SC2034  # VERDICT/LR/TOTAL/FAILED are outputs, read by the caller that sources this
run_verdict() {
  local pw_exit=$1 json=$2 max_age=$3 lr_rc
  LR=$(bash scripts/check-last-run.sh "$json" "$max_age" 2>/dev/null); lr_rc=$?
  TOTAL=${LR##*total=}; TOTAL=${TOTAL%% *}
  case "$TOTAL" in ''|*[!0-9-]*) TOTAL=-1 ;; esac
  FAILED=0
  case "$lr_rc" in
    3) VERDICT=missing;   return 0 ;;
    4) VERDICT=corrupt;   return 0 ;;
    5) VERDICT=zero-test; return 0 ;;
    6) VERDICT=stale;     return 0 ;;
    0) : ;;
    *) VERDICT=unchecked
       LR="last-run: unchecked (scripts/check-last-run.sh exited $lr_rc — missing script? re-run /qa-warden:init --resync)"
       return 0 ;;
  esac
  # rc 0 means .stats parsed, so `// 0` only covers a stats block without the key.
  FAILED=$(jq '.stats.unexpected // 0' "$json" 2>/dev/null)
  case "$FAILED" in ''|*[!0-9]*) FAILED=0 ;; esac
  # Only a literal 0 or 1 is an exit from a run that finished; an empty or non-numeric code, a
  # 130 or a signal's 128+N is not — checked before the failure count, so an interrupted run's
  # partial failures never read as a batch to fix or a red to summarize.
  case "$pw_exit" in
    0|1) : ;;
    *) VERDICT=incomplete; return 0 ;;
  esac
  if [ "$FAILED" -gt 0 ]; then
    VERDICT=red
  elif [ "$pw_exit" = 0 ]; then
    VERDICT=green
  else
    VERDICT=incomplete
  fi
  return 0
}
