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
# one per spec. Rule (5): a spec is smoke-tagged when a `tags:` KEY lists a token that BEGINS
# `smoke` (an `@` and quotes are allowed; a prefix, because the generator emits each tag as
# `@<tag>` and `--grep @smoke` is a substring match, so `smoke-fast` is on the gate too).
#
# WHERE it looks. A spec is Markdown prose plus fenced ```yaml blocks (the test-case contract),
# so when a file has a ```yaml fence only those blocks are read; prose, bullets and other code
# fences never are. A file with NO ```yaml fence is read whole, as bare YAML (older and
# hand-written specs), skipping any other fence; there a column-0 line that is not a `key:`
# (a prose sentence) ends the key it follows.
#
# WHICH `tags:` count — only the two the generator turns into `@<tag>`:
#   spec level   the top-level `tags:` key: `tags: [smoke, regression]`, or `tags:` then `- smoke`
#   per scenario a `tags:` key of one `scenarios:` entry, in any of the forms
#                  scenarios: [{ name: "ok", data: {…}, tags: [smoke] }]      (one line or several)
#                  scenarios:\n  - { name: ok, tags: [smoke] }
#                  scenarios:\n  - name: ok\n    tags: [smoke]                (or `tags:` + `- smoke`)
# A `tags:` under any other key (`meta:`, `data:`) or nested deeper inside a scenario (its
# `data: { tags: … }`) is not a test tag and is ignored. Flow collections are walked with a
# quote-aware depth counter, and ` #` starts a comment only outside quotes, so
# `name: "issue #3"` does not cut the line. Not read: a top-level `tags:` flow list split across
# lines (`tags: [` … `]`), which the contract never writes.
# The top-level `basis:` value is read from any line (as `index` does) and cut at the first space
# or `#`, the same boundary `match` anchors on.
# Portable awk only (BSD awk, gawk, mawk): getline from a named file, no `for (k in arr)`, nothing
# read from $0 in END, and no `^`/`$` inside a regex alternation.
spec_scan() {
  awk -v sq="'" '
    function smoketok(t) {
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      gsub(/"/, "", t); gsub(sq, "", t)
      return (t ~ /^@?smoke/)
    }
    # A tag value: a flow list `[a, b]` or a single scalar.
    function taglist(v,   k, n, i, parts) {
      sub(/^[ \t]+/, "", v)
      if (substr(v, 1, 1) == "[") {
        v = substr(v, 2); k = index(v, "]"); if (k) v = substr(v, 1, k - 1)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) if (smoketok(parts[i])) return 1
        return 0
      }
      sub(/[,}].*$/, "", v)
      return smoketok(v)
    }
    # Drop a ` #` comment that is outside quotes.
    function stripc(s,   i, c, q) {
      q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; continue }
        if (c == "\"" || c == sq) q = c
        else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) return substr(s, 1, i - 1)
      }
      return s
    }
    # Walk flow text, carrying quote state (fq), depth (fd) and the last non-blank character
    # (fprev) across lines. A `tags:` key right after `{` or `,` at depth fkey is a scenario key.
    function flowscan(s,   i, n, c) {
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (fq != "") { if (c == fq) fq = ""; continue }
        if (c == "\"" || c == sq) fq = c
        else if (c == "[" || c == "{") fd++
        else if (c == "]" || c == "}") fd--
        else if (c == "t" && fd == fkey && (fprev == "{" || fprev == ",") && substr(s, i, 5) == "tags:") {
          if (taglist(substr(s, i + 5))) smoke = 1
        }
        if (c !~ /[ \t]/) fprev = c
      }
    }
    function flowstart(s, depth) { fq = ""; fd = 0; fprev = ""; fkey = depth; flowscan(s) }
    # The value after a `tags:` key at column col: a block list when empty, else a flow/scalar.
    function tagval(rest, col) {
      sub(/^[ \t]+/, "", rest)
      if (rest == "") { inblock = 1; blockcol = col }
      else if (taglist(rest)) smoke = 1
    }
    {
      f = $0; smoke = 0; basis = ""
      fenced = 0
      while ((getline line < f) > 0) if (line ~ /^[ \t]*```[ \t]*(yaml|yml)/) { fenced = 1; break }
      close(f)
      infence = 0; isyaml = 0
      topkey = ""; inblock = 0; blockcol = 0; itemcol = -1; keycol = 0; fd = 0
      while ((getline line < f) > 0) {
        sub(/\r$/, "", line)
        if (basis == "" && line ~ /^basis:/) {
          v = line; sub(/^basis:[ \t]*/, "", v); sub(/[ \t#].*$/, "", v); basis = v
        }
        if (line ~ /^[ \t]*```/) {
          if (infence) infence = 0
          else { infence = 1; isyaml = (line ~ /^[ \t]*```[ \t]*(yaml|yml)/) }
          topkey = ""; inblock = 0; itemcol = -1; fd = 0
          continue
        }
        if (fenced ? !(infence && isyaml) : infence) continue
        if (line ~ /^[ \t]*#/) continue
        l = stripc(line)
        if (l ~ /^[ \t]*$/) continue
        match(l, /^[ \t]*/); ind = RLENGTH
        # Still inside a multi-line flow collection that a scenarios: line opened.
        if (fd > 0) { flowscan(l); continue }
        # Inside a block list: `- item` lines at or right of the key column are its items; the
        # first other line ends it and is then read as an ordinary line.
        if (inblock) {
          if ((l ~ /^[ \t]*-[ \t]/ || l ~ /^[ \t]*-$/) && ind >= blockcol) {
            item = l; sub(/^[ \t]*-[ \t]*/, "", item)
            if (smoketok(item)) smoke = 1
            continue
          }
          inblock = 0
        }
        # Column 0: a top-level key (or, for anything but a sequence item, the end of one).
        if (ind == 0 && l !~ /^-/) {
          if (match(l, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
            topkey = substr(l, 1, RLENGTH - 1); rest = substr(l, RLENGTH + 1); itemcol = -1
            if (topkey == "tags") tagval(rest, 0)
            else if (topkey == "scenarios") flowstart(rest, 2)
          } else topkey = ""
          continue
        }
        if (topkey != "scenarios") continue
        # A scenarios: entry. The first `- ` fixes the entry column; a deeper `- ` belongs to
        # something inside an entry and is skipped.
        if (match(l, /^[ \t]*-[ \t]+/)) {
          if (itemcol < 0) itemcol = ind
          if (ind != itemcol) continue
          keycol = RLENGTH; content = substr(l, RLENGTH + 1)
          if (substr(content, 1, 1) == "{") flowstart(content, 1)
          else if (content ~ /^tags:/) tagval(substr(content, 6), keycol)
          continue
        }
        # A key of the current entry, aligned under its first key.
        if (itemcol >= 0 && ind == keycol && l ~ /^[ \t]*tags:/) {
          c = l; sub(/^[ \t]*tags:/, "", c); tagval(c, keycol)
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
    # -H so each hit carries its path. Drop every path with a `_`-prefixed segment, the same rule
    # as the `specs` inventory: that takes out the _context/ tree (basis/cases files declare their
    # own `feature:`, they are not fanned specs) and scratch specs, so a `_draft` cannot satisfy a
    # back-link that `specs` does not list.
    grep -rHE '^basis:[[:space:]]*' specs --include='*.md' 2>/dev/null | grep -vE '^specs/([^:]*/)?_'
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
