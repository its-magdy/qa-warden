#!/usr/bin/env bash
# stamped-helper.sh — sourced (not executed) by the plugin scripts that call one of the project's
# stamped READ-ONLY helpers. It decides which copy of the helper a call runs.
#
# Plugin scripts (the brain) run from the project root and call helpers that /qa-warden:init
# stamped into scripts/ (the body). A stamp only changes on `/qa-warden:init --resync`, so a newer
# plugin meets an older stamp, or none: a spec-links.sh with no `tests` mode, a post-run-checks.sh
# that answers an unknown flag with a usage line and exit 0, a resolve-spec-path.sh that is not
# there at all. Each of those reads as an empty answer (a false clean) or a broken command. Until
# this file, only spec-links.sh had a fallback to the plugin's own copy, written out three times
# (doctor, impact, coverage) with different path forms and warning texts.
#
# stamped_helper <name>        e.g.  stamped_helper spec-links.sh; bash "$STAMPED_HELPER" tests
#   Sets STAMPED_HELPER to the copy to run, and always returns 0:
#     scripts/<name>                     the project's copy, when it is byte-identical to the
#                                        plugin's templates/scripts/<name> (the stamp is current)
#     <plugin>/templates/scripts/<name>  the plugin's copy, when the project's is missing or differs
#   On the second it prints ONE line on stdout, once per helper per process:
#     WARN: scripts/<name> <is missing|differs from this plugin's copy> — used the plugin's copy. Run /qa-warden:init --resync to update the stamp.
#   Call it OUTSIDE a `$( … )`: the variable and the once-only record are set in the caller's
#   shell. A caller that already reports the drift (doctor Check 9) sends the line to /dev/null.
#   No plugin copy (an incomplete install) → the project's copy, silently: nothing to compare
#   against, so the call runs as it did before this file existed.
#
# USABLE = BYTE-IDENTICAL, not "the project's copy fails the call". The failed-call test only works
# for spec-links.sh, whose unknown mode exits 2. Every other helper's exit code is an ANSWER:
# check-last-run.sh exits 3-6 for missing/corrupt/zero-test/stale, resolve-spec-path.sh exits 2 for
# "no compiled test", post-run-checks.sh exits 0 whatever happened. An old copy of those cannot be
# told from a correct "no" by running it. Byte equality can, and it keeps the spec-links precedent:
# every stamp that fails a call the template answers differs from the template, so it still falls
# back. It is the comparison doctor Check 9 already makes, so the resolver and the drift ⚠️ always
# name the same files. Running the plugin's copy is safe ONLY because every helper below reads
# the project tree and writes nothing (post-run-checks.sh's mktemp under $TMPDIR, removed before
# it exits, is the one file any of them creates), so its answer is the one the resynced stamp
# will give. The stamped settings deny Edit on these files (not Write, nor a hand edit), so a
# difference is almost always a stale stamp; a deliberate local change is overridden here too,
# and the WARN names it.
#
# ONE BODY-TO-BODY CALL: post-run-checks.sh runs `bash scripts/bug-status.sh --list-open 2>/dev/null`
# — the project's copy, whichever post-run-checks.sh is running — and cannot see that call fail.
# With a missing, unreadable or older project bug-status.sh, the plugin's post-run-checks.sh
# would print `open-bugs=0` for a scan that never ran, where a missing project post-run-checks.sh
# used to stop the caller. So post-run-checks.sh falls back only when the project's bug-status.sh
# is byte-identical to the plugin's; otherwise the project's path is kept, silently, and the call
# behaves as it did before this file (a missing script fails it).
#
# READ-ONLY HELPERS ONLY. The case below is the whole list; any other name gets scripts/<name> and
# never the plugin's copy. prod-guard.sh / prod-guard.ts / prod-guard-core.mjs are deliberately
# NOT on it: the guard must be the project's own copy, so a broken guard refuses every run rather
# than being quietly replaced. retire-delete.sh deletes files, cli-fill-env.sh writes .env, init.sh
# creates directories. Read a helper end to end, and confirm it writes nothing, before adding it.
#
# Bash 3.2 safe. Plugin-only: lib/ is not under templates/, so it is never stamped.

# Where the plugin keeps its templates, resolved once, when this file is sourced.
_QA_SH_TEMPLATES=$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/scripts" 2>/dev/null && pwd)
_QA_SH_WARNED=${_QA_SH_WARNED:- }   # sourced twice by run.sh (directly and via run-verdict.sh)

# shellcheck disable=SC2034  # STAMPED_HELPER is the output, read by the caller that sources this
stamped_helper() {
  local name=$1 plugin_copy why
  STAMPED_HELPER="scripts/$name"
  case "$name" in
    spec-links.sh|resolve-spec-path.sh|post-run-checks.sh|check-last-run.sh|bug-status.sh) : ;;
    *)
      echo "stamped_helper: '$name' is not a read-only helper — running the project's copy only" >&2
      return 0 ;;
  esac
  [ -n "$_QA_SH_TEMPLATES" ] || return 0
  plugin_copy="$_QA_SH_TEMPLATES/$name"
  [ -f "$plugin_copy" ] || return 0
  [ "$name" != post-run-checks.sh ] || cmp -s scripts/bug-status.sh "$_QA_SH_TEMPLATES/bug-status.sh" || return 0
  if [ ! -f "scripts/$name" ]; then
    why="is missing"
  elif cmp -s "scripts/$name" "$plugin_copy"; then
    return 0
  else
    why="differs from this plugin's copy"
  fi
  STAMPED_HELPER=$plugin_copy
  case "$_QA_SH_WARNED" in
    *" $name "*) : ;;
    *)
      echo "WARN: scripts/$name $why — used the plugin's copy. Run /qa-warden:init --resync to update the stamp."
      _QA_SH_WARNED="$_QA_SH_WARNED$name " ;;
  esac
  return 0
}
