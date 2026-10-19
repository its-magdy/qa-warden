#!/bin/sh
# retire-delete.sh — the ONE sanctioned deletion primitive for /qa-warden:retire.
#
# WHY THIS EXISTS (F-031): the shipped .claude/settings.json deny-list blocks the
# destructive primitives directly — `Bash(rm *)`, `Bash(find * -delete*)`,
# `Bash(truncate *)` — and deny ALWAYS beats allow AND cannot be interactively
# approved. So /qa-warden:retire (whose whole job is to delete a retired feature's files)
# had no way to actually delete out-of-the-box: its inline `find … -delete` was
# denied, producing a correct dry-run inventory but a no-op execute phase.
#
# The fix is an ALLOW-listed wrapper, not a weaker deny. `.claude/settings.json`
# permits `Bash(bash scripts/retire-delete.sh*)` — the permission matcher sees only
# the top-level command STRING (`bash scripts/retire-delete.sh <file>`), which no
# deny pattern matches; the `rm` inside runs as a child process the matcher never
# inspects. Same pattern the toolkit already uses for prod-guard.sh.
# Keeping deletion behind this script (not a broad `rm` allow) means the safety
# rails below are the ONLY delete path, and they are enforced in one place.
#
# Usage:
#   scripts/retire-delete.sh <path>            # delete ONE exact file after all guards pass
#   scripts/retire-delete.sh --dry-run <path>  # print what WOULD be deleted, delete nothing
#
# Guarantees / refusals (exit 2, delete nothing, on any violation):
#   - path must be RELATIVE and inside the repo (no leading '/', no '..' segment)
#   - path must live under a retire-able dir (specs/ tests/ page-objects/ steps/
#     bugs/ fixtures/ artifacts/ reports/) — never product source, config, .env,
#     .claude/**, package.json, playwright.config.ts, or the scripts/ dir itself
#   - exactly ONE path, no globs/wildcards, no shell metacharacters, no newline or other
#     control character (a `$( )` strips trailing newlines, so `tests/safe<NL>` would be checked
#     as the real `tests/safe` while `rm` followed a symlink named `tests/safe<NL>`)
#   - the target must be an existing regular file (not a dir, not a symlink)
#   - the target's directory, every symlink in it resolved (`cd -P`), must be inside the project
#     root (the cwd, resolved with `pwd -P`) AND still under a retire-able dir. The checks above
#     read only the string: with `tests -> /tmp/outside`, `tests/x.spec.ts` passes all of them and
#     `rm` follows the link out of the repo. A dir symlink that resolves inside a retire-able dir
#     (`tests/alias -> demo`) is allowed; one that resolves elsewhere in the project
#     (`tests/src -> ../src`) is refused, because that is product source.
#   - NOT hardened against another process rewriting the tree during the call. The delete runs
#     from inside the target's directory after re-checking it there, which narrows the window
#     (swapping an ancestor afterwards no longer redirects the rm), but POSIX sh cannot close it.
DRY=0
case "$1" in
  --dry-run) DRY=1; shift ;;
esac
TARGET="${1:?usage: retire-delete.sh [--dry-run] <path-under-a-retire-able-dir>}"

# Refuse more than one argument — a second token means a glob expanded or the
# caller passed several files; retire deletes one confirmed file per call.
if [ "$#" -gt 1 ]; then
  echo "retire-delete: refuses multiple paths ($# given) — call once per confirmed file, never a glob." >&2
  exit 2
fi

# Refuse shell-glob / metacharacters BEFORE any filesystem touch (a literal '*' or
# '?' reaching here means an unquoted glob or an injection attempt, not a real path).
case "$TARGET" in
  *[*?]* | *'['* | *';'* | *'&'* | *'|'* | *'`'* | *'$'* | *'('*)
    echo "retire-delete: path '$TARGET' contains a glob/metacharacter — pass one exact literal path." >&2
    exit 2 ;;
esac
# A newline or other control character: every `$( )` below strips trailing newlines, so the path
# checked would not be the path deleted.
case "$TARGET" in
  *[[:cntrl:]]*)
    echo "retire-delete: path contains a newline or another control character — refused." >&2
    exit 2 ;;
esac

