#!/usr/bin/env bash
# run.sh — deterministic run+guard for /qa-warden:run, all four modes, plus /qa-warden:batch-fix's
# step-1 precheck and step-5 recheck.
#
# Consolidates the three former single-purpose runners (headless, run-smoke,
# flake-check) behind one entry point. Each mode keeps its ORIGINAL on-disk
# output shape byte-for-byte (reports/headless-<name>.json, artifacts/last-run.json
# via the config json sink, artifacts/flake-<name>.json) — this is a consolidation
# of the entry point, not a behavior/output-path change, so every downstream
# consumer (/qa-warden:report, /qa-warden:heal, the reviewer's rail manifest) keeps working
# unmodified.
#
# The skill (../SKILL.md) owns the caveats and the summary/output format; this
# script owns the shell recipes (arg binding, resolver calls, run + guards,
# post-run scans) and must never format, paraphrase, or estimate a summary itself.
# Run from the PROJECT root (cwd), not from the plugin dir — every path below is
# project-relative.
#
# Usage:
#   run.sh single <spec-path-or-test-path>
#   run.sh smoke
#   run.sh repeat <spec-path-or-test-path> [N]
#   run.sh changed [<git-ref>]
#   run.sh precheck <path-or-substring>      (/qa-warden:batch-fix step 1 only)
#   run.sh recheck <path-or-substring>       (/qa-warden:batch-fix step 5 only)
#
# Exit codes (the four /qa-warden:run modes): 0 = completed cleanly, caller reads the named JSON
# and summarizes. 2 = do NOT report a pass — the printed reason names why
# (missing/stale/corrupt/zero-test JSON, a non-zero Playwright exit masked by a
# 0-failure JSON — F-04 — a run interrupted or killed before it finished, or a
# resolver/validation failure).
# precheck: 0 = ≥1 test failing, batch-fix proceeds · 1 = nothing to fix, or the filter matched
# nothing — batch-fix stops · 2 = no usable result, batch-fix stops and relays the reason.
# recheck: 0 = green · 1 = not green (still red, crashed or matched nothing — indistinguishable
# from the line reporter) · 2 = no filter given.
#
# Every mode reads its run through ONE verdict (run-verdict.sh, beside this file): the exit code
# AND the JSON become one word — green / red / incomplete / missing / corrupt / zero-test / stale /
# unchecked — and each mode only words its own message per word.
#
# NOTE: prod-guard is invoked by the SKILL body (not here) so the STOP-on-non-zero
# rail stays on the same line qa-selfcheck Check 9bd expects — do not move it into this
# script.
#
# NOTE: deliberately NO `-e`. $PW_EXIT must be captured even though Playwright can
# exit non-zero (test failures, timeout, --max-failures, worker crash, no-tests-matched),
# and every `case`/`if` arm from there on inspects a non-zero rc on purpose — `-e` would
# abort the script before those guards ever run.
set -uo pipefail

# Accept BOTH `run.sh smoke …` and the skill's raw `run.sh mode=smoke …` (the `mode=` token may
# sit anywhere). The skill used to bind `mode=` in an inline multi-line shell block before calling
# this script; only `bash …/run.sh *` is pre-approved, so that block prompted — and was denied
# headless (Test-35, 2026-09-21). Parsing here keeps the whole invocation one allow-listed call.
# precheck/recheck are the exception: batch-fix passes its raw $ARGUMENTS after the mode word,
# so every argument after it is filter data — a filter like `mode=smoke` must not pick a mode.
MODE=""; _rest=()
case "${1:-}" in
  precheck|recheck)
    MODE=$1; shift
    _rest=("$@") ;;
  *)
    for _a in "$@"; do
      case "$_a" in
        mode=*) MODE="${_a#mode=}" ;;
        *) _rest+=("$_a") ;;
      esac
    done
    if [ -z "$MODE" ] && [ "${#_rest[@]}" -gt 0 ]; then MODE="${_rest[0]}"; _rest=("${_rest[@]:1}"); fi
    ;;
esac
set -- ${_rest[@]+"${_rest[@]}"}

# run_verdict <pw_exit> <json> <max_age> → $VERDICT $LR $TOTAL $FAILED (see that file's header).
. "$(dirname "${BASH_SOURCE[0]}")/run-verdict.sh"

