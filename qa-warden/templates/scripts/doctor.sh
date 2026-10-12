#!/usr/bin/env bash
# scripts/doctor.sh — launcher for the /qa-warden:doctor check pass, for hand runs.
#
# The checks are not in this file. They ship in the plugin (skills/doctor/scripts/doctor.sh), and
# /qa-warden:doctor runs that copy directly. This launcher is for a terminal, from the project root:
#
#   bash scripts/doctor.sh
#
# It finds the plugin through the install Claude Code recorded in
# ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json: this project's local- or
# project-scope install first, then the user-scope one, then the most recently updated. Then it
# runs that plugin's doctor in this directory and passes its exit code through.
#
# Why the checks moved out of the project: a stamped doctor was refreshed only by
# /qa-warden:init --resync, so every new check reached a project one repair late, and a doctor
# older than the plugin it compared against misreported.
#
# Two things this launcher deliberately does not do:
#   - Guess. If no install is recorded it stops (exit 2). The doctor used to fall back to the
#     newest cached plugin version by mtime, and an orphaned old version can be the newest.
#   - Read $CLAUDE_PLUGIN_ROOT. This file EXECUTES the doctor it finds, and projects stamped
#     before this change carry the allow rule `Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)`.
#     Honouring the variable would pre-approve running any file an agent could place at
#     <dir>/skills/doctor/scripts/doctor.sh. To run a particular plugin build (a CI checkout, a
#     development tree), call its doctor directly from the project root:
#       bash <plugin>/skills/doctor/scripts/doctor.sh
#
# Exit codes: the doctor's own (0 healthy or warnings only, 1 on any ❌), or 2 when no plugin was
# found and nothing ran.

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
IPJ="$CFG/plugins/installed_plugins.json"
HOW="Run /qa-warden:doctor in Claude Code, or run a plugin's doctor directly from this directory: bash <plugin>/skills/doctor/scripts/doctor.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ scripts/doctor.sh: jq is not installed, so the plugin install record cannot be read. $HOW" >&2
  exit 2
fi
if [ ! -f "$IPJ" ]; then
  echo "❌ scripts/doctor.sh: no plugin install record at $IPJ, so the QA Warden plugin was not found. $HOW" >&2
  exit 2
fi

# pwd AND pwd -P: a recorded projectPath may be either form (/tmp is /private/tmp on macOS).
PLUGIN=$(jq -r --arg pwd "$(pwd)" --arg pwdp "$(pwd -P)" '
  [ .plugins // {} | to_entries[] | select(.key | startswith("qa-warden@")) | .value[] ]
  | (   map(select((.scope == "local" or .scope == "project")
                   and (.projectPath == $pwd or .projectPath == $pwdp)))
      + map(select(.scope == "user"))
      + (sort_by(.lastUpdated) | reverse) )
  | first
  | .installPath // empty' "$IPJ" 2>/dev/null)

if [ -z "$PLUGIN" ]; then
  echo "❌ scripts/doctor.sh: $IPJ records no qa-warden install. $HOW" >&2
  exit 2
fi
DOCTOR="$PLUGIN/skills/doctor/scripts/doctor.sh"
if [ ! -f "$DOCTOR" ]; then
  echo "❌ scripts/doctor.sh: the recorded qa-warden install at $PLUGIN has no skills/doctor/scripts/doctor.sh. It predates this launcher; update the plugin, or run its own /qa-warden:doctor." >&2
  exit 2
fi

echo "ℹ️  running the doctor of the recorded plugin install → $PLUGIN"
exec bash "$DOCTOR" "$@"