# Refuse absolute paths and any '..' traversal (keep deletion inside the repo).
case "$TARGET" in
  /*)            echo "retire-delete: absolute path '$TARGET' refused — pass a repo-relative path." >&2; exit 2 ;;
  ..|../*|*/..|*/../*) echo "retire-delete: '..' traversal in '$TARGET' refused." >&2; exit 2 ;;
esac

# Whitelist the retire-able top-level dirs. Deleting anything else — product source,
# config, secrets, the substrate — is out of retire's remit and refused here.
case "$TARGET" in
  specs/*|tests/*|page-objects/*|steps/*|bugs/*|fixtures/*|artifacts/*|reports/*) : ;;
  *) echo "retire-delete: '$TARGET' is outside the retire-able dirs (specs/ tests/ page-objects/ steps/ bugs/ fixtures/ artifacts/ reports/) — refused." >&2; exit 2 ;;
esac

# Resolve the target's directory and require it inside the project root. in_root is duplicated in
# the plugin's skills/review/scripts/review-marker.sh (this file is stamped into projects, that one
# runs from the plugin, so they cannot share it); qa-scaffoldtest section 9 runs one path table
# against both. A path whose directory does not exist yet is judged by its nearest existing
# ancestor, and a dangling symlink on the way up is refused. Each `pwd -P` is captured with a
# trailing '.' that is then cut off, so a `$( )` cannot drop a trailing newline from the result; a
# root or resolved dir that contains a control character is refused.
ROOT=$(pwd -P && echo .) || { echo "retire-delete: cannot resolve the current directory — refused." >&2; exit 2; }
ROOT=${ROOT%?.}
case "$ROOT" in
  *[[:cntrl:]]*|'')
    echo "retire-delete: the project root contains a control character — refused." >&2; exit 2 ;;
esac
in_root() {
  _d=$(dirname "$1")
  while [ ! -d "$_d" ]; do
    if [ -L "$_d" ]; then return 1; fi
    _d=$(dirname "$_d")
  done
  REAL=$(CDPATH='' cd -P "$_d" 2>/dev/null && pwd -P && echo .) || return 1
  REAL=${REAL%?.}
  case "$REAL" in *[[:cntrl:]]*) return 1 ;; "$ROOT"|"$ROOT"/*) return 0 ;; esac
  return 1
}
# retire_able <physical-dir> — inside the project is not enough for a delete: `tests -> .` would make
# tests/package.json the project's package.json. The directory must be under a retire-able dir.
retire_able() {
  case "$1" in "$ROOT"/*) : ;; *) return 1 ;; esac
  case "${1#"$ROOT"}/" in
    /specs/*|/tests/*|/page-objects/*|/steps/*|/bugs/*|/fixtures/*|/artifacts/*|/reports/*) return 0 ;;
  esac
  return 1
}
if ! in_root "$TARGET"; then
  echo "retire-delete: '$TARGET' resolves outside the project (a symlinked dir on its path) — refused." >&2
  exit 2
fi
if ! retire_able "$REAL"; then
  echo "retire-delete: '$TARGET' resolves outside the retire-able dirs (a symlinked dir on its path) — refused." >&2
  exit 2
fi

# Must be an existing REGULAR file — not a directory (retire deletes files one at a
# time, never `rm -r`), and not a symlink (which could point outside the repo).
if [ -L "$TARGET" ]; then
  echo "retire-delete: '$TARGET' is a symlink — refused (could escape the repo)." >&2
  exit 2
fi
if [ ! -f "$TARGET" ]; then
  echo "retire-delete: '$TARGET' is not an existing regular file — nothing to delete." >&2
  exit 2
fi

if [ "$DRY" -eq 1 ]; then
  echo "would delete: $TARGET"
  exit 0
fi

# Delete from INSIDE the target's directory, re-checked from there: once the cwd is held, swapping
# an ancestor dir for a symlink no longer redirects the rm. A leaf swapped for a symlink after the
# checks above is caught by the -L below or, if swapped later still, only unlinks the link (rm does
# not follow it). Not race-proof, only a narrower window: see the header.
DIR=${TARGET%/*}; BASE=${TARGET##*/}
cd -P "./$DIR" 2>/dev/null || { echo "retire-delete: cannot enter the directory of '$TARGET' — refused." >&2; exit 2; }
HELD=$(pwd -P && echo .) || exit 2
HELD=${HELD%?.}
case "$HELD" in
  *[[:cntrl:]]*) HELD='' ;;
esac
if ! retire_able "$HELD"; then
  echo "retire-delete: the directory of '$TARGET' changed while it was being checked — refused." >&2
  exit 2
fi
if [ -L "./$BASE" ] || [ ! -f "./$BASE" ]; then
  echo "retire-delete: '$TARGET' changed while it was being checked — refused." >&2
  exit 2
fi
rm -f -- "./$BASE"
if [ -e "./$BASE" ]; then
  echo "retire-delete: FAILED to delete '$TARGET' (still present)." >&2
  exit 1
fi
echo "deleted: $TARGET"
