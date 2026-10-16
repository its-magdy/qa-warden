#!/usr/bin/env bash
# /qa-warden:doctor — the deterministic self-check pass (checks 0–21 + rollup).
# Read-only: reruns no tests, heals nothing, hits no network, writes nothing.
# Run from the QA project root (the dir with playwright.config.ts + CLAUDE.md):
#   /qa-warden:doctor                                   (runs this file from the plugin)
#   bash <plugin>/skills/doctor/scripts/doctor.sh       (by hand, or in CI against a plugin checkout)
#   bash scripts/doctor.sh                              (the stamped launcher; finds the installed plugin)
# Each check prints ✅ / ⚠️ / ❌ + the offending path; exit 1 on any ❌.
#
# This file ships in the PLUGIN and is not stamped into projects. It used to be: a stamped copy
# was refreshed only by /qa-warden:init --resync, so every new check reached a project one repair
# late, and a copy older than the plugin it compared against misreported (it looked for manifests
# where an older plugin kept them). Now the checks and the baseline they compare against are
# always the same build.

# Not a project at all. Every check below reads a path relative to the current directory, so a
# doctor started anywhere else (a home directory, the plugin repo, a fresh mktemp) used to print
# some thirty ❌ — one per missing substrate file — which reads as a broken project rather than
# the wrong directory. When none of the three things a scaffold always leaves is here, say that
# once and stop. ANY one of them present means a project, however damaged, and the full pass runs
# so that it can name what is missing. Not a numbered check: it gates whether the checks run.
# It comes before the .env load (a stray .env in the wrong directory is not ours to execute) and
# before the jq check (so a machine without jq still gets this one line, not two ❌).
if [ ! -e playwright.config.ts ] && [ ! -e CLAUDE.md ] && [ ! -d scripts ]; then
  echo "❌ not a QA Warden project (run from the project root, or /qa-warden:init)"
  exit 1
fi

# Load the project's .env the way the stamped scripts do (prod-guard.sh, cli-fill-env.sh): inside
# this process, so Check 10 sees the BASE_URL_<SITE> values. One statement per line on purpose:
# qa-selfcheck Check 20 fails any line under agents/ or skills/ that chains the export toggle and
# the source of the env file into one line, because that one-liner in a Bash TOOL call prompts and
# dies with the call. A script's own load is the sanctioned form, not that.
if [ -f "${CLAUDE_PROJECT_DIR:-.}/.env" ]; then
  set -a
  . "${CLAUDE_PROJECT_DIR:-.}/.env"
  set +a
fi
fail=0; warn=0

# 0. jq is load-bearing for check 1 — without this precheck a missing jq (or corrupt
#    JSON) leaves the freshness gate blind, and the rollup prints "✅ healthy" over a
#    broken run-of-record — a false-green inside the anti-false-green tool.
command -v jq >/dev/null || { echo "❌ jq not installed — cannot validate last-run.json"; fail=$((fail+1)); }

# 0b. ripgrep (rg) is an undeclared but plugin-wide dependency — /qa-warden:retire's consumer-checks
#     and the healer/reviewer/planner greps all use it. A MISSING rg makes /qa-warden:retire's "is this
#     shared?" query return empty, which false-reads as "unused ⇒ DELETE" (D-4) — a destructive
#     fail-open. WARN (not FAIL): most commands still work, and retire's SKILL.md now falls back to
#     grep -rl, but a QA should know rg is absent before running a consumer-checked deletion.
command -v rg >/dev/null || { echo "⚠️  ripgrep (rg) not installed — /qa-warden:retire consumer-checks fall back to grep -rl; install rg (brew install ripgrep) so a missing tool can never false-read as 'safe to delete'"; warn=$((warn+1)); }

# 1. last-run.json freshness + zero-test guard (the F04/F07/F15 class) — single-sourced
#    in scripts/check-last-run.sh (also called by /qa-warden:report's pre-aggregation check; the
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
  echo "⚠️  scripts/check-last-run.sh missing — project scaffolded before it shipped; re-run /qa-warden:init --resync"; warn=$((warn+1))
fi

# 2. Closed-vocab drift — the oracle keys MUST be byte-identical across the SoT (the plugin's
#    test-case-contract skill) and every mirror (planner, generator, reviewer Check 4, and this
#    project's scripts/oracle-keys.txt). A divergence means the reviewer FAILs specs its own
#    planner authored.
#    The SoT used to be a section of this project's CLAUDE.md, so this check grepped CLAUDE.md.
#    It is now a plugin skill the agents preload, and the plugin-side mirrors are compared with it
#    by bin/qa-selfcheck Check 9b. What only this check can see is the PROJECT side: the manifest
#    /qa-warden:coverage counts with, against the skill the agents actually load.
#    The key set is READ from scripts/oracle-keys.txt, not hand-typed here. This check used to
#    carry its own copy and compare five files against it — a checker whose baseline was one
#    more unpoliced mirror, which is why it also needed a cardinality self-check on that copy
#    (a co-drifted list would silently bless a wrong vocab everywhere, at the right count).
#    Same manifest pattern as resync-set.txt / runtime-dirs.txt: one source, N consumers.
KEYS=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' scripts/oracle-keys.txt 2>/dev/null | grep -v '^$')
if [ -z "$KEYS" ]; then
  echo "❌ scripts/oracle-keys.txt missing or empty — the oracle vocabulary is UNVERIFIED (run /qa-warden:init --resync)"; fail=$((fail+1))
fi
# The skill ships beside this script: <plugin>/skills/doctor/scripts/doctor.sh -> <plugin>/skills/.
# Its key SET is read from the arg-shape table rows, with the same extractor bin/qa-selfcheck
# Check 9bb uses (a row is "| `key` | `shape` |"; the `fault:`/`clock:` rows keep their trailing
# colon precisely so this pattern skips them). The sets are compared EXACTLY. A substring scan
# (grep -oF of each key over the file) used to be enough for CLAUDE.md, but it passes a manifest
# that gains `value`, `url` or `lock`, because those words occur inside the skill's prose.
TCC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/test-case-contract/SKILL.md"
if [ -n "$KEYS" ]; then
  if [ ! -f "$TCC" ]; then
    echo "⚠️  the plugin's test-case-contract skill was not found at $TCC — the vocabulary the agents load is UNVERIFIED (run doctor from the plugin: /qa-warden:doctor)"; warn=$((warn+1))
  else
    SKILL_KEYS=$(sed -nE 's/^\| `([a-z0-9_]+)` \| `.*/\1/p' "$TCC" | sort -u)
    PROJ_KEYS=$(printf '%s\n' "$KEYS" | sort -u)
    if [ -z "$SKILL_KEYS" ]; then
      echo "⚠️  the arg-shape table in $TCC did not parse — the project's oracle keys are UNVERIFIED against the vocabulary the agents load"; warn=$((warn+1))
    else
      # In the project's manifest, not in the skill: a spec using the key fails review.
      while read -r k; do
        [ -n "$k" ] || continue
        echo "❌ oracle key '$k' (scripts/oracle-keys.txt) is not in the plugin's test-case-contract skill — the planner and reviewer do not know it, so a spec using it fails review. The project and the installed plugin disagree: run /qa-warden:init --resync, or update the plugin if this project is newer"; fail=$((fail+1))
      done < <(comm -23 <(printf '%s\n' "$PROJ_KEYS") <(printf '%s\n' "$SKILL_KEYS"))
      # In the skill, not in the manifest: the project is older than the plugin, and
      # /qa-warden:coverage (which builds its pattern from the manifest) does not count that key.
      while read -r k; do
        [ -n "$k" ] || continue
        echo "⚠️  oracle key '$k' is in the plugin's test-case-contract skill but not in scripts/oracle-keys.txt — /qa-warden:coverage does not count it. Run /qa-warden:init --resync"; warn=$((warn+1))
      done < <(comm -13 <(printf '%s\n' "$PROJ_KEYS") <(printf '%s\n' "$SKILL_KEYS"))
    fi
  fi
fi

# --- shared tree walks (Checks 3/13/14/15/15b/16/17/18) ----------------------------------
# These checks used to re-run the SAME walks over tests/ and specs/ (eight-plus traversals, and
# as many copies of filters that have already had to be fixed in lockstep). Walk each tree ONCE
# here, up front, and let every check downstream consume the result.
# The tests/ and specs/ walks, the spec↔test join and the smoke-tag parse are owned by
# scripts/spec-links.sh (`tests` / `specs`, its header rules 4 and 5): the same inventory
# /qa-warden:coverage, /qa-warden:impact and scripts/post-run-checks.sh read, so none of them can
# disagree about which tests Playwright collects. That walk applies playwright.config.ts's
# `testIgnore: ['**/_*.spec.ts','**/_*/**']` in BOTH forms. A `_`-prefixed BASENAME at the tests/
# root (tests/_audit-visual.spec.ts, the sanctioned /qa-warden:review url=<url> throwaway) has just
# ONE slash, so a `-path '*/_*/*'`-only filter let it through, and it drew a false "unmanaged test"
# WARN on a spec Playwright provably never collects (verified: `--list` on the shipped testIgnore
# reports it dropped). A scratch spec carries no verified-stamp / review-attestation contract either.
#   TEST_INV rows: <test> <base> <kind: spec|twin> <spec|-> <manifest|->     (Checks 3, 9l, 13, 15b)
#   SPEC_INV rows: <spec> <base> <test|-> <smoke|-> <basis|->                (Checks 15, 16, 17)
# A stamp that predates these modes prints nothing here, so both come back EMPTY; Check 9k
# reports that as a ❌ with the resync remedy rather than letting it read as an empty suite.
TEST_INV=$(bash scripts/spec-links.sh tests 2>/dev/null)
SPEC_INV=$(bash scripts/spec-links.sh specs 2>/dev/null)
TEST_FILES=$(printf '%s\n' "$TEST_INV" | cut -f1 | grep -v '^$')
# specs/_context/ is the tree with the MOST consumers — Checks 5, 5b, 13, 18 and 19 each used to
# walk it separately (five traversals for one small tree). Walk it once; the checks below filter
# this list in memory or pass it as operands to a single grep.
CTX_FILES=$(find specs/_context -type f -name '*.md' 2>/dev/null)
# Every top-level `basis: <area>/<feature>` back-link in an authored spec, as `<path>:basis: <value>`
# (grep -H). Checks 13 and 18 each used to re-run a full `grep -r … specs` walk PER feature — an
# O(features × tree) sweep for a relation that is one grep to harvest. Both the harvest and the
# trailing-comment-tolerant match anchor now live in scripts/spec-links.sh (`index` / `match`),
# which /qa-warden:coverage and /qa-warden:impact call too — that anchor had already needed one lockstep fix
# applied by hand in three places.
BASIS_LINKS=$(bash scripts/spec-links.sh index 2>/dev/null)

