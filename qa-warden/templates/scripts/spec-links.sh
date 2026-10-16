#!/bin/sh
# spec-links.sh — the ONE place the basis/feature ↔ spec ↔ test relation is parsed.
#
# These mechanical rules used to be hand-copied across doctor.sh, /qa-warden:coverage and /qa-warden:impact,
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
#   (3) the UNMANIFESTED walk — `tests/<base>.spec.ts` with no `artifacts/route-manifests/
#       <base>.json`. Lived only in impact.sh until /qa-warden:coverage was found to need the same
#       set and to be getting it WRONG: a withheld manifest made coverage dim-0 print the
#       route under "touched by NO compiled test", which is false for a test that is on disk
#       and compiled, and points the reader at "write a spec" when the real remedy is "the
#       verifier withheld the manifest — fix the blocker". The walk carries one property that
#       is silent when dropped: **metamorphic twins are excluded**, because a `*.metamorphic.
#       spec.ts` never gets a manifest BY DESIGN (verifier V4 emits one per spec, not per
#       twin) — an inlined copy that forgets the exclusion reports every twin as a blind spot.
#       One rule, one place; each caller owns its own prose.
#   (4) the COLLECTED-TEST inventory — which tests/**/*.spec.ts Playwright actually collects, and
#       each one's spec. playwright.config.ts's `testIgnore: ['**/*.setup.ts', '**/_*.spec.ts',
#       '**/_*/**']` drops a `_`-prefixed BASENAME and anything under a `_`-prefixed DIRECTORY;
#       BOTH forms must be excluded, because `-path '*/_*/*'` alone never matches a root-level
#       `tests/_audit-visual.spec.ts` (one slash). This walk used to exist three times with two
#       different filters: doctor and post-run-checks.sh carried both `_` forms, while the
#       `unmanifested` walk here carried NEITHER — so /qa-warden:impact's BLIND SPOTS and
#       /qa-warden:coverage's UNMANIFESTED arm listed `tests/_demo/failure-demo.spec.ts`, a file
#       Playwright never runs. The spec join (`tests/<base>[.metamorphic].spec.ts` ↔
#       `specs/<base>.md`) was re-typed at ~15 sites on top of that. Both now live in
#       collected_tests() / authored_specs() below, and every walk reads them.
#   (5) the SMOKE-TAG parser — "which specs put a scenario on the @smoke gate". Two parsers used
#       to disagree: coverage matched `smoke` ANYWHERE in the file (prose "not a smoke test"
#       counted), and doctor matched only a line-leading `tags: [… smoke …]`, so it missed the
#       per-scenario `scenarios: [{ …, tags: [smoke] }]` form the test-case contract REQUIRES for
#       a multi-scenario spec, and a block list (`tags:` then `- smoke`). One awk program now
#       reads all three YAML forms and nothing else; see spec_scan() below.
#
# Usage:
#   scripts/spec-links.sh feature <basisfile>   # prints the basis' `feature:` value (empty if none)
#   scripts/spec-links.sh index                 # prints `<specpath>:basis: <value>` for every
#                                               #   authored spec carrying a top-level back-link
#   scripts/spec-links.sh match <feat>          # reads an `index` on STDIN, prints the spec paths
#                                               #   whose back-link resolves to <feat>
#   scripts/spec-links.sh tests                 # one TAB-separated row per COLLECTED test:
#                                               #   <test> <base> <kind> <spec> <manifest>
#                                               #   kind = spec | twin (a *.metamorphic.spec.ts);
#                                               #   spec/manifest = the path, or `-` when absent
#   scripts/spec-links.sh specs                 # one TAB-separated row per AUTHORED spec:
#                                               #   <spec> <base> <test> <smoke> <basis>
#                                               #   test = tests/<base>.spec.ts, or `-` when absent;
#                                               #   smoke = `smoke` or `-`; basis = the top-level
#                                               #   `basis:` value, or `-`
#   scripts/spec-links.sh smoke                 # prints the spec paths that carry a smoke tag
#   scripts/spec-links.sh unmanifested          # prints `<testpath>\t<base>` for every collected
#                                               #   test with no route manifest (twins excluded)
#
# Every column is filled (`-` for "none") so a caller can split a row with `IFS=<TAB> read`:
# a tab is IFS whitespace, so adjacent tabs collapse and an EMPTY column would shift every
# column after it.
#
# `match` takes the index on stdin rather than rebuilding it so a caller iterating N features
# stays one tree walk, not N (doctor Checks 13/18 and /qa-warden:coverage all loop per feature):
#   INDEX=$(bash scripts/spec-links.sh index)
#   printf '%s\n' "$INDEX" | bash scripts/spec-links.sh match "$feat"
USAGE='usage: spec-links.sh feature <basisfile> | index | match <feat> | tests | specs | smoke | unmanifested'
MODE="${1:?$USAGE}"
TAB=$(printf '\t')

# collected_tests — rule (4), the tests/ half, in the `tests` row format. `while read -r` (not
# `for t in $(find …)`) so a path containing a space is one record. A twin pairs with its
# parent's spec and manifest by stripping `.metamorphic`, and is marked `twin` because it never
# carries a manifest of its own (rule 3).
collected_tests() {
  find tests -name '*.spec.ts' -type f ! -name '_*' ! -path '*/_*/*' 2>/dev/null | while read -r t; do
    rel="${t#tests/}"; base="${rel%.spec.ts}"; kind=spec
    case "$base" in
      (*.metamorphic) base="${base%.metamorphic}"; kind=twin ;;
    esac
    spec="specs/${base}.md"
    [ -f "$spec" ] || spec=-
    mf="artifacts/route-manifests/${base}.json"
    [ -f "$mf" ] || mf=-
    printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$base" "$kind" "$spec" "$mf"
  done
}

