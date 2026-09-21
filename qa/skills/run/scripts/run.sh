#!/usr/bin/env bash
# run.sh — deterministic run+guard for /qa:run, all four modes.
#
# Consolidates the three former single-purpose runners (headless, run-smoke,
# flake-check) behind one entry point. Each mode keeps its ORIGINAL on-disk
# output shape byte-for-byte (reports/headless-<name>.json, artifacts/last-run.json
# via the config json sink, artifacts/flake-<name>.json) — this is a consolidation
# of the entry point, not a behavior/output-path change, so every downstream
# consumer (/qa:report, /qa:heal, the reviewer's rail manifest) keeps working
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
#
# Exit codes (all modes): 0 = completed cleanly, caller reads the named JSON and
# summarizes. 2 = do NOT report a pass — the printed reason names why
# (missing/stale/corrupt/zero-test JSON, a non-zero Playwright exit masked by a
# 0-failure JSON — F-04 — or a resolver/validation failure).
#
# NOTE: prod-guard is invoked by the SKILL body (not here) so the STOP-on-non-zero
# rail stays on the same line doctor Check 9bd expects — do not move it into this
# script.
#
# NOTE: deliberately NO `-e`. $PW_EXIT must be captured even though Playwright can
# exit non-zero (test failures, timeout, --max-failures, worker crash, no-tests-matched),
# and every `case`/`if` arm from there on inspects a non-zero rc on purpose — `-e` would
# abort the script before those guards ever run.
set -uo pipefail

MODE="${1:-}"
shift || true

