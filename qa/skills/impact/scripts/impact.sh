#!/usr/bin/env bash
# impact.sh — deterministic extraction for /qa:impact (test-impact analysis).
#
# Extracted from the former /qa:impact prompt body: this is DATA COLLECTION only.
# The skill (../SKILL.md) owns the caveats and the output format; this script owns the
# shell recipes and must never format, paraphrase, or estimate. Run from the PROJECT root
# (cwd), not from the plugin dir — every path below is project-relative.
#
# Usage: bash impact.sh "<route=<path> | field=<name> | factory=<name> | area=<name> |
#                         operation=<name> | source=<name>>"
# Exit 0 = query ran (including a legitimate zero-match)
# Exit 2 = usage error (no args, or not exactly one key) — NOT a zero-match result
# Exit 3 = no manifests on disk at all — NOT a zero-match result
#
# NOTE: deliberately NO `set -euo pipefail` at top level. The blind-spot pass must still run
# after a zero-match query, and an absent tests/ or artifacts/ dir must degrade, not abort.
# The manifest query keeps its own `set -o pipefail` in a subshell so xargs' rc still surfaces.
#
# Word-splitting: this file has a bash shebang, so `set -- $ARGUMENTS` splits natively. The
# former inline block needed `setopt shwordsplit` because the Bash tool's shell is zsh, where
# `route=/x field=y` stayed ONE token and slipped past the exactly-one-key guard as a silent
# zero-match. Running as a bash script removes that hazard at the source — do not reintroduce
# the inline form.
ARGUMENTS="${1:-}"

usage() {
  echo "usage: /qa:impact (route|field|factory|area|operation|source)=<value>  (exactly one key)"
}

set -- $ARGUMENTS

# Distinguish "no args arrived" from a genuine wrong-count usage error — the two need
# different fixes. (F-29: $ARGUMENTS does not interpolate on the Skill-tool/subagent path;
# the caller must then pass the literal key=val as this script's argument.)
if [ "$#" -eq 0 ]; then
  echo "no arguments — if you invoked this non-interactively, pass the literal key=val as the script argument (e.g. bash impact.sh route=/login)"
  exit 2
fi

# ---------------------------------------------------------------------------
# source= is the ODD ONE OUT: it queries the intake-authored [grounded: …] stamps in
# specs/_context (not the route manifests), and a source NAME may contain spaces
# ("pricing-wiki §3.2") — so it consumes ALL remaining tokens and is handled before the
# exactly-one-key guard below.
# ---------------------------------------------------------------------------
case "$1" in
  source=*)
    VAL="${1#source=}"; shift
    while [ "$#" -gt 0 ]; do VAL="$VAL $1"; shift; done
    # Fixed-string grep (-F: source names carry regex metachars like §/().) and match
    # WITHOUT the closing bracket so "[grounded: pricing-wiki §3.2]" hits on the bare
    # name "pricing-wiki" too.
    MATCHES=$(grep -rlF "[grounded: $VAL" specs/_context --include='*.basis.md' 2>/dev/null)
    if [ -z "$MATCHES" ]; then
      echo "0 basis rules stamped [grounded: $VAL] — check the name against business_sources: in app.context.md (grounding is optional; no stamps != no dependence)"
      exit 0
    fi
    printf '%s\n' "$MATCHES" | while read -r basis; do
      # Canonical indent-tolerant `feature:` extractor (F-31: a col-0-only anchor silently
      # drops indented YAML and no-ops the row). /qa:coverage and doctor Check 13 call the
      # same script, so the accepted YAML shapes stay one edit.
      feat=$(bash scripts/spec-links.sh feature "$basis")
      [ -z "$feat" ] && continue
      n=$(grep -cF "[grounded: $VAL" "$basis")
      area="${feat%%/*}"; spec="specs/${feat}.md"; t="tests/${feat}.spec.ts"
      printf '%s | %s%s | %s%s | rules_grounded=%s\n' \
        "$area" \
        "$spec" "$([ -f "$spec" ] || echo ' (NO SPEC YET)')" \
        "$t" "$([ -f "$t" ] || echo ' (NOT COMPILED)')" \
        "$n"
    done | sort -u
    echo "$(printf '%s\n' "$MATCHES" | wc -l | tr -d ' ') basis file(s) carry rules grounded in \"$VAL\"."
    echo "CAVEATS: stamps are authored by intake — a rule can cite a source in prose without a stamp, so this list is a floor, not a ceiling; and a stamped rule may have been edited since intake."
    exit 0
    ;;
