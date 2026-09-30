#!/bin/bash
# cli-fill-env.sh — fill a form field from a .env variable WITHOUT the value ever appearing in a
# command line or in tool output. The ONE sanctioned way to type a credential via playwright-cli.
#
# WHY THIS EXISTS (Test-35, 2026-09-21): every Bash tool call is a FRESH shell, so an
# allow-listed `. .env` in one call exports nothing to the `npx playwright-cli fill` in the next.
# Agents that needed to log in either (a) read .env and typed the literal password into
# `fill <ref> "<password>"` — which lands in the transcript, 2 of 3 runs — or (b) refused to log
# in and left the post-login facts unverified. A compound `. .env; npx playwright-cli fill …` is
# no answer either: a permission rule must match EACH subcommand, so it prompts/denies. Same
# wrapper pattern as retire-delete.sh: the matcher sees only `bash scripts/cli-fill-env.sh …`,
# which carries a variable NAME, never a value.
#
# Usage:
#   bash scripts/cli-fill-env.sh <session> <target> <ENV_VAR>
#     <session>  the isolated playwright-cli session name (what you pass as -s=<session>)
#     <target>   the element ref from a snapshot (e.g. e8)
#     <ENV_VAR>  NAME of the .env variable to type (e.g. QA_USER_PASSWORD) — never the value
#   bash scripts/cli-fill-env.sh --check <ENV_VAR>...     # prints "<NAME>: set|UNSET", no values
#
# Guarantees / refusals (exit 2, nothing typed):
#   - exactly three arguments; ENV_VAR must be a plain UPPER_SNAKE name that is set and non-empty
#   - a secret-looking variable (PASS[WORD/PHRASE] / _PW / SECRET / TOKEN / KEY) is typed ONLY into an
#     <input type="password"> — so it cannot be parked in a visible field and read back by snapshot
#   - playwright-cli's own output is suppressed (it echoes the generated fill() call, value included)
set -u

# --check <ENV_VAR>... — report set/unset for each name, never a value. The sanctioned way to
# answer "are the creds filled in?"; `cat .env | grep -v PASSWORD` is not — the toolkit's own
# `*_PW` names slip straight through that filter (seen in a Test-35 trace).
if [ "${1:-}" = "--check" ]; then
  shift
  ROOT="${CLAUDE_PROJECT_DIR:-.}"
  if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi
  for VAR in "$@"; do
    case "$VAR" in ''|*[!A-Z0-9_]*|[0-9]*) echo "$VAR: not an ENV VAR NAME"; continue ;; esac
    if [ -n "${!VAR:-}" ]; then echo "$VAR: set"; else echo "$VAR: UNSET or empty"; fi
  done
  exit 0
fi

if [ "$#" -ne 3 ]; then
  echo "usage: bash scripts/cli-fill-env.sh <session> <target> <ENV_VAR>" >&2
  exit 2
fi
SESSION="$1"; TARGET="$2"; VAR="$3"

case "$VAR" in
  ''|*[!A-Z0-9_]*|[0-9]*) echo "cli-fill-env: '$VAR' is not an ENV VAR NAME (UPPER_SNAKE) — pass the variable's name, never its value." >&2; exit 2 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-.}"
if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi
VALUE="${!VAR:-}"
if [ -z "$VALUE" ]; then
  echo "cli-fill-env: $VAR is unset or empty in .env — nothing typed." >&2
  exit 2
fi

case "$VAR" in
  *PASS*|*_PW|*_PW_*|*SECRET*|*TOKEN*|*KEY*)
    TYPE=$(npx playwright-cli -s="$SESSION" eval "el => el.type" "$TARGET" 2>/dev/null)
    case "$TYPE" in
      *password*) : ;;
      *) echo "cli-fill-env: $VAR looks like a secret but target $TARGET is not an <input type=\"password\"> — refusing, a visible field would expose it to the next snapshot." >&2; exit 2 ;;
    esac ;;
esac

if npx playwright-cli -s="$SESSION" fill "$TARGET" "$VALUE" >/dev/null 2>&1; then
  echo "cli-fill-env: filled $TARGET from \$$VAR (value hidden)"
else
  echo "cli-fill-env: playwright-cli fill failed for target $TARGET in session $SESSION (stale ref? re-snapshot) — output suppressed to protect the value." >&2
  exit 1
fi
