#!/bin/sh
# retire-delete.sh — the ONE sanctioned deletion primitive for /qa:retire.
#
# WHY THIS EXISTS (F-031): the shipped .claude/settings.json deny-list blocks the
# destructive primitives directly — `Bash(rm *)`, `Bash(find * -delete*)`,
# `Bash(truncate *)` — and deny ALWAYS beats allow AND cannot be interactively
# approved. So /qa:retire (whose whole job is to delete a retired feature's files)
# had no way to actually delete out-of-the-box: its inline `find … -delete` was
# denied, producing a correct dry-run inventory but a no-op execute phase.
#
# The fix is an ALLOW-listed wrapper, not a weaker deny. `.claude/settings.json`
# permits `Bash(bash scripts/retire-delete.sh*)` — the permission matcher sees only
# the top-level command STRING (`bash scripts/retire-delete.sh <file>`), which no
# deny pattern matches; the `rm` inside runs as a child process the matcher never
# inspects. Same pattern the toolkit already uses for prod-guard.sh / doctor.sh.
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
#   - exactly ONE path, no globs/wildcards, no shell metacharacters
#   - the target must be an existing regular file (not a dir, not a symlink)
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

rm -f -- "$TARGET"
if [ -e "$TARGET" ]; then
  echo "retire-delete: FAILED to delete '$TARGET' (still present)." >&2
  exit 1
fi
echo "deleted: $TARGET"