# 3. Vacuous smoke gate — `--grep @smoke` must select ≥1 test, so count @smoke ON ITS OWN.
#    A combined '@smoke\|@regression' count is blind to the exact failure this check exists
#    for: a suite tagged only @regression (metamorphic twins are deliberately @regression,
#    never @smoke) makes the combined count >0 while /qa-warden:run mode=smoke still selects 0 tests (F07).
#    Match `@smoke` INSIDE A STRING LITERAL (a quote/double-quote/backtick opened earlier on
#    the line), excluding `//`-comment lines — this counts BOTH official tag forms that
#    `--grep @smoke` selects: the `tag: ['@smoke']` array AND a title-embedded
#    `test('... @smoke', ...)` (the old quote-ADJACENT match missed title-embedded tags →
#    false ❌ on a working smoke lane). A bare `// NOT @smoke` comment still doesn't count
#    (RUN-19). No trailing boundary after @smoke on purpose: --grep is a substring match, so
#    a `@smoke-fast` title IS selected by /qa-warden:run mode=smoke and must count here too. Residual: a
#    block-comment line mentioning '@smoke' still false-counts (fails toward noise, not
#    toward the false-green this check exists to prevent).
# Exclude `_`-prefixed SCRATCH specs from every count (P-05), in LOCKSTEP with
# playwright.config.ts's `testIgnore: ['**/_*.spec.ts', '**/_*/**']`: a `/qa-warden:review url=<url>` throwaway
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
[ "$TOTAL_SPECS" -gt 0 ] && [ "$SMOKE_SPECS" -eq 0 ] && { echo "❌ no test carries @smoke — /qa-warden:run mode=smoke's --grep @smoke selects 0 tests and passes vacuously"; fail=$((fail+1)); }

# 4 + 14. Orphaned heal sentinels and unmanaged tests — both single-sourced in
#    scripts/post-run-checks.sh, which /qa-warden:run mode=smoke, /qa-warden:report and /qa-warden:run mode=single also call.
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
    # Emit a COPY-PASTEABLE command, not the bare `mode=area` this used to print. exploration
    # STOPs on a `mode=area` whose `site=`/`area=` is missing rather than guessing the area
    # (agents/exploration.md §"Mode selection" arm 3), so a hint that omits them costs the reader
    # a round-trip — and $f already carries both. Off the expected depth, fall back to placeholders.
    site_id=$(printf '%s' "$f" | sed -nE 's|^specs/_context/([^/]+)/[^/]+\.md$|\1|p')
    area_id=$(printf '%s' "$f" | sed -nE 's|^specs/_context/[^/]+/([^/]+)\.md$|\1|p')
    if [ -n "$site_id" ] && [ -n "$area_id" ]; then expl="mode=area site=$site_id area=$area_id"
    else expl="mode=area site=<id> area=<name>"; fi
    [ "$age_days" -gt "$budget" ] && { echo "⚠️  stale context: $f (volatility=${vol:-reference}, last_verified $lv = ${age_days}d old > ${budget}d tier budget) — re-run /qa-warden:explore $expl"; warn=$((warn+1)); }
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
#    resolution calls — a project scaffolded before they shipped needs a /qa-warden:init
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
  [ -f "$f" ] || { echo "⚠️  $f missing — project scaffolded before it shipped; re-run /qa-warden:init"; warn=$((warn+1)); }
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
# 8b. Playwright FOUR-SITE PAIRED-BUMP lockstep. package.json's own `overrides_comment` mandates
#     four sites move together — `@playwright/test`, `overrides.playwright`,
#     `overrides.playwright-core`, and the version-pinned npx arg in `.mcp.explore.json`. FIVE arms
#     in two blocks; the first block is package.json-internal, the second needs `.mcp.explore.json`.
#
#     (c)(d)(e) — the three pairs INSIDE package.json. Measured 2026-09-20
#     during the 1.63.0 evaluation: of those four sites, arm (a) below enforced
#     exactly ONE pair (the MCP one). A bump of `@playwright/test` ALONE printed
#     "pins: stable + zod lockstep + lockfile core ✅" and nothing else: Check 7a only screens for
#     alpha/beta/rc and 7c only screens the LOCKFILE's core for alpha, so a clean, stable, SKEWED
#     set passes both. That is the T-01/F-002 skew the overrides block exists to prevent, arriving
#     through the half-done bump the comment warns about. Same unchecked-mirror shape as 9b/9bb/8.
#     Three arms, all comparing version LITERALS (symbols), never prose:
#     (c) `@playwright/test` == `overrides.playwright` — the runner and the forced core must be one
#         version. Skewed, `overrides` drag core BACK DOWN under a newer runner (T-01).
#     (d) `overrides.playwright` == `overrides.playwright-core` — @playwright/cli and @playwright/mcp
#         each hard-depend on an ALPHA playwright-core, so pinning only `playwright` leaves a nested
#         alpha core needing a browser revision `playwright install` never fetches (F-002).
#     (e) `@playwright/test` is EXACT (no ^ or ~). This is what makes (c) MEAN anything: a caret lets
#         a lockfile-less install float the runner to a newer 1.x while (c) still reads equal.
#     Deliberately in its OWN `[ -f package.json ]` guard, NOT folded into the block below: that
#     block is gated on `.mcp.explore.json` existing, so a project without an explore config got no
#     lockstep check at all. These three pairs are package.json-internal and must not inherit that gate.
if [ -f package.json ]; then
  node -e '
    const p = require("./package.json");
    const dev = Object.assign({}, p.dependencies, p.devDependencies);
    const runner = dev["@playwright/test"];
    const ov = (p.overrides || {})["playwright"];
    const ovCore = (p.overrides || {})["playwright-core"];
    const bad = [];
    const bare = v => String(v || "").replace(/^[~^]/, "");
    // (e) exactness first — a caret here makes (c) a false green.
    if (runner && /^[~^]/.test(runner))
      bad.push("@playwright/test is `" + runner + "` — must be EXACT (no ^/~), else a lockfile-less install floats the runner above the forced core (T-01)");
    // (c) runner <-> forced playwright
    if (runner && ov && bare(runner) !== bare(ov))
      bad.push("@playwright/test " + runner + " != overrides.playwright " + ov + " — runner/core skew (T-01)");
    // (d) forced playwright <-> forced playwright-core
    if (ov && ovCore && bare(ov) !== bare(ovCore))
      bad.push("overrides.playwright " + ov + " != overrides.playwright-core " + ovCore + " — a nested ALPHA core survives the pin (F-002)");
    if (bad.length) {
      console.log("❌ Playwright four-site lockstep drift (package.json overrides_comment mandates these move together):");
      for (const b of bad) console.log("   - " + b);
      process.exit(2);
    }
    // Report what was actually COMPARED, not a blanket pass: a project that deleted a site has
    // no pair to skew, and Check 9 (package.json is in resync-set.txt) already owns that class —
    // but the green line must not claim an equality it never tested.
    const sites = [runner && "@playwright/test", ov && "overrides.playwright", ovCore && "overrides.playwright-core"].filter(Boolean);
    console.log("playwright lockstep: " + sites.length + "/3 package.json sites present and in step"
      + (runner || ov || ovCore ? " at " + bare(runner || ov || ovCore) : "")
      + (sites.length < 3 ? " — missing: " + ["@playwright/test","overrides.playwright","overrides.playwright-core"].filter(s => !sites.includes(s)).join(", ") + " (see Check 9 substrate drift)" : "") + (sites.length < 3 ? " ⚠️" : " ✅"));
    // A missing site is not drift (nothing to skew) but it is not a pass either: exit 3 so the
    // shell tallies it as a warning instead of printing a ✅ beside "0/3 … missing".
    if (sites.length < 3) process.exit(3);
  ' 2>/dev/null
  pwls_rc=$?
  [ "$pwls_rc" -eq 2 ] && fail=$((fail+1))
  [ "$pwls_rc" -eq 3 ] && warn=$((warn+1))
  { [ "$pwls_rc" -ne 0 ] && [ "$pwls_rc" -ne 2 ] && [ "$pwls_rc" -ne 3 ]; } && { echo "⚠️  could not read package.json Playwright pins — four-site lockstep UNVERIFIED"; warn=$((warn+1)); }
fi

