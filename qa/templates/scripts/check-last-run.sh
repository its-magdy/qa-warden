#!/usr/bin/env bash
# Canonical last-run.json gate — single source for /qa:doctor Check 1 and /qa:report's
# pre-aggregation check (they used to mirror this in prose and drifted).
# total = expected+unexpected+skipped+flaky (NOT expected alone — that counts only PASSED
# tests; an all-red run has expected=0).
#
# Usage: check-last-run.sh [file] [max_age_seconds]
#   defaults: artifacts/last-run.json, 900
#
# Prints ONE line:
#   last-run: <fresh|missing|corrupt|zero-test|stale> total=<n> startTime=<t> age=<s>s
#
# Exit codes:
#   0 fresh · 3 missing · 4 corrupt (total<0: bad JSON / no .stats / no jq)
#   5 zero-test (total==0) · 6 stale (age > max_age_seconds)
set -u

FILE="${1:-artifacts/last-run.json}"
MAX_AGE="${2:-900}"

if [ ! -f "$FILE" ]; then
  echo "last-run: missing total=-1 startTime=? age=?s"
  exit 3
fi

# Canonical TOTAL formula — every RESOLVED test, whatever its outcome. A missing/broken
# .stats (or a jq failure) yields -1, never 0: corrupt must not read as zero-test.
# ONE jq pass for both fields: this script is on the hot path of doctor Check 1, /qa:report (×2),
# /qa:run mode=smoke, /qa:run mode=single and /qa:batch-fix, and two invocations meant every one of them paid
# to parse the same JSON twice. `// "?"` covers a null startTime; the `||` fallback covers a jq
# failure, so both halves of the read are always non-empty.
read -r TOTAL START <<EOF
$(jq -r 'if .stats then "\((.stats.expected // 0)+(.stats.unexpected // 0)+(.stats.skipped // 0)+(.stats.flaky // 0)) \(.stats.startTime // "?")" else "-1 ?" end' "$FILE" 2>/dev/null || echo "-1 ?")
EOF
# Belt-and-suspenders: anything non-numeric (partial jq output, empty, a bare `-`) counts as
# corrupt. The alternatives here are exhaustive, so $TOTAL is a validated integer or -1 after this.
case "$TOTAL" in ''|*[!0-9-]*|-|*-*-*) TOTAL=-1 ;; esac
START="${START:-?}"

# mtime age — `date -r <file> +%s` = file mtime as epoch (works on BSD/macOS AND GNU).
AGE=$(( $(date +%s) - $(date -r "$FILE" +%s) ))

if [ "$TOTAL" -lt 0 ]; then
  echo "last-run: corrupt total=$TOTAL startTime=$START age=${AGE}s"
  exit 4
elif [ "$TOTAL" -eq 0 ]; then
  echo "last-run: zero-test total=$TOTAL startTime=$START age=${AGE}s"
  exit 5
elif [ "$AGE" -gt "$MAX_AGE" ]; then
  echo "last-run: stale total=$TOTAL startTime=$START age=${AGE}s"
  exit 6
fi

echo "last-run: fresh total=$TOTAL startTime=$START age=${AGE}s"
exit 0
