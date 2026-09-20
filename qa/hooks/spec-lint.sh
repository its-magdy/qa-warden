#!/usr/bin/env bash
# spec-lint.sh — PreToolUse gate on writes into tests/** and page-objects/**.
#
# Denies the reviewer FAILs that are decidable from the proposed text ALONE, with no
# repository context, no paired spec, and no judgment — five patterns across four checks:
#
#   reviewer Check 1   assertion on a literal        (expect(true).toBe(true) — cannot fail)
#   reviewer Check 5   page.waitForTimeout / networkidle
#   reviewer Check 9   raw CSS/XPath locators
#   reviewer Check 11  .only() markers, and routeFromHAR (HAR replay)
#
# Everything else in the reviewer stays with the reviewer. See hooks/README.md §"What is
# NOT hooked" for the per-check reasoning — in particular Check 11's credential regex,
# which reviewer.md itself documents as false-FAILing valid specs when run deterministically.
#
# This is a SUBSET gate, not a replacement gate. It moves the catch from PR time to write
# time for the cases where being early is free. The reviewer is still the backstop.

set -uo pipefail
. "$(dirname "$0")/hook-lib.sh" || exit 0

hook_escape_hatch
hook_require_jq

input=$(cat) || exit 0
[ -n "$input" ] || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool" in Edit|Write) : ;; *) exit 0 ;; esac

fp=$(printf '%s' "$input"  | jq -r '.tool_input.file_path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
abs=$(hook_abs_path "$fp" "$cwd") || exit 0

# TypeScript sources only. `.d.ts` is a declaration file — no test code, no locators.
case "$abs" in *.d.ts) exit 0 ;; *.ts) : ;; *) exit 0 ;; esac
hook_qa_root "$abs" >/dev/null || exit 0

# Scan only what is being ADDED. On an Edit that is `new_string`, never the whole file:
# denying on a pre-existing violation elsewhere in the file would make an unrelated,
# correct edit unblockable — the agent would have no way forward except to bypass.
if [ "$tool" = "Write" ]; then
  payload=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
else
  payload=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi
[ -n "$payload" ] || exit 0

# Strip comments before scanning. The generated specs are heavily commented and the comments
# legitimately NAME the banned constructs ("web-first assertion instead of networkidle",
# "// covers oracle: …"), so a raw grep would deny the generator for documenting the rule it
# is following. Full-line comments become blank; a trailing `//` comment is cut, but only when
# the slashes are not preceded by `:` so that `https://` inside a string survives intact.
clean=$(printf '%s\n' "$payload" | awk '
  { s = $0; sub(/^[ \t]+/, "", s)
    if (s ~ /^(\/\/|\*|\/\*)/) { print ""; next }
    if (match($0, /[^:]\/\/.*$/)) { print substr($0, 1, RSTART) } else { print $0 }
  }') || exit 0

# report <check> <fix> — prints the first offending line and denies.
report() {
  local line
  line=$(printf '%s' "$3" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c1-200)
  hook_deny "QA toolkit — blocked by reviewer $1 (PreToolUse hook).

Offending line in the proposed write to ${abs##*/}:
    $line

$2

This is a reviewer FAIL, so the write would be blocked at PR review anyway; the hook only
moves the catch earlier. To disable this layer for the session, set QA_HOOKS_OFF=1 in Claude Code's own
environment or in .claude/settings.json's "env" block (a hook never reads the project .env)."
}

first_match() { printf '%s\n' "$clean" | grep -nE "$1" | head -1; }

# --- Check 5: raw sleeps and networkidle ----------------------------------------------
hit=$(first_match 'page\.waitForTimeout[[:space:]]*\(')
[ -n "$hit" ] && report "Check 5 (no raw sleeps)" \
  "Replace the sleep with a web-first assertion that resolves on the actual post-condition,
e.g. await expect(page).toHaveURL(/…/) or await expect(page.getByRole('alert')).toBeVisible().
A timeout OPTION is fine: expect(...).toBeVisible({ timeout: 10_000 })." "${hit#*:}"

hit=$(first_match 'networkidle')
[ -n "$hit" ] && report "Check 5 (networkidle is banned)" \
  "networkidle is a top flake source and is banned toolkit-wide (healer, visual-regression,
eslint-plugin-playwright/no-networkidle, Biome noPlaywrightNetworkidle). Settle on the real
post-condition instead. Bare await page.waitForLoadState() — no argument — is allowed." "${hit#*:}"

# --- Check 9: locator policy ------------------------------------------------------------
# The chained form is the one a `page.locator(`-only grep misses: getByRole('row').locator('.price')
# is still raw CSS. The only unflagged `.locator(...)` argument is another Locator object, so the
# test is "does the first argument open with a quote or backtick".
hit=$(first_match "page\.locator[[:space:]]*\(|page\.\\\$\\\$?[[:space:]]*\(|xpath=|\.locator[[:space:]]*\([[:space:]]*['\"\`]")
[ -n "$hit" ] && report "Check 9 (locator policy)" \
  "Raw CSS/XPath is not an allowed locator anywhere under tests/ or page-objects/. The allowed
factories are getByRole, getByText, getByLabel, getByPlaceholder, getByAltText, getByTitle and
getByTestId — in that priority order, with getByTestId as the escape hatch. Page objects holding
raw CSS is the exact anti-pattern that makes a POM layer rot." "${hit#*:}"

# --- Check 11: .only markers ------------------------------------------------------------
hit=$(first_match '\b(test|describe|it)\.only[[:space:]]*\(')
[ -n "$hit" ] && report "Check 11 (no .only markers)" \
  "A .only() marker silently narrows the whole suite to one test — the #1 way a green CI run
means nothing. Remove it; select with --grep or a project filter instead." "${hit#*:}"

# --- Check 11: HAR replay ----------------------------------------------------------------
# A suite served from a recorded HAR asserts the frontend against a FROZEN backend: it stays
# green through every server-side regression, which inverts the one promise the nightly replay
# makes. Purely lexical and admits no legitimate use anywhere under tests/ or page-objects/,
# so it clears the same bar as the four above. `page.route()` is NOT banned — a declared
# `fault:` step compiles to one, and the verifier's step-8b probe uses one.
hit=$(first_match '\.routeFromHAR[[:space:]]*\(')
[ -n "$hit" ] && report "Check 11 (no HAR replay)" \
  "Replaying from a recorded HAR tests the frontend against a frozen backend — the suite stays
green through every server-side regression, which is the opposite of what the nightly replay is
for. To stub ONE dependency, have the planner declare a fault: step in the spec (CLAUDE.md
section 'Situation steps'); it compiles to a narrow page.route with a mandatory fired-proof." "${hit#*:}"

# --- Check 1: assertion on a literal ----------------------------------------------------
# expect(true).toBe(true) / expect(1).toEqual(1): the asserted value is a constant in the test
# file, so no behaviour of the application under test can ever make it fail.
hit=$(first_match 'expect[[:space:]]*\([[:space:]]*(true|false|-?[0-9]+)[[:space:]]*\)[[:space:]]*\.[[:space:]]*(not\.)?(toBe|toEqual|toStrictEqual|toBeTruthy|toBeFalsy)')
[ -n "$hit" ] && report "Check 1 (at least one expect that can fail)" \
  "This asserts a constant against a constant — nothing the application does can make it fail,
so it is a green-but-empty test. Assert on a locator or a value read from the app." "${hit#*:}"

exit 0