#     (a)(b) — the MCP server site. As of Playwright 1.62 the MCP server ships BUNDLED with
#     `playwright`, so .mcp.explore.json launches `npx -y playwright@<version> mcp`. That npx arg
#     MUST be pinned and MUST equal the `overrides.playwright` pin: an UNPINNED `npx -y playwright
#     mcp` silently fetches the LATEST Playwright whenever node_modules is absent (a fresh clone,
#     a lockfile-less CI step) — the exact runner/core version skew the whole `overrides` block
#     exists to prevent, except sourced from the explore config instead of the dep tree.
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
#      (b) Write-allowlist-EXCLUDED — scripts/init.sh, scripts/README.md, and the two stamped
#          scripts/*.txt manifests (runtime-dirs.txt, oracle-keys.txt), .github/**, .env. Not in
#          deny[], so per-prompt-approved. The manifests nothing in a project reads
#          (resync-set.txt, claude-md-vocab.txt, prod-guard-rails.txt) live in the plugin's
#          manifests/ and are never stamped.
#      (c) Inside a Write/Edit ALLOW glob — the resync-set members under specs/** and
#          fixtures/**. These were once silently auto-writable (no deny, no prompt): an agent
#          could clobber specs/_context/_templates/basis.md with a real feature's basis and
#          every later /qa-warden:intake would read the corrupted file as its template. Now denied by
#          path, but keep this tier in mind when ADDING a resync-set entry under an allowed
#          tree — the deny is per-path and does not follow automatically.
#    /qa-warden:init is skip-if-exists, so a plugin fix to any of these does NOT reach a project
#    scaffolded before the fix — a shipped fix silently strands every existing project
#    (F-015/F-016). Detect the drift here (read-only) against the shipped templates and name
#    the repair: /qa-warden:init --resync. The baseline is the plugin this script ships in, so
#    detection, the manifest and the templates are always one build. Also covers scripts/init.sh (F-03: toolkit-owned, scaffold-copied,
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
# The baseline is the plugin this script ships in: <plugin>/skills/doctor/scripts/doctor.sh, so the
# plugin root is three directories up. No lookup, no guess. Until this script moved into the plugin
# it lived in the project and had to FIND a plugin: $CLAUDE_PLUGIN_ROOT, else the install recorded in
# installed_plugins.json, else the newest cached version by mtime, which could be a stale orphaned
# version. Running from the plugin removed that whole question. $CLAUDE_PLUGIN_ROOT is not read: the
# script's own location is the plugin it belongs to, and the stamped launcher (scripts/doctor.sh)
# does any looking-up a hand run needs.
TMPL=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)
TMPL="${TMPL:+$TMPL/templates}"
if [ -n "$TMPL" ] && [ ! -d "$TMPL" ]; then
  TMPL=""
fi
if [ -n "$TMPL" ] && [ -d "$TMPL" ]; then
  # The toolkit-owned set is SINGLE-SOURCED in the plugin's manifests/resync-set.txt,
  # which qa-scaffold's --resync reads too — detection and repair MUST cover the SAME files,
  # else drift in a resync-refreshed file (e.g. _templates/basis.md, which seeds every intake)
  # is silently repaired by `--resync` but never DETECTED here, so doctor never fires the "run
  # --resync" nudge its own header promises (M-8). Two hand-kept lists could not hold that;
  # one manifest can. The manifest also documents the user-editable exclusions.
  # It lives OUTSIDE templates/ because nothing in a project reads it: only this check and
  # qa-scaffold do, and both read the plugin's copy. A stamped copy was dead weight that fired
  # drift warnings when edited. No older-layout fallback: this script and the manifest ship in
  # the same plugin, so a missing manifest means an incomplete install.
  RESYNC_MANIFEST="$TMPL/../manifests/resync-set.txt"
  OWNED=$(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$RESYNC_MANIFEST" 2>/dev/null | grep -v '^$')
  [ -n "$OWNED" ] || { echo "⚠️  toolkit-owned manifest (manifests/resync-set.txt) not readable in the plugin at $TMPL/.. — substrate drift is UNVERIFIED (the plugin install is incomplete; reinstall it)"; warn=$((warn+1)); }
  for rel in $OWNED; do
    [ -f "$TMPL/$rel" ] || continue
    if [ ! -f "$rel" ]; then
      echo "❌ substrate missing: $rel absent from project — run /qa-warden:init --resync"; fail=$((fail+1))
    elif ! cmp -s "$TMPL/$rel" "$rel"; then
      echo "⚠️  substrate drift: $rel differs from the shipped template — run /qa-warden:init --resync (backs up to $rel.qa-bak)"; warn=$((warn+1))
    fi
  done
  # Leftovers of that move. A project stamped before it carries copies of the three plugin-only
  # manifests under scripts/. Nothing reads them any more, --resync no longer refreshes them
  # and this check no longer compares them, so an edit to one does nothing at all. Say so once
  # per run as INFO, uncounted: the files are harmless, but a user who edits one expecting an
  # effect deserves to know.
  for rel in scripts/resync-set.txt scripts/claude-md-vocab.txt scripts/prod-guard-rails.txt; do
    [ -f "$rel" ] || continue
    echo "ℹ️  $rel is a leftover from an older stamp — that manifest now lives only in the plugin (manifests/) and nothing in this project reads it; safe to delete"
  done
  # Same story for the review marker writer: /qa-warden:review now runs the plugin's own copy
  # (skills/review/scripts/review-marker.sh), so the stamped one is called by nothing. Its two
  # settings.json rules are named here but NOT retired by Check 9c: they are harmless, and the
  # file and its rules should go together, by hand.
  if [ -f scripts/review-marker.sh ]; then
    echo "ℹ️  scripts/review-marker.sh is a leftover from an older stamp — nothing calls it now (/qa-warden:review runs the plugin's copy); safe to delete, together with its two .claude/settings.json rules: \"Bash(bash scripts/review-marker.sh*)\" (allow) and \"Edit(scripts/review-marker.sh)\" (deny)"
  fi
  # And for the plain allow rule the stamped doctor needed: /qa-warden:doctor runs this file, so
  # nothing Claude runs calls scripts/doctor.sh (now a launcher for terminal runs, which need no
  # allow rule). Named here, not retired by Check 9c: the rule starts with the program, so an
  # allow match cannot carry a variable assignment in front of it, and a compound command is
  # matched per subcommand. All it pre-approves is running the edit-denied launcher. The file
  # stays (it is the launcher, toolkit-owned); only the rule is a leftover. Its sibling,
  # `Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)`, is NOT harmless and is in Check 9c.
  if [ -f .claude/settings.json ] && grep -qF '"Bash(bash scripts/doctor.sh*)"' .claude/settings.json 2>/dev/null; then
    echo "ℹ️  .claude/settings.json still allows \"Bash(bash scripts/doctor.sh*)\" — a leftover from an older stamp: /qa-warden:doctor runs the plugin's own doctor and nothing calls scripts/doctor.sh any more (keep the file, it is the launcher for terminal runs); the rule is safe to delete"
  fi
else
  # A skipped drift check must be VISIBLE (WARN, counted), not a silent green INFO — this check
  # guards the highest-value propagation class (F-015/F-027); a quiet skip hides exactly that drift.
  # Reachable only when this file was copied out of its plugin.
  echo "⚠️  substrate-drift check SKIPPED — no plugin templates/ three directories above this script; it was copied out of the plugin. Run it as /qa-warden:doctor, or as bash <plugin>/skills/doctor/scripts/doctor.sh; drift to the shipped substrate is UNVERIFIED"; warn=$((warn+1))
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

# CLAUDE.md VOCABULARY CONTAINMENT — the second shared-ownership file, and the one excluded
# above WITHOUT a containment complement. `--resync` refreshes the toolkit-owned set but
# deliberately skips CLAUDE.md (users customise project policy), and the byte-compare above skips
# it for the same reason. Both exclusions are right in isolation; together they leave the widest
# hole in the upgrade path, because CLAUDE.md is where every new AUTHORING feature is documented
# and the in-PROJECT agents read that file rather than the plugin.
# MEASURED, not reasoned — a real 0.2.0 -> HEAD upgrade on a scratch install: after a clean,
# green, exit-0 `/qa-warden:init --resync` the stamped CLAUDE.md carried ZERO mentions of `fault:`,
# `clock:`, `lock:` or `verifier`. The runtime was current and the vocabulary was a whole release
# behind, and doctor said nothing. The shipping vehicle for every new feature was the one file
# the upgrade could not deliver.
# WHY CONTAINMENT AND NOT A SECTION DIFF. The obvious shape — byte-compare the toolkit-owned
# SECTIONS — is refuted by that same upgrade: the `## ` heading set is IDENTICAL across it
# (19 = 19) while the 93 new lines landed INSIDE ten pre-existing sections. A section-level check
# reports green on precisely the release it would have been built for. What arrives is SYMBOLS
# scattered through prose the user is invited to edit, so police the symbols — the
# prod-guard-rails.txt lesson (compare the invariant, never the wording) applied to a file that
# cannot be resynced at all.
# The required set is DERIVED, like STOCK_VARS above: manifest x shipped template. Presence
# anywhere satisfies it, so rewording and user additions are free and only a DELETION is
# reported. Not the oracle keys, and not `fault:`/`clock:` any more: they are defined in the
# plugin's test-case-contract skill, which ships with the plugin, so a CLAUDE.md without them is
# missing nothing. And `lock:` must never be added to oracle-keys.txt (it is a TestDetails field,
# not an oracle key, and that manifest also feeds Check 2, Check 9b and /qa-warden:coverage's KEYS_RE).
# WARN, never FAIL: alone among Check 9's findings the repair is not a command but a hand-merge,
# and a repair the toolkit cannot perform must not be louder than the ones it can (substrate
# drift and 9f arm 2 are both WARNs with a one-command fix). A FAIL would red every upgrading
# consumer's CI for a condition only a human can clear.
if [ -n "$TMPL" ] && [ -f "$TMPL/CLAUDE.md" ] && [ -f CLAUDE.md ]; then
  # The manifest is plugin-only (manifests/, never stamped): this check is its one reader and
  # it reads the plugin's copy, which ships beside this script.
  VOCAB="$TMPL/../manifests/claude-md-vocab.txt"
  if [ ! -f "$VOCAB" ]; then
    echo "⚠️  manifests/claude-md-vocab.txt not found in the plugin at $TMPL/.. — CLAUDE.md vocabulary DELIVERY is UNVERIFIED (the plugin install is incomplete; reinstall it)"; warn=$((warn+1))
  else
    # Strip FULL-LINE comments only — unlike the sibling manifests, a row here carries prose in
    # its why-field, so the usual `s/#.*$//` would truncate it mid-sentence.
    while IFS='|' read -r sym swhy; do
      [ -n "$sym" ] || continue
      # Anchored exactly as Check 9i (bin/qa-selfcheck) anchors the step symbols, so `lock:` cannot match `unlock:`.
      if ! grep -qE "(^|[^a-zA-Z_])$sym" "$TMPL/CLAUDE.md"; then
        # The 9c stranded-rule shape, inverted: a manifest demanding a symbol the toolkit no
        # longer ships would nag every consumer about a retired feature forever. Report the
        # MANIFEST as stale and check nothing downstream of it.
        echo "⚠️  claude-md-vocab.txt requires \`$sym\` but the SHIPPED templates/CLAUDE.md no longer mentions it — the manifest is stale (drop the line) or the symbol was dropped from the template by mistake"; warn=$((warn+1)); continue
      fi
      grep -qE "(^|[^a-zA-Z_])$sym" CLAUDE.md \
        || { echo "⚠️  CLAUDE.md never mentions \`$sym\` — $swhy. /qa-warden:init --resync does NOT refresh CLAUDE.md (shared ownership), so this is a HAND-MERGE, not a command: diff yours against $TMPL/CLAUDE.md and copy the missing prose across."; warn=$((warn+1)); }
    done < <(grep -v '^[[:space:]]*#' "$VOCAB" | sed 's/[[:space:]]*$//' | grep -v '^$')
  fi
fi

# Pre-0.4.0 command names in CLAUDE.md. The plugin id changed from `qa` to `qa-warden` in 0.4.0,
# so every `/qa:<cmd>` became `/qa-warden:<cmd>`. CLAUDE.md is shared-ownership and never
# resynced, so an upgraded project keeps telling agents to run commands that no longer exist.
# WARN, for the same reason as the vocabulary check above: the repair is a hand-edit.
if [ -f CLAUDE.md ]; then
  old_cmds=$(grep -cE '/qa:[a-z]' CLAUDE.md || true)
  if [ "${old_cmds:-0}" -gt 0 ]; then
    echo "⚠️  CLAUDE.md still uses the pre-0.4.0 command prefix /qa: on $old_cmds line(s) — those commands are now /qa-warden:<cmd>. Replace /qa: with /qa-warden: in CLAUDE.md (/qa-warden:init --resync does not rewrite it)."
    warn=$((warn+1))
  fi
fi

# The spec format contract moved out of CLAUDE.md into the plugin's test-case-contract skill, which
# the planner, generator, verifier, reviewer and ideation agents preload. A project stamped before
# that keeps the old section, because CLAUDE.md is shared-ownership and never resynced. Left in
# place it is a second copy of the vocabulary and the argument shapes that nothing compares with
# the skill, so the two drift apart, and it still costs every session its ~19 KB on every turn.
# Keyed on the section's own heading, which the shipped template no longer carries. WARN, for the
# same reason as the two checks above: the repair is a hand-edit.
if [ -f CLAUDE.md ] && grep -qE '^##[[:space:]]+Test case format contract[[:space:]]*$' CLAUDE.md; then
  echo "⚠️  CLAUDE.md still has the '## Test case format contract' section. It moved into the plugin's test-case-contract skill, which the agents preload, and the two copies will drift apart. Run /qa-warden:init --resync first (it does not edit CLAUDE.md). Then move any project-specific rules out of the section, replace it (from that heading down to the next '## ' heading, '### Situation steps' included) with the shipped template's '## Spec format' section, and in '## Oracle defense' change 'Closed vocabulary — see above' to name the skill."
  warn=$((warn+1))
fi

# 9b / 9bb / 9bc / 9bd / 9be / 9d / 9e / 9f arm 1 / 9g / 9h / 9i / 9j / 20 — MOVED to the plugin's
#     own `bin/qa-selfcheck`, NOT shipped here. They read ONLY the plugin's source (agents/,
#     skills/, hooks/, reference/, templates/, manifests/) and nothing in this project, so there
#     was never anything a consumer could fix when one fired: they are the toolkit's unit tests,
#     and they belong where the toolkit is built. They also made a project whose substrate is
#     NEWER than a teammate's installed plugin print a wall of ❌ that all meant "update your
#     plugin". Seven moved first; 9bb, 9bd, 9f arm 1, 9g, 9i and 20 followed once the same test
#     was applied to each of them. The checks that COMPARE this project with the plugin (9, 9c,
#     9f arms 2-3, 9k) stay — that comparison can only be made from here. The ids are kept, so a
#     citation of "Check 9bc" or "Check 9bb" resolves — to bin/qa-selfcheck.

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
      "Bash(printenv)") why="It auto-approves a BARE printenv — a full dump of every .env secret loaded into that shell (QA_ADMIN_PASSWORD, QA_TOTP_SECRET, QA_CLIENT_CERT_PASSPHRASE) into the transcript — and nothing in the toolkit uses it." ;;
      "Bash(printenv *)") why="It auto-approves printenv of any named variable(s) without a prompt, so 'printenv QA_ADMIN_PASSWORD' puts that secret into the transcript — and nothing in the toolkit uses it: agents resolve base URLs with 'bash scripts/prod-guard.sh --list-targets'." ;;
      "Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)") why="Its first * matches any text, spaces included, so it also auto-approves 'CLAUDE_PLUGIN_ROOT=x CLAUDE_CONFIG_DIR=artifacts/x bash scripts/doctor.sh' (the launcher reads CLAUDE_CONFIG_DIR, so an agent-written install record under artifacts/ names the doctor it runs) and 'CLAUDE_PLUGIN_ROOT=x bash -c <any command> bash scripts/doctor.sh' — and nothing calls it any more: /qa-warden:doctor runs the plugin's own doctor." ;;
      *) why="It was retracted from the shipped template." ;;
    esac
    echo "⚠️  retired permission rule still in .claude/settings.json: \"$retired\" — the scaffold's jq merge is additive (union) and never removes a rule, so this must be deleted BY HAND. $why"
    warn=$((warn+1))
  done <<'RETIRED'
