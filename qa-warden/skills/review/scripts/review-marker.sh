#!/bin/sh
# review-marker.sh — the /qa-warden:review attestation marker for ONE spec/test pair. It WRITES the
# marker (for the review skill) and CHECKS it (for /qa-warden:doctor Check 15), so the marker's
# format (its path, its fields, how a digest is taken) is defined in this file and nowhere else.
#
# WHY THIS EXISTS (Test-35, 2026-09-21): /qa-warden:review described the marker's five fields in prose
# and left the agent to improvise the shell — `git rev-parse HEAD && shasum … && date`, a
# `mkdir -p … && printf …` with an inline function. None of those compound forms matches an
# allow rule (a rule must match every subcommand), so each one prompted, and was denied headless:
# 4 denied calls in a single review. One allow-listed call, and the digest fallback lives in one
# place instead of being re-typed per run.
#
# WHY IT ALSO CHECKS: doctor used to read the marker with its own copy of the path rule, its own
# digest function and its own field greps. The two digest copies had already drifted once (the
# exit-126 sha256sum below), and doctor never read `result:`, so a FAILED review counted as
# attested. With the writer and the reader in one file they cannot disagree about the format.
#
# WHERE IT LIVES: in the plugin, beside the review skill, and run from there. It used to be stamped
# into every project as scripts/review-marker.sh, but nothing in a project called it except this
# skill, so the copy was substrate to resync and two settings.json rules to keep in step. The
# skill's allowed-tools rule pre-approves exactly this path. A project stamped earlier keeps an
# inert scripts/review-marker.sh; /qa-warden:doctor names it as safe to delete. Doctor runs this
# file from the same plugin, found relative to doctor's own location.
#
# Usage (from the QA project root; the paths below are relative to it):
#   bash "${CLAUDE_SKILL_DIR}/scripts/review-marker.sh" <spec.md> <test.spec.ts> PASS|FAIL
#     Writes: reports/review/<area>/<feature>.reviewed   (path derived from the spec path)
#     Fields: commit, spec_sha256, test_sha256, date, result.
#   bash review-marker.sh check <spec.md> <test.spec.ts>
#     Read-only. Prints ONE word on stdout and exits 0:
#       current  the marker's hashes match the spec and test now, and its result is not FAIL
#       stale    the spec or the test changed since the marker was written
#       failed   the hashes match, but the review recorded `result: FAIL`
#       missing  there is no marker for this pair
#     A marker with no `result:` line, or a value other than FAIL, is `current` when its hashes
#     match, so a marker written before doctor read the result stays attested. A changed pair is
#     `stale` whatever its result: the review it records was of other code.
#
# Refuses (exit 2, writes nothing, prints nothing on stdout): wrong arg count, a verdict other than
# PASS/FAIL, a spec not under specs/ or a test not under tests/, either file missing, a spec, test or
# marker that is a symlink or sits under a symlinked dir resolving outside the project, or no working
# sha256 tool (one whose output is a 64-hex digest). It records a verdict the CALLER confirmed — it
# does not judge; never call it on a guessed or truncated review.
set -u
MODE="write"
if [ "${1:-}" = "check" ]; then
  MODE=check
  shift
  if [ "$#" -ne 2 ]; then
    echo "usage: bash $0 check <spec.md> <test.spec.ts>" >&2; exit 2
  fi
  SPEC="$1"; TEST="$2"
else
  if [ "$#" -ne 3 ]; then
    echo "usage: bash $0 <spec.md> <test.spec.ts> PASS|FAIL" >&2; exit 2
  fi
  SPEC="$1"; TEST="$2"; RESULT="$3"
  case "$RESULT" in PASS|FAIL) : ;; *) echo "review-marker: verdict must be PASS or FAIL, got '$RESULT'" >&2; exit 2 ;; esac
fi
case "$SPEC" in specs/*.md) : ;; *) echo "review-marker: spec must be a relative specs/**/*.md path, got '$SPEC'" >&2; exit 2 ;; esac
case "$TEST" in tests/*.spec.ts) : ;; *) echo "review-marker: test must be a relative tests/**/*.spec.ts path, got '$TEST'" >&2; exit 2 ;; esac
case "$SPEC$TEST" in *..*) echo "review-marker: '..' is not allowed in a path" >&2; exit 2 ;; esac
[ -f "$SPEC" ] || { echo "review-marker: $SPEC not found" >&2; exit 2; }
[ -f "$TEST" ] || { echo "review-marker: $TEST not found" >&2; exit 2; }

