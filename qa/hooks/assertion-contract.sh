#!/usr/bin/env bash
# assertion-contract.sh — PreToolUse gate on the two agents that are forbidden to touch
# an assertion: the HEALER and the VERIFIER.
#
# This is the one hook that guards the moat rather than a lint rule.
#
#   healer.md  ("Assertion contract is sacred", and §"Never change the assertion contract"):
#     the healer patches selectors and waits. It may NOT change which matcher is called
#     (toHaveText -> toContainText, anything -> toBeVisible), may not flip a .not, may not
#     retype an expected string, number or regex, and may not drop an assertion. Both
#     directions are silent-false-pass: a matcher swap guts what the test proves while
#     leaving every string and locator intact, and retyping the expected string to whatever
#     the app now says is the changed-text bucket — escalate, never patch.
#
#   verifier.md Hard rule 1: the verifier may NOT edit any expect(...), locator, matcher or
#     asserted value in the parent spec — "not to fix a mis-wire, not to make the probe land,
#     not to strengthen a weak oracle". Author-independence is the entire reason the agent
#     exists; an edit here silently re-merges the two halves the generator split created.
#
# Both rules were prose-only until this hook. Both are decidable from the edit alone.
#
# A THIRD prohibition rides here because it has the same shape and the same scope: the healer
# may not INTRODUCE a network stub or a fake-clock call (healer.md §"Anti-drift rule"). Both are
# ways to make a red test green without touching a single assertion, so the subset test below
# cannot see either of them:
#   page.route(...)  - a genuinely broken backend is the most valuable signal the nightly
#                      produces; stubbing it green converts a real outage into a test that
#                      passes forever.
#   page.clock.*     - runFor(2000) is a sleep that the waitForTimeout ban does not lexically
#                      catch, i.e. the cheapest green on a timing flake.
# Scoped to the HEALER ALONE, deliberately: the verifier's step-8b fault injection IS a
# page.route, so extending this arm to the verifier would deny the negative control that the
# whole oracle-defense layer rests on. Only an edit that ADDS one where the before-text had
# none is denied - healing a locator inside a scenario that legitimately declares a `fault:`
# step stays allowed.
#
# The test in both cases is SUBSET, not equality: every assertion present BEFORE the edit
# must still be present after it. Additions pass (the reviewer's orphan-assert arm of
# Check 2 handles those, and denying an addition would block the healer's sanctioned
# barrier asserts). Removals and rewrites are the weakening direction, and that is what
# gets denied. What "the same assertion" means differs per agent — see the normaliser below.

set -uo pipefail
. "$(dirname "$0")/hook-lib.sh" || exit 0

hook_escape_hatch
hook_require_jq

input=$(cat) || exit 0
[ -n "$input" ] || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool" in Edit|Write) : ;; *) exit 0 ;; esac

# Who is writing. `agent_type` is optional in the payload — when it is absent (the main
# thread, or a harness that stopped sending it) this hook does NOT fire. That is a real
# limitation, stated in hooks/README.md: this layer is defence in depth for two known
# agents, never the backstop. Strip any plugin namespace so `qa:healer` and `healer` both
# match, and lowercase so a display-name variant does not slip past.
agent=$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')
agent=${agent##*:}; agent=${agent##*/}
case "$agent" in healer|verifier) : ;; *) exit 0 ;; esac