case "$MODE" in
  single)
    # ---- single: CI-shaped one-shot run of ONE spec (formerly /qa:headless) ----
    ARG="${1:?usage: /qa:run mode=single <spec-path-or-test-path>}"
    mkdir -p reports artifacts   # guard: redirect targets must exist (else the run aborts before Playwright starts)
    # This runs the COMPILED TEST. Map every accepted form (bare <area>/<feature>, .md
    # spec, test path) to it AND verify it exists via the canonical resolver — a raw .md
    # path matches ZERO tests (testDir is ./tests) and the report would be a phantom
    # 0-test "run". Missing script → re-run /qa:init to stamp it.
    TEST=$(bash scripts/resolve-spec-path.sh test "$ARG") || exit 2
    # Report slug from the SAME canonical resolver (`reportname` mode) — area-qualified
    # (auth/login → auth-login) so two areas' same-named specs can't clobber each other's
    # report files.
    name=$(bash scripts/resolve-spec-path.sh reportname "$ARG") || exit 2
    npx playwright test "$TEST" \
      --reporter=json \
      > "reports/headless-$name.json" 2> "reports/headless-$name.log"
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.
    LR=$(bash scripts/check-last-run.sh "reports/headless-$name.json" 900); lr_rc=$?
    echo "run(single): $LR (rc=$lr_rc)"
    if [ "$lr_rc" -eq 0 ] && [ "${PW_EXIT:-1}" -ne 0 ] && [ "$(jq '.stats.unexpected // 0' "reports/headless-$name.json" 2>/dev/null)" -eq 0 ]; then
      echo "run(single): playwright exited non-zero ($PW_EXIT) but the report shows 0 failures —"
      echo "the run did NOT complete cleanly (timeout / worker crash). NOT green; inspect the .log and re-run."
      exit 2
    fi
    case "$lr_rc" in
      0) : ;;
      3) echo "run(single): no/unparseable-as-missing JSON — startup error (prod-guard/config), not a green run."; exit 2 ;;
      4) echo "run(single): unparseable JSON — do NOT report a pass."; exit 2 ;;
      5) echo "run(single): resolved no tests — a resolution error, not a pass."; exit 2 ;;
    esac
    echo "run(single): report at reports/headless-$name.json (log: reports/headless-$name.log)"
    bash scripts/post-run-checks.sh --only bugs
    exit 0
    ;;

  smoke)
    # ---- smoke: run the @smoke-tagged suite (formerly /qa:run-smoke) ----
    mkdir -p artifacts
    RUN_START=$(date +%s)   # freshness anchor — the guard below requires last-run.json to be newer than this
    QA_RUN_OF_RECORD=1 npx playwright test --grep @smoke
    PW_EXIT=$?   # F-04: CAPTURE the exit code NOW — see header note.

    # Freshness + zero-test + corrupt-JSON gate — single-sourced in scripts/check-last-run.sh
    # (the same gate /qa:report and doctor Check 1 call). Passing `now - RUN_START` as max_age
    # makes the script's staleness predicate exactly "mtime < RUN_START": an ABORTED run
    # (prod-guard throw in globalSetup, config syntax error) leaves the PREVIOUS run's file on
    # disk and lands in the rc-6 arm below. Script exit codes: 3=missing 4=corrupt 5=zero-test 6=stale.
    bash scripts/check-last-run.sh artifacts/last-run.json "$(( $(date +%s) - RUN_START ))"
    lr_rc=$?
    case "$lr_rc" in
      0) : ;;
      3|6)
        echo "run(smoke) produced NO report — artifacts/last-run.json is missing or predates"
        echo "this run (the run aborted before Playwright wrote it: prod-guard? config error?)."
        echo "Do NOT summarize the stale file. Fix the abort cause and re-run."
        exit 2 ;;
      4)
        echo "last-run.json unparseable — do NOT report a pass. Fix the run and re-run."
        exit 2 ;;
      5)
        echo "run(smoke) resolved NO tests — --grep @smoke matched nothing (RESOLUTION ERROR,"
        echo "not a green run — check the @smoke tags / spec paths). Do NOT report a pass."
        exit 2 ;;
      *)
        echo "check-last-run.sh returned unexpected exit $lr_rc — do NOT report a pass."
        exit 2 ;;
    esac

    if [ "${PW_EXIT:-1}" -ne 0 ] && [ "$(jq '.stats.unexpected // 0' artifacts/last-run.json)" -eq 0 ]; then
      echo "run(smoke): playwright exited non-zero ($PW_EXIT) but last-run.json shows 0 failures —"
      echo "the run did NOT complete cleanly (timeout / --max-failures / worker crash). NOT green."
      echo "Inspect the output above; do not report a pass. Fix the abort cause and re-run."
      exit 2
    fi

    if ! bash scripts/post-run-checks.sh; then
      echo "run(smoke): scripts/post-run-checks.sh failed to run (missing script? wrong cwd?) —"
      echo "sentinel/stray/open-bug scans did NOT run. Do not report a pass without them."
      exit 2
    fi
    exit 0
    ;;

  repeat)
    # ---- repeat: run the same spec N times back-to-back (formerly /qa:flake-check) ----
    ARG="${1:?usage: /qa:run mode=repeat <spec-path-or-test-path> [N]}"
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
    # .json — stderr would corrupt it. The `|| true` (a red repeat must not abort the
    # probe) is safe ONLY because $TEST is pre-verified.
    npx playwright test "$TEST" --repeat-each="$N" --workers=1 --retries=0 --reporter=json \
      > "artifacts/flake-$name.json" 2> "artifacts/flake-$name.log" || true

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
    LR=$(bash scripts/check-last-run.sh reports/changed.json 900); lr_rc=$?
    echo "run(changed): $LR (rc=$lr_rc)"

    # Specs are Markdown — no test imports them, so an edited spec selects NOTHING. Name them:
    # an edited spec's test is stale until /qa:gen recompiles it, which a re-run cannot fix.
    CHANGED_SPECS=$( { git diff --name-only ${REF:-HEAD} -- specs/ 2>/dev/null; git ls-files --others --exclude-standard -- specs/ 2>/dev/null; } \
      | grep -E '^specs/.*\.md$' | grep -v '^specs/_context/' | sort -u )
    if [ -n "$CHANGED_SPECS" ]; then
      echo "run(changed): spec(s) edited — NOT selected by --only-changed (no test imports a .md). Their tests are stale until /qa:gen recompiles them:"
      printf '%s\n' "$CHANGED_SPECS" | sed 's/^/  - /'
    fi

    case "$lr_rc" in
      0) : ;;
      5) echo "run(changed): NOTHING SELECTED — no changed test, page-object or fixture file${REF:+ vs $REF}. Nothing ran; this is NOT a pass of anything."; exit 0 ;;
      3) echo "run(changed): no JSON — startup error (prod-guard/config), not a green run. See reports/changed.log."; exit 2 ;;
      *) echo "run(changed): unparseable/stale JSON (rc=$lr_rc) — do NOT report a pass."; exit 2 ;;
    esac
    if [ "${PW_EXIT:-1}" -ne 0 ] && [ "$(jq '.stats.unexpected // 0' reports/changed.json 2>/dev/null)" -eq 0 ]; then
      echo "run(changed): playwright exited non-zero ($PW_EXIT) but the report shows 0 failures —"
      echo "the run did NOT complete cleanly (timeout / worker crash). NOT green; inspect reports/changed.log and re-run."
      exit 2
    fi
    echo "run(changed): report at reports/changed.json (log: reports/changed.log)"
    bash scripts/post-run-checks.sh --only bugs
    exit 0
    ;;

  *)
    echo "run.sh: unknown or missing mode '$MODE' — usage: run.sh <single|smoke|repeat|changed> [args...]"
    exit 2
    ;;
esac
