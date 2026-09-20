#!/usr/bin/env bash
# hook-lib.sh — shared guards for the PreToolUse hooks in this directory.
#
# Sourced by assertion-contract.sh and spec-lint.sh. Not a hook itself.
#
# Everything here exists to answer one question safely: "is this tool call one the QA
# toolkit is allowed to have an opinion about?" The default answer is NO. A plugin hook
# fires in EVERY session in EVERY repository the plugin is enabled in — including repos
# that have nothing to do with this toolkit — so every guard below is written to exit 0
# (stay out of the way) on the slightest doubt. A hook that blocks wrongly breaks every
# session; that is the whole reason this layer was withheld for so long.
#
# FAIL-OPEN is a rule, not a preference: a bug in a hook must degrade to "the reviewer
# catches it at PR time", never to "the agent cannot write a file".

# --- escape hatch -------------------------------------------------------------------
# QA_HOOKS_OFF=1 disables the whole layer for a session. Mirrors the QA_ALLOW_PROD
# precedent: one documented, greppable env var rather than N per-check toggles.
# Deliberately NOT fail-closed on a placeholder value the way prod-guard is — this layer
# protects a review contract, not a production database, and an operator who cannot turn
# a linter off will route around it instead.
hook_escape_hatch() { [ "${QA_HOOKS_OFF:-}" = "1" ] && exit 0; return 0; }

# --- deny ---------------------------------------------------------------------------
# Emit the PreToolUse deny envelope and exit 0. Exit 0 + JSON is the documented decision
# path; exit 2 also blocks but routes the reason through stderr, which renders worse.
# Built with `jq -n` so the reason (which quotes the offending source line) can never
# break the JSON the harness parses — a malformed envelope is a non-blocking error, i.e.
# a silently-skipped gate.
hook_deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- preconditions ------------------------------------------------------------------
# jq is load-bearing for parsing the hook payload. It is an UNDECLARED dependency in a
# consumer project (doctor Check 0 FAILs on it for the same reason) — but a missing jq
# must not block writes, so this is the fail-open arm, not a refusal.
hook_require_jq() { command -v jq >/dev/null 2>&1 || exit 0; return 0; }

# --- project marker -----------------------------------------------------------------
# hook_qa_root <abs-path> — prints the QA project root that owns <abs-path>, and returns
# non-zero when there isn't one. Callers MUST write `root=$(hook_qa_root "$abs") || exit 0`:
# these helpers run inside a command substitution, so an `exit` in here would kill only the
# subshell and let the hook sail on — the fail-open path would silently become fail-closed.
#
# Two conditions must BOTH hold, and neither is about the file being edited:
#   1. the path sits under a `tests/` or `page-objects/` directory, and
#   2. the directory above that one is a scaffolded QA project.
#
# The marker pair is `playwright.config.ts` + `scripts/prod-guard.ts`. Both are stamped by
# bin/qa-scaffold on every /qa:init and both are in scripts/resync-set.txt, so they exist
# from the first minute of a project's life and are force-restored by --resync. Plain
# `playwright.config.ts` alone is NOT enough: it is present in thousands of unrelated
# repositories, and matching on it would make this plugin lint every Playwright project
# its owner happens to open. `prod-guard.ts` is this toolkit's own filename.
#
# Deliberately NOT keyed on specs/_context/app.context.md: that file is written by
# /qa:explore, not by the scaffold, so a freshly-initialised project would be unguarded.
hook_qa_root() {
  local abs="$1" root
  case "$abs" in
    */tests/*)        root="${abs%%/tests/*}" ;;
    */page-objects/*) root="${abs%%/page-objects/*}" ;;
    *) return 1 ;;
  esac
  [ -n "$root" ] || return 1
  [ -f "$root/playwright.config.ts" ] || return 1
  [ -f "$root/scripts/prod-guard.ts" ] || return 1
  printf '%s\n' "$root"
}

# --- path resolution ----------------------------------------------------------------
# The harness may hand us a relative file_path; resolve it against the session cwd from
# the payload (NOT $PWD — the hook process inherits a cwd we do not control).
# Same subshell caveat as hook_qa_root: returns non-zero instead of exiting.
hook_abs_path() {
  local fp="$1" cwd="$2"
  case "$fp" in
    "") return 1 ;;
    /*) printf '%s\n' "$fp" ;;
    *)  printf '%s\n' "${cwd:-.}/$fp" ;;
  esac
}