Bash(sed *e)
Bash(sed *e *)
Bash(sed *e;*)
Bash(printenv)
Bash(printenv *)
Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)
RETIRED
  # 9c-ii. Path-scoped `Write(...)` rules — never consulted. Claude Code checks file permissions
  #        against `Edit(path)` and `Read(path)` rules ONLY; a `Write(<path>)` rule is accepted,
  #        never consulted, and warned about at startup (code.claude.com/docs/en/permissions
  #        §Read and Edit). `Edit` rules already cover the Write tool. The template shipped 30 of
  #        them (each with an `Edit` twin) until 0.4.0, and the additive merge strands them, so
  #        this is ONE summary warning rather than 30 RETIRED entries. A bare `Write` (no path)
  #        is a valid tool-level rule and is not flagged.
  if command -v jq >/dev/null 2>&1; then
    write_rules=$(jq -r '.permissions | (.allow // []), (.deny // []), (.ask // []) | .[]
                         | select(type == "string" and startswith("Write("))' \
                    .claude/settings.json 2>/dev/null)
  else
    write_rules=$(grep -oE '"Write\([^"]*\)"' .claude/settings.json 2>/dev/null | tr -d '"')
  fi
  n_write=$(printf '%s\n' "$write_rules" | grep -c . | tr -d ' ')
  if [ "$n_write" -gt 0 ]; then
    echo "⚠️  $n_write path-scoped Write(...) rule(s) in .claude/settings.json are never consulted — Claude Code checks file permissions against Edit(...)/Read(...) rules only and warns about these at startup. Delete them BY HAND (the scaffold's merge never removes a rule); where a rule has no Edit(...) twin, replace it with one. First: $(printf '%s\n' "$write_rules" | head -3 | tr '\n' ' ')"
    warn=$((warn+1))
  fi
fi

# 9f. Healer MCP grants — did the grants the plugin SHIPS actually reach this project (arm 2),
#     and did the permission merge run at all (arm 3). Arm 1 — agents/healer.md's `tools:` line
#     against templates/settings.json's `mcp__playwright__*` allow entries — compares two
#     plugin files and nothing in this project, so it lives in the plugin's `bin/qa-selfcheck`
#     under the same id.
#     Arm 2 is the settings-side complement Check 9c does NOT cover: 9c catches a rule the
#     toolkit RETRACTED that is stranded downstream; nothing caught a rule the toolkit ADDED
#     that never reached an already-scaffolded project. Deliberately scoped to the mcp__ entries
#     and not the whole allow[]: those are agent-capability grants with exactly one right
#     answer, whereas a user legitimately deletes a POLICY rule they disagree with (that has
#     happened) and a full-list subset check would nag them forever.
#     That scoping was RE-EXAMINED after session 14 measured the blind spot (a resync-only
#     upgrade delivered 0 of 37 new rules; this arm nudged on 2 of them). It STANDS, and the
#     full-list check stays unbuilt, for a reason stronger than the nag — measured, not argued:
#       - The nag is real and the obvious fix does not dodge it. A plain subset check run over
#         three scratch projects reported 37 missing on a resync-only upgrade (right), 0 on a
#         current project (right) and 2 on a current project whose owner had deleted two deny
#         rules on purpose (wrong). Deriving the required set from the shipped template — the
#         shape that closed the CLAUDE.md gap one check up -- does not separate those last two:
#         both rules are still shipped, so the gate passes and the false nag survives.
#       - The gap is now closed at the SOURCE instead: qa-scaffold's stamp_permissions() runs
#         on `--resync` as well as on the plain stamp, so the rules travel with the files.
#       - Which leaves a full-list check with no population to serve. When this was decided,
#         doctor was itself a line of resync-set.txt, so a check added here could reach a
#         project only through the same command that performs the repair. Doctor now runs from
#         the plugin, so that argument is gone; the two above still decide it.
if [ -n "$TMPL" ] && [ -f "$TMPL/settings.json" ] && command -v jq >/dev/null 2>&1; then
  s_mcp=$(jq -r '.permissions.allow[]? | select(startswith("mcp__"))' "$TMPL/settings.json" 2>/dev/null | sort -u)
  # Arm 2 — did the shipped grants actually REACH this project? The scaffold's jq merge is an
  # additive union, so the repair is a plain re-run of /qa-warden:init (no hand edit, unlike 9c).
  if [ -f .claude/settings.json ]; then
    p_mcp=$(jq -r '.permissions.allow[]? | select(startswith("mcp__"))' .claude/settings.json 2>/dev/null | sort -u)
    unstamped=$(comm -23 <(printf '%s\n' "$s_mcp") <(printf '%s\n' "$p_mcp") | grep . || true)
    [ -n "$unstamped" ] && {
      echo "⚠️  .claude/settings.json is missing MCP grants the plugin now ships: $(printf '%s\n' "$unstamped" | tr '\n' ' ')— this project was scaffolded before they were added. Re-run /qa-warden:init (the permission merge is additive and runs on every init, so this needs no hand edit)."; warn=$((warn+1)); }
  fi
fi

# 9f arm 3 (same check, no new number). The one delivery failure the source fix CANNOT close:
#     the merge needs `jq`, and without it qa-scaffold writes the shipped rules to
#     `.claude/settings.qa-suggested.json` for a hand-merge and moves on. That file's presence
#     is proof the merge did not run — an intent-free signal, which is exactly what the subset
#     check lacks: it says the rules were never DELIVERED, not that they were declined. Paired
#     with stamp_permissions() deleting the file on a successful merge, so the signal cannot go
#     stale (M-8: detection and repair cover the same set).
#     The presence test is deliberately OUTSIDE the jq gate above — the state it detects is
#     "jq was missing", so a jq-gated detector for it could never fire. jq only refines the
#     message from "unmerged" to "which rules".
#     WARN, not FAIL, matching arm 2: an under-permissioned project prompts and stalls, it does
#     not produce a wrong test result, and the repair is one command.
#     The comparison also counts the extraKnownMarketplaces entry NAMES the template ships (the
#     qa-warden marketplace, so teammates who trust the folder get the plugin): a hand-merge of
#     the permission arrays alone would otherwise read as STALE while teammates still lack it.
if [ -f .claude/settings.qa-suggested.json ]; then
  unmerged=""; counted=0
  if command -v jq >/dev/null 2>&1 && [ -f .claude/settings.json ]; then
    sug=$(jq -r '(.permissions.allow[]?|"allow "+.),(.permissions.deny[]?|"deny "+.),(.extraKnownMarketplaces // {} | keys[] | "marketplace "+.)' .claude/settings.qa-suggested.json 2>/dev/null | sort -u)
    cur=$(jq -r '(.permissions.allow[]?|"allow "+.),(.permissions.deny[]?|"deny "+.),(.extraKnownMarketplaces // {} | keys[] | "marketplace "+.)' .claude/settings.json 2>/dev/null | sort -u)
    if [ -n "$sug" ]; then
      counted=1
      unmerged=$(comm -23 <(printf '%s\n' "$sug") <(printf '%s\n' "$cur") | grep . || true)
    fi
  fi
  if [ "$counted" = "1" ] && [ -z "$unmerged" ]; then
    echo "⚠️  .claude/settings.qa-suggested.json is STALE — every rule in it is already present in .claude/settings.json. Delete it; while it sits there it reads as an outstanding manual merge."; warn=$((warn+1))
  else
    n_txt="its rules"; [ "$counted" = "1" ] && n_txt="$(printf '%s\n' "$unmerged" | wc -l | tr -d ' ') of its rules"
    echo "⚠️  .claude/settings.qa-suggested.json exists — qa-scaffold could not merge permissions (jq missing, or an unparseable settings.json) and left them here instead, so $n_txt never reached .claude/settings.json. Agents will PROMPT on tool calls the toolkit means to pre-approve, and the Write/Edit denies guarding the substrate are absent. Install jq and re-run /qa-warden:init (the merge is additive and deletes this file), or hand-merge the arrays (and the extraKnownMarketplaces entry) and delete it."; warn=$((warn+1))
  fi
fi

# 9g / 9i — MOVED to bin/qa-selfcheck (see the MOVED note above Check 9c).

# 9k. UNMANIFESTED-walk OWNERSHIP. "which compiled tests have no route manifest" is one rule
#     with two consumers that must never disagree: /qa-warden:impact prints it as ### BLIND SPOTS (a
#     zero-match there is only honest if the caller is told which specs were invisible), and
#     /qa-warden:coverage dim 0 needs it to avoid the false label it used to print — an unmanifested
#     test contributes no routes, so every route it touches landed under "touched by NO compiled
#     test (planned, untested)", which is FALSE for a test that is on disk and compiled and
#     sends the reader to author a second spec when the real remedy is to clear the blocker the
#     verifier withheld the manifest for. The walk therefore lives in `scripts/spec-links.sh
#     unmanifested` and nowhere else (the same move that put the `feature:` extractor and the
#     back-link anchor there — see that file's header rules 1-3).
#     The walk itself is the collected-test inventory (spec-links.sh `collected_tests()`, header
#     rule 4), which doctor's own TEST_INV/SPEC_INV, coverage and post-run-checks.sh also read.
#     Keys on SYMBOLS, never wording — the mode name, the function name, the twin marker, the two
#     testIgnore exclusions, and the shape of a manifest path built from a variable. Three arms:
#       Arm 1 — scripts/spec-links.sh still carries the `unmanifested)` arm (the owner exists).
#       Arm 2 — the shared walk exists, and its two silent properties hold. A stamp with no
#               `collected_tests()` predates the inventory: every `tests`/`specs` call above
#               printed nothing, so this is where that gets said (once), with the resync remedy.
#               (a) twins: the walk's `(*.metamorphic)` case marks a twin and the arm skips `= twin`.
#               A twin never carries a manifest BY DESIGN (verifier V4 emits one per spec), so
#               without the skip every twin is reported as a blind spot and both consumers cry
#               wolf until someone disables the section.
#               (b) scratch specs: the walk's find keeps BOTH `! -name '_*'` and `! -path
#               '*/_*/*'` (playwright.config.ts's testIgnore). Without them every consumer lists
#               `tests/_demo/…` files Playwright never runs — the bug this arm was widened for.
#               Comment lines are dropped before matching, so a mention in prose cannot pass it.
#       Arm 3 — no OTHER file re-derives the walk. ADJACENCY is the anchor, as in 9j, and the
#               exact anchor point was found by RUNNING the check, not by designing it. The
#               obvious symbol — a manifest directory immediately followed by a shell
#               interpolation, `route-manifests/${...}` — false-FAILED on THREE live sites on
#               its first real run: coverage.sh's new dim-0 message, which QUOTES the missing
#               path back to the reader, and doctor.sh itself (both the template and the
#               stamped copy) because THIS COMMENT contains the shape. A symbol that fires on
#               its own documentation is the check that gets deleted — the property 9bb and 9bd
#               are each built around. So the anchor is the whole CONSTRUCT, not the mention:
#               an existence TEST on a manifest path built from a variable
#               (`-f "artifacts/route-manifests/${...}`), which is the walk itself and cannot
#               be prose. Check 12's `${mf#artifacts/route-manifests/}` is a prefix STRIP (the
#               `${` comes first) and was never a match either way.
#               Then the tightened symbol false-FAILED on doctor.sh — because THESE COMMENT
#               LINES spell it out. That recursion is the general property, not a quirk of this
#               check: an ownership check has to name the construct it bans, so it will always
#               match its own documentation unless it looks at CODE. So arm 3 drops full-line
#               comments before matching. A mention parked in a TRAILING comment would still
#               trip it; that is the deliberate direction, and the escape is to put the mention
#               on its own comment line — which is where documentation lives anyway.
#               Re-measured after both fixes: exactly one live site, spec-links.sh, the owner.
if [ -f scripts/spec-links.sh ]; then
  sl_arm=$(awk '/^[[:space:]]*unmanifested\)/{f=1} f{print} f&&/^[[:space:]]*;;/{exit}' scripts/spec-links.sh | sed '/^[[:space:]]*#/d')
  sl_walk=$(awk '/^collected_tests\(\)/{f=1} f{print} f&&/^}/{exit}' scripts/spec-links.sh | sed '/^[[:space:]]*#/d')
  if [ -z "$sl_arm" ]; then
    echo "❌ scripts/spec-links.sh has no \`unmanifested)\` arm — /qa-warden:impact's ### BLIND SPOTS and /qa-warden:coverage dim 0 both call it; without it impact reports a zero-match as if it were exhaustive and coverage re-labels every unmanifested test's routes as 'planned, untested'"
    fail=$((fail+1))
  elif [ -z "$sl_walk" ]; then
    echo "❌ scripts/spec-links.sh has no collected_tests() walk — the stamp predates the shared test inventory (\`tests\` / \`specs\` / \`smoke\`), so doctor Checks 3/9l/13/15/15b/16/17 saw an EMPTY suite and /qa-warden:coverage refuses. Run /qa-warden:init --resync, then re-run /qa-warden:doctor"
    fail=$((fail+1))
  elif ! printf '%s\n' "$sl_walk" | grep -qF -e '(*.metamorphic)' || ! printf '%s\n' "$sl_arm" | grep -q '= twin'; then
    echo "❌ scripts/spec-links.sh \`unmanifested\` no longer excludes *.metamorphic.spec.ts — a twin never carries a manifest by design (verifier V4 emits one per SPEC), so every twin now reports as a blind spot in /qa-warden:impact and as an UNMANIFESTED warning in /qa-warden:coverage dim 0"
    fail=$((fail+1))
  elif ! printf '%s\n' "$sl_walk" | grep -qF -e "! -name '_*'" || ! printf '%s\n' "$sl_walk" | grep -qF -e "! -path '*/_*/*'"; then
    echo "❌ scripts/spec-links.sh collected_tests() no longer excludes \`_\`-prefixed scratch specs in both forms (\`! -name '_*'\` and \`! -path '*/_*/*'\`, playwright.config.ts's testIgnore) — /qa-warden:impact, /qa-warden:coverage, post-run-checks.sh and doctor now count tests Playwright never runs"
    fail=$((fail+1))
  fi
fi
# Arm 3 — scan the plugin's own tree plus the project's scripts/ for a re-derived walk.
# `-e` is MANDATORY here and is not style: this pattern BEGINS WITH `-f`, so passed positionally
# it is consumed as grep's own `-f FILE` option. Caught by running the check — the error went to
# the `2>/dev/null` the scan needs for absent dirs, arm 3 produced no output for ANY input, and it
# read as permanently clean. A check that cannot fail is the false-green this toolkit exists to
# catch; it was wearing a passing baseline at the time. (Reproduced on ugrep, which names the
# option in its error; GNU/BSD grep swallow it the same way.)
umw_re='-f[[:space:]]*"artifacts/route-manifests/\$\{'
# File list, not `grep -rl`: each candidate is filtered through `sed` first. `bin/` is listed
# explicitly because qa-scaffold is EXTENSIONLESS (the §6 note) and a `*.sh` glob misses it.
UMW_PLUG=$([ -n "$TMPL" ] && cd "$TMPL/.." 2>/dev/null && pwd)   # resolve, as Check 9j does, so a
# reported path reads `qa-warden/skills/...` and not `qa-warden/templates/../skills/...`.
umw_files=$({ [ -n "$UMW_PLUG" ] && find "$UMW_PLUG" -name '*.sh' -type f 2>/dev/null
              [ -n "$UMW_PLUG" ] && [ -d "$UMW_PLUG/bin" ] && find "$UMW_PLUG/bin" -type f 2>/dev/null
              find scripts -name '*.sh' -type f 2>/dev/null
            } | sort -u)
umw_bad=0
for f in $umw_files; do
  case "$f" in */spec-links.sh) continue ;; esac
  sed '/^[[:space:]]*#/d' "$f" 2>/dev/null | grep -qE -e "$umw_re" || continue
  echo "❌ ${f#"${UMW_PLUG%/*}/"} builds a route-manifest path from a variable — the unmanifested walk is owned by \`scripts/spec-links.sh unmanifested\` (see its header rule 3). A second copy drifts silently: the twin exclusion is the half that is invisible when it is wrong, and /qa-warden:impact and /qa-warden:coverage must report the SAME invisible-spec set or one of them is quietly claiming a complete answer"
  umw_bad=$((umw_bad+1))
done
fail=$((fail+umw_bad))

# 9l. `test lock:` PAIRING + shard voidance. Playwright 1.63 added `lock?: string | string[]` to
#     `TestDetails`, the first cross-file mutual-exclusion primitive the runner has ever shipped,
#     and reviewer Check 13's cross-FEATURE bullet now offers it as a narrower fix than pinning a
#     whole lane. It is a hand-mirrored cross-file STRING with no runtime signal of its own — the
#     9b/9bb/9be/8 shape — so it gets the deterministic half here and the judgment half there.
#     Both arms key on SYMBOLS (the lock literal; the shard flag), never on wording, and both
#     scan CODE — full-line comments are dropped first, because an ownership check that reads
#     comments false-FAILs on its own documentation (the 9k lesson).
#
#     Arm 1 — a lock name occurring at exactly ONE site under tests/** is SILENTLY INERT. A lock
#       excludes the holder from every OTHER group that wants the same name; with no second
#       declaration there is nothing to exclude, so the suite races exactly as it did before and
#       every oracle still passes. Measured on a fixture at 1.63.0, not reasoned: a pair sharing
#       `lock:'seed:user2'` across two files never overlapped, while a third test holding a lock
#       nobody else names overlapped both. That is session 9's non-firing `fault:` glob again,
#       and it is why the cross-FEATURE case is the dangerous one — the CONSUMER side carries the
#       name for no reason of its own, so it is the side a typo or a later edit drops.
#       Counted per SITE, not per FILE: two same-lock tests in ONE file DO exclude each other
#       under `fullyParallel` (each top-level test is its own group — verified on the same
#       fixture), so a file-granular count would FAIL a pairing that genuinely holds.
#     Arm 2 — locks + SHARDING is a void remedy. `filterForShard` splits the ordered group list
#       by test count and never consults `group.locks`, so a lock-sharing pair straddles a shard
#       boundary and the two shards run as separate processes with no shared lock table.
#       Demonstrated: one filler spec was enough to push a lock-sharing pair into different
#       shards, and running both shards concurrently put them back in overlap. Nothing in the
#       suite can re-pin them — so once a project shards, the ONLY shard-safe answer is the one
#       Check 13 still lists first, folding the contention into ONE file's serial `describe`.
if [ -n "$TEST_FILES" ]; then
  # `-e` on every pattern below (the 9k lesson): a pattern passed positionally that begins with
  # a dash is eaten as an option and the arm goes silently dead behind a clean baseline.
  lock_sites=$(for f in $TEST_FILES; do
    sed '/^[[:space:]]*\/\//d' "$f" 2>/dev/null \
      | grep -oE -e "lock:[[:space:]]*(\[[^]]*\]|'[^']*'|\"[^\"]*\")" \
      | grep -oE -e "'[^']*'|\"[^\"]*\"" \
      | tr -d "\"'" \
      | sed -e "s|^|${f}	|"
  done)
  if [ -n "$lock_sites" ]; then
    lock_names=$(printf '%s\n' "$lock_sites" | cut -f2- | sort -u)
    while IFS= read -r lname; do
      [ -z "$lname" ] && continue
      lcount=$(printf '%s\n' "$lock_sites" | cut -f2- | grep -cxF -e "$lname")
      [ "$lcount" -ge 2 ] && continue
      lwhere=$(printf '%s\n' "$lock_sites" | grep -F -e "	$lname" | cut -f1 | head -1)
      echo "❌ lock '$lname' is declared at exactly ONE site ($lwhere) — a singleton lock is SILENTLY INERT (it has no counterpart to exclude, so the pair races exactly as it did before and every oracle still passes). Declare the same name on the other side of the contention — for the cross-FEATURE case that is the CONSUMER spec, which carries it for no reason of its own — or drop it and fold the contention into one file's serial describe (reviewer Check 13)"
      fail=$((fail+1))
    done < <(printf '%s\n' "$lock_names")
    lock_shard=$(for wf in .github/workflows/*; do
      [ -f "$wf" ] || continue
      case "$wf" in (*.example) continue ;; esac
      sed -e '/^[[:space:]]*#/d' "$wf" 2>/dev/null | grep -qE -e '--shard|^[[:space:]]*shard:' && echo "$wf"
    done | head -1)
    if [ -n "$lock_shard" ]; then
      echo "❌ tests/** declares \`test lock:\` but $lock_shard shards the run — locks are SHARD-BLIND (filterForShard splits the ordered group list by test count and never reads group.locks), so a lock-sharing pair lands in whatever shards its position dictates and the two shard PROCESSES hold no common lock table. The mutual exclusion silently stops holding for anyone following this recipe: either drop the sharding, or use the shard-safe fix reviewer Check 13 lists first — fold the contention into ONE file's serial describe"
      fail=$((fail+1))
    fi
  fi
fi

# 10. Site-id ↔ config-project routing (F-51: a site declared in app.context.md with no matching
#     playwright.config project — specs target a phantom site and silently run zero tests; renumbered
#     from the old "F-15" tag, which collided with the last-run-staleness F15 in check 1 above — the
#     hyphen was the only disambiguator between two DIFFERENT findings) — the toolkit's OWN green-but-empty class, at the
#     config layer. The generator ALWAYS emits `@site:<id>`; playwright.config.ts routes only the
#     project names it declares. A hot-tier sites[].id with NO matching config project → its specs
#     match no project → run in ZERO project = silently green-but-empty (a whole site never tested,
#     every gate green). `/qa-warden:explore` can pick a descriptive id (`shop`).
#     The config DERIVES every non-`app` project from the environment (derivedSiteProjects() in
#     playwright.config.ts): a set BASE_URL_<SITE> registers project <site> = <SITE> lowercased,
#     `_` → `-`. It used to tell the user to hand-add the project instead, but playwright.config.ts
#     is toolkit-owned — Check 9 flagged the edit as drift and --resync deleted it, so this check
#     and Check 9 sent the user round in a loop. So this check now holds each sites[] entry to the
#     derivation rule instead of grepping the config for a `name:`:
#       ❌ the id is not lowercase [a-z0-9-] (no BASE_URL_<SITE> can produce it), or its
#          base_url_env is not BASE_URL_<ID> (the config never reads that var for a project);
#       ⚠️ BASE_URL_<ID> is unset or empty after loading .env — no project this run (CI may set it).
#     `app` is exempt: its project is always registered (BASE_URL_APP → BASE_URL fallback).
CTXH=specs/_context/app.context.md
if [ -f "$CTXH" ] && [ -f playwright.config.ts ]; then
  # One `id<TAB>base_url_env` row per `- id:` entry (base_url_env empty when the entry has none).
  # A row starts on ANY `- id:` line, quoted or not: keying on an unquoted value let a quoted
  # `- id: "shop"` slip past, so its base_url_env overwrote the PREVIOUS entry's (a false ❌ on
  # that site, and shop never checked). Values keep every character up to whitespace or `#`
  # once the quotes are stripped, so an invalid id is reported as written rather than truncated.
  # The quote class comes in through -v: a `'` cannot appear inside this single-quoted program.
  site_rows=$(awk -v q="\"'" '
    function bare(v) {
      gsub("[" q "]", "", v)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]#].*$/, "", v)
      return v
    }
    /^[[:space:]]*-[[:space:]]*id:/ {
      if (have) print id "\t" envname
      id = $0
      sub(/^[[:space:]]*-[[:space:]]*id:/, "", id)
      id = bare(id)
      envname = ""
      have = 1
      next
    }
    have && /^[[:space:]]*base_url_env:/ {
      envname = $0
      sub(/^[[:space:]]*base_url_env:/, "", envname)
      envname = bare(envname)
    }
    END { if (have) print id "\t" envname }
  ' "$CTXH")
  while IFS="$(printf '\t')" read -r sid senv; do
    [ -z "$sid" ] && continue
    [ "$sid" = app ] && continue
    canon=$(printf '%s' "$sid" | tr 'A-Z_' 'a-z-')
    want="BASE_URL_$(printf '%s' "$canon" | tr 'a-z-' 'A-Z_')"
    if [ "$canon" = setup ]; then
      echo "❌ site id '$sid' is reserved — playwright.config.ts already has a 'setup' project (the auth setup), so it never derives a site project of that name and specs tagged @site:$sid run in NO project; rename the site in $CTXH and in its specs' site: fields"
      fail=$((fail+1))
    elif ! printf '%s' "$sid" | grep -qE -e '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      if printf '%s' "$canon" | grep -qE -e '^[a-z0-9]+(-[a-z0-9]+)*$'; then
        echo "❌ site id '$sid' cannot match a playwright.config.ts project — projects are derived from BASE_URL_<SITE> as lowercase with '-' for '_' (so $want → '$canon'), and specs tagged @site:$sid run in NO project (silent green-but-empty); rename the id to '$canon' in $CTXH and in its specs' site: fields"
      else
        echo "❌ site id '$sid' cannot match a playwright.config.ts project — a site id must be lowercase letters and digits in '-'-separated words (e.g. 'shop', 'admin-portal'), the only names derived from BASE_URL_<SITE>; specs tagged @site:$sid run in NO project (silent green-but-empty). Rename it in $CTXH and in its specs' site: fields"
      fi
      fail=$((fail+1))
    elif [ "$senv" != "$want" ]; then
      echo "❌ site '$sid' declares base_url_env: ${senv:-<none>}, but playwright.config.ts registers the '$sid' project only from $want — specs tagged @site:$sid run in NO project (silent green-but-empty); set base_url_env: $want in $CTXH and use that var name in .env"
      fail=$((fail+1))
    elif [ -z "$(printenv "$want")" ]; then
      echo "⚠️  site '$sid': $want is unset or empty after loading .env, so playwright.config.ts registers no '$sid' project and specs tagged @site:$sid run in NO project this run — set $want to the site's staging/QA URL (fine to ignore if CI supplies it)"
      warn=$((warn+1))
    fi
  done < <(printf '%s\n' "$site_rows")
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
  # The copied bugs/<slug>/trace.zip is LOCAL evidence only. A Playwright trace stores the
  # browser context options (the httpCredentials password, the extraHTTPHeaders values), every
  # fill() value and the Cookie/Authorization headers in plain text. templates/gitignore ignores
  # `bugs/**/trace.zip`, but .gitignore is outside the resync set, so a project scaffolded before
  # that rule shipped only hears about it here. Read-only: git ls-files / check-ignore write nothing.
  if [ -n "$(find bugs -mindepth 2 -name trace.zip -type f 2>/dev/null | head -1)" ] \
     && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    tracked_traces=$(git ls-files -- 'bugs/*/trace.zip' 2>/dev/null | tr '\n' ' ')
    if [ -n "$tracked_traces" ]; then
      echo "⚠️  bug trace committed to git: ${tracked_traces% } — a trace holds credentials in plain text (basic-auth password, extra headers, typed values, cookies). Run: git rm --cached <each path>, add 'bugs/**/trace.zip' to .gitignore, and rotate any QA credential that was pushed"; warn=$((warn+1))
    fi
    if ! git check-ignore -q "bugs/qa-probe/trace.zip" 2>/dev/null; then
      echo "⚠️  bugs/<slug>/trace.zip is not gitignored — the next 'git add bugs/' commits credentials in plain text. Add 'bugs/**/trace.zip' to .gitignore (it ships in the template since 0.5.4)"; warn=$((warn+1))
    fi
  fi
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

# 12. Manifest staleness (F-08) — /qa-warden:impact trusts artifacts/route-manifests/<area>/<feature>.json
#     as its SOLE input; a spec edited AFTER its manifest was generated silently yields a stale
#     change→test map (the guards are all-or-nothing — zero manifests, or a compiled test with none
#     — never present-but-stale). WARN when a spec .md is newer than its manifest (regenerate via
#     /qa-warden:gen). Mirrors the safe-fallback: impact is an optimization, never the gate.
if [ -d artifacts/route-manifests ]; then
  while read -r mf; do
    rel=${mf#artifacts/route-manifests/}; spec="specs/${rel%.json}.md"
    [ -f "$spec" ] || continue
    [ "$spec" -nt "$mf" ] && { echo "⚠️  stale manifest: $spec is newer than $mf — /qa-warden:impact may miss its routes; re-run /qa-warden:gen"; warn=$((warn+1)); }
  done < <(find artifacts/route-manifests -name '*.json' -type f 2>/dev/null)
fi

# 13. Declared-mutating features must isolate (wires the basis test_data: block). WARN — the
#     reviewer's code-level Check 13 remains the enforcing gate; this catches the
#     declared-then-ignored gap. Test resolution mirrors /qa-warden:coverage dim 1 (LOCKSTEP): the
#     direct path tests/<feat>.spec.ts PLUS every fanned spec linking back via a top-level
#     `basis: <area>/<feature>` key, mapped spec→test by the inventory's <base> column
#     (scripts/spec-links.sh `tests`; a twin shares its spec's base). A mutating feature that
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
    # feature, and let scripts/spec-links.sh own the anchor — Check 18 and /qa-warden:coverage dims 1/5/6
    # need the identical trailing-comment tolerance, which has already needed one hand-applied
    # lockstep fix across those three sites.
  done < <(printf '%s\n' "$BASIS_LINKS" | bash scripts/spec-links.sh match "$feat")
  found=0
  for b in $bases; do
    # The collected tests whose base is $b — the spec and its twin, paired by the inventory
    # (TEST_INV column 2) rather than by re-typing the tests/<b>[.metamorphic].spec.ts join here.
    for t in $(printf '%s\n' "$TEST_INV" | awk -F'\t' -v b="$b" '$2 == b { print $1 }'); do
      found=$((found+1))
      grep -qE "parallelIndex|workerIndex|mode:[[:space:]]*[\"']serial[\"']|seeded[A-Z]|lock:[[:space:]]*[\"'[]" "$t" \
        || { echo "⚠️  $feat: basis declares mutates_server_state:true but $t shows no isolation marker (parallelIndex/serial/seed fixture/lock:) — un-isolated mutation is green at 1 worker, flaky at scale"; warn=$((warn+1)); }
    done
  done
  [ "$found" -eq 0 ] && { echo "⚠️  $feat: basis declares mutates_server_state:true but NO compiled test resolved (neither tests/${feat}.spec.ts nor any fanned spec via 'basis: ${feat}') — the mutating feature is never isolation-checked; compile it or fix the basis 'feature:' path"; warn=$((warn+1)); }
done < <(ctx_grep_l '^[[:space:]]*mutates_server_state:[[:space:]]*true')

# (The test and spec inventories Checks 15/15b consume — $TEST_INV / $SPEC_INV, with the
#  spec↔test pairing already joined — are hoisted to the top of the script, above Check 3.)

# 14. Unmanaged tests — see Check 4+14 above; scripts/post-run-checks.sh owns that scan.

# 15. Review attestation — for each spec with a compiled test, a reports/review/<area>/<feature>.reviewed
#     marker must exist, its recorded hashes must match the CURRENT spec+test, and the review it
#     records must not have FAILED. Markers are agent-writable convenience, not proof — the
#     anti-forgery layer is a human approving the PR (a required approval in branch protection);
#     this catches FORGOTTEN reviews, not malicious ones.
#     The marker's format is owned by the review skill's review-marker.sh, which wrote it: its
#     `check` mode answers current / stale / failed / missing for one pair. Doctor used to parse
#     the marker itself, with its own digest function (the two had drifted once) and without ever
#     reading `result:`, so a FAILED review passed as attested. The script ships in this plugin:
#     <plugin>/skills/doctor/scripts/doctor.sh -> <plugin>/skills/review/scripts/review-marker.sh.
REVIEW_MARKER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/review/scripts/review-marker.sh"
if [ ! -f "$REVIEW_MARKER" ]; then
  echo "⚠️  the plugin's review-marker.sh was not found at $REVIEW_MARKER — review attestation (Check 15) is UNVERIFIED (run doctor from the plugin: /qa-warden:doctor)"; warn=$((warn+1))
else
  while IFS=$'\t' read -r spec base t smoke basis; do
    [ -n "$spec" ] || continue
    [ "$t" = - ] && continue
    # stdout ONLY: the answer is one word there. Folding stderr in let any noise from the shell
    # itself (a setlocale warning under an LC_ALL that names a missing locale) turn every
    # reviewed pair into "could not be checked".
    review_state=$(bash "$REVIEW_MARKER" check "$spec" "$t" 2>/dev/null)
    case "$review_state" in
      current) : ;;
      stale|missing)
        echo "⚠️  ${base}: changed since last review (or never reviewed) — re-run /qa-warden:review"; warn=$((warn+1)) ;;
      failed)
        echo "⚠️  ${base}: reviewed, FAILED — fix and re-run /qa-warden:review"; warn=$((warn+1)) ;;
      *)
        # Not an answer, so the script refused. It is read-only: run it again for its reason,
        # the last `review-marker:` line of its stderr.
        review_why=$(bash "$REVIEW_MARKER" check "$spec" "$t" 2>&1 >/dev/null | grep '^review-marker:' | tail -1)
        echo "⚠️  ${base}: review attestation could not be checked: ${review_why:-review-marker.sh gave no answer}"; warn=$((warn+1)) ;;
    esac
  done < <(printf '%s\n' "$SPEC_INV")
fi
# 15b. Stale verified-comment — a `// verified: must_fail_when "<text>"` stamp in a test whose
#      captured text no longer appears in the paired spec means the invariant was edited/removed
#      AFTER verification; the stamp attests a probe of an invariant that no longer exists.
#      (Portable grep+sed spelling of `rg -o '…"([^"]+)"' -r '$1'` — doctor guarantees only grep/sed.)
while IFS=$'\t' read -r t base kind spec mf; do
  [ -n "$t" ] || continue
  [ "$spec" = - ] && continue
  while IFS= read -r vtxt; do
    [ -n "$vtxt" ] || continue
    grep -qF "$vtxt" "$spec" \
      || { echo "⚠️  ${base}: test carries // verified: must_fail_when \"$vtxt\" but that text is not in $spec — the invariant changed since verification; re-run --verify-invariants or update the stamp"; warn=$((warn+1)); }
  done < <(grep -o '// verified: must_fail_when "[^"]*"' "$t" 2>/dev/null | sed 's/.*must_fail_when "\(.*\)"/\1/')
done < <(printf '%s\n' "$TEST_INV")

# 16. Smoke-tagged spec with NO compiled test (RUN-27) — the smoke-gate-blind catch. Check 3 above
#     confirms SOME test carries @smoke so `--grep @smoke` isn't vacuous; this is the complementary
#     gap: a SPEC that declares a `tags: [smoke, …]` scenario but was never compiled to a test. The
#     spec author put a P1 flow on the fast gate (the smoke-lane rule), but with no .spec.ts the
#     `--grep @smoke` run selects nothing for it — a fully-broken governed flow (admin RBAC, checkout
#     charge==total) passes the nightly smoke gate silently because there's simply no test to fail.
#     The smoke column comes from the ONE tag parser (scripts/spec-links.sh rule 5): the YAML `tags:`
#     key in its inline, per-scenario (`scenarios: [{ …, tags: [smoke] }]`) and block-list forms —
#     the machine-authored tag, not a prose `@smoke` mention. The old line-leading-only regex missed
#     the per-scenario form the test-case contract REQUIRES for a multi-scenario spec, so exactly
#     the specs that follow the smoke-lane rule fell through to Check 17's weaker message.
#     Resolution mirrors Check 15: direct tests/<base>.spec.ts (twins never carry smoke).
while IFS=$'\t' read -r spec base t smoke basis; do
  [ "$smoke" = smoke ] || continue
  [ "$t" = - ] || continue                                          # compiled → on the gate, fine
  # fanned: a sibling spec may own the compiled test via a `basis: <area>/<feature>` back-link
  # (the inventory's basis column, cut at the same boundary `spec-links.sh match` anchors on)
  if [ "$basis" != - ] && [ -n "$(printf '%s\n' "$TEST_INV" | awk -F'\t' -v b="$basis" '$2 == b && $3 == "spec"')" ]; then continue; fi
  echo "⚠️  smoke-tagged spec with no compiled test: $spec declares 'tags: [… smoke …]' but tests/${base}.spec.ts does not exist — /qa-warden:run mode=smoke's --grep @smoke is BLIND to this P1 flow; compile it with /qa-warden:gen or drop the smoke tag"; warn=$((warn+1))
done < <(printf '%s\n' "$SPEC_INV")

# 17. Spec authored but NEVER compiled (ANY tag) — the complement to Check 16 (F-026). Check 16
#     catches the @smoke subset with a stronger gate-blind message; a @regression-only spec that
#     was authored but never generated to a .spec.ts escapes Check 15 (which `continue`s when the
#     test is absent) AND Check 16 (smoke-only), so it sits outside the assertion contract and no
#     run — smoke OR full — ever exercises it. Every spec compiles to tests/<same-basename>.spec.ts
#     (CLAUDE.md file-layout rule); a `basis:` back-link only names the spec's ideation SOURCE
#     (its .cases.md), NOT where its tests live — so it is deliberately NOT treated as coverage
#     here (that over-lenient skip is exactly what let a fanned sibling like session-guard.md
#     escape). Skip @smoke-tagged specs: Check 16 already reports them, don't double-warn.
while IFS=$'\t' read -r spec base t smoke basis; do
  [ -n "$spec" ] || continue
  [ "$t" = - ] || continue
  [ "$smoke" = smoke ] && continue                # smoke → Check 16 owns it (same inventory row)
  echo "⚠️  spec with no compiled test: $spec has no tests/${base}.spec.ts (any tag) — authored but never generated, so it is outside the assertion contract and no run exercises it. Run /qa-warden:gen on it; or if its scenarios are intentionally folded into a sibling spec, /qa-warden:retire it or add a '# waived:' note"; warn=$((warn+1))
done < <(printf '%s\n' "$SPEC_INV")

# 18. Abandoned authoring chain — a `.cases.md` (the human-approval artifact) with NO downstream
#     spec (F-026). The intake→ideate→approve chain ran (a checklist exists) but /qa-warden:new-spec/gen
#     never produced a spec, so the intended coverage silently never shipped and nothing else in
#     doctor sees it. Feature key = the path minus the `_context/<site>/` prefix and `.cases.md`
#     suffix — the same `<area>/<feature>` a fanned spec's `basis:` back-link uses.
while read -r cases; do
  feat=$(printf '%s' "$cases" | sed -E 's#^specs/_context/[^/]+/##; s#\.cases\.md$##')
  [ -f "specs/${feat}.md" ] && continue                                          # spec exists → chain completed
  [ -n "$(printf '%s\n' "$BASIS_LINKS" | bash scripts/spec-links.sh match "$feat")" ] && continue   # a fanned spec back-links it (hoisted index, canonical anchor — same call as Check 13)
  echo "⚠️  abandoned authoring chain: ${cases} has no downstream spec (specs/${feat}.md absent, no spec back-links 'basis: ${feat}') — the approved checklist never became a spec; run /qa-warden:new-spec ${feat} or /qa-warden:retire the chain"; warn=$((warn+1))
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
      echo "⚠️  unattested interview: $basis has [human-answered] oracle rules but interview: '${iv:-<absent>}' — the human grounding is unattested (a fabricated basis looks identical); /qa-warden:intake should stamp the real question count"; warn=$((warn+1)) ;;
  esac
done < <(printf %s\\n "$CTX_FILES" | grep -e "\\.basis\\.md$")

# 20 — MOVED to bin/qa-selfcheck (plugin-side guard on the agents' and skills' .env handling; see the MOVED note above Check 9c).

# 21. Fresh-project readiness verdict (F-025) — a brand-new project trips several checks as WARNs
#     purely because nothing is authored yet (no app.context.md, 0 specs), so "OK with warnings"
#     reads as "something's wrong" when the honest state is "expected at this stage". Name it and
#     point at the next step so a newcomer knows setup is healthy.
# 21a. Unconfigured target — BASE_URL_APP still empty or a placeholder (the shipped .env.example
#      ships `BASE_URL_APP=CHANGEME`). Without this, a freshly scaffolded project whose .env was
#      copied but never edited got the "Setup looks healthy" verdict below, and the first real
#      command then STOPped on prod-guard. The placeholder test is NOT re-typed here: doctor runs
#      scripts/prod-guard.sh itself in its default mode (offline — only `--probe` touches the
#      network; the default mode screens strings and exits) and keeps only its empty/placeholder
#      REFUSING lines, so the CHANGEME / <…> / example.com|net|org / *.example sentinels stay
#      single-sourced in prod-guard (and its .ts lockstep twin). Prod-marker refusals are
#      deliberately NOT surfaced here: QA_ALLOW_PROD is a per-command override, so doctor cannot
#      tell a deliberate prod target from a mistake. Empty QA_USER_* is NOT checked either — a
#      site with no login legitimately has none. WARN, not FAIL: nothing is wrong with the
#      substrate, but nothing can run until .env names a real staging/QA host.
tgt_unset=0
if [ -f scripts/prod-guard.sh ]; then
  tgt_lines=$(sh scripts/prod-guard.sh 2>/dev/null | grep -E -e '^REFUSING: (BASE_URL_APP is empty|[A-Z0-9_]+ is a placeholder)')
  if [ -n "$tgt_lines" ]; then
    tgt_unset=1
    printf '%s\n' "$tgt_lines" | while IFS= read -r l; do
      echo "⚠️  .env target not configured — ${l#REFUSING: } (scripts/prod-guard.sh refuses this, so every run/explore command will STOP until it is fixed)"
    done
    warn=$((warn+$(printf '%s\n' "$tgt_lines" | wc -l | tr -d ' ')))
  fi
fi
# (21, continued) The readiness verdict itself — withheld while 21a found an unconfigured target,
#      because "Setup looks healthy" over a CHANGEME .env is exactly the false-green 21a closes.
if [ ! -f specs/_context/app.context.md ] && [ "$fail" -eq 0 ]; then
  if [ "$tgt_unset" -eq 1 ]; then
    echo "ℹ️  fresh project — no app.context.md / specs yet, so the context/spec/interview checks are n/a at this stage (not failures). Setup is NOT ready yet — fill in .env (see the ⚠️ above), then run /qa-warden:explore to build the context layer."
  else
    echo "ℹ️  fresh project — no app.context.md / specs yet, so the context/spec/interview checks are n/a at this stage (not failures). Setup looks healthy — next run /qa-warden:explore to build the context layer."
  fi
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