# The case patterns above read only the string. With `reports -> /elsewhere` the marker would be
# written outside the project, and with `specs -> /elsewhere` an outside file would be hashed. So
# every path this script touches must resolve inside the project root: in_root resolves the path's
# directory (every symlink, `cd -P`) and compares it with the cwd's `pwd -P`. A directory that does
# not exist yet (the marker's, before its first write) is judged by its nearest existing ancestor,
# and a dangling symlink on the way up is refused. A dir symlink that resolves inside the project is
# allowed. in_root is duplicated in templates/scripts/retire-delete.sh, which is stamped into
# projects and so cannot share it; qa-scaffoldtest section 9 runs one path table against both.
ROOT=$(pwd -P) || exit 2
in_root() {
  _d=$(dirname "$1")
  while [ ! -d "$_d" ]; do
    if [ -L "$_d" ]; then return 1; fi
    _d=$(dirname "$_d")
  done
  REAL=$(CDPATH='' cd -P "$_d" 2>/dev/null && pwd -P) || return 1
  case "$REAL" in "$ROOT"|"$ROOT"/*) return 0 ;; esac
  return 1
}
for _p in "$SPEC" "$TEST"; do
  if [ -L "$_p" ]; then
    echo "review-marker: $_p is a symlink — refused (it could point outside the project)" >&2; exit 2
  fi
  if ! in_root "$_p"; then
    echo "review-marker: $_p resolves outside the project (a symlinked dir on its path) — refused" >&2; exit 2
  fi
done

# sha256sum (coreutils; minimal Linux/CI) first, shasum -a 256 (macOS/BSD) as the fallback (T-05).
# The digest is identical either way. Decided per call, not once by `command -v`: a sha256sum that
# is found but cannot run (an x86-only binary on Apple silicon: "Bad CPU type", exit 126) must fall
# through to shasum, not yield an empty hash that makes every reviewed pair look changed. The test
# is the OUTPUT, not the exit status, so a sha256sum that exits 0 and prints nothing falls through too.
# And the output must BE a digest — exactly 64 lowercase hex chars — not merely be non-empty: a
# broken tool that prints "unavailable" would otherwise be recorded as both hashes, and every later
# edit would still compare equal (junk == junk) and read `current`. Anything else falls through, and
# if neither tool yields a digest, digest prints nothing and the caller refuses.
# The file goes in on STDIN, never as an argument: given a name with a backslash or a newline, both
# tools escape it and prefix the line with `\`, so `awk '{print $1}'` would read a 65-char token and
# a valid file would be refused. On stdin the line is always `<digest>  -`.
is_digest() {
  case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 64 ]
}
digest() {
  _d=$(sha256sum < "$1" 2>/dev/null | awk '{print $1}')
  if ! is_digest "$_d"; then
    _d=$(shasum -a 256 < "$1" 2>/dev/null | awk '{print $1}')
  fi
  if is_digest "$_d"; then printf '%s\n' "$_d"; fi
}
# field <marker> <name> — the value of the first `<name>: <value>` line, or nothing.
field() { grep -m1 "^$2:" "$1" | awk '{print $2}'; }

rel="${SPEC#specs/}"; rel="${rel%.md}"
out="reports/review/$rel.reviewed"
# Checked in both modes, before anything is read or created: the marker itself must not be a
# symlink, and its directory (or, before the first write, its nearest existing ancestor) must
# resolve inside the project.
if [ -L "$out" ]; then
  echo "review-marker: $out is a symlink — refused (it could point outside the project)" >&2; exit 2
fi
if ! in_root "$out"; then
  echo "review-marker: $out resolves outside the project (a symlinked dir on its path) — refused" >&2; exit 2
fi

# A pair with no marker is `missing` before any hashing, so a never-reviewed pair reads as that even
# on a machine where no sha256 tool works.
if [ "$MODE" = "check" ] && [ ! -f "$out" ]; then
  echo missing; exit 0
fi

s_now=$(digest "$SPEC")
t_now=$(digest "$TEST")
# With no working tool both digests are empty. The writer would then record "", and the checker
# would call a marker that recorded "" current. Refuse instead. Because a non-empty digest is always
# 64-hex, a marker whose recorded hash is anything else (junk from an older, laxer writer) can never
# compare equal, so it reads `stale`, never `current`.
if [ -z "$s_now" ] || [ -z "$t_now" ]; then
  echo "review-marker: neither sha256sum nor shasum -a 256 produced a digest" >&2; exit 2
fi

if [ "$MODE" = "check" ]; then
  if [ "$s_now" != "$(field "$out" spec_sha256)" ] || [ "$t_now" != "$(field "$out" test_sha256)" ]; then
    echo stale
  elif [ "$(field "$out" result)" = "FAIL" ]; then
    echo failed
  else
    echo current
  fi
  exit 0
fi

mkdir -p "$(dirname "$out")"
{
  echo "commit: $(git rev-parse --verify -q HEAD 2>/dev/null || echo unknown)"
  echo "spec_sha256: $s_now"
  echo "test_sha256: $t_now"
  echo "date: $(date +%F)"
  echo "result: $RESULT"
} > "$out"
echo "review-marker: wrote $out ($RESULT)"
