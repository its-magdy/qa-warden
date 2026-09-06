#!/usr/bin/env bash
# post-run-checks.sh — the three advisory scans every "a run just finished, is this green
# actually all-clear?" caller needs. Advisory only: it reruns nothing, writes nothing, and
# ALWAYS exits 0 — the caller decides what a WARN means for its own verdict.
#
# Usage: bash scripts/post-run-checks.sh [--prefix <str>] [--only <a,b,c>]
#   --prefix  line prefix for each warning (default `WARN:`; /qa:doctor passes its ⚠️ marker)
#   --only    comma-separated subset of `sentinels,stray,bugs` (default: all three).
#             /qa:doctor runs `--only sentinels,stray` — it reconciles bug files itself in
#             Check 11b (evidence durability over ALL bugs, not just open ones), so surfacing
#             them here too would double-count them into its warn rollup.
#
# Prints zero or more warning lines, then ALWAYS a machine-readable trailer:
#   post-run: sentinels=<n> stray=<n> open-bugs=<n>
# so a caller can fold the counts into its roll-up (`… · 1 open bug → NOT all-clear`) without
# re-deriving them.
#
# WHY THIS EXISTS: all three scans were copy-pasted across /qa:run mode=smoke, /qa:report,
# /qa:run mode=single and doctor Checks 4/11b/14 — the sentinel one-liner was BYTE-identical in
# run-smoke and report, and the stray-spec loop's `_`-prefix filter existed in four copies that
# have to stay in lockstep with playwright.config.ts's `testIgnore`. Each copy also carried its
# own 6-10 line comment essay re-explaining the same rationale. One owner, every caller invokes it.
set -u
PREFIX='WARN:'
ONLY='sentinels,stray,bugs'
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
    --only)   ONLY="${2:?--only needs a value}"; shift 2 ;;
    *) echo "usage: post-run-checks.sh [--prefix <str>] [--only sentinels,stray,bugs]" >&2; exit 0 ;;
  esac
done
# Substring test with comma delimiters on BOTH sides so a scan name can never partial-match another.
enabled() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

n_sent=0; n_stray=0; n_bugs=0

# (1) Unprocessed healer sentinels — a stuck `.healer-needs-*` means a prior heal escalated and
# its follow-up (re-seed / re-explore / migrate) was never run, so that failure is likely STILL
# LIVE even if this run's lane is green. GLOB, don't enumerate: agents/healer.md owns the sentinel
# roster and it has grown before; a hand-kept list here silently misses the next one added there.
enabled sentinels && while IFS= read -r s; do
  [ -n "$s" ] || continue
  echo "$PREFIX unprocessed healer sentinel $s → $(cat "$s") — a prior heal escalated and its follow-up was never run; that failure is likely still live."
  n_sent=$((n_sent+1))
done < <(find artifacts -maxdepth 1 -name '.healer-needs-*' -type f 2>/dev/null)

# (2) Suite-integrity pre-flight (F-25 stray-spec) — the run of record is typically the `--grep
# @smoke` subset, but a full `npx playwright test` collects EVERY .spec.ts under tests/. An
# unmanaged spec (no paired specs/<base>.md — e.g. a `tests/_demo/failure-demo.spec.ts` left after
# a trace-capture demo) is invisible to this run's stats yet WILL run, and can fail, in a full
# suite: the green being reported is not the full-suite truth.
# EXCLUDE `_`-prefixed scratch specs in BOTH forms — basename AND directory segment — in lockstep
# with playwright.config.ts's `testIgnore: ['**/_*.spec.ts','**/_*/**']`. `-path '*/_*/*'` alone
# catches only a `_`-prefixed DIRECTORY; a `_`-prefixed BASENAME at the tests/ root (the sanctioned
# /qa:review url=<url> throwaway `tests/_audit-visual.spec.ts`) has just ONE slash and never matches it. Without
# both, the warning below is FACTUALLY WRONG for that file — it claims a full run "WILL run it" when
# testIgnore provably drops it from collection, and a false alarm trains readers to ignore a warning
# whose whole job is catching a genuinely stray spec.
enabled stray && while IFS= read -r t; do
  [ -n "$t" ] || continue
  rel="${t#tests/}"; base="${rel%.spec.ts}"; base="${base%.metamorphic}"   # twins pair by stripping .metamorphic
  [ -f "specs/${base}.md" ] && continue
  echo "$PREFIX unmanaged spec $t — no specs/${base}.md, so it sits outside the assertion contract. It is not in this run's lane, but a full 'npx playwright test' WILL collect it: qualify the go/no-go. Delete the stray spec (or pair it with a spec) and run /qa:doctor."
  n_stray=$((n_stray+1))
done < <(find tests -name '*.spec.ts' -type f ! -name '_*' ! -path '*/_*/*' 2>/dev/null)

# (3) Parked open-bug surfacing (F-17/F-19) — Playwright folds conditional `test.fail` xfails into
# the `expected` count, and a `test.fixme` in a lane this run didn't grep leaves NO trace in the
# stats at all. So a run can print "N passed" while scenarios are parked against a CONFIRMED-LIVE
# defect and a naive read looks all-clear. The scan + the resolved-keyword set are single-sourced in
# scripts/bug-status.sh --list-open (fail-safe: an unmarked or free-text Status classifies as open,
# so a defect is over-surfaced rather than laundered green).
enabled bugs && while IFS= read -r bug; do
  [ -n "$bug" ] || continue
  echo "$PREFIX open bug filed — $bug: $(grep -m1 '^# ' "$bug" 2>/dev/null | sed 's/^# //'). If a scenario is parked (test.fail/test.fixme) against it, this green is NOT all-clear."
  n_bugs=$((n_bugs+1))
done < <(bash scripts/bug-status.sh --list-open 2>/dev/null)

[ "$n_bugs" -gt 0 ] && echo "$PREFIX → $n_bugs open bug(s) on file: a run is NOT a verdict. Run /qa:report for the go/no-go quality state."

echo "post-run: sentinels=$n_sent stray=$n_stray open-bugs=$n_bugs"
exit 0