esac

# Exactly one key=val token — reject extra flags (e.g. `route=/x field=y`), which the old
# greedy `route=*` captured as VAL="/x field=y" -> silent zero-match.
[ "$#" -eq 1 ] || { usage; exit 2; }

case "$1" in
  route=*)     KEY=routes;     VAL="${1#route=}"     ;;
  field=*)     KEY=fields;     VAL="${1#field=}"     ;;
  factory=*)   KEY=factories;  VAL="${1#factory=}"   ;;
  area=*)      KEY=area;       VAL="${1#area=}"      ;;
  operation=*) KEY=operations; VAL="${1#operation=}" ;;
  *) usage; exit 2 ;;
esac

# Guard: are there any manifests at all? No manifests != zero matches.
MANIFESTS=$(find artifacts/route-manifests -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$MANIFESTS" -eq 0 ]; then
  echo "NO MANIFESTS FOUND under artifacts/route-manifests — run /qa:gen on a spec first; this is NOT a zero-match result."
  exit 3
fi

echo "### MATCHES"
(
  set -o pipefail
  # Surface jq parse errors (a malformed manifest silently skipped is the dangerous failure
  # mode for a 'don't miss an affected test' tool).
  # `-n1`: invoke jq ONCE PER manifest so a single malformed file fails only ITSELF and every
  # other manifest is still matched. A batched `xargs -0 jq …` (all files to one jq) aborts at
  # the first parse error and silently drops every manifest ordered after it — a truncated
  # match list for a "don't-miss-an-affected-test" tool is the cardinal failure. xargs
  # continues past a failed child (final rc 123, surfaced by pipefail) and the sed wrapper
  # still flags the bad file.
  find artifacts/route-manifests -name '*.json' -print0 |
    xargs -0 -n1 jq -r --arg key "$KEY" --arg val "$VAL" \
      'if ($key == "area") then
         select(.area == $val) | "\(.area)\t\(.spec)"
       else
         select((.[$key] // []) | index($val)) | "\(.area)\t\(.spec)"
       end' 2> >(sed 's/^/[jq parse error — malformed manifest] /' >&2) |
    sort -u
)

# ---------------------------------------------------------------------------
# BLIND SPOTS — the PARTIAL-manifest gap. The zero-manifests guard above only catches the
# all-or-nothing case. The dangerous case is a *partial* gap: some specs are compiled and on
# disk but their manifest is missing or was withheld (e.g. the verifier withheld a manifest
# for a spec left RED by a product bug). Such a spec is silently absent from the impact graph
# — for a "don't miss an affected test" tool, a false "not impacted" is the cardinal failure.
# ---------------------------------------------------------------------------
echo "### BLIND SPOTS"
for t in $(find tests -name '*.spec.ts' ! -name '*.metamorphic.spec.ts' 2>/dev/null); do
  rel="${t#tests/}"; base="${rel%.spec.ts}"          # e.g. checkout/coupon
  # A manifest is emitted per spec under artifacts/route-manifests/<area>/<feature>.json
  if [ ! -f "artifacts/route-manifests/${base}.json" ]; then
    echo "  • $t  (no manifest — NOT in the impact graph; regenerate with /qa:gen specs/${base}.md)"
  fi
done