# The `incomplete` message, shared by every mode. $1 = mode label, $2 = what to inspect.
incomplete_exit() {
  echo "run($1): playwright exited $PW_EXIT with $FAILED failure(s) recorded — the run did NOT complete cleanly"
  echo "(exit 1 with 0 failures: timeout / --max-failures / worker crash; any exit but 0 or 1: interrupted, killed"
  echo "or crashed, so any recorded failures are a partial count). NOT green, NOT a finished red; inspect $2 and re-run."
  exit 2
}

case "$MODE" in
  single)
    # ---- single: CI-shaped one-shot run of ONE spec (formerly /qa-warden:headless) ----
    ARG="${1:?usage: /qa-warden:run mode=single <spec-path-or-test-path>}"
    mkdir -p reports artifacts   # guard: redirect targets must exist (else the run aborts before Playwright starts)
    # This runs the COMPILED TEST. Map every accepted form (bare <area>/<feature>, .md
    # spec, test path) to it AND verify it exists via the canonical resolver — a raw .md
    # path matches ZERO tests (testDir is ./tests) and the report would be a phantom
    # 0-test "run". Missing script → re-run /qa-warden:init to stamp it.
    TEST=$(bash scripts/resolve-spec-path.sh test "$ARG") || exit 2
    # Report slug from the SAME canonical resolver (`reportname` mode) — area-qualified
    # (auth/login → auth-login) so two areas' same-named specs can't clobber each other's
    # report files.
    name=$(bash scripts/resolve-spec-path.sh reportname "$ARG") || exit 2
    npx playwright test "$TEST" \
      --reporter=json \
      > "reports/headless-$name.json" 2> "reports/headless-$name.log"
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    run_verdict "$PW_EXIT" "reports/headless-$name.json" 900
    echo "run(single): $LR (verdict=$VERDICT)"
    case "$VERDICT" in
      green|red) : ;;
      missing)    echo "run(single): no JSON — startup error (prod-guard/config), not a green run. See reports/headless-$name.log."; exit 2 ;;
      corrupt)    echo "run(single): unparseable JSON — do NOT report a pass. See reports/headless-$name.log."; exit 2 ;;
      zero-test)  echo "run(single): resolved no tests — a resolution error, not a pass."; exit 2 ;;
      incomplete) incomplete_exit single "reports/headless-$name.log" ;;
      *)          echo "run(single): $VERDICT report — NOT a pass."; exit 2 ;;
    esac
    echo "run(single): report at reports/headless-$name.json (log: reports/headless-$name.log)"
    bash scripts/post-run-checks.sh --only bugs
    exit 0
    ;;

  smoke)
    # ---- smoke: run the @smoke-tagged suite (formerly /qa-warden:run-smoke) ----
    mkdir -p artifacts
    RUN_START=$(date +%s)   # freshness anchor — the guard below requires last-run.json to be newer than this
    QA_RUN_OF_RECORD=1 npx playwright test --grep @smoke
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.

    # Freshness + zero-test + corrupt-JSON gate (check-last-run.sh, via run_verdict — the same gate
    # /qa-warden:report and doctor Check 1 call). Passing `now - RUN_START` as max_age makes the
    # staleness predicate exactly "mtime < RUN_START": an ABORTED run (prod-guard throw in
    # globalSetup, config syntax error) leaves the PREVIOUS run's file on disk and lands in the
    # `stale` arm below.
    run_verdict "$PW_EXIT" artifacts/last-run.json "$(( $(date +%s) - RUN_START ))"
    echo "$LR"
    case "$VERDICT" in
      green|red) : ;;
      missing|stale)
        echo "run(smoke) produced NO report — artifacts/last-run.json is missing or predates"
        echo "this run (the run aborted before Playwright wrote it: prod-guard? config error?)."
        echo "Do NOT summarize the stale file. Fix the abort cause and re-run."
        exit 2 ;;
      corrupt)
        echo "last-run.json unparseable — do NOT report a pass. Fix the run and re-run."
        exit 2 ;;
      zero-test)
        echo "run(smoke) resolved NO tests — --grep @smoke matched nothing (RESOLUTION ERROR,"
        echo "not a green run — check the @smoke tags / spec paths). Do NOT report a pass."
        exit 2 ;;
      incomplete)
        incomplete_exit smoke "the output above" ;;
      *)
        echo "run(smoke): $VERDICT report — do NOT report a pass."
        exit 2 ;;
    esac

    if ! bash scripts/post-run-checks.sh; then
      echo "run(smoke): scripts/post-run-checks.sh failed to run (missing script? wrong cwd?) —"
      echo "sentinel/stray/open-bug scans did NOT run. Do not report a pass without them."
      exit 2
    fi
    exit 0
    ;;

  repeat)
    # ---- repeat: run the same spec N times back-to-back (formerly /qa-warden:flake-check) ----
    ARG="${1:?usage: /qa-warden:run mode=repeat <spec-path-or-test-path> [N]}"
    N="${2:-10}"
    case "$N" in ''|*[!0-9]*) echo "run(repeat): N must be a positive integer (got '$N') — a mis-typed flag or path in slot 2 would otherwise run each test only ONCE and report a false 'stable'."; exit 2 ;; esac
    [ "$N" -ge 1 ] || { echo "run(repeat): N must be >= 1 (got '$N')."; exit 2; }
    # Map every accepted argument form (bare <area>/<feature>, .md spec, test path) to
    # the compiled test AND verify it exists, via the canonical resolver — a raw .md
    # path matches ZERO tests (testDir is ./tests) and would otherwise be counted as a
    # 100%-stable pass on nothing (the false-green this toolkit exists to prevent).
    TEST=$(bash scripts/resolve-spec-path.sh test "$ARG") || exit 2
    mkdir -p artifacts   # guard: redirect target must exist
    # Report slug from the SAME canonical resolver (`reportname` mode) — area-qualified
    # so two areas' same-named specs can't clobber each other's report files.
    name=$(bash scripts/resolve-spec-path.sh reportname "$ARG") || exit 2
    # ONE invocation with --repeat-each, not N separate runs: every extra invocation
    # pays full Playwright startup. --workers=1 keeps the repeats back-to-back serial
    # (what a repeatability probe wants); --retries=0 so a flake can't hide behind a retry.
    # The inline --reporter=json replaces the config reporter array, so this probe can
    # never clobber artifacts/last-run.json (the run-of-record). Never `2>&1` into the
    # .json — stderr would corrupt it. A red repeat is a result, not an abort: the verdict
    # below lets `red` through.
    npx playwright test "$TEST" --repeat-each="$N" --workers=1 --retries=0 --reporter=json \
      > "artifacts/flake-$name.json" 2> "artifacts/flake-$name.log"
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    # An aborted run (prod-guard throw in globalSetup, config error) leaves an empty or
    # stats-less report; both jq passes below would then print NOTHING and exit 0. A crashed
    # one (non-zero exit, 0 failures recorded) would read as 100% stable on the repeats that ran.
    run_verdict "$PW_EXIT" "artifacts/flake-$name.json" 900
    case "$VERDICT" in
      green|red) : ;;
      incomplete) incomplete_exit repeat "artifacts/flake-$name.log" ;;
      *)
        echo "run(repeat): the probe did not produce a usable report (verdict=$VERDICT) — no stability measured; inspect artifacts/flake-$name.log."
        exit 2 ;;
    esac

    # Each repeat is a separate test entry in ONE report: stats.expected = passed
    # executions, stats.unexpected = failed. Zero executions means the path resolved
    # to no runnable test — surface that (null pass rate), never a fabricated 100%.
    jq '{
      executed:       (.stats.expected + .stats.unexpected),
      passed:         .stats.expected,
      failed:         .stats.unexpected,
      pass_rate_pct:  (if (.stats.expected + .stats.unexpected) == 0 then null
                       else (.stats.expected * 100) / (.stats.expected + .stats.unexpected) end),
      durations_ms:   [.. | .results? // empty | .[] | .duration]
    }' "artifacts/flake-$name.json"

    # PER-TITLE worst stability (F-41) — the aggregate above DILUTES a localized flake.
    # Group by spec title and count at the TEST-OUTCOME level (`.tests[].status` ∈
    # expected/unexpected/flaky/skipped) — NOT the result level (`.results[].status`
    # ∈ passed/failed/timedOut/skipped) — see P-13: a parked test.fail() has RESULT
    # status "failed" but test OUTCOME "expected". Counting OUTCOME == "expected" as
    # stable treats both a reliable pass AND a reliable expected-fail as 100% stable.
    # A "skipped" repeat (parked test.fixme / test.skip guard) is EXCLUDED from the
    # denominator, not counted as a 0/N red. Sorted WORST-first.
    jq '[ .. | objects | select(has("title") and has("tests"))
          | .title as $t | .tests[]
          | { title: $t, outcome: .status } ]
        | group_by(.title)
        | map( (map(select(.outcome != "skipped")) | length) as $executed
             | { title: .[0].title, runs: length,
                 stable:   (map(select(.outcome == "expected")) | length),
                 skipped:  (map(select(.outcome == "skipped")) | length),
                 executed: $executed,
                 pass_rate_pct: (if $executed == 0 then null
                                 else (map(select(.outcome == "expected")) | length) * 100 / $executed end) })
        | sort_by(.pass_rate_pct // 101)' "artifacts/flake-$name.json"
    exit 0
    ;;

  changed)
    # ---- changed: run only the tests git says this change touches (Playwright --only-changed) ----
    # A PR-speed lane, never the run-of-record: inline --reporter=json replaces the config
    # reporter array, so artifacts/last-run.json is untouched (same reasoning as `repeat`).
    REF="${1:-}"
    # Both guards exist because Playwright answers each of these with "0 tests, exit 0" and NO
    # error (measured on a scratch repo, 2026-09-21) — indistinguishable from "nothing changed":
    #   - a repo with no commit yet (fresh project: every file untracked, HEAD unborn)
    #   - a ref that does not resolve (a typo in `main`)
    git rev-parse --verify -q HEAD >/dev/null 2>&1 \
      || { echo "run(changed): no git commit yet (or not a git repo) — --only-changed has no baseline and would silently select 0 tests. Commit once, or use mode=smoke."; exit 2; }
    if [ -n "$REF" ]; then
      git rev-parse --verify -q "$REF^{commit}" >/dev/null 2>&1 \
        || { echo "run(changed): ref '$REF' does not resolve to a commit — Playwright would silently select 0 tests for it. Check the branch name (origin/main?)."; exit 2; }
    fi
    mkdir -p reports
    OC="--only-changed"; [ -n "$REF" ] && OC="--only-changed=$REF"
    npx playwright test "$OC" \
      --reporter=json \
      > reports/changed.json 2> reports/changed.log
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    run_verdict "$PW_EXIT" reports/changed.json 900
    echo "run(changed): $LR (verdict=$VERDICT)"

    # Specs are Markdown — no test imports them, so an edited spec selects NOTHING. Name them:
    # an edited spec's test is stale until /qa-warden:gen recompiles it, which a re-run cannot fix.
    CHANGED_SPECS=$( { git diff --name-only ${REF:-HEAD} -- specs/ 2>/dev/null; git ls-files --others --exclude-standard -- specs/ 2>/dev/null; } \
      | grep -E '^specs/.*\.md$' | grep -v '^specs/_context/' | sort -u )
    if [ -n "$CHANGED_SPECS" ]; then
      echo "run(changed): spec(s) edited — NOT selected by --only-changed (no test imports a .md). Their tests are stale until /qa-warden:gen recompiles them:"
      printf '%s\n' "$CHANGED_SPECS" | sed 's/^/  - /'
    fi

    case "$VERDICT" in
      green|red) : ;;
      zero-test)  echo "run(changed): NOTHING SELECTED — no changed test, page-object or fixture file${REF:+ vs $REF}. Nothing ran; this is NOT a pass of anything."; exit 0 ;;
      missing)    echo "run(changed): no JSON — startup error (prod-guard/config), not a green run. See reports/changed.log."; exit 2 ;;
      incomplete) incomplete_exit changed reports/changed.log ;;
      *)          echo "run(changed): $VERDICT JSON — do NOT report a pass."; exit 2 ;;
    esac
    echo "run(changed): report at reports/changed.json (log: reports/changed.log)"
    bash scripts/post-run-checks.sh --only bugs
    exit 0
    ;;

  precheck)
    # ---- precheck: /qa-warden:batch-fix step 1 — the CURRENT failing set for one filter ----
    # Not a /qa-warden:run mode: batch-fix calls it under its own allow rule. It used to be an inline
    # block in batch-fix's SKILL.md that never read Playwright's exit code (`|| true`), so a timeout
    # or worker crash with 0 recorded failures landed in "nothing to fix" — a vacuous green.
    # Required: an empty filter would run the WHOLE suite, and the healer would then "diagnose a
    # pattern" across every unrelated failure (maximum blast radius for a batch tool).
    # (Not `${1:?}`: that exits 1, which here means "nothing to fix".)
    ARG="${1:-}"
    [ -n "$ARG" ] || { echo "run(precheck): usage: /qa-warden:batch-fix <path-or-substring> — a filter is required. Do NOT proceed."; exit 2; }
    mkdir -p artifacts   # guard: the redirect target MUST exist (F-S05), else a FALSE "nothing matched"
    # --retries=0 so a flaky failure counts as failing. The inline --reporter=json replaces the
    # config reporter array, so artifacts/last-run.json (the run-of-record) is never clobbered.
    npx playwright test "$ARG" --retries=0 --reporter=json \
      > artifacts/batch-fix-precheck.json 2> artifacts/batch-fix-precheck.log
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    # TOTAL is check-last-run's total (expected+unexpected+skipped+flaky), never `.stats.expected`
    # alone: an all-red batch has expected=0 and would read as "matched nothing" (F-39).
    run_verdict "$PW_EXIT" artifacts/batch-fix-precheck.json 900
    echo "run(precheck): $LR (verdict=$VERDICT)"
    case "$VERDICT" in
      red)
        echo "run(precheck): filter matched $TOTAL test(s); $FAILED failing — proceed to step 2."
        # Cluster hint from heal telemetry (healer.md §"Heal telemetry"). Tolerant of an absent
        # log; top-5 signatures = the pattern this batch likely shares.
        if [ -f artifacts/heal-log.jsonl ]; then
          echo "run(precheck): top heal-log signatures (cluster hint):"
          jq -s 'group_by(.classification + "|" + .root_cause) | map({signature: (.[0].classification + " | " + .[0].root_cause), count: length, specs: (map(.spec) | unique)}) | sort_by(-.count) | .[:5]' artifacts/heal-log.jsonl 2>/dev/null || true
        fi
        exit 0 ;;
      green)
        echo "run(precheck): filter matched $TOTAL test(s); 0 failing — nothing to fix. Stop."
        exit 1 ;;
      zero-test)
        echo "run(precheck): filter matched 0 tests — the pattern resolved to nothing. Stop."
        exit 1 ;;
      incomplete)
        incomplete_exit precheck artifacts/batch-fix-precheck.log ;;
      missing|corrupt)
        echo "run(precheck): no valid JSON — Playwright failed to start (globalSetup/prod-guard/config?); see artifacts/batch-fix-precheck.log."
        echo "This is NOT 'nothing matched'. Fix that first; do NOT proceed to step 2."
        exit 2 ;;
      *)
        echo "run(precheck): $VERDICT report — no usable result. Do NOT proceed to step 2."
        exit 2 ;;
    esac
    ;;

  recheck)
    # ---- recheck: /qa-warden:batch-fix step 5 — re-run the batch after the patch ----
    # Was another inline block in batch-fix's SKILL.md (re-binding $ARGUMENTS by hand). Required
    # filter, refused when empty — not `${1:?}`, whose exit 1 here would read as "still red".
    ARG="${1:-}"
    [ -n "$ARG" ] || { echo "run(recheck): usage: /qa-warden:batch-fix <path-or-substring> — a filter is required (an empty one would run the WHOLE suite)."; exit 2; }
    # The `--reporter=line` override is LOAD-BEARING: in a run-of-record context (CI, or
    # QA_RUN_OF_RECORD=1 in the environment) a bare re-run fires the config's gated `json`
    # reporter and rewrites artifacts/last-run.json with ONLY this batch's subset — a later
    # /qa-warden:report then reads the subset as the whole suite and hides real failures elsewhere.
    # An inline --reporter replaces the config array, so last-run.json is left intact.
    npx playwright test "$ARG" --retries=0 --reporter=line
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    # No JSON here, so no verdict: only the exit code. Playwright exits 1 for failures, a
    # crash and "No tests found" alike, so a non-zero exit is reported as one outcome.
    if [ "$PW_EXIT" -eq 0 ]; then
      echo "run(recheck): green — every test matching '$ARG' passed."
      exit 0
    fi
    echo "run(recheck): NOT green (playwright exit $PW_EXIT) — still red, OR the run crashed / matched"
    echo "nothing; the line reporter cannot tell these apart. Read the output above for the counts."
    exit 1
    ;;

  *)
    echo "run.sh: unknown or missing mode '$MODE' — usage: run.sh <single|smoke|repeat|changed|precheck|recheck> [args...]"
    exit 2
    ;;
esac
