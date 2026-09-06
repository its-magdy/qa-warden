#!/bin/sh
# bug-status.sh — the ONE place a bugs/<slug>.md lifecycle value is parsed.
#
# Prints the LOWERCASED Status value (e.g. `open`, `fixed — landed in #123`); prints
# nothing when the file carries no Status marker. Tolerates all three authored forms:
#   - canonical two-line heading: `## Status`\n`open — …`
#   - inline heading:             `## Status: open`
#   - bare line:                  `Status: open`
#
# `--class <file>` prints the CLASSIFICATION instead of the raw value — `resolved` or `open`:
#   [ "$(bash scripts/bug-status.sh --class "$f")" = resolved ] && continue
# Use this rather than re-typing the resolved-keyword case: that `fixed*|reverted*|resolved*|
# closed*` alternation was itself copy-pasted into /qa:run mode=smoke, /qa:run mode=single, /qa:report and
# doctor Checks 11b + 11c — the same five-way duplication (one level up) that this script was
# created to end, so a FIFTH resolved keyword still had to be hand-applied five times.
# An absent/blank value classifies as `open` — the fail-safe direction (over-surface a defect,
# never hide one).
#
# `--list-open` prints the PATH of every still-open bug, one per line (no argument):
#   while IFS= read -r bug; do …; done < <(bash scripts/bug-status.sh --list-open)
# This owns the SCAN the way --class owns the keyword set. The scan shape — `find bugs -maxdepth 1
# -name '*.md' -type f | while read` — was itself copy-pasted into /qa:run mode=smoke, /qa:run mode=single,
# /qa:report and doctor Check 11b, each carrying its own copy of the F-36 rationale (under zsh, the
# Bash tool's default shell, a `for bf in bugs/*.md` glob fires `nomatch` on an EMPTY bugs/ — the
# common all-green state — and aborts the caller before the loop body runs; `[ -d bugs ]` doesn't
# help because the dir exists, and `shopt -s nullglob` is bash-only. `find` is safe in both). One
# copy of `-maxdepth 1` per caller also means a future nested `bugs/<slug>/` layout breaks in four
# places independently. Prints nothing (exit 0) when bugs/ is absent or every bug is resolved.
#
# WHY THIS EXISTS (M-4): this exact awk was copy-pasted into five spots — /qa:run mode=smoke,
# /qa:run mode=single, /qa:report, and /qa:doctor Checks 11b + 11c — each COMMENTED "single-sourced
# / canonical parser" while being nothing of the sort. A first-keyword grep once read
# `## Status: closed`/`resolved` as UN-resolved, and the fix had to be hand-applied to every
# copy or a resolved defect launders green in whichever one drifted. Single-source it here,
# mirroring scripts/check-last-run.sh / resolve-spec-path.sh — one owner, every caller invokes it.
# The two heading rules are ANCHORED at the end of the word `Status` (either a `:` or end-of-line,
# after optional spaces). An unanchored /^##[[:space:]]*Status/ prefix-matched `## Statuses` and
# `## Status History` too, then printed the FOLLOWING line as the lifecycle value — so a bug file
# with a `## Status History` section reported whatever prose sat under it. That fell to the callers'
# `*)` arm and was read as OPEN, so it never laundered a resolved bug green (the fail-safe direction
# held), but it silently misreported the value. Anchor it.
CLASSIFY=0
if [ "${1:-}" = "--class" ]; then CLASSIFY=1; shift; fi
if [ "${1:-}" = "--list-open" ]; then
  # Re-invoke self per file rather than inlining the awk twice — the parser stays single-sourced.
  find bugs -maxdepth 1 -name '*.md' -type f 2>/dev/null | while IFS= read -r bf; do
    [ "$(sh "$0" --class "$bf" 2>/dev/null)" = open ] && printf '%s\n' "$bf"
  done
  exit 0
fi

status=$(awk '
  /^##[[:space:]]*Status[[:space:]]*:/  { sub(/^[^:]*:[[:space:]]*/,""); if ($0!="") { print tolower($0); exit } h=1; next }
  /^##[[:space:]]*Status[[:space:]]*$/  { h=1; next }
  h && NF                               { print tolower($0); exit }
  /^Status:/                            { sub(/^Status:[[:space:]]*/,""); print tolower($0); exit }
' "${1:?usage: bug-status.sh [--class] <bugfile>}")

if [ "$CLASSIFY" = "1" ]; then
  # The ONE place the resolved-keyword set lives. Everything else — `open`, free-text prose,
  # an absent marker — is `open`, so a defect is over-surfaced rather than laundered green.
  case "$status" in
    fixed*|reverted*|resolved*|closed*) echo resolved ;;
    *)                                  echo open ;;
  esac
else
  [ -n "$status" ] && printf '%s\n' "$status"
fi
