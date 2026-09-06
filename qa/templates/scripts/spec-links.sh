#!/bin/sh
# spec-links.sh — the ONE place the basis/feature ↔ spec relation is parsed.
#
# Two mechanical rules used to be hand-copied across doctor.sh, /qa:coverage and /qa:impact,
# each site carrying its own "LOCKSTEP with …" comment instead of a mechanism:
#
#   (1) the indent-tolerant `feature:` extractor from a `<feature>.basis.md`. A col-0-only
#       `^feature:` anchor silently drops an INDENTED YAML value, leaving $feat empty →
#       `specs/.md` → the check no-ops instead of erroring (F-31, found in the a11y-oracle
#       dimension, the best gap detector coverage has).
#   (2) the fanned-spec back-link anchor `:basis:[[:space:]]*<feat>([[:space:]#]|$)`. The
#       trailing-`#` alternative is load-bearing: the plugin's OWN fanned-spec convention
#       writes `basis: <area>/<feature>   # comment`, and a bare `…<feat>$` end-anchor requires
#       the feature to be the last thing on the line — silently dropping every commented link.
#       That has already needed one lockstep fix applied by hand in three places.
#
# Usage:
#   scripts/spec-links.sh feature <basisfile>   # prints the basis' `feature:` value (empty if none)
#   scripts/spec-links.sh index                 # prints `<specpath>:basis: <value>` for every
#                                               #   authored spec carrying a top-level back-link
#   scripts/spec-links.sh match <feat>          # reads an `index` on STDIN, prints the spec paths
#                                               #   whose back-link resolves to <feat>
#
# `match` takes the index on stdin rather than rebuilding it so a caller iterating N features
# stays one tree walk, not N (doctor Checks 13/18 and /qa:coverage all loop per feature):
#   INDEX=$(bash scripts/spec-links.sh index)
#   printf '%s\n' "$INDEX" | bash scripts/spec-links.sh match "$feat"
MODE="${1:?usage: spec-links.sh feature <basisfile> | index | match <feat>}"

case "$MODE" in
  feature)
    BASIS="${2:?usage: spec-links.sh feature <basisfile>}"
    grep -m1 -E '^[[:space:]]*feature:' "$BASIS" 2>/dev/null \
      | sed -E 's/.*feature:[[:space:]]*//; s/["'"'"']//g' | tr -d '[:space:]'
    ;;
  index)
    # -H so each hit carries its path; drop the _context/ tree (basis/cases files declare their
    # own `feature:`, they are not fanned specs).
    grep -rHE '^basis:[[:space:]]*' specs --include='*.md' 2>/dev/null | grep -v '^specs/_context/'
    ;;
  match)
    FEAT="${2:?usage: spec-links.sh match <feat> (index on stdin)}"
    grep -E ":basis:[[:space:]]*${FEAT}([[:space:]#]|\$)" | cut -d: -f1
    ;;
  *) echo "usage: spec-links.sh feature <basisfile> | index | match <feat>" >&2; exit 2 ;;
esac