fp=$(printf '%s' "$input"  | jq -r '.tool_input.file_path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
abs=$(hook_abs_path "$fp" "$cwd") || exit 0

case "$abs" in *.spec.ts) : ;; *) exit 0 ;; esac
case "$abs" in */tests/*) : ;; *) exit 0 ;; esac
hook_qa_root "$abs" >/dev/null || exit 0

# The verifier AUTHORS the metamorphic twins (its step 8a), so its own twin files are its
# to write freely. The healer still heals locators inside them, and the subset rule below
# is correct for that, so only the verifier is exempted here.
case "$abs" in
  *.metamorphic.spec.ts) [ "$agent" = "verifier" ] && exit 0 ;;
esac

# BEFORE and AFTER text. On a Write the "before" is the file already on disk — a full-file
# overwrite of an existing spec is exactly how an assertion disappears without an Edit ever
# being issued, so it is covered rather than waved through.
if [ "$tool" = "Write" ]; then
  [ -f "$abs" ] || exit 0
  before=$(cat "$abs" 2>/dev/null) || exit 0
  after=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
else
  before=$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
  after=$(printf '%s' "$input"  | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi
[ -n "$before" ] || exit 0

# --- the normaliser ------------------------------------------------------------------
#
# Both agents are judged on the same question — "is every assertion that existed before
# this edit still there after it?" — and differ only in what counts as "the same
# assertion". One awk pass produces both readings.
#
#   MASK=1 (healer)   the argument of expect(...) is replaced with `#`, so the LOCATOR is
#                     not part of the identity. Re-pointing a locator is the healer's job.
#   MASK=0 (verifier) nothing is masked. The verifier may not touch any part of an
#                     expect, locator and asserted value included.
#
# In both readings an options object — `{ timeout: 10_000 }` — is stripped before
# comparing, because widening a matcher's own timeout is the sanctioned alternative to
# inserting a sleep (healer.md step 5) and must not read as a rewrite.
#
# What survives masking is therefore: which matcher is called, in what order, with what
# asserted literal. That is exactly the surface healer.md §"Never change the assertion
# contract" forbids — matcher swaps and .not flips (its bullet 2) AND changed strings,
# ranges and regexes (its bullet 1). The matcher-only version of this hook caught the
# first and missed the second, which is the more common weakening: the app's wording
# drifts, and the cheapest green is to retype the expected string. That is the
# changed-text bucket — escalate to the planner, never patch.
#
# Paren-balance is counted naively, so a quoted string containing an unmatched paren
# leaves the line unmaskable. Those lines are DROPPED from both sides rather than compared
# unmasked, which would false-deny a legitimate locator heal. Fail-open, as everywhere here.
assertions() {
  local mask="$1"
  awk -v mask="$mask" '
    function maskexpects(s,   out, head, rest, depth, n, ch, ok) {
      out = ""
      while (match(s, /expect[.a-zA-Z]*\(/) > 0) {
        head = substr(s, RSTART, RLENGTH)
        out  = out substr(s, 1, RSTART - 1) head
        rest = substr(s, RSTART + RLENGTH)
        depth = 1; n = 0; ok = 0
        while (n < length(rest)) {
          n++; ch = substr(rest, n, 1)
          if (ch == "(") depth++
          else if (ch == ")") { depth--; if (depth == 0) { ok = 1; break } }
        }
        if (!ok) return ""            # unbalanced — drop the line
        out = out "#)"
        s = substr(rest, n + 1)
      }
      return out s
    }
    /expect[.a-zA-Z]*\(/ {
      line = $0
      if (mask == 1) { line = maskexpects(line); if (line == "") next }
      gsub(/,[ \t]*\{[^}]*\}/, "", line)     # trailing options object: toHaveText("x", { timeout })
      gsub(/\([ \t]*\{[^}]*\}[ \t]*\)/, "()", line)  # sole options arg: toBeVisible({ timeout })
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      gsub(/[ \t]+/, " ", line)
      if (line != "") print line
    }' | LC_ALL=C sort
}

if [ "$agent" = "verifier" ]; then
  lost=$(comm -23 <(printf '%s\n' "$before" | assertions 0) <(printf '%s\n' "$after" | assertions 0))
  rule="Hard rule 1 in agents/verifier.md — you may NOT edit any expect(...), locator, matcher or
asserted value in the parent spec. You did not choose them, and the whole reason you exist as an
agent separate from the generator is that you have no authorship to defend.

Hand it back instead:
  - a mis-compiled oracle (right intent, wrong expect)  -> the GENERATOR, with <file>:<line>
  - a decorative or under-specified oracle              -> the PLANNER
Record the invariant as BLIND and withhold the route manifest. Do not make the probe land."
else
  lost=$(comm -23 <(printf '%s\n' "$before" | assertions 1) <(printf '%s\n' "$after" | assertions 1))
  rule="agents/healer.md §\"Never change the assertion contract\" — you patch selectors and waits.
Changing WHICH matcher is called (toHaveText -> toContainText, anything -> toBeVisible), flipping a
.not, or dropping an assertion weakens the test while leaving every string, range and locator
untouched. That is the canonical silent-false-pass.

Re-point the locator instead, or widen the matcher's own timeout — both keep the contract. If the
assertion itself is now wrong, this is a contract-change or a product bug: classify it, file
bugs/<slug>.md, revert, and kick the oracle back to the planner."
fi

# --- healer-only: no NEWLY INTRODUCED network stub or fake clock ----------------------
# Counted, not merely grepped: the comparison is "more occurrences after than before", so an
# edit inside a scenario that already carries a declared `fault:` step is untouched, and only
# a net addition is denied. Comments are stripped first for the same reason spec-lint strips
# them - a spec may legitimately NAME the construct in a `// covers oracle:` narration.
if [ "$agent" = "healer" ]; then
  strip_comments() {
    awk '{ s = $0; sub(/^[ \t]+/, "", s)
           if (s ~ /^(\/\/|\*|\/\*)/) { print ""; next }
           if (match($0, /[^:]\/\/.*$/)) { print substr($0, 1, RSTART) } else { print $0 } }'
  }
  n_occurrences() { printf '%s\n' "$1" | strip_comments | grep -cE "$2" || true; }

  # Two probes, spelled out rather than looped over packed "regex:label" strings: every
  # obvious delimiter is already a regex metacharacter here, and `[[:space:]]` contains a
  # colon, so a ${probe%%:*} split would silently truncate the pattern to `page\.route[[`
  # and match nothing. A gate that quietly stops matching is worse than no gate.
  probe_re=''; probe_what=''
  for n in 1 2; do
    if [ "$n" = 1 ]; then
      probe_re='page\.route[[:space:]]*\(|context\.route[[:space:]]*\('
      probe_what='a network stub (page.route)'
    else
      probe_re='page\.clock[[:space:]]*\.'
      probe_what='a fake-clock call (page.clock)'
    fi
    re=$probe_re; what=$probe_what
    b=$(n_occurrences "$before" "$re"); a=$(n_occurrences "$after" "$re")
    [ "${a:-0}" -gt "${b:-0}" ] || continue
    hook_deny "QA toolkit - the healer tried to INTRODUCE $what (PreToolUse hook).

This edit to ${abs##*/} adds an occurrence that was not there before ($b -> $a).

