#!/bin/sh
# review-marker.sh — write the /qa-warden:review attestation marker for ONE reviewed spec/test pair.
#
# WHY THIS EXISTS (Test-35, 2026-09-21): /qa-warden:review described the marker's five fields in prose
# and left the agent to improvise the shell — `git rev-parse HEAD && shasum … && date`, a
# `mkdir -p … && printf …` with an inline function. None of those compound forms matches an
# allow rule (a rule must match every subcommand), so each one prompted, and was denied headless:
# 4 denied calls in a single review. One allow-listed call, and the digest fallback that
# /qa-warden:doctor Check 15 depends on lives in one place instead of being re-typed per run.
#
# WHERE IT LIVES: in the plugin, beside the review skill, and run from there. It used to be stamped
# into every project as scripts/review-marker.sh, but nothing in a project called it except this
# skill, so the copy was substrate to resync and two settings.json rules to keep in step. The
# skill's allowed-tools rule pre-approves exactly this path. A project stamped earlier keeps an
# inert scripts/review-marker.sh; /qa-warden:doctor names it as safe to delete.
#
# Usage (from the QA project root; the paths below are relative to it):
#   bash "${CLAUDE_SKILL_DIR}/scripts/review-marker.sh" <spec.md> <test.spec.ts> PASS|FAIL
# Writes: reports/review/<area>/<feature>.reviewed   (path derived from the spec path)
#   Fields: commit, spec_sha256, test_sha256, date, result. /qa-warden:doctor Check 15 reads them
#   and WARNs when the pair changed since its marker.
#
# Refuses (exit 2, writes nothing): wrong arg count, a verdict other than PASS/FAIL, a spec not
# under specs/ or a test not under tests/, or either file missing. It records a verdict the
# CALLER confirmed — it does not judge; never call it on a guessed or truncated review.
set -u
if [ "$#" -ne 3 ]; then
  echo "usage: bash $0 <spec.md> <test.spec.ts> PASS|FAIL" >&2; exit 2
fi
SPEC="$1"; TEST="$2"; RESULT="$3"
case "$RESULT" in PASS|FAIL) : ;; *) echo "review-marker: verdict must be PASS or FAIL, got '$RESULT'" >&2; exit 2 ;; esac
case "$SPEC" in specs/*.md) : ;; *) echo "review-marker: spec must be a relative specs/**/*.md path, got '$SPEC'" >&2; exit 2 ;; esac
case "$TEST" in tests/*.spec.ts) : ;; *) echo "review-marker: test must be a relative tests/**/*.spec.ts path, got '$TEST'" >&2; exit 2 ;; esac
case "$SPEC$TEST" in *..*) echo "review-marker: '..' is not allowed in a path" >&2; exit 2 ;; esac
[ -f "$SPEC" ] || { echo "review-marker: $SPEC not found" >&2; exit 2; }
[ -f "$TEST" ] || { echo "review-marker: $TEST not found" >&2; exit 2; }

# sha256sum (coreutils; minimal Linux/CI) first, shasum -a 256 (macOS/BSD) as the fallback — the
# same order /qa-warden:doctor Check 15 reads them with (T-05). The digest is identical either way.
digest() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }

rel="${SPEC#specs/}"; rel="${rel%.md}"
out="reports/review/$rel.reviewed"
mkdir -p "$(dirname "$out")"
{
  echo "commit: $(git rev-parse --verify -q HEAD 2>/dev/null || echo unknown)"
  echo "spec_sha256: $(digest "$SPEC")"
  echo "test_sha256: $(digest "$TEST")"
  echo "date: $(date +%F)"
  echo "result: $RESULT"
} > "$out"
echo "review-marker: wrote $out ($RESULT)"
