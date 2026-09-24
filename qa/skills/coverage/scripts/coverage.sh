#!/usr/bin/env bash
# coverage.sh — deterministic extraction for /qa-warden:coverage (9 dimensions).
#
# Extracted from the former /qa-warden:coverage prompt body: this is DATA COLLECTION only.
# The skill (../SKILL.md) owns the design contract and the output format; this script owns
# the shell recipes and must never format, paraphrase, or estimate. Run from the PROJECT
# root (cwd), not from the plugin dir — every path below is project-relative.
#
# Usage: bash coverage.sh "[area=<name>] [site=<id>]"
# Exit 2 = filter resolution error (a bogus area=), NOT a gap-free result.
# NOTE: deliberately NO `set -euo pipefail`. Every dimension must DEGRADE GRACEFULLY on
# absent optional inputs (basis/cases/manifests are all optional); -e or -u would abort the
# whole report on the first missing file, turning "no data" into "no gaps". Faithful to the
# original prompt block, which ran with no set flags.
ARGUMENTS="${1:-}"

AREA=""; SITE=""
for tok in $ARGUMENTS; do case "$tok" in area=*) AREA="${tok#area=}";; site=*) SITE="${tok#site=}";; esac; done
# Feature paths are <area>/<feature>; context paths are _context/<site>/<area>/…
# NOTE: <site> and <area> are ADJACENT path segments (…/_context/<site>/<area>/…), so the
# combined form is "/<site>/<area>/" — never "/<site>/.*/<area>/", whose mandatory `/`
# after `.*` was already consumed matching "/<site>/" and therefore matches NOTHING
# (a silently-empty dimension that reads as "no gaps").
COV_FILTER="."
[ -n "$AREA" ] && COV_FILTER="/${AREA}/"
[ -n "$SITE" ] && COV_FILTER="/${SITE}/${AREA:+${AREA}/}"
# AREA_FILTER — the area-ONLY companion to COV_FILTER, used by the presence gate below AND by
# dims 1b and 2. Derived ONCE here: the identical expression was previously re-assigned at three
# sites (as PRESENCE_FILTER, then twice as SPEC_FILTER), each with its own paragraph explaining
# why it is not COV_FILTER — three places to fix if the area-path convention changes, in a block
# whose whole failure mode is "a filter silently matches nothing and reads as no gaps".
# WHY it is not COV_FILTER (the one shared rationale):
# Presence gate — hard-abort ONLY on a bogus `area=`, validated against an AREA-ONLY filter, NOT the
# site-inclusive COV_FILTER (M-2). A bogus `area=typo` filters every FEATURE dimension to empty and
# reads as "no gaps" — the real false-clean risk, worth failing loudly. But authored feature specs are
# `specs/<area>/<feature>.md` with NO site segment, so a site-inclusive COV_FILTER matches ONLY optional
# `*.basis.md` files: a normal specs-only project with `site=` set (intake/ideate that emit basis files
# are OPTIONAL, and dims 1b/2 already ignore `site=`) would false-RED abort a fully computable report.
# So gate on area only; a site= degrades gracefully (feature dims still compute) with a soft WARN below.
AREA_FILTER="."; [ -n "$AREA" ] && AREA_FILTER="/${AREA}/"
# Two shared tree walks, hoisted here because the presence gate is their first consumer and each
# was previously re-run per dimension: AUTHORED_SPECS (dims 1b, 2) and BASIS_FILES (dims 1, 6).
AUTHORED_SPECS=$(find specs -name '*.md' ! -path 'specs/_context/*' 2>/dev/null)
BASIS_FILES=$(find specs/_context -name '*.basis.md' 2>/dev/null)
if [ -n "$AREA" ]; then
  if ! printf '%s\n%s\n' "$AUTHORED_SPECS" "$BASIS_FILES" | grep -qE "$AREA_FILTER"; then
    echo "ERROR: filter 'area=$AREA' matched NO spec or basis under specs/. Nothing to report — this is a RESOLUTION ERROR (check the area name), NOT a gap-free result."
    exit 2
  fi
fi
# Soft site-typo check — a `site=` naming no `specs/_context/<site>/` dir is likely a typo, but the
# feature dimensions stay fully computable, so WARN and degrade (never hard-abort on absent optional context).
if [ -n "$SITE" ] && [ ! -d "specs/_context/$SITE" ]; then
  echo "WARN: site=$SITE has no specs/_context/$SITE/ directory — check the site name (the basis-derived dim-1 rows will be empty for it); feature dimensions are still computed."
fi
# scripts/spec-links.sh owns the basis<->spec link index that dims 1, 5 and 6 (and the
# `unmanifested` walk) are computed FROM. Without it those dimensions print ZERO rows — which
# reads exactly like "no gaps". Refuse instead of emitting a partial report: an empty section
# is this command's one unforgivable output.
if [ ! -f scripts/spec-links.sh ]; then
  echo "ERROR: scripts/spec-links.sh missing — dims 1, 5 and 6 cannot be computed and would print EMPTY (a false clean). Substrate predates it; run /qa-warden:init --resync, then re-run. This is NOT a gap-free result."
  exit 2
fi
# The closed oracle vocabulary — a REGISTERED mirror of CLAUDE.md §"Test case format
# contract" (any new key beyond the current 16 must be added to this alternation in the
# same commit as every other mirror; a stale copy silently under-counts assertions in
# dimensions 1 and 2).
KEYS_RE='(text_visible|url_matches|count_equals|value_between|error_shown|no_order_created|attribute_equals|element_state|network_response_status|response_body_contains|download_received|clipboard_contains|storage_state|upload_accepted|dialog_dismissed|a11y_violations_below)[[:space:]]*:'

# specfiles_for <area/feature> — the ONE resolver for "which spec files belong to this feature"
# (UTIL-03/04). Dims 1, 5 and 6 each used to inline this, kept in sync by a hand-written
# "LOCKSTEP with dim N" comment — and the union had already drifted into two different
# spellings. One function instead: the canonical specs/<feat>.md (when it exists) PLUS every
# fanned spec that links back via a top-level `basis: <area>/<feature>` key, deduped.
# The back-link ANCHOR itself lives in scripts/spec-links.sh (`match`), which doctor Checks 13
# and 18 call too — it must tolerate a TRAILING comment after the feature (the plugin's OWN
# fanned-spec convention writes `basis: <area>/<feature>   # comment`, and a bare `…${feat}\$`
# end-anchor silently drops every commented link), and that tolerance has already needed one
# lockstep fix hand-applied across all three sites. `sort -u` matters because a canonical spec
# that ALSO carries a self-referential `basis:` link would otherwise be counted twice.
specfiles_for() {
  { [ -f "specs/$1.md" ] && printf '%s\n' "specs/$1.md"
    printf '%s\n' "$BASIS_LINKS" | bash scripts/spec-links.sh match "$1"
  } | sort -u
}

# --- shared tree walks — every dimension below reads these, nothing re-walks ------------------
# Dims 0 and 4 both consume the route manifests.
MANIFESTS=$(find artifacts/route-manifests -name '*.json' 2>/dev/null)
# ...and both are SILENTLY WRONG about a compiled test whose manifest is missing or was WITHHELD
# (verifier V4 withholds on a red parent, a BLIND/INCONCLUSIVE invariant, a disagreeing twin or
# budget exhaustion — withholding IS the durable blocker signal). Such a test contributes no
# routes, so dim 0 printed its routes under "touched by NO compiled test, planned, untested" —
# false for a test that is on disk and compiled, and it sends the reader to WRITE A SPEC when the
# real remedy is to clear the blocker — and dim 4's footprint quietly under-counted with no note.
# /qa-warden:impact has enumerated exactly this set as "BLIND SPOTS" all along; the walk is now shared
# (scripts/spec-links.sh unmanifested, doctor Check 9k) rather than re-derived, so the two
# commands cannot disagree about which specs are invisible to a manifest-derived answer.
UNMANIFESTED=$(bash scripts/spec-links.sh unmanifested 2>/dev/null)
# Every top-level `basis:` back-link in an authored spec, as `<path>:basis: <value>` (grep -H).
# specfiles_for() is called once per feature from dims 1, 5 and 6, and each call used to run a
# FULL recursive grep of specs/ — so a 20-feature project made ~40-60 complete traversals of the
# same tree looking for the same key. Harvest it ONCE; the function filters this string in memory.
# (doctor.sh hoists the same index the same way, from the same script — Checks 13/18.)
BASIS_LINKS=$(bash scripts/spec-links.sh index)

echo "LEGEND (for non-specialists) — SFDIPOT: a 7-lens test-angle checklist (Structure · Function · Data · Interfaces · Platform · Operations · Time), plus error-guessing as an 8th lens the toolkit adds — 8 in total, which is the /8 denominator below. 🔵 rule: a business rule captured in the basis. oracle key: one of the 16 assertion types a spec is allowed to use. Every 'gap' below is a WARN — something to look at, NOT a hard failure or a score."
echo ""
echo "== 0. Route plan vs footprint — area routes[] vs manifest routes (both directions, WARN-only) =="
# Exclude the _templates dir on the FIND/PATH side (C-04). The old `grep -rhoE … | grep -v
# '_templates'` was DEAD code: `grep -rh` SUPPRESSES the filename, so no output line ever
# contained the string "_templates" for `grep -v` to drop — a template's non-placeholder
# example `path:` would leak into DECL as a phantom "declared but untested" route. `grep -r
# --exclude-dir='_templates'` filters at the source (and `Bash(grep *)` is allowlisted — do NOT
# use `find … -exec grep`: the deny-list `Bash(find * -exec *)` OVERRIDES the `find specs*` allow,
# deny always wins, so a find-exec here prompts/denies, F-046). `-rh` suppresses the filename so
# the trailing `grep -vE '<[^>]*>'` still only sees path values, dropping angle-bracket PLACEHOLDER
# tokens (F-033) like `- path: "/<route>"` as belt-and-suspenders.
DECL=$(grep -rhoE '^[[:space:]]*-[[:space:]]*path:[[:space:]]*"[^"]+"' --include='*.md' --exclude-dir='_templates' specs/_context 2>/dev/null | sed -E 's/.*path:[[:space:]]*"([^"]+)".*/\1/' | grep -vE '<[^>]*>' | sort -u)
if [ -n "$MANIFESTS" ]; then
  TESTED=$(printf '%s\n' "$MANIFESTS" | tr '\n' '\0' | xargs -0 jq -r '.routes[]?' 2>/dev/null | sort -u)
  echo "-- declared in an area file but touched by NO compiled test (planned, untested):"
  comm -23 <(printf '%s\n' "$DECL") <(printf '%s\n' "$TESTED") | sed '/^$/d; s/^/  ⚠ /'   # drop the blank line printf emits for an empty DECL/TESTED so it never prints a phantom "  ⚠ " gap (m-12)
  echo "-- touched by tests but declared in NO area file (unplanned/undocumented — refresh /qa-warden:explore mode=area site=<id> area=<name>, or an API/login route area files legitimately don't list — review prompt, not defect list):"
  comm -13 <(printf '%s\n' "$DECL") <(printf '%s\n' "$TESTED") | sed '/^$/d; s/^/  ⚠ /'   # drop the blank line printf emits for an empty DECL/TESTED (m-12)
  # Third arm — WHY the first arm may be lying. Print it only when non-empty, and name the
  # remedy that differs: an unmanifested spec is authored AND compiled, so "write a spec" is
  # the wrong instruction for every route it touches.
  if [ -n "$UNMANIFESTED" ]; then
    echo "-- compiled but UNMANIFESTED — these tests exist on disk and contribute NO routes above, so any route they touch is mis-reported as 'planned, untested' (the verifier withholds a manifest on a red parent, a BLIND/INCONCLUSIVE invariant, a disagreeing twin or budget exhaustion — clear the blocker, do NOT author a second spec):"
    printf '%s\n' "$UNMANIFESTED" | while IFS=$'\t' read -r t base; do
      echo "  ⚠ $t  (no artifacts/route-manifests/${base}.json — same set /qa-warden:impact reports as BLIND SPOTS)"
    done
  fi
else echo "— (no route manifests; dim-0 unavailable)"; fi

echo "== 1. Requirement coverage — basis rules → spec/test exists =="
# Every basis → its expected spec + test path. Basis YAML carries `feature: <area>/<feature>`.
printf '%s\n' "$BASIS_FILES" | grep -E "$COV_FILTER" | while read -r basis; do
  feat=$(bash scripts/spec-links.sh feature "$basis")   # canonical indent-tolerant extractor (F-31)
  [ -z "$feat" ] && continue
  test="tests/${feat}.spec.ts"
  # Canonical + fanned spec files for this feature — one shared resolver (see specfiles_for above).
  specfiles=$(specfiles_for "$feat")
  # Legacy-covered rules: `- legacy:` list rows mark rules covered by an unmanaged legacy suite.
  # (grep -c prints 0 AND exits 1 on no-match, so an `|| echo 0` fallback would yield "0\n0" —
  # default the empty/unreadable case instead.)
  lg=$(grep -cE '^[[:space:]]*-[[:space:]]*legacy:' "$basis" 2>/dev/null); lg=${lg:-0}
  # Count 🔵 rules: list items under `rules:`, `must_not:` AND `integrity_invariants:` (F-30) —
  # the blue-oracle surface is all three blocks, not just `rules:`. Counting only `rules:` understated
  # the assertions-vs-rules signal (a spec could satisfy every `rules:` row while ignoring a `must_not:`
  # or `integrity_invariants:` obligation). Each of the three headers turns the counter on; any other
  # top-level YAML key turns it off.
  rules=$(awk '/^(rules|must_not|integrity_invariants):/{f=1;next} /^[A-Za-z_]+:/{f=0} f&&/^[[:space:]]*-[[:space:]]/{c++} END{print c+0}' "$basis")
  # Count oracle assertions across the direct spec AND any linked (fanned) specs
  # (closed-vocab keys; a PROXY — may over/under-count).
  keys="-"; specstat=NO; teststat=NO
  if [ -n "$specfiles" ]; then
    specstat=yes
    keys=$(grep -hoE "$KEYS_RE" $specfiles 2>/dev/null | wc -l | tr -d ' ')   # -h: grep takes the file list directly, no `cat`; suppress filename prefixes
  fi
  # Resolve the test the SAME fanned way specs are resolved (UTIL-03): a fanned feature's
  # test lives beside its fanned spec (tests/<area>/<fanned-feature>.spec.ts), never at the
  # canonical tests/<feat>.spec.ts — so a canonical-only `[ -f "$test" ]` reports test=NO for
  # a feature whose fanned tests exist and pass (the login-success/login-rejected case).
  # Walking $specfiles covers the canonical spec too (its basename IS $feat), so the direct
  # check below is just the fast path.
  [ -f "$test" ] && teststat=yes
  if [ "$teststat" = NO ]; then
    for ls in $specfiles; do lf="${ls#specs/}"; lf="${lf%.md}"
      [ -f "tests/${lf}.spec.ts" ] && { teststat=yes; break; }
    done
  fi
  # LEGACY(n) instead of NO when the basis marks n rules legacy-covered — a caveat, not parity.
  if [ "$specstat" = NO ] && [ "${lg:-0}" -gt 0 ]; then specstat="LEGACY(${lg})"; fi
  if [ "$teststat" = NO ] && [ "${lg:-0}" -gt 0 ]; then teststat="LEGACY(${lg})"; fi
  printf '%s\trules=%s\tspec=%s\ttest=%s\tassertions=%s\n' \
    "$feat" "$rules" "$specstat" "$teststat" "$keys"
done

echo "== 1b. Spec-without-test — an authored spec that never compiled to a .spec.ts (smoke/doctor/impact BLIND SPOT) =="
# Dim 1 above is basis-DRIVEN, so a spec authored without a basis (basis is optional — the
# intake→ideate chain is optional) is never enumerated there, and an approved/@smoke spec that
# was never generated is invisible to the smoke gate (--grep @smoke can't run a test that doesn't
# exist), to doctor Check 15 (which `continue`s past test-less specs), and to /qa-warden:impact. Enumerate
# it directly and surface it as a NAMED gap: every authored spec whose paired test file is absent.
gap1b=0
# site= has no path component in authored specs/<area>/<feature>.md paths (same as dim 2 below), so
# filter on the area-only AREA_FILTER here. COV_FILTER's /${SITE}/${AREA}/ form matches NO authored
# spec path, so a site=-only run would silently filter this dimension to empty and print a false
# "no spec-without-test gaps" — the exact critical blind spot this dimension exists to catch.
printf '%s\n' "$AUTHORED_SPECS" | grep -E "$AREA_FILTER" | while read -r spec; do
  feat="${spec#specs/}"; feat="${feat%.md}"
  [ -f "tests/${feat}.spec.ts" ] && continue
  smoke=""; grep -qE '@?smoke\b' "$spec" 2>/dev/null && smoke="  ← @smoke: the smoke GATE is blind to this un-compiled spec — a fully-broken feature hides behind 'no test to fail'"
  echo "  ⚠ GAP spec-without-test: $spec → no tests/${feat}.spec.ts${smoke}"
done
echo "  (none above = every authored spec has a compiled test; run /qa-warden:gen on any listed spec)"

echo "== 2. Assertion presence — density + the zero-assertion check =="
# One assertion count per authored spec (exclude context + templates). site= has no
# path component in authored specs/<area>/<feature>.md paths, so site= alone widens
# to the whole suite — area= is the effective filter here (AREA_FILTER, derived once above).
printf '%s\n' "$AUTHORED_SPECS" | grep -E "$AREA_FILTER" | while read -r spec; do
  printf '%s\t%s\n' "$spec" "$(grep -oE "$KEYS_RE" "$spec" | wc -l | tr -d ' ')"
done

echo "== 3. Lens gaps — SELF-REPORTED 'Lens coverage:' line from each *.cases.md (echoed, NOT recomputed) =="
# The ideate checklist logs every SFDIPOT lens with ✓ or "0 — <reason>". This line is the ideate
# agent's OWN self-report — coverage ECHOES it, it does NOT independently recompute lens presence
# (RUN-18: don't launder the self-reported ✓ as computed truth). So a ✓ here means "ideate claimed
# it", not "coverage verified it"; cross-check against the basis `nonfunctional:` block, and treat
# the ideation critic (per-feature) as the real enforcement.
# `grep -r --include` (not `grep $(find …)`): with zero .cases.md files the command-substitution
# form leaves grep with no file operands, so it reads STDIN — hanging an interactive shell; `grep -r`
# walks the tree directly (no STDIN, just empty output on no match). `find … -exec grep` is denied
# by the deny-list `Bash(find * -exec *)` (overrides the `find specs*` allow, F-046) — use grep -r.
grep -rH '^Lens coverage:' --include='*.cases.md' specs/_context 2>/dev/null

echo "== 4. Flow footprint — routes/areas actually touched (manifest-derived) =="
if [ -n "$MANIFESTS" ]; then
  # ONE walk (hoisted above dim 0) + ONE jq pass yields both counts.
  printf '%s\n' "$MANIFESTS" | tr '\n' '\0' \
    | xargs -0 jq -r '(.routes[]? | "R\t\(.)"), (.area // empty | "A\t\(.)")' 2>/dev/null \
    | sort -u | awk -F'\t' '{c[$1]++} END{print "distinct routes: " c["R"]+0; print "distinct areas: " c["A"]+0}'
  # The footprint is manifest-derived, so it is a FLOOR whenever dim 0's third arm fired. Say by
  # how much rather than printing a bare count that reads as the whole picture.
  nun=$(printf '%s' "$UNMANIFESTED" | grep -c . )
  [ "${nun:-0}" -gt 0 ] && echo "FLOOR, not the total: $nun compiled test(s) carry no manifest and contributed 0 routes here — see dim-0's 'compiled but UNMANIFESTED' list"
else echo "no route manifests — flow footprint unavailable (run /qa-warden:gen on a spec first)"; fi

echo "== 5. Case coverage — approved cases (*.cases.md) vs authored scenarios (RUN-18 backstop) =="
# Each ideate rule-group → one spec; its cases → that spec's scenarios. This dim is the COARSE,
# suite-wide COUNT companion to reviewer Check 14 (approved-case traceability), which does the
# per-case prose→scenario judgment and WARNs on a specific dropped approved case. This count is the
# deterministic dashboard signal (a number, not a per-case match): data-driven `scenarios:`
# legitimately collapse several cases into one, so cases>scenarios is a "confirm none were silently
# dropped — see the reviewer's Check 14 WARN for which" review prompt, not a hard gap (a deliberate
# drop should leave a `# waived:` note in the spec, or be named "Deferred" in the .cases.md banner).
find specs/_context -name '*.cases.md' 2>/dev/null | grep -E "$COV_FILTER" | while read -r cases; do
  feat=$(grep -m1 -E '^#[[:space:]]*cases:' "$cases" | sed -E 's/^#[[:space:]]*cases:[[:space:]]*//; s/[[:space:]].*$//')
  [ -z "$feat" ] && continue
  # case rows end in "→ oracle: <key> … risk: <level>". Count the APPROVED subset, not every
  # ideated row (RUN-27 gap): the old `grep -cE 'oracle:.*risk:'` counted approved + ☐-deferred +
  # ~~pruned~~ alike, inflating the "N cases vs M scenarios" gap (e.g. reporting ~32 for a file with
  # 20 ☑-approved + 12 deferred/pruned — and applying a suspiciously identical ~32 to two areas).
  # Deferred/pruned rows are DELIBERATE non-builds; counting them as "approved-but-unbuilt" overstates
  # the hole. So count ☑-approved rows when the file uses checkbox approval; fall back to all-ideated
  # only when it has NO ☑ boxes (approval lives in the banner prose — reviewer Check 14's "humans don't
  # reliably flip ☐→☑"), and LABEL which mode ran so the number is honest either way. (The ☑ byte
  # sequence is a fixed UTF-8 match — locale-independent in practice; the old ASCII-only rationale
  # traded correctness for a portability concern that grep -E handles fine on the UTF-8 .cases.md files.)
  ncases_all=$(grep -cE 'oracle:.*risk:' "$cases" 2>/dev/null)
  ncases_appr=$(grep -E 'oracle:.*risk:' "$cases" 2>/dev/null | grep -c '☑')
  if [ "${ncases_appr:-0}" -gt 0 ]; then ncases="$ncases_appr"; cbasis="approved"; else ncases="$ncases_all"; cbasis="all-ideated(no ☑)"; fi
  # Canonical + fanned spec files (shared resolver); scenario counts aggregate across all of them.
  allspecs=$(specfiles_for "$feat")
  if [ -n "$allspecs" ]; then
    # ≈ named scenarios: count the per-scenario `- name:` LIST items; a single-scenario spec has no
    # list (just one top-level `name:`) → count 1. (F-18: also anchoring the top-level `name:` — the
    # old `-?` optional-dash form — over-counted by exactly +1 per spec; a bare dash-anchor alone
    # under-counts a single-scenario spec to 0, so special-case that.) Summed across linked specs.
    nscen=0
    for sp in $allspecs; do
      nlist=$(grep -cE '^[[:space:]]*-[[:space:]]+name:' "$sp" 2>/dev/null)
      if [ "${nlist:-0}" -gt 0 ]; then nscen=$((nscen + nlist)); else nscen=$((nscen + 1)); fi
    done
    printf '%s\t%s_cases≈%s (of %s ideated)\tspec_scenarios≈%s\n' "$feat" "$cbasis" "$ncases" "$ncases_all" "$nscen"
  else
    printf '%s\t%s_cases≈%s (of %s ideated)\tspec=NO (uncovered)\n' "$feat" "$cbasis" "$ncases" "$ncases_all"
  fi
done

echo "== 5b. Waiver destinations — approved cases fanned to a sibling spec that must EXIST =="
# A spec descopes an approved case by fanning it to a sibling: `# waived: R2.a — … → specs/cart/cart-accumulate.md`.
# That is legitimate ONLY if the destination spec exists (or is tracked backlog) — otherwise the case is
# unbuilt AND its stated home is a phantom, so BOTH reviewer Check 14 and dim-5 above read it as "handled"
# while nothing tests it (RUN-27: ~20 auth+cart cases waived to five never-authored specs). Deterministic
# COUNT companion to reviewer Check 14's waiver-to-phantom-spec WARN: list every `→ specs/….md` destination
# that does not resolve to a file. (Prose/bolded `**area/feature**` destinations are left to the reviewer's
# judgment pass — this block only resolves explicit `specs/….md` path tokens, which are mechanically checkable.)
grep -rhoE '# waived:[^→]*→[[:space:]]*(specs/[A-Za-z0-9_./-]+\.md)' specs --include='*.md' 2>/dev/null \
  | grep -oE 'specs/[A-Za-z0-9_./-]+\.md' | sort -u \
  | while read -r dest; do
      [ -f "$dest" ] || echo "PHANTOM WAIVER DEST: $dest — a waiver fans approved cases here but the spec does not exist (create it, backlog it, or fold the cases back)"
    done

echo "== 6. Nonfunctional need → oracle KEY authored (not just lens ✓) =="
# Dim 3 checks a lens is non-EMPTY in cases; it does NOT check the declared need actually reached
# the spec's oracle. A basis `a11y: required` with an approved [Platform/a11y] case can still ship a
# spec with NO a11y_violations_below key — the lens shows ✓ (ideate listed a candidate) while the
# assertion silently evaporated between .cases.md and .md (the a11y-drop laundering, F-071). The one
# nonfunctional need with a direct closed-vocab key is a11y → a11y_violations_below; check it per feature.
printf '%s\n' "$BASIS_FILES" | grep -E "$COV_FILTER" | while read -r basis; do
  grep -qE '^[[:space:]]*a11y:[[:space:]]*required' "$basis" 2>/dev/null || continue
  # Anchor `^[[:space:]]*feature:` (indent-tolerant), matching dim-1 (F-31): a bare `^feature:`
  # (col-0 only) left `feat` EMPTY for an INDENTED `feature:` line → `spec="specs/.md"` → the
  # `[ -f ]` guard skipped it → the a11y-oracle check silently no-op'd on the best gap detector.
  feat=$(bash scripts/spec-links.sh feature "$basis")   # canonical indent-tolerant extractor (F-31)
  # Fan the spec set with the SAME resolver dims 1 & 5 use (UTIL-04): a fanned feature has no
  # canonical specs/<feat>.md, so a bare `[ -f "specs/$feat.md" ] || continue` SILENTLY SKIPS
  # the a11y-laundering check on exactly the fanned specs it exists to police — structurally
  # blind to the F-071 drop it claims to catch. Check the a11y key across the whole file set.
  specfiles=$(specfiles_for "$feat")
  [ -z "$specfiles" ] && continue
  grep -qh 'a11y_violations_below' $specfiles 2>/dev/null \
    || echo "⚠️  $feat: basis declares a11y:required but NO spec (canonical or fanned) carries an a11y_violations_below oracle — the a11y case dropped between cases.md and the spec (add the oracle or waive it in the spec's Open questions)"
done
# Other nonfunctional needs (i18n/performance/concurrency) have NO direct oracle key — the closed
# vocab can't express them, so they can only be flagged at the lens level (dim 3), not here.