agents/healer.md §"Anti-drift rule": you patch selectors and waits. Neither of these is a patch.
  - page.route  - a red test whose backend is genuinely broken is the most valuable signal the
                  nightly produces. Stubbing that backend green converts a real outage into a
                  test that passes forever. A dependency that is down or flaky is a PRODUCT BUG
                  (file bugs/<slug>.md) or an ENVIRONMENT problem (escalate) - classify and stop.
  - page.clock  - runFor(...)/fastForward(...) is a sleep the waitForTimeout ban does not
                  lexically catch. It is legitimate only when a clock: step in the paired spec
                  declared it; reviewer Check 5 FAILs an undeclared one. For a timing flake,
                  re-point the locator or widen that matcher's own timeout: - both keep the
                  contract.

To disable this layer for the session, set QA_HOOKS_OFF=1 in Claude Code's own
environment or in .claude/settings.json's \"env\" block (a hook never reads the project .env)."
  done
fi

[ -n "$lost" ] && hook_deny "QA toolkit — the $agent tried to change an assertion (PreToolUse hook).

Removed or rewritten by this edit to ${abs##*/}:
$(printf '%s' "$lost" | sed 's/^/    /' | head -5)

$rule

To disable this layer for the session, set QA_HOOKS_OFF=1 in Claude Code's own
environment or in .claude/settings.json's "env" block (a hook never reads the project .env)."

exit 0