# spec_scan — reads spec paths on STDIN, prints `<spec>\t<smoke|->\t<basis|->` for each. ONE awk
# process for the whole list (it opens each file with getline), so the harvest is one fork, not
# one per spec. Rule (5): a scenario is smoke-tagged when a `tags:` KEY lists a token that BEGINS
# `smoke` (an `@` and quotes are allowed; a prefix, because the generator emits each tag as
# `@<tag>` and `--grep @smoke` is a substring match, so `smoke-fast` is on the gate too), in any
# of the three YAML forms:
#   inline       `tags: [smoke, regression]`, at line start or as a `- tags:` list item
#   per-scenario `scenarios: [{ name: "ok", data: {…}, tags: [smoke] }]` — the key follows `{` or `,`
#   block list   `tags:` alone on its line, then `- smoke` items indented at least as far as the key
# A `tags:` preceded by a WORD is prose, not a key, and is not read; a ` #` comment is dropped
# before matching, so `tags: [regression]  # not smoke` does not count. The top-level `basis:`
# value is cut at the first space or `#`, the same boundary `match` anchors on.
# Portable awk only (BSD awk, gawk, mawk): getline from a named file, no `for (k in arr)`, nothing
# read from $0 in END.
spec_scan() {
  awk -v q="'" '
    function smoketok(t) {
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      gsub(/"/, "", t); gsub(q, "", t)
      return (t ~ /^@?smoke/)
    }
    function flowlist(s,   n, i, k, parts) {
      if (substr(s, 1, 1) != "[") return smoketok(s)
      s = substr(s, 2); k = index(s, "]"); if (k) s = substr(s, 1, k - 1)
      n = split(s, parts, ",")
      for (i = 1; i <= n; i++) if (smoketok(parts[i])) return 1
      return 0
    }
    {
      f = $0; smoke = 0; basis = ""; inblock = 0; keycol = 0
      while ((getline line < f) > 0) {
        sub(/\r$/, "", line)
        if (basis == "" && line ~ /^basis:/) {
          v = line; sub(/^basis:[ \t]*/, "", v); sub(/[ \t#].*$/, "", v); basis = v
        }
        if (line ~ /^[ \t]*#/) continue
        l = line; sub(/[ \t]#.*$/, "", l)
        # Inside a block list: `- item` lines at or right of the key column are its items; the
        # first other non-blank line ends it and is then read as an ordinary line.
        if (inblock) {
          if (l ~ /^[ \t]*$/) continue
          match(l, /^[ \t]*/)
          if ((l ~ /^[ \t]*-[ \t]/ || l ~ /^[ \t]*-$/) && RLENGTH >= keycol) {
            item = l; sub(/^[ \t]*-[ \t]*/, "", item)
            if (smoketok(item)) smoke = 1
            continue
          }
          inblock = 0
        }
        # A key at line start (after the indent and an optional `- `): the inline form, or with
        # nothing after it, the head of a block list. Two regexes rather than one alternation
        # with a `^` inside it, which not every awk anchors the same way.
        if (match(l, /^[ \t]*(-[ \t]+)?tags:[ \t]*/)) {
          rest = substr(l, RLENGTH + 1)
          if (rest == "") { inblock = 1; keycol = index(l, "tags:") - 1; continue }
          if (flowlist(rest)) smoke = 1
          l = rest
        }
        # Keys inside a flow mapping (`{ …, tags: [smoke] }`) — a flow list of scenarios can
        # carry several on one line, so read every one.
        while (match(l, /[{,][ \t]*tags:[ \t]*/)) {
          l = substr(l, RSTART + RLENGTH)
          if (flowlist(l)) smoke = 1
        }
      }
      close(f)
      printf "%s\t%s\t%s\n", f, (smoke ? "smoke" : "-"), (basis == "" ? "-" : basis)
    }'
}

# authored_specs — rule (4), the specs/ half, in the `specs` row format. The same `_` exclusion
# as the tests/ walk (which also drops specs/_context/ and its _templates/), so a spec's base
# names exactly the test path the tests/ walk would collect.
authored_specs() {
  find specs -name '*.md' -type f ! -name '_*' ! -path '*/_*/*' 2>/dev/null | spec_scan \
    | while IFS="$TAB" read -r s smoke basis; do
        base="${s#specs/}"; base="${base%.md}"
        t="tests/${base}.spec.ts"
        [ -f "$t" ] || t=-
        printf '%s\t%s\t%s\t%s\t%s\n' "$s" "$base" "$t" "$smoke" "$basis"
      done
}

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
  tests)
    collected_tests
    ;;
  specs)
    authored_specs
    ;;
  smoke)
    authored_specs | while IFS="$TAB" read -r s base t smoke basis; do
      if [ "$smoke" = smoke ]; then printf '%s\n' "$s"; fi
    done
    ;;
  unmanifested)
    # The PARTIAL-manifest blind spot: a spec compiled to disk whose manifest is missing or was
    # deliberately WITHHELD (verifier V4 withholds on a red parent, a BLIND/INCONCLUSIVE invariant,
    # a disagreeing twin or budget exhaustion — withholding IS the durable blocker signal). Such a
    # test is invisible to every manifest-derived answer while looking fully shipped on disk.
    # Read off the collected-test walk, so a `_`-prefixed scratch spec Playwright never runs is
    # never listed. Twins are skipped: see rule (3), they never carry a manifest by design.
    collected_tests | while IFS="$TAB" read -r t base kind spec mf; do
      [ "$kind" = twin ] && continue
      if [ "$mf" = - ]; then printf '%s\t%s\n' "$t" "$base"; fi
    done
    ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac
