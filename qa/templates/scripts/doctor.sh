#!/usr/bin/env bash
# /qa:doctor — the deterministic self-check pass (checks 0–21 + rollup).
# Read-only: reruns no tests, heals nothing, hits no network, writes nothing.
# Run from the QA project root (the dir with playwright.config.ts + CLAUDE.md):
#   bash scripts/doctor.sh
# Each check prints ✅ / ⚠️ / ❌ + the offending path; exit 1 on any ❌.

set -a; [ -f "${CLAUDE_PROJECT_DIR:-.}/.env" ] && . "${CLAUDE_PROJECT_DIR:-.}/.env"; set +a
fail=0; warn=0

# 0. jq is load-bearing for check 1 — without this precheck a missing jq (or corrupt
#    JSON) leaves the freshness gate blind, and the rollup prints "✅ healthy" over a
#    broken run-of-record — a false-green inside the anti-false-green tool.
command -v jq >/dev/null || { echo "❌ jq not installed — cannot validate last-run.json"; fail=$((fail+1)); }

# 0b. ripgrep (rg) is an undeclared but plugin-wide dependency — /qa:retire's consumer-checks
#     and the healer/reviewer/planner greps all use it. A MISSING rg makes /qa:retire's "is this
#     shared?" query return empty, which false-reads as "unused ⇒ DELETE" (D-4) — a destructive
#     fail-open. WARN (not FAIL): most commands still work, and retire's SKILL.md now falls back to
#     grep -rl, but a QA should know rg is absent before running a consumer-checked deletion.
command -v rg >/dev/null || { echo "⚠️  ripgrep (rg) not installed — /qa:retire consumer-checks fall back to grep -rl; install rg (brew install ripgrep) so a missing tool can never false-read as 'safe to delete'"; warn=$((warn+1)); }

# 1. last-run.json freshness + zero-test guard (the F04/F07/F15 class) — single-sourced
#    in scripts/check-last-run.sh (also called by /qa:report's pre-aggregation check; the
#    two used to mirror this logic in prose and drifted). total = expected+unexpected+
#    skipped+flaky, NOT expected alone (that counts only PASSED tests — an all-red run
#    has expected=0 and must read as a real, fresh run, not as zero-test).
if [ -f scripts/check-last-run.sh ]; then
  lr_line=$(bash scripts/check-last-run.sh artifacts/last-run.json 900); lr_rc=$?
  # Show the raw status line for real runs (fresh/stale/corrupt/zero-test carry total+age), but NOT
  # the missing case — the friendly branch below states it plainly, and total=-1 is an internal
  # "no run yet" sentinel that reads to a non-coder like a negative count. Strip it defensively too.
  [ "$lr_rc" -ne 3 ] && printf '%s\n' "${lr_line// total=-1/}"
  case "$lr_rc" in
    0) : ;;                                                                              # fresh
    4) echo "❌ last-run.json unparseable — the run-of-record is corrupt"; fail=$((fail+1)) ;;
    5) echo "❌ last-run.json recorded 0 tests — a resolution error read as green"; fail=$((fail+1)) ;;
    3) echo "⚠️  no artifacts/last-run.json yet"; warn=$((warn+1)) ;;
    6) echo "⚠️  last-run.json >15min old — confirm it's the run you mean"; warn=$((warn+1)) ;;
    *) echo "⚠️  check-last-run.sh returned unexpected exit $lr_rc"; warn=$((warn+1)) ;;
  esac
else
  echo "⚠️  scripts/check-last-run.sh missing — project scaffolded before it shipped; re-run /qa:init --resync"; warn=$((warn+1))
fi

# 2. Closed-vocab drift — the oracle keys MUST be byte-identical across the SoT (CLAUDE.md)
#    and every mirror (planner, generator, reviewer Check 4). A divergence means the reviewer
#    FAILs specs its own planner authored.
#    The key set is READ from scripts/oracle-keys.txt, not hand-typed here. This check used to
#    carry its own copy and compare five files against it — a checker whose baseline was one
#    more unpoliced mirror, which is why it also needed a cardinality self-check on that copy
#    (a co-drifted list would silently bless a wrong vocab everywhere, at the right count).
#    Same manifest pattern as resync-set.txt / runtime-dirs.txt: one source, N consumers.
KEYS=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' scripts/oracle-keys.txt 2>/dev/null | grep -v '^$')
if [ -z "$KEYS" ]; then
  echo "❌ scripts/oracle-keys.txt missing or empty — the oracle vocabulary is UNVERIFIED (run /qa:init --resync)"; fail=$((fail+1))
fi
# missing_keys <file> — prints the keys ABSENT from <file>, one per line. Check 9b below runs the
# same scan over four plugin files; one helper instead of two copies of the loop, and one pass over
# each file instead of 16 (the per-key `grep -q` form re-read every file end to end, 16× per file).
# `grep -oFf` lists the keys the file DOES contain; `grep -vxFf` subtracts them from the full set.
# An empty pattern file matches nothing, so a file with ZERO keys correctly reports all 16 missing.
missing_keys() {
  [ -n "$KEYS" ] || return 0
  grep -vxFf <(grep -oFf <(printf '%s\n' "$KEYS") "$1" 2>/dev/null | sort -u) <(printf '%s\n' "$KEYS")
}
while read -r k; do
  [ -n "$k" ] || continue
  echo "❌ oracle key '$k' missing from CLAUDE.md"; fail=$((fail+1))
done < <(missing_keys CLAUDE.md)
# (Reviewer/planner/generator live in the plugin, not the project — the project's CLAUDE.md
#  is the stamped SoT. Check 9b below greps these same 16 keys against the plugin's agents when
#  the templates dir resolves, so post-upgrade plugin-side drift is caught too, not just local edits.)

# --- shared tree walks (Checks 3/13/14/15/15b/16/17/18) ----------------------------------
# These checks used to re-run the SAME walks over tests/ and specs/ (eight-plus traversals, and
# as many copies of filters that have already had to be fixed in lockstep). Walk each tree ONCE
# here, up front, and let every check downstream consume the result.
# `! -name '_*'` AND `! -path '*/_*/*'` — BOTH forms, in lockstep with playwright.config.ts's
# `testIgnore: ['**/_*.spec.ts','**/_*/**']`. `-path '*/_*/*'` alone catches only a `_`-prefixed
# DIRECTORY (tests/_probe/x.spec.ts); a `_`-prefixed BASENAME at the tests/ root
# (tests/_audit-visual.spec.ts, the sanctioned /qa:review url=<url> throwaway) has just ONE slash and so never
# matches it — it survived that filter and drew a false "unmanaged test" WARN on a spec Playwright
# provably never collects (verified: `--list` on the shipped testIgnore reports it dropped).
# A scratch spec carries no verified-stamp / review-attestation contract either.
TEST_FILES=$(find tests -name '*.spec.ts' -type f ! -name '_*' ! -path '*/_*/*' 2>/dev/null)
SPEC_FILES=$(find specs -name '*.md' ! -path 'specs/_context/*' ! -path '*/_*/*' -type f 2>/dev/null)
# specs/_context/ is the tree with the MOST consumers — Checks 5, 5b, 13, 18 and 19 each used to
# walk it separately (five traversals for one small tree). Walk it once; the checks below filter
# this list in memory or pass it as operands to a single grep.
CTX_FILES=$(find specs/_context -type f -name '*.md' 2>/dev/null)
# Every top-level `basis: <area>/<feature>` back-link in an authored spec, as `<path>:basis: <value>`
# (grep -H). Checks 13 and 18 each used to re-run a full `grep -r … specs` walk PER feature — an
# O(features × tree) sweep for a relation that is one grep to harvest. Both the harvest and the
# trailing-comment-tolerant match anchor now live in scripts/spec-links.sh (`index` / `match`),
# which /qa:coverage and /qa:impact call too — that anchor had already needed one lockstep fix
# applied by hand in three places.
BASIS_LINKS=$(bash scripts/spec-links.sh index 2>/dev/null)
# The spec↔test naming rule (specs/<p>.md ↔ tests/<p>.spec.ts, twins add .metamorphic) is applied
# by Checks 14/15/15b/16/17. As a shell FUNCTION rather than five copies of the same three
# parameter expansions — a layout change is one edit here, at zero fork cost per file.
# Accepts EITHER half of the pair (a tests/… or a specs/… path) and prints the shared <area>/<feature>
# stem, so a caller can name its counterpart as tests/<base>.spec.ts / specs/<base>.md.
spec_base() { local r="${1#tests/}"; r="${r#specs/}"; r="${r%.spec.ts}"; r="${r%.metamorphic}"; printf '%s' "${r%.md}"; }
# Specs declaring a `tags: [… smoke …]` scenario (the machine-authored tag, not a prose `@smoke`
# mention). Checks 16 and 17 partition this set between them; harvesting once means Check 17 needs
# no per-spec re-grep to find the half Check 16 owns.
SMOKE_SPECS_LIST=$(grep -rlE '^[[:space:]]*tags:[[:space:]]*\[[^]]*\bsmoke\b' specs --include='*.md' 2>/dev/null | grep -v '^specs/_context/')

# 3. Vacuous smoke gate — `--grep @smoke` must select ≥1 test, so count @smoke ON ITS OWN.
#    A combined '@smoke\|@regression' count is blind to the exact failure this check exists
#    for: a suite tagged only @regression (metamorphic twins are deliberately @regression,
#    never @smoke) makes the combined count >0 while /qa:run mode=smoke still selects 0 tests (F07).
#    Match `@smoke` INSIDE A STRING LITERAL (a quote/double-quote/backtick opened earlier on
#    the line), excluding `//`-comment lines — this counts BOTH official tag forms that
#    `--grep @smoke` selects: the `tag: ['@smoke']` array AND a title-embedded
#    `test('... @smoke', ...)` (the old quote-ADJACENT match missed title-embedded tags →
#    false ❌ on a working smoke lane). A bare `// NOT @smoke` comment still doesn't count
#    (RUN-19). No trailing boundary after @smoke on purpose: --grep is a substring match, so
#    a `@smoke-fast` title IS selected by /qa:run mode=smoke and must count here too. Residual: a
#    block-comment line mentioning '@smoke' still false-counts (fails toward noise, not
#    toward the false-green this check exists to prevent).
# Exclude `_`-prefixed SCRATCH specs from every count (P-05), in LOCKSTEP with
# playwright.config.ts's `testIgnore: ['**/_*.spec.ts', '**/_*/**']`: a `/qa:review url=<url>` throwaway
# like `tests/_audit-visual.spec.ts` OR a whole `tests/_probe/` dir is a probe byproduct the
# nightly does NOT run, so counting it here made a pristine scaffold that ran one audit hard-FAIL
# "1 spec, 0 @smoke → vacuous gate" on day one. Drop any path with a `_`-prefixed SEGMENT —
# basename OR directory — via the path-aware `(^|/)_` filter (F-027).
# ONE walk, not two: `@(smoke|regression)` is a strict superset of `@smoke`, and both counts used
# to run the identical 5-stage filter chain over the whole tests/ tree (~12 processes). Harvest the
# superset's `<path>:<line>:<text>` hits once, then derive each count by filtering it in memory.
TAG_HITS=$(grep -rnE "['\"\`][^'\"\`]*@(smoke|regression)" tests/ 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')
count_tagged() { printf '%s\n' "$TAG_HITS" | grep -E "$1" | cut -d: -f1 | grep -vE '(^|/)_' | sort -u | grep -c . | tr -d ' '; }
SMOKE_SPECS=$(count_tagged "['\"\`][^'\"\`]*@smoke")
TAGGED_SPECS=$(count_tagged '.')
# Same collected-test set every other check uses — count $TEST_FILES rather than re-walking tests/
# with a fourth hand-copy of the scratch-spec filter (`grep -c .` so an EMPTY set counts 0, which
# a bare `wc -l` on the single blank line printf emits would report as 1).
TOTAL_SPECS=$(printf '%s\n' "$TEST_FILES" | grep -c . | tr -d ' ')
echo "smoke-tagged spec files: $SMOKE_SPECS / $TOTAL_SPECS (smoke-or-regression: $TAGGED_SPECS)"
[ "$TOTAL_SPECS" -gt 0 ] && [ "$SMOKE_SPECS" -eq 0 ] && { echo "❌ no test carries @smoke — /qa:run mode=smoke's --grep @smoke selects 0 tests and passes vacuously"; fail=$((fail+1)); }

# 4 + 14. Orphaned heal sentinels and unmanaged tests — both single-sourced in
#    scripts/post-run-checks.sh, which /qa:run mode=smoke, /qa:report and /qa:run mode=single also call.
#    Each of those three used to carry its own copy of both scans (the sentinel one-liner was
#    BYTE-identical in two of them), and the stray-spec `_`-prefix filter existed in four copies
#    that must stay in lockstep with playwright.config.ts's `testIgnore`. Doctor asks for the two
#    tree scans only (`--only`): it reconciles bugs/ itself in Check 11b over ALL bug files, not
#    just the open ones, so letting the script surface them here would double-count the rollup.
#    The script prints its warnings already-formatted and a trailing `post-run: … stray=<n> …`
#    count line, which is what feeds $warn — no re-derivation of either scan here.
prc=$(bash scripts/post-run-checks.sh --prefix '⚠️ ' --only sentinels,stray 2>/dev/null)
printf '%s\n' "$prc" | grep -v '^post-run:' | grep -v '^$'
prc_n=$(printf '%s\n' "$prc" | sed -nE 's/^post-run: sentinels=([0-9]+) stray=([0-9]+).*/\1 \2/p')
for n in $prc_n; do warn=$((warn+n)); done

# 5. Stale context — any specs/_context/**/<area>.md past its volatility tier, OR draft:true.
#    Anchor `^draft: *true` (a real top-level YAML value) so a COMMENT like
#    "# …remove draft: true" in a draft:false file is not mis-flagged. Iterate via a
#    process-substitution (NOT a pipe) so `warn=1` set in the loop survives — a pipe
#    would run the `while` in a subshell and the flag would never propagate.
#    Greps the hoisted $CTX_FILES list rather than re-walking specs/_context/ (Checks 5/5b/13/19
#    were five separate traversals of the same small tree). `grep -l` with the files as operands
#    needs at least one operand, hence the guard.
ctx_grep_l() { [ -n "$CTX_FILES" ] && printf '%s\n' "$CTX_FILES" | tr '\n' '\0' | xargs -0 grep -lE "$1" 2>/dev/null; }
while read -r f; do [ -n "$f" ] || continue; echo "⚠️  unconfirmed draft context: $f"; warn=$((warn+1)); done \
  < <(ctx_grep_l '^draft:[[:space:]]*true')
# 5b. Volatility-tier staleness (the half RUN-20 found unimplemented — the header above
#     promised it but the code only greped draft:). Each area file's `volatility:` picks a
#     day-budget from `staleness_tiers:` in the hot-tier app.context.md; compare its
#     `last_verified:` date and WARN when older than the budget. Mirrors reviewer Check 7 so
#     `doctor` and the reviewer agree on "stale". date→epoch is dual-dialect (GNU `date -d`,
#     BSD `date -j -f`) — same macOS+GNU portability the other checks assume.
CTX=specs/_context/app.context.md
if [ -f "$CTX" ]; then
  # Three tier budgets out of one small file in ONE pass — this was three double-grep pipelines
  # (six processes) reading the same file to extract three integers.
  t_crit=''; t_ref=''; t_stab=''
  while IFS=: read -r tier days; do
    days=$(printf '%s' "$days" | tr -dc '0-9')
    [ -n "$days" ] || continue
    # FIRST declaration wins (matches the old `head -1`): a duplicated tier line must not let the
    # later one silently override the budget the reader sees at the top of the file.
    case "$tier" in
      critical)  [ -z "$t_crit" ] && t_crit=$days ;;
      reference) [ -z "$t_ref" ]  && t_ref=$days ;;
      stable)    [ -z "$t_stab" ] && t_stab=$days ;;
    esac
  done < <(grep -oE '(critical|reference|stable):[[:space:]]*[0-9]+' "$CTX")
  t_crit=${t_crit:-7}; t_ref=${t_ref:-30}; t_stab=${t_stab:-90}
  now=$(date +%s)
  while read -r f; do
    vol=$(grep -m1 -oE '^volatility:[[:space:]]*[a-z]+' "$f" | awk '{print $2}')   # -m1: first declaration wins — a duplicated volatility: line otherwise makes $vol multi-word, case falls to *) and a critical area silently gets the 30d default budget
    lv=$(grep -oE '^last_verified:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [ -z "$lv" ] && continue                                   # unfilled template (<YYYY-MM-DD>) → skip
    case "$vol" in critical) budget=$t_crit;; stable) budget=$t_stab;; *) budget=$t_ref;; esac
    lv_epoch=$(date -d "$lv" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$lv" +%s 2>/dev/null)
    [ -z "$lv_epoch" ] && continue
    age_days=$(( (now - lv_epoch) / 86400 ))
    [ "$age_days" -gt "$budget" ] && { echo "⚠️  stale context: $f (volatility=${vol:-reference}, last_verified $lv = ${age_days}d old > ${budget}d tier budget) — re-run /qa:explore mode=area"; warn=$((warn+1)); }
  done < <(ctx_grep_l '^volatility:')
fi

# 6. Undeclared env — any `process.env.<NAME>` read in the writable tree that is not
#    declared in .env.example resolves to `undefined` at runtime (the silent-auth-failure
#    class: a seed adapter POSTs to `undefined/...` with `Bearer undefined`; or a
#    `test.skip(!process.env.QA_TEST_SECRET)` guard silently skips a whole test). GENERALIZED:
#    extract the names actually read instead of enumerating known markers, so app-specific
#    adapters (SEED_API_KEY, a signed-cookie secret, …) are covered too. SCAN fixtures/ AND
#    tests/ AND page-objects/ — an undeclared read in a spec (a skipped checkout/seed test)
#    is the same silent-undefined bug, and scanning fixtures/ only lets it through.
for v in $(grep -rhoE 'process\.env\.[A-Z][A-Z0-9_]*' fixtures/ tests/ page-objects/ 2>/dev/null | sed 's/^process\.env\.//' | sort -u); do
  # Accept EITHER an uncommented `NAME=` OR a COMMENTED `# NAME=` declaration (R-32). The stock template
  # ships optional-with-fallback vars (BASE_URL, API_URL — both read `?? <fallback>`) COMMENTED *by design*
  # — so REQUIRING an uncommented decl here made every clean install show 2 un-fixable warnings,
  # eroding the whole warning channel. What Check 6 must still catch is a var read in
  # code that is ABSENT from .env.example entirely (not even commented) — the real silent-undefined omission.
  # Still anchor to a `NAME=` assignment (after an optional `# `): a bare `grep -q "$v"` false-matches a
  # longer var (BASE_URL in BASE_URL_APP) or prose inside a comment; requiring `=` right after NAME prevents
  # both (the `BASE_URL_APP=` line does NOT satisfy `^#? *BASE_URL=`).
  grep -qE "^#? *${v}=" .env.example 2>/dev/null || { echo "⚠️  code reads \$$v but it's not declared in .env.example at all (not even commented) — silent undefined → skipped test / bad request"; warn=$((warn+1)); }
done

# 7. Version-pin sanity — three guards in one node pass (RUN-21/RD-10 widened it from
#    package.json-alpha-only to also catch the two skews the prose claimed but didn't check):
#    Sub-guards are labelled 7a/7b/7c so a cross-reference elsewhere in this file (e.g. Check 8b
#    cites "Check 7b" for the zod lockstep) resolves by grep; 7d below is the fourth sub-guard.
#    (7a) no alpha/beta/rc anywhere in package.json deps/devDeps/overrides;
#    (7b) zod↔zod-fixture LOCKSTEP — zod-fixture introspects Zod-3 internals, so if it's a dep
#        zod MUST stay on the 3.x line (a bare package.json regex for alpha/beta never caught a
#        clean-but-Zod-4 bump that silently breaks every generated fixture);
#    (7c) the LOCKFILE's RESOLVED playwright-core is stable — the `overrides` pin only helps if
#        package-lock.json actually dedupes to a non-alpha core; an alpha core that slips into
#        the lockfile despite a clean package.json is the exact "Executable doesn't exist" CI skew.
# Exit 2 on any bad pin so the shell can raise `fail` — a `❌` printed by the node subprocess
# must count toward the rollup, else doctor prints "✅ healthy" over a bad pin.
node -e '
  const p = require("./package.json");
  const bad = [];

  // (a) no alpha/beta/rc anywhere in package.json version strings
  const scan = (obj, prefix) => {
    for (const [k, v] of Object.entries(obj || {})) {
      if (typeof v === "string") { if (/alpha|beta|rc/.test(v)) bad.push([prefix + k, v]); }
      else scan(v, prefix + k + ".");
    }
  };
  scan(p.dependencies, ""); scan(p.devDependencies, ""); scan(p.overrides, "overrides.");

  // (b) zod <-> zod-fixture lockstep. zod-fixtures peer range is ">=3.0.0", so npm ACCEPTS
  //     zod@4 with no warning — but zod-fixture 2.5.2 introspects Zod-3 internals and throws
  //     at runtime on Zod 4, snapping every generated fixture. If zod-fixture is a dep, zod
  //     MUST stay pinned on the 3.x line. (Verified against npm: peer=">=3.0.0", 2.5.2 is the
  //     newest release and has no Zod-4 support.)
  const deps = Object.assign({}, p.dependencies, p.devDependencies);
  if (deps["zod-fixture"] && deps["zod"] && !/^[~^]?3\./.test(deps["zod"])) {
    bad.push(["zod<->zod-fixture lockstep", "zod " + deps["zod"] + " needs to stay on 3.x for zod-fixture"]);
  }

  // (c) lockfile resolved playwright-core must be stable. The overrides pin only helps if
  //     package-lock.json actually deduped to a non-alpha core; an alpha core in the lock
  //     despite a clean package.json is the "Executable doesnt exist" CI skew.
  try {
    const lock = require("./package-lock.json");
    for (const [name, meta] of Object.entries(lock.packages || {})) {
      if (/(^|\/)playwright-core$/.test(name) && meta && /alpha|beta|rc/.test(meta.version || "")) {
        bad.push(["lockfile " + name, meta.version]);
      }
    }
  } catch (e) { /* no lockfile yet — not this checks job to flag that */ }

  if (bad.length) { console.log("❌ non-stable pin / lockstep:", bad); process.exit(2); }
  console.log("pins: stable + zod lockstep + lockfile core ✅");
' 2>/dev/null
pin_rc=$?
[ "$pin_rc" -eq 2 ] && fail=$((fail+1))                                    # ❌ non-stable pin
{ [ "$pin_rc" -ne 0 ] && [ "$pin_rc" -ne 2 ]; } && { echo "⚠️  could not read package.json pins"; warn=$((warn+1)); }  # node crashed / no package.json

# 7d. Version<->idiom consistency — the pins above say WHICH major is installed; this catches
#     GENERATED code written in the WRONG major's idiom. It's the mechanical backstop for the
#     fact that this suite is AI-authored by tools (Claude Code, Cursor, Copilot, …) whose
#     model training cutoffs are all months stale: a fresher model emits Zod-4 top-level format
#     validators (z.email()/z.url()/z.uuid()/z.iso.*) that DO NOT EXIST in the pinned Zod-3 line
#     (v3 spells them z.string().email() etc.), and a staler model on a future Zod-4 bump emits
#     the removed z.string().email() form. Either way it typechecks-or-mis-generates silently —
#     generator.md TELLS the model the idiom but nothing VERIFIED the output until here.
#     Gated on the installed major so it's correct after a future migration, not just today.
if [ -d fixtures/schemas ]; then
  zpin=$(node -e 'const d=Object.assign({},require("./package.json").dependencies,require("./package.json").devDependencies);process.stdout.write(d.zod||"")' 2>/dev/null)
  case "$zpin" in
    *3.*)   # pinned to Zod 3 — flag Zod-4-only top-level format validators.
            # Exclude COMMENT lines (//, /*, * JSDoc), anchored on grep's own file:NN: prefix —
            # the shipped user.ts.example's comment mentions the idiom, and the documented
            # copy-to-user.ts path otherwise draws a false ❌ on a correct Zod-3 file. Residual:
            # an inline TRAILING comment on a code line still flags (rare; errs toward visible).
      hits=$(grep -rnE 'z\.(email|url|uuid|int|iso)\b' fixtures/schemas/ 2>/dev/null | grep -v '\.example:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|/\*|\*)')
      [ -n "$hits" ] && { echo "❌ Zod-4 idiom under a Zod-3 pin (use z.string().email() etc.):"; echo "$hits"; fail=$((fail+1)); } ;;
    *4.*)   # future: pinned to Zod 4 — flag the deprecated v3 string-format chain (same comment-line exclusion)
      hits=$(grep -rnE 'z\.string\(\)\.(email|url|uuid)\b' fixtures/schemas/ 2>/dev/null | grep -v '\.example:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|/\*|\*)')
      [ -n "$hits" ] && { echo "❌ deprecated Zod-3 idiom under a Zod-4 pin (use z.email() etc.):"; echo "$hits"; fail=$((fail+1)); } ;;
  esac
fi

# 8. Canonical scripts present + prod-guard lockstep. scripts/prod-guard.sh and
#    scripts/resolve-spec-path.sh are what every command's safety rail / path
#    resolution calls — a project scaffolded before they shipped needs a /qa:init
#    refresh. And the two prod-guard layers must carry the SAME word-boundary marker
#    (sh spells it [0-9]*, ts spells it \d* — same semantics); a drifted pair means
#    the advisory layer and the enforced layer disagree on what "prod" means.
#
#    FOUR lockstep pairs, not one (2026-09-06 parity audit, §4b finding 3). The files'
#    OWN comments demand lockstep on three more literals, and nothing checked them:
#    prod-guard.ts:15 "Keep this var-name set in lockstep with prod-guard.sh", and
#    prod-guard.sh:101 "Keep these two case patterns in lockstep with prod-guard.ts's
#    PLACEHOLDER_VALUE_RE / PLACEHOLDER_HOST_RE". Differential testing proved the two
#    layers AGREE today (55 cases, 54 identical verdicts), so this pins the agreement
#    rather than fixing a break — the same unchecked-hand-mirrored-pair shape Checks
#    9b/9bb/9bc exist for. The var-name set is the load-bearing one: NARROWING it on one
#    side silently unscreens a target on that layer, so a prod URL parked in the dropped
#    var sails past that guard while the other still refuses — a divergence that presents
#    as "the guard is inconsistent", not as an obvious break.
#    Two of the three pairs are pinned PER-FILE rather than compared byte-to-byte,
#    because the layers legitimately spell them in different languages (JS regex vs shell
#    `case` glob) — exactly like the marker regex above.
for f in scripts/prod-guard.sh scripts/resolve-spec-path.sh scripts/spec-links.sh scripts/post-run-checks.sh scripts/oracle-keys.txt; do
  [ -f "$f" ] || { echo "⚠️  $f missing — project scaffolded before it shipped; re-run /qa:init"; warn=$((warn+1)); }
done
if [ -f scripts/prod-guard.sh ]; then
  grep -qF '(^|[.-])(prod|production)[0-9]*($|[.-])' scripts/prod-guard.sh \
    || { echo "❌ scripts/prod-guard.sh: canonical prod-marker regex not found (drifted or removed)"; fail=$((fail+1)); }
  # Pair 2 of 4 — screened var-name set. Byte-identical in both layers, so this same
  # literal is asserted against the .ts below; a narrowed set unscreens a live target.
  grep -qF '(BASE_URL[A-Z0-9_]*|API_URL|[A-Z0-9_]*_API_URL)' scripts/prod-guard.sh \
    || { echo "❌ scripts/prod-guard.sh: screened var-name set drifted — must stay in lockstep with prod-guard.ts (a narrowed set silently stops screening a target on this layer)"; fail=$((fail+1)); }
  # Pair 3 of 4 — placeholder VALUE sentinel (.ts spells it /changeme|[<>]/i).
  grep -qF "*changeme*|*'<'*|*'>'*" scripts/prod-guard.sh \
    || { echo "❌ scripts/prod-guard.sh: placeholder-value case pattern drifted — must stay in lockstep with prod-guard.ts's PLACEHOLDER_VALUE_RE"; fail=$((fail+1)); }
  # Pair 4 of 4 — RFC-2606 placeholder HOST list, label-anchored (.ts spells it
  # /(^|\.)example(\.(com|org|net))?$/i).
  grep -qF 'example.com|*.example.com|example.org|*.example.org|example.net|*.example.net|example|*.example' scripts/prod-guard.sh \
    || { echo "❌ scripts/prod-guard.sh: RFC-2606 placeholder-host case list drifted — must stay in lockstep with prod-guard.ts's PLACEHOLDER_HOST_RE"; fail=$((fail+1)); }
fi
if [ -f scripts/prod-guard.ts ]; then
  grep -qF '(^|[.-])(prod|production)\d*($|[.-])' scripts/prod-guard.ts \
    || { echo "❌ scripts/prod-guard.ts: canonical prod-marker regex not found (drifted or removed)"; fail=$((fail+1)); }
  # Pair 2 of 4 — same literal as the .sh above (this pair IS byte-identical).
  grep -qF '(BASE_URL[A-Z0-9_]*|API_URL|[A-Z0-9_]*_API_URL)' scripts/prod-guard.ts \
    || { echo "❌ scripts/prod-guard.ts: screened var-name set drifted — must stay in lockstep with prod-guard.sh (a narrowed set silently stops screening a target on this layer)"; fail=$((fail+1)); }
  # Pair 3 of 4 — PLACEHOLDER_VALUE_RE.
  grep -qF 'changeme|[<>]' scripts/prod-guard.ts \
    || { echo "❌ scripts/prod-guard.ts: PLACEHOLDER_VALUE_RE drifted — must stay in lockstep with prod-guard.sh's *changeme*/<>/ case pattern"; fail=$((fail+1)); }
  # Pair 4 of 4 — PLACEHOLDER_HOST_RE.
  grep -qF '(^|\.)example(\.(com|org|net))?$' scripts/prod-guard.ts \
    || { echo "❌ scripts/prod-guard.ts: PLACEHOLDER_HOST_RE drifted — must stay in lockstep with prod-guard.sh's RFC-2606 case list"; fail=$((fail+1)); }
fi
# 8b. MCP server PAIRED-BUMP lockstep. As of Playwright 1.62 the MCP server ships BUNDLED with
#     `playwright`, so .mcp.explore.json launches `npx -y playwright@<version> mcp`. That npx arg
#     MUST be pinned and MUST equal the `overrides.playwright` pin: an UNPINNED `npx -y playwright
#     mcp` silently fetches the LATEST Playwright whenever node_modules is absent (a fresh clone,
#     a lockfile-less CI step) — the exact runner/core version skew the whole `overrides` block
#     exists to prevent, except sourced from the explore config instead of the dep tree. Two arms:
#     (a) BUNDLED (current) — .mcp.explore.json's `playwright@X.Y.Z` npx arg vs overrides.playwright;
#         a bare unpinned `playwright` arg is itself a FAIL.
#     (b) LEGACY standalone `@playwright/mcp` — only if a project still carries that invocation;
#         its 0.0.x line means npm's caret does NOT float, so the bump is manual and easy to half-do.
if [ -f package.json ] && [ -f .mcp.explore.json ]; then
  # (a) bundled invocation
  if grep -qE '"playwright(@[0-9]+\.[0-9]+\.[0-9]+)?"[[:space:]]*,[[:space:]]*$|"playwright(@[0-9]+\.[0-9]+\.[0-9]+)?"' .mcp.explore.json; then
    pw_pin=$(grep -oE '"playwright"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' package.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    pw_cfg=$(grep -oE '"playwright@[0-9]+\.[0-9]+\.[0-9]+"' .mcp.explore.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$pw_cfg" ]; then
      echo "❌ .mcp.explore.json launches an UNPINNED \`npx -y playwright mcp\` — pin it to \`playwright@<version>\` matching overrides.playwright, or a node_modules-less run silently fetches the LATEST Playwright (runner/core skew)"; fail=$((fail+1))
    elif [ -n "$pw_pin" ] && [ "$pw_pin" != "$pw_cfg" ]; then
      echo "❌ Playwright MCP paired-bump drift: package.json overrides pin $pw_pin but .mcp.explore.json launches $pw_cfg — bump BOTH in the same change (package.json mcp_comment)"; fail=$((fail+1))
    fi
  fi
  # (b) legacy standalone package, only when still referenced
  mcp_dep=$(grep -oE '"@playwright/mcp"[[:space:]]*:[[:space:]]*"[^"]+"' package.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  mcp_cfg=$(grep -oE '@playwright/mcp@[0-9]+\.[0-9]+\.[0-9]+' .mcp.explore.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -n "$mcp_dep" ] && [ -n "$mcp_cfg" ] && [ "$mcp_dep" != "$mcp_cfg" ]; then
    echo "❌ @playwright/mcp paired-bump drift (legacy invocation): package.json pins $mcp_dep but .mcp.explore.json launches $mcp_cfg — bump BOTH in the same change (package.json mcp_comment)"; fail=$((fail+1))
  fi
fi

# 9. Substrate drift — toolkit-OWNED config/scripts agents cannot repair in place. Three
#    protection tiers, and this check is the only thing that covers all three:
#      (a) HARD-DENIED in settings.json deny[] — package.json, package-lock.json,
#          playwright.config.ts, tsconfig.json, .mcp.json, .mcp.explore.json, prod-guard.sh/.ts,
#          and every scripts/*.sh EXCEPT init.sh. Blocked outright.
#      (b) Write-allowlist-EXCLUDED — scripts/init.sh, scripts/README.md, and the four
#          scripts/*.txt manifests, .github/**, .env. Not in deny[], so per-prompt-approved.
#      (c) Inside a Write/Edit ALLOW glob — the resync-set members under specs/** and
#          fixtures/**. These were once silently auto-writable (no deny, no prompt): an agent
#          could clobber specs/_context/_templates/basis.md with a real feature's basis and
#          every later /qa:intake would read the corrupted file as its template. Now denied by
#          path, but keep this tier in mind when ADDING a resync-set entry under an allowed
#          tree — the deny is per-path and does not follow automatically.
#    /qa:init is skip-if-exists, so a plugin fix to any of these does NOT reach a project
#    scaffolded before the fix — a shipped fix silently strands every existing project
#    (F-015/F-016). Detect the drift here (read-only) against the shipped templates and name
#    the repair: /qa:init --resync. Skips cleanly when the plugin root isn't resolvable (doctor
#    run standalone). Also covers scripts/init.sh (F-03: toolkit-owned, scaffold-copied,
#    force-overwritten by --resync — so drift there must be DETECTED, not silently reset).
#    Excludes user-authored files (.env, CLAUDE.md, settings.json, fixtures/test.ts) — those
#    are not toolkit-owned. package-lock.json IS compared (it is in RESYNC_SET, and the M-8
#    lockstep requires detection and repair to cover the same set). It was once excluded here
#    on a "churns on local installs" assumption that does not hold for this project: every dep
#    is exact-pinned and the lockfile is lockfileVersion 3, so `npm install` leaves it
#    byte-identical (verified) and this comparison does not generate a standing false WARN.
#    .env.example is SHARED-ownership — users must extend it for seed vars (Check 6 /
#    test-data-seed) — excluded like CLAUDE.md; the stock-var containment sub-check below
#    still catches a stock variable being DELETED from it.
# Resolve the plugin templates dir: prefer $CLAUDE_PLUGIN_ROOT (inline-substituted when run via
# /qa:doctor — the env var is NOT exported to bash subprocesses, F-069), else the ACTIVE install
# recorded in ~/.claude/plugins/installed_plugins.json (this project's entry, else the user-scope
# entry, else the most recently updated), else — last resort — newest cached qa/*/templates by
# mtime. Side-by-side version dirs are EXPECTED in the cache (an orphaned version lingers ~7 days
# after an update), so a blind mtime pick can compare against a STALE plugin; always NAME the dir
# used so a wrong pick is visible. (Do NOT prefer a semver-named dir over 'unknown' — in
# commit-SHA mode from a non-git directory source, 'unknown' IS the active install.)
TMPL="${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/templates}"
if [ -z "$TMPL" ] || [ ! -d "$TMPL" ]; then
  TMPL=""
  IPJ="$HOME/.claude/plugins/installed_plugins.json"
  if command -v jq >/dev/null && [ -f "$IPJ" ]; then
    TMPL="$(jq -r --arg pwd "$PWD" '
      [ .plugins // {} | to_entries[] | select(.key | startswith("qa@")) | .value[] ]
      | ( map(select(.scope=="local" and .projectPath==$pwd))
          + map(select(.scope=="user"))
          + (sort_by(.lastUpdated) | reverse) )
      | first | .installPath // empty' "$IPJ" 2>/dev/null)"
    [ -n "$TMPL" ] && TMPL="$TMPL/templates"
    if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
      echo "ℹ️  substrate-drift baseline: recorded active plugin install → $TMPL"
    else
      TMPL=""
    fi
  fi
fi
if [ -z "$TMPL" ]; then
  TMPL="$(ls -dt "$HOME"/.claude/plugins/cache/*/qa/*/templates 2>/dev/null | head -1)"
  if [ -n "$TMPL" ]; then
    echo "⚠️  substrate-drift baseline GUESSED by newest mtime: $TMPL — orphaned plugin versions linger ~7 days beside the active one, so this may be STALE; run via /qa:doctor (resolves CLAUDE_PLUGIN_ROOT) to be sure"; warn=$((warn+1))
  fi
fi
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  # The toolkit-owned set is SINGLE-SOURCED in the shipped templates/scripts/resync-set.txt,
  # which qa-scaffold's --resync reads too — detection and repair MUST cover the SAME files,
  # else drift in a resync-refreshed file (e.g. _templates/basis.md, which seeds every intake)
  # is silently repaired by `--resync` but never DETECTED here, so doctor never fires the "run
  # --resync" nudge its own header promises (M-8). Two hand-kept lists could not hold that;
  # one manifest can. The manifest also documents the user-editable exclusions.
  OWNED=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$TMPL/scripts/resync-set.txt" 2>/dev/null | grep -v '^$')
  [ -n "$OWNED" ] || { echo "⚠️  toolkit-owned manifest (scripts/resync-set.txt) not readable in $TMPL — substrate drift is UNVERIFIED"; warn=$((warn+1)); }
  for rel in $OWNED; do
    [ -f "$TMPL/$rel" ] || continue
    if [ ! -f "$rel" ]; then
      echo "❌ substrate missing: $rel absent from project — run /qa:init --resync"; fail=$((fail+1))
    elif ! cmp -s "$TMPL/$rel" "$rel"; then
      echo "⚠️  substrate drift: $rel differs from the shipped template — run /qa:init --resync (backs up to $rel.qa-bak)"; warn=$((warn+1))
    fi
  done
else
  # A skipped drift check must be VISIBLE (WARN, counted), not a silent green INFO — this check
  # guards the highest-value propagation class (F-015/F-027); a quiet skip hides exactly that drift.
  echo "⚠️  substrate-drift check SKIPPED — plugin templates not found (set CLAUDE_PLUGIN_ROOT or run via /qa:doctor); drift to the shipped substrate is UNVERIFIED"; warn=$((warn+1))
fi
# Stock-var containment — .env.example is shared-ownership (excluded from the byte-compare
# above), but the STOCK variables must survive user extension: a deleted stock var silently
# breaks the scaffolded config/fixtures that read it. DERIVE the list from the shipped
# template's UNCOMMENTED assignments (don't hand-enumerate — the template has grown before
# and a hand-kept list here silently misses the next var added there); fall back to the
# frozen shipped list only when $TMPL didn't resolve (standalone run — that path has already
# WARNed visibly above). A commented '# NAME=' in the project's .env.example still satisfies
# the check — that is the sanctioned way to park a stock var you don't use (e.g. QA_ALICE_PW).
if [ -f .env.example ]; then
  # No hardcoded fallback list. This used to fall back to a frozen copy of the stock vars when
  # $TMPL didn't resolve — a second hand-kept mirror of the template, inside the very check whose
  # comment says not to hand-enumerate, and one that would silently validate against a stale set
  # after the template grew. When the baseline is unresolvable the honest answer is "unverified"
  # (the $TMPL resolution failure has already WARNed loudly above), not a quiet check of the
  # wrong list.
  if [ -n "$TMPL" ] && [ -f "$TMPL/.env.example" ]; then
    STOCK_VARS=$(grep -oE '^[A-Z_][A-Z0-9_]*=' "$TMPL/.env.example" | cut -d= -f1)
  else
    STOCK_VARS=''
    echo "ℹ️  stock-var containment SKIPPED — the shipped .env.example baseline did not resolve (see the substrate-drift warning above); no stale hardcoded list is substituted."
  fi
  for v in $STOCK_VARS; do
    grep -qE "^#? *${v}=" .env.example || { echo "⚠️  stock var $v missing from .env.example — restore it (see the shipped template; a commented '# ${v}=' also satisfies this check)"; warn=$((warn+1)); }
  done
fi

# 9b. Plugin-side vocab drift (F-09) — check 2 greps the 16 keys against the PROJECT's CLAUDE.md
#     ONLY, but the planner/generator/reviewer that actually COMPILE specs live in the plugin, and
#     that is exactly where drift lands after a plugin upgrade (a project CLAUDE.md can be in sync
#     while the shipped agents diverged). When $TMPL resolved (check 9), also grep the 16 keys
#     against the plugin's agents so a post-upgrade divergence is caught, not just a local edit.
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  # /qa:coverage's KEYS_RE alternation is the FOURTH enumerating mirror (CLAUDE.md §"Test case
  # format contract" and reference/DESIGN.md both name it as a same-commit edit site) — it was
  # the one mirror nothing policed, so a stale copy there silently UNDER-COUNTS assertions in
  # coverage dims 1 and 2 with no signal anywhere.
  for af in agents/planner.md agents/generator.md agents/reviewer.md skills/coverage/scripts/coverage.sh; do
    apath="$TMPL/../$af"
    # A MISSING mirror must never read as "no drift". This check exists for the post-upgrade
    # case, and a plugin layout move (e.g. the commands/ -> skills/ migration) is exactly how a
    # mirror path goes stale — a silent `continue` would report green for an UNCHECKED mirror.
    if [ ! -f "$apath" ]; then
      echo "⚠️  vocab-drift mirror '$af' not found at $apath — the plugin layout moved; oracle-key drift in that mirror is UNVERIFIED (run /qa:init --resync to refresh this script)"
      warn=$((warn+1)); continue
    fi
    while read -r k; do
      [ -n "$k" ] || continue
      echo "❌ oracle key '$k' missing from plugin $af — post-upgrade vocab drift (reviewer would FAIL specs its own planner authors)"; fail=$((fail+1))
    done < <(missing_keys "$apath")
  done
fi

# 9bb. Oracle ARGUMENT-SHAPE drift. Checks 2 and 9b compare key PRESENCE only — `missing_keys`
#      is set membership, no argument parsing anywhere — so a mirror can carry all 16 keys while
#      pinning a DIFFERENT shape for one of them. That is the closed vocab's own failure mode one
#      level down: `count_equals: { count }` where the canonical shape is `{ locator, n }` passes
#      every existing check green, and the generator (which reads `.n`) silently DROPS the
#      assertion. reference/DESIGN.md called this pair a deliberate emitter-side copy but nothing
#      compared it; planner.md's own maintainer comment said so outright.
#      Compares the SHIPPED templates/CLAUDE.md against the plugin's agents/planner.md — the same
#      post-upgrade framing as 9b, not the project's editable copy.
#      Shape = the FIRST backticked expression in column 2. The trailing prose deliberately
#      differs between the two tables (CLAUDE.md carries longer notes), so a byte-compare of the
#      whole cell would fire on every wording edit; comparing only the shape expression is what
#      makes this check quiet enough to keep.
#      NOTE the key charclass includes digits — `a11y_violations_below` is silently dropped by a
#      naive [a-z_]+, which would leave one of the 16 unchecked while the check reported green.
#      COVERAGE LIMIT: this compares the two MARKDOWN-TABLE mirrors only. agents/generator.md
#      holds shapes as an Oracle->expect mapping and agents/reviewer.md Check 4 states them inline
#      as prose counter-examples; neither is a table, so neither is comparable with this extractor
#      and both remain UNGUARDED. DOCUMENTATION.md's numbered table lives outside the plugin dir
#      and is unreachable from a scaffolded project. Do not read a green 9bb as "all mirrors agree".
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  # arg_shapes <file> — "key<TAB>canonical-shape" per arg-shape table row.
  arg_shapes() { sed -nE 's/^\| `([a-z0-9_]+)` \| `([^`]*)`.*/\1\t\2/p' "$1" 2>/dev/null; }
  sot_tbl="$TMPL/CLAUDE.md"; pln_tbl="$TMPL/../agents/planner.md"
  if [ ! -f "$sot_tbl" ] || [ ! -f "$pln_tbl" ]; then
    echo "⚠️  arg-shape mirrors not both found ($sot_tbl / $pln_tbl) — argument-shape drift is UNVERIFIED (run /qa:init --resync)"; warn=$((warn+1))
  else
    sot_shapes=$(arg_shapes "$sot_tbl"); pln_shapes=$(arg_shapes "$pln_tbl")
    # A table that fails to parse must not read as "no drift" — an empty side means the format
    # moved out from under the extractor, which is a silent-green risk, not a pass.
    n_sot=$(printf '%s\n' "$sot_shapes" | grep -c . || true)
    n_pln=$(printf '%s\n' "$pln_shapes" | grep -c . || true)
    n_keys=$(printf '%s\n' "$KEYS" | grep -c . || true)
    if [ "$n_sot" -eq 0 ] || [ "$n_pln" -eq 0 ]; then
      echo "❌ arg-shape table did not parse (CLAUDE.md rows=$n_sot, planner.md rows=$n_pln) — the table format changed; argument-shape drift is UNCHECKED"; fail=$((fail+1))
    else
      [ -n "$KEYS" ] && [ "$n_sot" -ne "$n_keys" ] && {
        echo "⚠️  arg-shape table in templates/CLAUDE.md has $n_sot rows but the vocabulary has $n_keys keys — a key is pinned nowhere (or the table gained a row)"; warn=$((warn+1)); }
      while IFS="$(printf '\t')" read -r k sot_shape; do
        [ -n "$k" ] || continue
        pln_shape=$(printf '%s\n' "$pln_shapes" | awk -F'\t' -v k="$k" '$1==k{print $2; exit}')
        if [ -z "$pln_shape" ]; then
          echo "❌ arg-shape row for '$k' is in templates/CLAUDE.md but MISSING from agents/planner.md — the planner emits a shape it has no pin for"; fail=$((fail+1))
        elif [ "$pln_shape" != "$sot_shape" ]; then
          echo "❌ arg-shape drift for '$k': CLAUDE.md pins \`$sot_shape\` but agents/planner.md pins \`$pln_shape\` — a wrong-named arg drops the assertion silently"; fail=$((fail+1))
        fi
      done < <(printf '%s\n' "$sot_shapes")
      while IFS="$(printf '\t')" read -r k _; do
        [ -n "$k" ] || continue
        printf '%s\n' "$sot_shapes" | awk -F'\t' -v k="$k" '$1==k{f=1} END{exit !f}' || {
          echo "❌ arg-shape row for '$k' is in agents/planner.md but MISSING from templates/CLAUDE.md — the planner pins a shape the stamped SoT does not"; fail=$((fail+1)); }
      done < <(printf '%s\n' "$pln_shapes")
    fi
  fi
  # 9bb (cont). `invariant_holds_when:` SHAPE. Same drift class as the table above but invisible to
  #      its extractor — this key lives in the YAML schema block, not the arg-shape table. It shipped
  #      with TWO incompatible shapes: planner.md emitted a list of {invariant, holds_when} pairs
  #      while templates/CLAUDE.md showed a bare scalar. The reviewer reads shapes from the STAMPED
  #      CLAUDE.md, so it validated a scalar the planner never emits (Check 2e). Canonical = the LIST
  #      form. Assert both mirrors declare the key and neither declares it inline (anything but a
  #      comment after the colon is the scalar form).
  for f in "$sot_tbl" "$pln_tbl"; do
    [ -f "$f" ] || continue
    if ! grep -qE '^[[:space:]]*invariant_holds_when:' "$f"; then
      echo "❌ $(basename "$f"): no invariant_holds_when: declaration — the equality-domain shape is UNPINNED in this mirror (reviewer Check 2e reads it from the stamped CLAUDE.md)"; fail=$((fail+1)); continue
    fi
    if grep -qE '^[[:space:]]*invariant_holds_when:[[:space:]]*[^[:space:]#]' "$f"; then
      echo "❌ $(basename "$f"): invariant_holds_when: is pinned as a SCALAR — canonical shape is a LIST of {invariant, holds_when} pairs; a scalar cannot say which equality it scopes, and the two mirrors disagreeing is what made reviewer Check 2e validate a shape the planner never emits"; fail=$((fail+1))
    elif ! awk '/^[[:space:]]*invariant_holds_when:/{f=1;next} f{ if ($0 ~ /^[[:space:]]*(#|$)/) next; exit ($0 ~ /^[[:space:]]*-[[:space:]]*invariant:/) ? 0 : 1 } END{ if(!f) exit 1 }' "$f"; then
      echo "❌ $(basename "$f"): invariant_holds_when: is not followed by a '- invariant:' list item — the block shape did not parse; equality-domain drift is UNCHECKED"; fail=$((fail+1))
    fi
  done
fi

# 9bc. Turn-budget ORDERING — the frontmatter `maxTurns` ceiling MUST stay strictly above the
#      agent's own prose turn budget. The two are NOT interchangeable: the prose budget ends in a
#      BEHAVIOR (healer files a bug and reverts the patch; reviewer emits PARTIAL REVIEW + FAIL;
#      exploration/ideation write an incompleteness banner), whereas maxTurns is a harness
#      hard-stop that returns PARTIAL output and runs NO fallback at all. Pinned AT or BELOW the
#      prose number, the ceiling PREEMPTS the fail-safe — trading "file a bug and revert" for a
#      half-applied patch and no bug, which is the silent-failure class this toolkit exists to
#      prevent. Nothing else compares these two numbers: they live in different files' different
#      halves (YAML frontmatter vs §"Budget / escalation" prose), so a bump to either silently
#      inverts the ordering with every other check green. reference/DESIGN.md §"Turn budgets are
#      a fail-safe" carries the why.
#      NOTE both prose spellings are matched — `**Turn budget: N` and healer's `**Hard budget: N
#      turns` — and the FIRST match wins (reviewer's §Inputs prose says "the 15-turn budget" in
#      passing, which must not be mistaken for the declaration).
#      CAVEAT — this check verifies the ORDERING of two numbers; it does NOT verify that
#      `maxTurns` itself actually fires. anthropics/claude-code#41143 reports maxTurns going
#      unenforced (an agent pinned at 10 ran 70+ turns unimpeded), open and closed-not-planned
#      as of this writing. If that holds on the CLI version this toolkit's users run, the harness
#      ceiling is best-effort, NOT a guaranteed backstop — the agent's own prose-budget
#      self-policing is the load-bearing fail-safe in practice, not maxTurns. Re-verify empirically
#      (drive an agent past its stated budget and confirm partial-output/stop) before treating a
#      passing 9bc as proof the runaway case is actually caught.
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  agents_dir="$TMPL/../agents"
  if [ ! -d "$agents_dir" ]; then
    echo "⚠️  plugin agents/ not found at $agents_dir — turn-budget ordering is UNVERIFIED (run /qa:init --resync)"; warn=$((warn+1))
  else
    tb_seen=0
    for af in "$agents_dir"/*.md; do
      [ -f "$af" ] || continue
      aname=$(basename "$af" .md)
      # Frontmatter ceiling: first `maxTurns:` at column 0 (comment lines start with #).
      ceil=$(sed -nE 's/^maxTurns:[[:space:]]*([0-9]+).*/\1/p' "$af" | head -1)
      # Prose budget: first **Turn budget: N or **Hard budget: N.
      prose=$(sed -nE 's/.*\*\*(Turn|Hard) budget:[[:space:]]*([0-9]+).*/\2/p' "$af" | head -1)
      if [ -z "$prose" ]; then
        echo "❌ $aname: no prose turn budget found (expected '**Turn budget: N' or '**Hard budget: N turns') — the ordering invariant is UNCHECKED for this agent, not satisfied"; fail=$((fail+1)); continue
      fi
      if [ -z "$ceil" ]; then
        echo "❌ $aname: prose budget is $prose but NO maxTurns ceiling is pinned — a runaway is unbounded"; fail=$((fail+1)); continue
      fi
      tb_seen=$((tb_seen+1))
      if [ "$ceil" -le "$prose" ]; then
        echo "❌ $aname: maxTurns=$ceil is NOT above the prose budget of $prose — the harness hard-stop PREEMPTS the agent's fallback (no bug filed, no verdict emitted, PARTIAL output)"; fail=$((fail+1))
      elif [ "$((ceil - prose))" -lt 3 ]; then
        echo "⚠️  $aname: maxTurns=$ceil leaves only $((ceil - prose)) turn(s) above the prose budget of $prose — the fallback (write/return/revert) may not fit before the hard-stop"; warn=$((warn+1))
      fi
    done
    # Cardinality self-check: this checker is only as good as the set it walked. A layout move
    # that leaves agents/ present but empty (or renames the files) would otherwise report green
    # having compared nothing — the oracle-keys.txt doctrine applied to a directory walk.
    n_agents=$(find "$agents_dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n_agents" -eq 0 ]; then
      echo "❌ plugin agents/ contains no .md files — turn-budget ordering is UNCHECKED"; fail=$((fail+1))
    elif [ "$tb_seen" -ne "$n_agents" ]; then
      echo "⚠️  turn-budget ordering verified for $tb_seen of $n_agents agent file(s) — the rest were reported above"; warn=$((warn+1))
    fi
  fi
fi

# 9bd. Prod-guard RAIL coverage. Eight skills carry a prod-guard rail in prose, and on the
#      CLI-driving paths (gen/new-spec/intake/explore/review) that prose is the ONLY prod rail —
#      the enforced scripts/prod-guard.ts globalSetup fires only under `npx playwright test`,
#      which `playwright-cli goto` never invokes. The rails are ACTIVE TRIM CANDIDATES, and the
#      plausible regression is not a reworded lead but a dropped STOP clause: flake-check was
#      already shipped once running the guard and ignoring its exit code (a repeat-each run
#      MULTIPLIES the blast radius), and nothing detected it.
#      Compares INVOCATION + STOP-on-non-zero, never the wording. The eight sites deliberately
#      carry TWO lead forms and materially different bodies, so a whole-text compare would fire
#      on every edit and get this check disabled — the same property that keeps 9bb alive.
#      The skill list is READ from scripts/prod-guard-rails.txt, not hand-typed here.
#      rail_window_ok tests EACH invocation's own +1 window independently and returns success
#      if ANY one has the STOP clause — a file with 2+ invocations (explore/SKILL.md has one at
#      the real rail and one at a --list-targets call) must not let a distant window's "non-zero"
#      wording satisfy a DIFFERENT invocation whose own clause was stripped. Concatenating all
#      windows into one grep (the prior approach) re-admitted the cross-site false-green class
#      9bd was built to close, just narrowed from file-wide to per-invocation-file.
#      The two tokens are matched as a WORD-ORDER-INDEPENDENT pair (both `stop` and `non-zero`
#      present in the same window), not an ordered alternation: the prior
#      `STOP.*non-zero|non-zero.*exit` had two defects — its second branch required no STOP token
#      at all (a pure description like "prod-guard.sh returns non-zero on exit" would pass with the
#      STOP clause fully deleted), and a correctly-worded rail with "non-zero" appearing before
#      "STOP" matched neither branch (false FAIL). Requiring both tokens present, order-independent,
#      closes both without reverting to a whole-window substring match that ignores order entirely.
#      ALL-semantics, not ANY: a prior version returned success if ANY ONE invocation's window
#      carried the clause, which meant a skill that keeps its one guarded rail AND gains a NEW
#      live-driving `bash scripts/prod-guard.sh` call with no exit-code handling still reported
#      green — the flake-check regression class surviving at per-invocation granularity. Every
#      invocation must now carry the clause in its own window, with one deliberate exception:
#      `--list-targets` is a read-only enumeration mode (no target is actually driven), so it is
#      not required to gate. A file with only `--list-targets` invocations and no gating one at all
#      now FAILS here rather than passing: those lines are skipped before `hits` is counted, so such
#      a file reaches the `hits -gt 0` test with zero hits and returns false. That closes what was
#      previously a documented narrow gap (it used to pass, since the (1) existence check only tests
#      for A `bash scripts/prod-guard.sh` invocation, not a gating one). The message a maintainer
#      hits in that case reads "runs the guard but never acts on its exit code" — accurate in effect,
#      since nothing is gated, though the file's only call is the read-only enumeration mode.
rail_window_ok() {
  # `hits` distinguishes "has a valid rail" from "has NO rail at all" — without it the while
  # loop simply never runs on a rail-less file and `ok=1` returns TRUE, so every skill that
  # never mentions prod-guard reported as "carries a rail but is not in the manifest" (16
  # spurious WARNs per run, which buries the real FAILs this check exists to surface).
  local f="$1" ln line ok=1 hits=0
  while IFS=: read -r ln line; do
    [ -n "$ln" ] || continue
    case "$line" in *--list-targets*) continue ;; esac
    hits=$((hits+1))
    win=$(sed -n "${ln},$((ln+1))p" "$f" | tr '\n' ' ')
    if printf '%s' "$win" | grep -qi 'stop' && printf '%s' "$win" | grep -q 'non-zero'; then
      :
    else
      ok=0
    fi
  done < <(grep -n 'bash scripts/prod-guard\.sh' "$f")
  [ "$hits" -gt 0 ] && [ "$ok" -eq 1 ]
}
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  RAILS=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$TMPL/scripts/prod-guard-rails.txt" 2>/dev/null | grep -v '^$')
  skills_dir="$TMPL/../skills"
  if [ -z "$RAILS" ]; then
    echo "❌ scripts/prod-guard-rails.txt missing or empty — prod-guard rail coverage is UNVERIFIED (run /qa:init --resync)"; fail=$((fail+1))
  elif [ ! -d "$skills_dir" ]; then
    echo "⚠️  plugin skills/ not found at $skills_dir — prod-guard rail coverage is UNVERIFIED (run /qa:init --resync)"; warn=$((warn+1))
  else
    rail_seen=0
    while read -r sk; do
      [ -n "$sk" ] || continue
      sf="$skills_dir/$sk/SKILL.md"
      if [ ! -f "$sf" ]; then
        echo "❌ prod-guard rail: skill '$sk' is listed in prod-guard-rails.txt but $sf does not exist — the manifest is stale or the skill was renamed; its rail is UNVERIFIED"; fail=$((fail+1)); continue
      fi
      rail_seen=$((rail_seen+1))
      # (1) the guard must actually be INVOKED, not merely referred to.
      if ! grep -q 'bash scripts/prod-guard\.sh' "$sf"; then
        echo "❌ prod-guard rail MISSING from skills/$sk — no 'bash scripts/prod-guard.sh' invocation. On the CLI-driving paths this prose is the only prod rail; do not delete it to satisfy a trim"; fail=$((fail+1)); continue
      fi
      # (2) a guard whose exit code is ignored is not a rail. This is the clause trims drop.
      #     SCOPED TO THE INVOCATION LINE (+1, for a wrapped clause — batch-fix/heal wrap
      #     "non-zero" onto the next line) — a file-WIDE grep silently passed the mutation
      #     test: flake-check:19 has an unrelated "STOP and ask the user to confirm" one line
      #     below the rail, so a whole-file scan reported green on a rail whose own STOP clause
      #     had been deleted. The alternation ALSO requires "non-zero" (not just "STOP"), so a
      #     future edit that merges bare "STOP and ask" decoy prose onto the invocation line
      #     still fails this — the STOP-clause language must actually name the exit-code
      #     condition, not just contain the word STOP.
      if ! rail_window_ok "$sf"; then
        echo "❌ prod-guard rail in skills/$sk runs the guard but never acts on its exit code — a passing-through rail is not a rail (this is the flake-check regression)"; fail=$((fail+1))
      fi
    done < <(printf '%s\n' "$RAILS")
    # Reverse direction: a skill that grew a rail but was never added to the manifest. WARN —
    # the rail is present (safe); what is missing is the guarantee it stays.
    # A skill "carries a rail" only when the invocation and the STOP-on-non-zero clause appear
    # TOGETHER, within the invocation line (+1, for a wrap). Matching a bare invocation anywhere
    # flagged skills/doctor, whose own remediation text QUOTES `bash scripts/prod-guard.sh` while
    # documenting this very check — prose that names the rail is not a rail.
    for sf in "$skills_dir"/*/SKILL.md; do
      [ -f "$sf" ] || continue
      rail_window_ok "$sf" || continue
      sk=$(basename "$(dirname "$sf")")
      printf '%s\n' "$RAILS" | grep -qx "$sk" || {
        echo "⚠️  skills/$sk carries a prod-guard rail but is NOT in scripts/prod-guard-rails.txt — add it so the rail is policed"; warn=$((warn+1)); }
    done
    # Cardinality self-check: a manifest that resolved to nothing must not read as green.
    n_rails=$(printf '%s\n' "$RAILS" | grep -c . || true)
    [ "$rail_seen" -ne "$n_rails" ] && {
      echo "⚠️  prod-guard rails verified for $rail_seen of $n_rails listed skill(s) — the rest were reported above"; warn=$((warn+1)); }
  fi
fi

# 9be. Oracle arg-shape drift in the REMAINING mirrors. Check 9bb compares the two markdown-table
#      mirrors (templates/CLAUDE.md <-> agents/planner.md) by BYTE-comparing the shape expression.
#      That works only because those two tables share a format. The other mirrors do not:
#        - agents/generator.md states shapes as INSTANTIATED examples (`{ locator: ..., n: 3 }`)
#        - DOCUMENTATION.md uses a numbered table with deliberately SHORTENED notes
#      so a byte-compare is impossible there and 9bb's extractor cannot read them at all.
#      What IS comparable across every format is the set of ARGUMENT NAMES — and that is exactly
#      the failure mode: `{ count }` where the canonical shape is `{ locator, n }` makes the
#      generator (which reads `.n`) silently DROP the assertion. So this check normalises each
#      shape to a sorted arg-name list (`locator,n`) and compares those. A scalar shape
#      ("<string>", <bool>) normalises to `-`.
#      QUIET BY CONSTRUCTION: `{ cookies?, localStorage? }` and
#      `{ cookies?: [...], localStorage?: { key: value } }` both normalise to `cookies,localStorage`,
#      so the two files can keep their different note lengths without ever firing this.
#      generator.md pins shapes for only 13 of 16 keys — attribute_equals / element_state /
#      network_response_status are grouped at "straightforward one-line expect mappings" with no
#      shape claim — so ABSENCE there is legitimate and silent; only a PINNED shape is compared.
#      DOCUMENTATION.md lives OUTSIDE the plugin dir and is unreachable from a scaffolded project,
#      so its absence is a WARN, never a FAIL.
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  # arg_names normaliser, shared by every mirror below. Reads "key<TAB>shape" and prints
  # "key<TAB>sorted,arg,names". Brackets/braces/quoted alternations are masked first so a
  # nested [min, max] or 'confirm'|'alert' cannot be mistaken for an argument separator.
  norm_prog='function arg_names(s,   t,i,n,parts,out,arr,k,p,res,v,j) {
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s !~ /^\{/) return "-"
    t = s; sub(/^\{/, "", t); sub(/\}[ \t]*$/, "", t)
    while (match(t, /\[[^]]*\]/)) t = substr(t,1,RSTART-1) "X" substr(t,RSTART+RLENGTH)
    while (match(t, /\{[^{}]*\}/)) t = substr(t,1,RSTART-1) "X" substr(t,RSTART+RLENGTH)
    while (match(t, /'"'"'[^'"'"']*'"'"'/)) t = substr(t,1,RSTART-1) "X" substr(t,RSTART+RLENGTH)
    n = split(t, parts, ",")
    for (i=1;i<=n;i++) { p=parts[i]; sub(/:.*$/,"",p); gsub(/[ \t?}]/,"",p); gsub(/\|.*$/,"",p); if(p!="") out[p]=1 }
    k=0; for (p in out) arr[++k]=p
    for (i=2;i<=k;i++){ v=arr[i]; j=i-1; while(j>0 && arr[j]>v){arr[j+1]=arr[j];j--} arr[j+1]=v }
    res=""; for (i=1;i<=k;i++) res = res (i>1?",":"") arr[i]
    return res==""?"-":res
  }
  BEGIN{FS="\t"} { print $1 "\t" arg_names($2) }'
  sot_md="$TMPL/CLAUDE.md"
  if [ ! -f "$sot_md" ]; then
    echo "⚠️  $sot_md not found — remaining-mirror arg-shape drift is UNVERIFIED (run /qa:init --resync)"; warn=$((warn+1))
  else
    sot_norm=$(sed -nE 's/^\| `([a-z0-9_]+)` \| `([^`]*)`.*/\1\t\2/p' "$sot_md" | awk "$norm_prog" | sort)
    if [ -z "$sot_norm" ]; then
      echo "❌ the arg-shape SoT table in templates/CLAUDE.md did not parse — remaining-mirror drift is UNCHECKED"; fail=$((fail+1))
    else
      # mirror <label> <file> <sed-extractor> <mode: full|partial> [min-rows]
      # min-rows is a cardinality FLOOR for a `partial` mirror — a `full` mirror already gets
      # per-key cardinality below; a `partial` one only compares whichever keys it happens to
      # pin, so if its own bullet format silently breaks for JUST ONE key (rather than all),
      # that key drops out of $mnorm and absence there reads as legitimate, unchecked partial
      # coverage — the same class of bug 9bb's charclass miss was (13/16 checked, reporting
      # green). min-rows makes a below-floor row count a FAIL instead of silent.
      check_mirror() {
        ml="$1"; mf="$2"; mx="$3"; mmode="$4"; mmin="${5:-0}"
        if [ ! -f "$mf" ]; then
          echo "⚠️  arg-shape mirror '$ml' not found at $mf — its drift is UNVERIFIED"; warn=$((warn+1)); return
        fi
        mnorm=$(sed -nE "$mx" "$mf" | awk "$norm_prog" | sort -u)
        if [ -z "$mnorm" ]; then
          echo "❌ arg-shape mirror '$ml' produced no rows — its format changed and drift is UNCHECKED, not absent"; fail=$((fail+1)); return
        fi
        mmatched=0
        while IFS="$(printf '\t')" read -r k shape; do
          [ -n "$k" ] || continue
          # Only compare keys that are in the closed vocabulary — the extractors also match
          # non-oracle bullets (e.g. `must_fail_when`), which are not shape claims.
          printf '%s\n' "$KEYS" | grep -qx "$k" || continue
          mmatched=$((mmatched+1))
          sot_shape=$(printf '%s\n' "$sot_norm" | awk -F'\t' -v k="$k" '$1==k{print $2; exit}')
          if [ -z "$sot_shape" ]; then
            echo "❌ arg-shape mirror '$ml' pins key '$k' which is ABSENT from the templates/CLAUDE.md SoT table"; fail=$((fail+1))
          elif [ "$shape" != "$sot_shape" ]; then
            echo "❌ arg-shape drift for '$k' in $ml: SoT args are [$sot_shape] but this mirror pins [$shape] — a wrong-named arg drops the assertion silently"; fail=$((fail+1))
          fi
        done < <(printf '%s\n' "$mnorm")
        # A `full` mirror claims to pin every key; a `partial` one legitimately pins a subset.
        if [ "$mmode" = "full" ]; then
          while IFS="$(printf '\t')" read -r k _; do
            [ -n "$k" ] || continue
            printf '%s\n' "$mnorm" | awk -F'\t' -v k="$k" '$1==k{f=1} END{exit !f}' || {
              echo "❌ arg-shape mirror '$ml' is MISSING key '$k' — it documents the vocabulary as complete"; fail=$((fail+1)); }
          done < <(printf '%s\n' "$sot_norm")
        elif [ "$mmin" -gt 0 ] && [ "$mmatched" -lt "$mmin" ]; then
          echo "❌ arg-shape mirror '$ml' pins only $mmatched oracle keys, below its expected floor of $mmin — a key may have silently dropped out of its bullet format rather than being a deliberate omission"; fail=$((fail+1))
        fi
      }
      check_mirror "agents/generator.md" "$TMPL/../agents/generator.md" \
        's/^- `([a-z0-9_]+): ([^`]*)`.*/\1\t\2/p' partial 13
      check_mirror "DOCUMENTATION.md" "$TMPL/../../DOCUMENTATION.md" \
        's/^\| *[0-9]+ *\| `([a-z0-9_]+)` \| `([^`]*)`.*/\1\t\2/p' full
    fi
  fi
fi

# 9c. RETIRED permission rules still present in .claude/settings.json — the settings-side
#     complement to Check 9. settings.json is EXCLUDED from Check 9's byte-compare and from
#     qa-scaffold's --resync (shared ownership: users add their own rules), AND the scaffold's
#     jq merge is an additive UNION — it can only ADD rules, never remove one. So a rule the
#     toolkit RETRACTS is stranded in every already-scaffolded project forever, with no
#     mechanism to notice. That is not hypothetical: `Bash(sed *e)` / `Bash(sed *e *)` /
#     `Bash(sed *e;*)` were shipped to block GNU sed's execute forms, but Bash rules are
#     full-string globs where `*` spans spaces (code.claude.com/docs/en/permissions), so
#     `sed *e *` matched ANY sed whose script contains an `e` followed by a space — hard-denying
#     the ordinary `-e` flag and everyday substitutions like `sed 's/the /a /'` — while the
#     actual execute form `sed 's/.*/id/e'` (an `e` before the closing quote) matched NONE of
#     them. Over-blocking AND under-blocking at once; deny beats allow and cannot be
#     interactively approved, so the agent had no recourse. They are replaced by the precise
#     `Bash(sed *e'*)` / `Bash(sed *e"*)` pair.
#     A retraction is not always a DENY rule: an over-broad ALLOW strands identically. So the
#     remedy text is selected PER RULE below instead of being hardcoded to the sed story — the
#     first non-sed entry would otherwise have been reported with a sed fix. Flag any retired
#     rule still present.
if [ -f .claude/settings.json ]; then
  while IFS= read -r retired; do
    [ -z "$retired" ] && continue
    grep -qF "\"$retired\"" .claude/settings.json 2>/dev/null || continue
    case "$retired" in
      "Bash(sed "*) why="It over-blocks ordinary sed (the deny cannot be interactively approved); the replacements are \"Bash(sed *e'*)\" and \"Bash(sed *e\\\"*)\"." ;;
      "Bash(printenv)") why="It auto-approves a BARE printenv — a full dump of every .env secret loaded into that shell (QA_ADMIN_PASSWORD, QA_TOTP_SECRET, QA_CLIENT_CERT_PASSPHRASE) into the transcript — and nothing ever consumed it: the mandated form is the SCOPED \"printenv \$base_url_env\" (agents/exploration.md), still covered by \"Bash(printenv *)\"." ;;
      *) why="It was retracted from the shipped template." ;;
    esac
    echo "⚠️  retired permission rule still in .claude/settings.json: \"$retired\" — the scaffold's jq merge is additive (union) and never removes a rule, so this must be deleted BY HAND. $why"
    warn=$((warn+1))
  done <<'RETIRED'
Bash(sed *e)
Bash(sed *e *)
Bash(sed *e;*)
Bash(printenv)
RETIRED
fi

# 9d. Plugin layout regression — a `commands/` directory has reappeared in the plugin.
#     Custom commands were MERGED INTO SKILLS upstream (code.claude.com/docs/en/skills): a
#     `commands/x.md` and a `skills/x/SKILL.md` both produce `/qa:x`, so the two layouts coexist
#     silently and nothing upstream complains. This toolkit migrated wholesale to `skills/` so it
#     can use `context: fork` (keeps a heavy read-only pass out of the caller's context),
#     `allowed-tools` (exact-match Bash pre-approval via ${CLAUDE_SKILL_DIR}), and bundled
#     `scripts/`+`reference/` — none of which exist on the command side. The failure mode this
#     check exists for is a SPLIT surface: someone adds the next `/qa:*` in the old shape, both
#     layouts live on, and the fork/allowed-tools guarantees quietly stop being universal.
#     Same-name collisions are worse still (two definitions of one command name, resolution
#     order unstated here). Requires $TMPL (the plugin-side checks) to have resolved.
if [ -n "$TMPL" ] && [ -d "$TMPL/../commands" ]; then
  ncmd=$(find "$TMPL/../commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${ncmd:-0}" -eq 0 ]; then
    # An EMPTY commands/ defines no command, so it cannot split the surface — warn, don't red a
    # user's CI over a stray directory they did not create and cannot fix (this is plugin-authoring
    # state, not project state).
    echo "⚠️  plugin has an empty commands/ directory — harmless today, but it is where the old layout
   creeps back in. Delete it; every /qa:* lives at skills/<name>/SKILL.md."
    warn=$((warn+1))
  else
  echo "❌ plugin has a commands/ directory again (${ncmd} .md) — every /qa:* must live at skills/<name>/SKILL.md. Move each file to skills/<name>/SKILL.md and delete commands/ (a command and a skill of the same name both define /qa:<name>, so a split surface is invisible until behavior diverges)."
  fail=$((fail+1))
  for c in "$TMPL/../commands"/*.md; do
    [ -f "$c" ] || continue
    cn=$(basename "$c" .md)
    [ -f "$TMPL/../skills/$cn/SKILL.md" ] && { echo "   ↳ NAME COLLISION: commands/$cn.md AND skills/$cn/SKILL.md both define /qa:$cn"; }
  done
  fi
fi

# 9e. /qa:help catalog vs the actual skill set. The help skill's catalog lives in
#     reference/knowledge-map.md (split out because SKILL.md exceeded the ~5k-token ceiling past
#     which only the first 5k is re-attached after a compaction). A hand-kept catalog in a
#     SEPARATE file is exactly the drift shape this toolkit single-sources away — but generating
#     it from frontmatter was rejected (the rows carry a "Delegates to" column, workflow order,
#     and per-command detail that `description:` does not hold). So police the row SET instead of
#     generating it: every user-invocable skill must have a catalog row, and every row must name a
#     real skill. That catches the only failure that matters — a skill added or retired without a
#     catalog row, leaving /qa:help to answer from a stale map or invent a command that never existed.
if [ -n "$TMPL" ] && [ -f "$TMPL/../reference/knowledge-map.md" ]; then
  # Two catalog row shapes, both legitimate: the slash-command table uses `| \`/qa:<name>\` |`
  # — sometimes WITH an argument (`| \`/qa:run mode=smoke\` |`), so the name match must NOT
  # anchor on a closing backtick or every argumented command reads as an uncatalogued skill.
  # The capability-skill table uses `| **<name>** |`. The two shapes are NOT interchangeable:
  # the bare shape is what a `user-invocable: false` capability skill gets (it has no command to
  # print), and the slash shape is what a real command needs. See the `missing` arm below.
  kmslashrows=$(grep -oE '^\| `/qa:[a-z0-9-]+' "$TMPL/../reference/knowledge-map.md" 2>/dev/null | sed 's/.*\/qa://; s/`//' | sort -u)
  # A skill is user-invocable unless it says otherwise; only those need a catalog row.
  kmskills=""
  for d in "$TMPL"/../skills/*/; do
    sn=$(basename "$d")
    grep -qE '^user-invocable:[[:space:]]*(false|no|off|0)[[:space:]]*$' "$d/SKILL.md" 2>/dev/null && continue
    kmskills="$kmskills$sn
