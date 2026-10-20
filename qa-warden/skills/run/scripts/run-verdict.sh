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
# run_verdict <pw_exit> <json> <max_age_seconds> [fresh_since]
#   fresh_since  optional epoch second (the caller's `date +%s` from before the run). When given,
#                `stale` means "mtime < fresh_since", read with ONE clock read (the file's mtime)
#                and max_age is ignored. An age test can't express that: the caller's
#                `now - start` and check-last-run.sh's `now - mtime` read the clock twice, so a
#                second boundary between the two reads turned a report written in the start
#                second into `stale`.
#   Always returns 0. Sets:
#     VERDICT  one word, decided in this order (the JSON first: a missing or zero-test report
#              outranks the exit code, which is what every mode did before; then the exit code,
#              then the failure count):
#                missing     no JSON file — the run aborted before Playwright wrote it
#                corrupt     the file is not a usable report (bad JSON, no .stats)
#                zero-test   the report resolved no tests
#                stale       the file is older than max_age, or its mtime is before fresh_since —
#                            a previous run's report
#                unchecked   check-last-run.sh itself failed (missing script on an old stamp, any
#                            other exit), or fresh_since is malformed (not 1-18 digits) — never a pass
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
  local pw_exit=$1 json=$2 max_age=$3 fresh_since=${4:-} lr_rc mtime
  # A malformed anchor fails CLOSED, before it can switch the age test off: freshness was not
  # checked, so the verdict is unchecked (never a pass), like a check-last-run.sh that failed.
  # Malformed = anything but digits, or more than 18 of them (past a shell integer, so `[`
  # could not compare it; an epoch second has 10).
  case "$fresh_since" in
    *[!0-9]*|???????????????????*)
      VERDICT=unchecked; TOTAL=-1; FAILED=0
      LR="last-run: unchecked (run_verdict got a malformed freshness anchor '$fresh_since' — a run.sh bug, not a pass)"
      return 0 ;;
  esac
  # With an anchor, check-last-run.sh gets an age limit no file can exceed (~31,000 years), so
  # it still decides missing, corrupt and zero-test, in its order, and never stale; the anchor
  # test below decides that. check-last-run.sh is stamped into projects, so it stays as it is.
  [ -z "$fresh_since" ] || max_age=999999999999
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
  # The anchor test: one clock read, the file's mtime (`date -r` works on BSD and GNU). A file
  # written in the anchor second is fresh. Freshness must be PROVEN: only a comparison that
  # succeeds passes, so an unreadable mtime or any `[` error (silenced) is stale, never a pass.
  # The rewritten line keeps check-last-run.sh's shape, so callers echo it unchanged.
  if [ -n "$fresh_since" ]; then
    mtime=$(date -r "$json" +%s 2>/dev/null)
    case "$mtime" in ''|*[!0-9]*) mtime=-1 ;; esac
    if ! [ "$mtime" -ge "$fresh_since" ] 2>/dev/null; then
      VERDICT=stale
      LR="last-run: stale ${LR#last-run: fresh }"
      return 0
    fi
  fi
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