"
  done
  kmskills=$(printf '%s' "$kmskills" | sort -u)
  # A USER-INVOCABLE skill needs the SLASH row specifically, not just any row. Accepting either
  # shape here (the original behaviour) let a real command hide behind a bare `| **name** |` row in
  # the capability-skills table and read as catalogued — which is exactly how
  # `metamorphic-relations` sat uncatalogued as a command while this check stayed green. The
  # either-shape leniency exists for CAPABILITY skills (user-invocable: false), and those are
  # already excluded from $kmskills above, so it buys nothing here. What /qa:help owes a user is
  # the invocation; a row that never shows `/qa:<name>` cannot supply it.
  missing=$(comm -23 <(printf '%s\n' "$kmskills") <(printf '%s\n' "$kmslashrows") | grep . || true)
  # The PHANTOM arm must use only the SLASH-form rows and compare against ALL skill dirs (not just
  # the user-invocable ones): the bare `| **name** |` shape is shared with the AGENTS table, and a
  # non-invocable capability skill legitimately has a row while being absent from $kmskills — both
  # would false-FAIL as "phantom" under the union set.
  kmslash=$(grep -oE '^\| `/qa:[a-z0-9-]+' "$TMPL/../reference/knowledge-map.md" 2>/dev/null | sed 's/.*\/qa://; s/`//' | sort -u)
  allskills=$(for d in "$TMPL"/../skills/*/; do basename "$d"; done | sort -u)
  phantom=$(comm -13 <(printf '%s\n' "$allskills") <(printf '%s\n' "$kmslash") | grep . || true)
  # KNOWN GAP (both arms): skills and agents share this one namespace. A SKILL whose name equals
  # an AGENT's is treated as catalogued by the agents-table row (the `missing` arm unions both row
  # shapes), and symmetrically a retired capability skill named after an agent keeps a live-looking
  # row here. Neither is reachable with today's names; documented so a future rename is not assumed
  # to be free.
  # Bare-form phantom arm. The slash arm above is blind to CAPABILITY skills (user-invocable:
  # false): they have no `/qa:` row, so retiring one leaves its `| **name** |` row behind with
  # doctor staying green over a catalog entry that points at nothing. Diff the bare rows too —
  # but subtract the agent names first, since the AGENTS table shares this exact row shape and
  # would otherwise false-FAIL as phantom (the reason the slash arm was narrowed in the first
  # place). Skills and agents share a namespace here only by convention; a name in neither set
  # is a genuinely dangling row.
  kmbare=$(grep -oE '^\| \*\*[a-z0-9-]+\*\*' "$TMPL/../reference/knowledge-map.md" 2>/dev/null | sed 's/^| \*\*//; s/\*\*$//' | sort -u)
  kmagents=$(for a in "$TMPL"/../agents/*.md; do [ -f "$a" ] && basename "$a" .md; done | sort -u)
  kmknown=$(printf '%s\n%s\n' "$allskills" "$kmagents" | sort -u | grep . || true)
  barephantom=$(comm -13 <(printf '%s\n' "$kmknown") <(printf '%s\n' "$kmbare") | grep . || true)
  [ -n "$missing" ] && { echo "⚠️  /qa:help catalog is missing a row for: $(echo "$missing" | tr '\n' ' ')— reference/knowledge-map.md must list every user-invocable skill, or /qa:help answers from a stale map"; warn=$((warn+1)); }
  [ -n "$barephantom" ] && { echo "⚠️  /qa:help catalog lists a capability skill that does not exist: $(echo "$barephantom" | tr '\n' ' ')— reference/knowledge-map.md names a skill/agent with no directory or agent file (retired without removing its row)"; warn=$((warn+1)); }
  [ -n "$phantom" ] && { echo "⚠️  /qa:help catalog lists a command with no skill: $(echo "$phantom" | tr '\n' ' ')— reference/knowledge-map.md names a /qa:* that does not exist (retired without removing its row)"; warn=$((warn+1)); }
fi

# 9f. Healer MCP tool-grant ↔ settings.json permission mirror. `agents/healer.md`'s `tools:`
#     line and `templates/settings.json`'s `mcp__playwright__*` allow entries are a 17-entry
#     list hand-typed TWICE, in two different syntaxes, in two different files — the same
#     unchecked-hand-mirrored-pair shape Checks 9b/9bb/9bc/8 exist for, and the last pair in the
#     substrate with nothing behind it. It has already been edited by hand once (15 -> 17 when
#     the healer was granted browser_evaluate + browser_close) and the mirror was kept in sync
#     only because someone remembered.
#     Why each direction is a FAIL, not cosmetic drift:
#       - in healer.md, NOT in the allow-list -> the healer's declared tool prompts at call
#         time. The healer runs as a SUBAGENT: there is nobody to answer the prompt, so a tool
#         its own prose mandates (HEAL01 re-probes with browser_evaluate before believing an
#         empty reading) is simply unavailable, and it burns turns against a 14-turn budget
#         discovering that.
#       - in the allow-list, NOT in healer.md -> a standing pre-approval for a tool no agent
#         declares. Harmless today, but it is how the two sides drift apart unnoticed, and an
#         agent with an explicit `tools:` list cannot call it anyway.
#     Arm 2 is the settings-side complement Check 9c does NOT cover: 9c catches a rule the
#     toolkit RETRACTED that is stranded downstream; nothing caught a rule the toolkit ADDED
#     that never reached an already-scaffolded project. Deliberately scoped to the mcp__ entries
#     and not the whole allow[]: those are agent-capability grants with exactly one right
#     answer, whereas a user legitimately deletes a POLICY rule they disagree with (that has
#     happened) and a full-list subset check would nag them forever.
if [ -n "$TMPL" ] && [ -f "$TMPL/settings.json" ] && [ -f "$TMPL/../agents/healer.md" ] && command -v jq >/dev/null 2>&1; then
  # `tools:` is a comma-separated frontmatter scalar; settings.json is a JSON array. Normalize
  # both to a sorted line set so the comparison is of SETS, not of formatting or order.
  h_mcp=$(grep -m1 '^tools:' "$TMPL/../agents/healer.md" | tr ',' '\n' | grep -oE 'mcp__[a-z0-9_]+' | sort -u)
  s_mcp=$(jq -r '.permissions.allow[]? | select(startswith("mcp__"))' "$TMPL/settings.json" 2>/dev/null | sort -u)
  if [ -z "$h_mcp" ] || [ -z "$s_mcp" ]; then
    echo "⚠️  healer/settings MCP mirror UNVERIFIED — could not extract one of the two lists (healer.md tools: line, or settings.json permissions.allow[])"; warn=$((warn+1))
  else
    only_h=$(comm -23 <(printf '%s\n' "$h_mcp") <(printf '%s\n' "$s_mcp") | grep . || true)
    only_s=$(comm -13 <(printf '%s\n' "$h_mcp") <(printf '%s\n' "$s_mcp") | grep . || true)
    [ -n "$only_h" ] && {
      echo "❌ MCP mirror drift — declared in agents/healer.md 'tools:' but NOT allowed in templates/settings.json: $(printf '%s\n' "$only_h" | tr '\n' ' ')— the healer runs as a subagent, so this tool PROMPTS with nobody to answer and is effectively unavailable mid-heal. Add it to permissions.allow[]."; fail=$((fail+1)); }
    [ -n "$only_s" ] && {
      echo "❌ MCP mirror drift — allowed in templates/settings.json but NOT declared in agents/healer.md 'tools:': $(printf '%s\n' "$only_s" | tr '\n' ' ')— a standing pre-approval no agent can use (an explicit tools: list is a restriction). Add it to the healer or drop the rule."; fail=$((fail+1)); }
  fi
  # Arm 2 — did the shipped grants actually REACH this project? The scaffold's jq merge is an
  # additive union, so the repair is a plain re-run of /qa:init (no hand edit, unlike 9c).
  if [ -f .claude/settings.json ]; then
    p_mcp=$(jq -r '.permissions.allow[]? | select(startswith("mcp__"))' .claude/settings.json 2>/dev/null | sort -u)
    unstamped=$(comm -23 <(printf '%s\n' "$s_mcp") <(printf '%s\n' "$p_mcp") | grep . || true)
    [ -n "$unstamped" ] && {
      echo "⚠️  .claude/settings.json is missing MCP grants the plugin now ships: $(printf '%s\n' "$unstamped" | tr '\n' ' ')— this project was scaffolded before they were added. Re-run /qa:init (the permission merge is additive and runs on every init, so this needs no hand edit)."; warn=$((warn+1)); }
  fi
fi

# 10. Site-id ↔ config-project routing (F-51: a site declared in app.context.md with no matching
#     playwright.config project — specs target a phantom site and silently run zero tests; renumbered
#     from the old "F-15" tag, which collided with the last-run-staleness F15 in check 1 above — the
#     hyphen was the only disambiguator between two DIFFERENT findings) — the toolkit's OWN green-but-empty class, at the
#     config layer. The generator ALWAYS emits `@site:<id>`; playwright.config.ts routes only the
#     project names it declares. A hot-tier sites[].id with NO matching config project → its specs
#     match no project → run in ZERO project = silently green-but-empty (a whole site never tested,
#     every gate green). Template defaults (app/admin) match the config, so the happy path is safe —
#     but `/qa:explore` can pick a descriptive id (`shop`), and only the agent's honesty catches it.
#     Assert every sites[].id has a `name: '<id>'` project (setup is not a site).
CTXH=specs/_context/app.context.md
if [ -f "$CTXH" ] && [ -f playwright.config.ts ]; then
  for sid in $(grep -oE '^[[:space:]]*-[[:space:]]*id:[[:space:]]*[a-zA-Z0-9_-]+' "$CTXH" | grep -oE '[a-zA-Z0-9_-]+$'); do
    grep -qE "name:[[:space:]]*['\"]${sid}['\"]" playwright.config.ts \
      || { echo "❌ site '$sid' has no matching playwright.config.ts project — specs tagged @site:$sid run in NO project (silent green-but-empty); add the project or fix the site id"; fail=$((fail+1)); }
  done
fi

# 11. Bug-file lifecycle marker (F-20) — CLAUDE.md §Bug-report schema makes `Status` the mandatory
#     FIRST section: a bug file with no lifecycle marker reads as a LIVE production defect even after
#     the fix landed. The generator/healer author these inconsistently, so verify every bugs/*.md
#     carries a Status marker (a `## Status` heading or a leading `Status:` line).
# 11b. Durable-evidence reconciliation (HEAL03/HEAL04) — a filed bug OUTLIVES the run that found it,
#      but `artifacts/test-results/<id>/` (screenshot/trace) is WIPED the next time that test runs
#      green (preserveOutput overwrites the per-test outputDir). So an OPEN bug that cites its
#      evidence under `artifacts/test-results/…` points reviewers at links that go dead the moment
#      the defect is fixed — the exact orphaned-evidence trap seen in review. The healer is supposed
#      to copy evidence into a durable `bugs/<slug>/` folder and cite THAT; this is the backstop
#      when it didn't. Also flags the "open bug but its cited path is already gone" case (dead now).
if [ -d bugs ]; then
  while read -r bf; do
    # Presence = the canonical parser reads a value. scripts/bug-status.sh prints NOTHING when the
    # file carries no Status marker, so invoking it IS the presence check — do not re-type its
    # anchored regex here. That anchoring (`:` or end-of-line after the word, so a `## Status
    # History` section does not satisfy the check) was already copy-pasted five times before
    # bug-status.sh was extracted to end it; a hand-mirrored sixth copy in the file that POLICES
    # the others means a newly-accepted authored form makes doctor warn "missing Status marker"
    # on files the canonical parser then classifies fine.
    [ -n "$(bash scripts/bug-status.sh "$bf" 2>/dev/null)" ] \
      || { echo "⚠️  bug file missing Status marker: $bf (reads as a live defect — add '## Status: open|fixed|reverted')"; warn=$((warn+1)); }
    # lifecycle CLASS (canonical parser + canonical resolved-keyword set, both in
    # scripts/bug-status.sh): resolved bugs need no evidence reconciliation. Deliberately a SECOND
    # invocation rather than re-typing the `fixed*|reverted*|resolved*|closed*` alternation against
    # the value above — that alternation is exactly what --class exists to single-source (M-4), and
    # bugs/ holds a handful of small files, so the extra fork is not worth re-opening that gap.
    [ "$(bash scripts/bug-status.sh --class "$bf" 2>/dev/null)" = resolved ] && continue
    # this bug reads as a LIVE red — reconcile its evidence durability
    while read -r ev; do
      [ -z "$ev" ] && continue
      if [ ! -e "$ev" ]; then
        echo "⚠️  dead evidence in $bf: cites '$ev' which does not exist (wiped by a later green run) — copy the trace/screenshot into bugs/$(basename "${bf%.md}")/ and cite that (HEAL03), or resolve the bug (HEAL04)"; warn=$((warn+1))
      else
        echo "⚠️  volatile evidence in $bf: '$ev' lives under artifacts/test-results/ — it is overwritten the next time the test runs green; copy it into a durable bugs/$(basename "${bf%.md}")/ folder and cite that (HEAL03)"; warn=$((warn+1))
      fi
    done < <(grep -oE 'artifacts/test-results/[^ )`"'"'"']+\.(png|zip|md)' "$bf" 2>/dev/null | sort -u)
  done < <(find bugs -maxdepth 1 -name '*.md' -type f 2>/dev/null)
fi

# 11c. Parked-marker <-> bug lifecycle cross-check (P-14) — a test.fail()/test.fixme() parks a scenario
#      against a KNOWN defect; the linked bugs/<slug>.md must still be Status: open. When the app is
#      fixed, the generator's default CONDITIONAL park (test.fail(<observed>===<buggy>, 'bugs/…'))
#      self-neutralizes SILENTLY — no "expected-but-passed" flip — so nothing forces the stale
#      marker/bug out of the tree. This cross-check is that force: a live parked marker pointing at a
#      fixed/reverted bug launders a resolved defect into the green roll-up. Mirrors reviewer Check 3's
#      PR-time FAIL (forward direction only — an OPEN bug without a marker is legitimate, not flagged).
if [ -d bugs ] && [ -d tests ]; then
  while IFS= read -r hit; do
    t=${hit%%:*}                                                   # tests/<…>.spec.ts (paths carry no ':')
    bug=$(printf '%s\n' "$hit" | grep -oE 'bugs/[A-Za-z0-9_./-]+\.md' | head -1)
    [ -n "$bug" ] || continue
    [ -f "$bug" ] || { echo "⚠️  parked marker in $t links $bug which does NOT exist — file the bug or remove the marker (reviewer Check 3 FAILs this)"; warn=$((warn+1)); continue; }
    # canonical parser AND canonical resolved-keyword set — scripts/bug-status.sh --class
    if [ "$(bash scripts/bug-status.sh --class "$bug" 2>/dev/null)" = resolved ]; then
      sv=$(bash scripts/bug-status.sh "$bug" 2>/dev/null)   # raw value, for the message only
      echo "⚠️  stale parked marker: $t parks against $bug but its Status is '${sv%% *}' — the defect is resolved; remove the test.fail/test.fixme marker (or reopen the bug). A live marker on a fixed bug launders it green (P-14)."; warn=$((warn+1))
    fi
  done < <(grep -rnE 'test\.(fail|fixme)' tests/ 2>/dev/null | grep 'bugs/')
fi

# 12. Manifest staleness (F-08) — /qa:impact trusts artifacts/route-manifests/<area>/<feature>.json
#     as its SOLE input; a spec edited AFTER its manifest was generated silently yields a stale
#     change→test map (the guards are all-or-nothing — zero manifests, or a compiled test with none
#     — never present-but-stale). WARN when a spec .md is newer than its manifest (regenerate via
#     /qa:gen). Mirrors the safe-fallback: impact is an optimization, never the gate.
if [ -d artifacts/route-manifests ]; then
  while read -r mf; do
    rel=${mf#artifacts/route-manifests/}; spec="specs/${rel%.json}.md"
    [ -f "$spec" ] || continue
    [ "$spec" -nt "$mf" ] && { echo "⚠️  stale manifest: $spec is newer than $mf — /qa:impact may miss its routes; re-run /qa:gen"; warn=$((warn+1)); }
  done < <(find artifacts/route-manifests -name '*.json' -type f 2>/dev/null)
fi

# 13. Declared-mutating features must isolate (wires the basis test_data: block). WARN — the
#     reviewer's code-level Check 13 remains the enforcing gate; this catches the
#     declared-then-ignored gap. Test resolution mirrors /qa:coverage dim 1 (LOCKSTEP): the
#     direct path tests/<feat>.spec.ts PLUS every fanned spec linking back via a top-level
#     `basis: <area>/<feature>` key, mapped spec→test by the Check-14 naming rule
#     (specs/<p>.md ↔ tests/<p>.spec.ts, twins add .metamorphic). A mutating feature that
#     resolves to ZERO test files is itself a WARN — never a silent skip.
while read -r basis; do
  grep -qE '^[[:space:]]*mutates_server_state:[[:space:]]*true' "$basis" || continue
  feat=$(bash scripts/spec-links.sh feature "$basis")   # canonical indent-tolerant extractor (F-31)
  [ -z "$feat" ] && continue
  bases="$feat"
  while read -r sp; do
    b="${sp#specs/}"; b="${b%.md}"
    [ "$b" = "$feat" ] && continue                 # self-link → already in the list
    bases="$bases $b"
    # Match against the hoisted $BASIS_LINKS index rather than re-walking specs/ once per mutating
    # feature, and let scripts/spec-links.sh own the anchor — Check 18 and /qa:coverage dims 1/5/6
    # need the identical trailing-comment tolerance, which has already needed one hand-applied
    # lockstep fix across those three sites.
  done < <(printf '%s\n' "$BASIS_LINKS" | bash scripts/spec-links.sh match "$feat")
  found=0
  for b in $bases; do
    for t in "tests/${b}.spec.ts" "tests/${b}.metamorphic.spec.ts"; do
      [ -f "$t" ] || continue
      found=$((found+1))
      grep -qE "parallelIndex|workerIndex|mode:[[:space:]]*[\"']serial[\"']|seeded[A-Z]" "$t" \
        || { echo "⚠️  $feat: basis declares mutates_server_state:true but $t shows no isolation marker (parallelIndex/serial/seed fixture) — un-isolated mutation is green at 1 worker, flaky at scale"; warn=$((warn+1)); }
    done
  done
  [ "$found" -eq 0 ] && { echo "⚠️  $feat: basis declares mutates_server_state:true but NO compiled test resolved (neither tests/${feat}.spec.ts nor any fanned spec via 'basis: ${feat}') — the mutating feature is never isolation-checked; compile it or fix the basis 'feature:' path"; warn=$((warn+1)); }
done < <(ctx_grep_l '^[[:space:]]*mutates_server_state:[[:space:]]*true')

# --- shared helper for Checks 15/15b ------------------------------------------------------
# (The tests/ and specs/ tree walks these checks consume — $TEST_FILES / $SPEC_FILES — are
#  hoisted to the top of the script, above Check 3.)
# Portable SHA-256 (T-05): prefer coreutils `sha256sum` (present on minimal Linux/CI/alpine),
# fall back to Perl-based `shasum -a 256` (macOS/BSD). Both print "<hash>  <file>", so `awk
# {print $1}` extracts the digest either way — and the digest value is identical regardless of
# tool. Assuming only `shasum` made every reviewed spec falsely WARN "changed since review" on a
# `sha256sum`-only image (empty hash ≠ recorded hash). Resolved ONCE here, not per file.
if command -v sha256sum >/dev/null 2>&1; then SHA_CMD=sha256sum; else SHA_CMD='shasum -a 256'; fi
sha256_of() { $SHA_CMD "$1" 2>/dev/null | awk '{print $1}'; }

# 14. Unmanaged tests — see Check 4+14 above; scripts/post-run-checks.sh owns that scan.

# 15. Review attestation — for each spec with a compiled test, a reports/review/<area>/<feature>.reviewed
#     marker must exist and its recorded hashes must match the CURRENT spec+test. Markers are
#     agent-writable convenience — the unforgeable layer is the CI required-status; this catches
#     FORGOTTEN reviews, not malicious ones.
while read -r spec; do
  [ -n "$spec" ] || continue
  base=$(spec_base "$spec")
  t="tests/${base}.spec.ts"
  [ -f "$t" ] || continue
  marker="reports/review/${base}.reviewed"
  stale_review=0
  if [ ! -f "$marker" ]; then
    stale_review=1
  else
    s_now=$(sha256_of "$spec")
    t_now=$(sha256_of "$t")
    s_rec=$(grep -m1 '^spec_sha256:' "$marker" | awk '{print $2}')
    t_rec=$(grep -m1 '^test_sha256:' "$marker" | awk '{print $2}')
    { [ "$s_now" != "$s_rec" ] || [ "$t_now" != "$t_rec" ]; } && stale_review=1
  fi
  [ "$stale_review" -eq 1 ] && { echo "⚠️  ${base}: changed since last review (or never reviewed) — re-run /qa:review"; warn=$((warn+1)); }
done < <(printf '%s\n' "$SPEC_FILES")
# 15b. Stale verified-comment — a `// verified: must_fail_when "<text>"` stamp in a test whose
#      captured text no longer appears in the paired spec means the invariant was edited/removed
#      AFTER verification; the stamp attests a probe of an invariant that no longer exists.
#      (Portable grep+sed spelling of `rg -o '…"([^"]+)"' -r '$1'` — doctor guarantees only grep/sed.)
while read -r t; do
  [ -n "$t" ] || continue
  base=$(spec_base "$t")
  spec="specs/${base}.md"
  [ -f "$spec" ] || continue
  while IFS= read -r vtxt; do
    [ -n "$vtxt" ] || continue
    grep -qF "$vtxt" "$spec" \
      || { echo "⚠️  ${base}: test carries // verified: must_fail_when \"$vtxt\" but that text is not in $spec — the invariant changed since verification; re-run --verify-invariants or update the stamp"; warn=$((warn+1)); }
  done < <(grep -o '// verified: must_fail_when "[^"]*"' "$t" 2>/dev/null | sed 's/.*must_fail_when "\(.*\)"/\1/')
done < <(printf '%s\n' "$TEST_FILES")

# 16. Smoke-tagged spec with NO compiled test (RUN-27) — the smoke-gate-blind catch. Check 3 above
#     confirms SOME test carries @smoke so `--grep @smoke` isn't vacuous; this is the complementary
#     gap: a SPEC that declares a `tags: [smoke, …]` scenario but was never compiled to a test. The
#     spec author put a P1 flow on the fast gate (CLAUDE.md smoke-lane rule), but with no .spec.ts the
#     `--grep @smoke` run selects nothing for it — a fully-broken governed flow (admin RBAC, checkout
#     charge==total) passes the nightly smoke gate silently because there's simply no test to fail.
#     Match the YAML `tags: [ … smoke … ]` list form (the machine-authored tag), not prose `@smoke`
#     mentions. Resolution mirrors Check 15: direct tests/<base>.spec.ts (twins never carry smoke).
while read -r spec; do
  base=$(spec_base "$spec")
  [ -f "tests/${base}.spec.ts" ] && continue                       # compiled → on the gate, fine
  # fanned: a sibling spec may own the compiled test via a `basis: <area>/<feature>` back-link
  feat=$(grep -m1 -E '^basis:[[:space:]]*' "$spec" 2>/dev/null | sed -E 's/^basis:[[:space:]]*//; s/[[:space:]#].*$//')
  [ -n "$feat" ] && [ -f "tests/${feat}.spec.ts" ] && continue
  echo "⚠️  smoke-tagged spec with no compiled test: $spec declares 'tags: [… smoke …]' but tests/${base}.spec.ts does not exist — /qa:run mode=smoke's --grep @smoke is BLIND to this P1 flow; compile it with /qa:gen or drop the smoke tag"; warn=$((warn+1))
done < <(printf '%s\n' "$SMOKE_SPECS_LIST" | grep -v '^$')

# 17. Spec authored but NEVER compiled (ANY tag) — the complement to Check 16 (F-026). Check 16
#     catches the @smoke subset with a stronger gate-blind message; a @regression-only spec that
#     was authored but never generated to a .spec.ts escapes Check 15 (which `continue`s when the
#     test is absent) AND Check 16 (smoke-only), so it sits outside the assertion contract and no
#     run — smoke OR full — ever exercises it. Every spec compiles to tests/<same-basename>.spec.ts
#     (CLAUDE.md file-layout rule); a `basis:` back-link only names the spec's ideation SOURCE
#     (its .cases.md), NOT where its tests live — so it is deliberately NOT treated as coverage
#     here (that over-lenient skip is exactly what let a fanned sibling like session-guard.md
#     escape). Skip @smoke-tagged specs: Check 16 already reports them, don't double-warn.
while read -r spec; do
  [ -n "$spec" ] || continue
  base=$(spec_base "$spec")
  [ -f "tests/${base}.spec.ts" ] && continue
  # smoke → Check 16 owns it. Membership test against the hoisted set Check 16 iterated, instead
  # of re-applying the tag regex to every spec (a fourth copy of it, and one grep per spec).
  # Newline-delimited on BOTH sides so the match is whole-line: a bare substring test would let
  # `specs/auth/login.md` be "found" inside `specs/auth/login-extra.md`.
  case "
$SMOKE_SPECS_LIST
" in *"
$spec
"*) continue ;; esac
  echo "⚠️  spec with no compiled test: $spec has no tests/${base}.spec.ts (any tag) — authored but never generated, so it is outside the assertion contract and no run exercises it. Run /qa:gen on it; or if its scenarios are intentionally folded into a sibling spec, /qa:retire it or add a '# waived:' note"; warn=$((warn+1))
done < <(printf '%s\n' "$SPEC_FILES")

# 18. Abandoned authoring chain — a `.cases.md` (the human-approval artifact) with NO downstream
#     spec (F-026). The intake→ideate→approve chain ran (a checklist exists) but /qa:new-spec/gen
#     never produced a spec, so the intended coverage silently never shipped and nothing else in
#     doctor sees it. Feature key = the path minus the `_context/<site>/` prefix and `.cases.md`
#     suffix — the same `<area>/<feature>` a fanned spec's `basis:` back-link uses.
while read -r cases; do
  feat=$(printf '%s' "$cases" | sed -E 's#^specs/_context/[^/]+/##; s#\.cases\.md$##')
  [ -f "specs/${feat}.md" ] && continue                                          # spec exists → chain completed
  [ -n "$(printf '%s\n' "$BASIS_LINKS" | bash scripts/spec-links.sh match "$feat")" ] && continue   # a fanned spec back-links it (hoisted index, canonical anchor — same call as Check 13)
  echo "⚠️  abandoned authoring chain: ${cases} has no downstream spec (specs/${feat}.md absent, no spec back-links 'basis: ${feat}') — the approved checklist never became a spec; run /qa:new-spec ${feat} or /qa:retire the chain"; warn=$((warn+1))
done < <(printf %s\\n "$CTX_FILES" | grep -e "\\.cases\\.md$")

# 19. Unattested interview (F-016) — a `.basis.md` whose oracle carries `[human-answered]` rules
#     but does NOT declare a non-`none` `interview:` count. The oracle's human grounding is the one
#     un-automatable link; a fully-automated run can invent rules and stamp them `[human-answered]`,
#     and a zero-question basis looks identical to a real interview WITHOUT this attestation. The
#     `interview:` count is the cheap signal that a human was actually interviewed. (WARN only —
#     free-text; a basis with NO `[human-answered]` rules — all grounded/imported/pinned — is exempt.)
while read -r basis; do
  grep -qF '[human-answered]' "$basis" 2>/dev/null || continue                    # no human-answered rules → nothing to attest
  iv=$(grep -m1 -E '^[[:space:]]*interview:[[:space:]]*' "$basis" 2>/dev/null | sed -E 's/^[[:space:]]*interview:[[:space:]]*//; s/[[:space:]]*#.*$//')
  case "$iv" in
    ''|none|None|NONE|'<'*)   # absent, "none", or the unfilled `<n questions…>` placeholder
      echo "⚠️  unattested interview: $basis has [human-answered] oracle rules but interview: '${iv:-<absent>}' — the human grounding is unattested (a fabricated basis looks identical); /qa:intake should stamp the real question count"; warn=$((warn+1)) ;;
  esac
done < <(printf %s\\n "$CTX_FILES" | grep -e "\\.basis\\.md$")

# 20. Plugin-side normative-prose drift (F-016) — the canonical `.env`-load one-liner is duplicated
#     VERBATIM across several plugin command/agent files (explore/exploration/intake) because each
#     subagent needs its own inline copy (it cannot read CLAUDE.md). That copy-paste is a silent
#     drift risk: if one file's load line diverges, that path reads an empty $BASE_URL_* and quietly
#     degrades. When $TMPL resolved, assert the idiom stays byte-identical wherever it appears — WARN
#     only if MORE THAN ONE distinct form exists (all-identical = healthy, no warn). The
#     conditional-park rule is deliberately NOT byte-checked: each agent contextualizes it
#     differently and that variance is intended, so a byte-check there would false-FAIL.
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  envforms=$(grep -rhoE 'set -a;.*\.env.*set \+a' "$TMPL/../agents" "$TMPL/../skills" 2>/dev/null | sed 's/^[[:space:]]*//' | sort -u)
  nforms=$(printf '%s\n' "$envforms" | grep -c .)
  [ "${nforms:-0}" -gt 1 ] && { echo "⚠️  .env-load idiom drift (F-016): $nforms distinct forms of the duplicated one-liner across plugin skill/agent files — re-sync every copy to the canonical CLAUDE.md §Environment form"; warn=$((warn+1)); }
fi

# 21. Fresh-project readiness verdict (F-025) — a brand-new project trips several checks as WARNs
#     purely because nothing is authored yet (no app.context.md, 0 specs), so "OK with warnings"
#     reads as "something's wrong" when the honest state is "expected at this stage". Name it and
#     point at the next step so a newcomer knows setup is healthy.
if [ ! -f specs/_context/app.context.md ] && [ "$fail" -eq 0 ]; then
  echo "ℹ️  fresh project — no app.context.md / specs yet, so the context/spec/interview checks are n/a at this stage (not failures). Setup looks healthy — next run /qa:explore to build the context layer."
fi

# Rollup reflects EVERY ❌/⚠️ above. `fail`/`warn` are real counts (incremented,
# not latched to 1), so "(N blocking)" is honest. And it EXITS non-zero on any ❌ (F-14):
# without an explicit `exit`, the block's status was whatever the last check returned — a real
# FAIL could leave exit 0, so CI (or a caller `&&`-chaining doctor) never saw the failure. The
# "✅ healthy — all N checks passed" line also distinguishes a clean run from a crashed/partial
# one, which the old silent-PASS design could not.
echo "---"
if [ "$fail" -ne 0 ]; then
  echo "doctor: ❌ FAIL ($fail blocking, $warn warning$([ "$warn" = 1 ] || echo s))"; exit 1
elif [ "$warn" -ne 0 ]; then
  echo "doctor: ⚠️  OK with warnings ($warn)"; exit 0
else
  echo "doctor: ✅ healthy — all checks passed"; exit 0
fi
