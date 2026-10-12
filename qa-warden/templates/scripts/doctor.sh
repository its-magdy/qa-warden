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
# project-scope install first, then the user-scope one, then any other that is not tied to a
# project (a managed one, say), the most recently updated first within each. Another project's
# local- or project-scope install is never used: that scope applies only to its own repository,
# so it is not the plugin this project runs. Then it runs that plugin's doctor in this directory
# and passes its exit code through.
#
# Why the checks moved out of the project: a stamped doctor was refreshed only by
# /qa-warden:init --resync, so every new check reached a project one repair late, and a doctor
# older than the plugin it compared against misreported.
#
# Two things this launcher deliberately does not do:
#   - Guess. If no install is recorded it stops (exit 2). The doctor used to fall back to the
#     newest cached plugin version by mtime, and an orphaned old version can be the newest. The
#     same goes when the only installs belong to other projects: it names them and stops.
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

# Which install to run: this project's local- or project-scope install, then the user-scope one,
# then any other that is not local- or project-scope. Within each tier the most recently updated
# entry wins, so a stale record that happens to come first in the file does not. pwd AND pwd -P:
# a recorded projectPath may be either form (/tmp is /private/tmp on macOS).
# The last tier used to be every record, so with no install for this project and none for the
# user it ran ANOTHER project's install: a version this project does not run, and one that may
# be older or newer than its stamp.
# stderr is captured with stdout on purpose: on success jq prints only the path, and on failure
# (a jq that cannot execute, e.g. one built for another CPU, or a malformed record) the message
# says why instead of reading as "no install recorded".
if ! PLUGIN=$(jq -r --arg pwd "$(pwd)" --arg pwdp "$(pwd -P)" '
    def newest_first: sort_by(.lastUpdated // "") | reverse;
    def per_project: .scope == "local" or .scope == "project";
    def here: .projectPath == $pwd or .projectPath == $pwdp;
    [ .plugins // {} | to_entries[] | select(.key | startswith("qa-warden@")) | .value[] ]
    | (   (map(select(per_project and here)) | newest_first)
        + (map(select(.scope == "user")) | newest_first)
        + (map(select(per_project | not)) | newest_first) )
    | first
    | .installPath // empty' "$IPJ" 2>&1); then
  echo "❌ scripts/doctor.sh: jq failed to read $IPJ: $PLUGIN. $HOW" >&2
  exit 2
fi

if [ -z "$PLUGIN" ]; then
  # Nothing usable. Say whether that is "no install at all" or "installs, but only for other
  # projects": the second needs an install here, not a reinstall.
  OTHERS=$(jq -r '[ .plugins // {} | to_entries[] | select(.key | startswith("qa-warden@")) | .value[]
                    | select(.scope == "local" or .scope == "project")
                    | .projectPath // "(no projectPath)" ] | unique | join(", ")' "$IPJ" 2>/dev/null)
  if [ -n "$OTHERS" ]; then
    echo "❌ scripts/doctor.sh: $IPJ records qa-warden only for other projects ($OTHERS), not for this one ($(pwd)) or for your user. A local- or project-scope install applies only to its own project, so it is not run here. Install the plugin for this project or for your user (/plugin in Claude Code), then run this again. $HOW" >&2
  else
    echo "❌ scripts/doctor.sh: $IPJ records no qa-warden install. $HOW" >&2
  fi
  exit 2
fi
if [ ! -d "$PLUGIN" ]; then
  echo "❌ scripts/doctor.sh: the recorded qa-warden install at $PLUGIN no longer exists, so the install record is stale. Reinstall or update the plugin in Claude Code (/plugin), then run this again. $HOW" >&2
  exit 2
fi
DOCTOR="$PLUGIN/skills/doctor/scripts/doctor.sh"
if [ ! -f "$DOCTOR" ]; then
  echo "❌ scripts/doctor.sh: the recorded qa-warden install at $PLUGIN is older than this launcher (it has no skills/doctor/scripts/doctor.sh). Update the plugin (claude plugin update qa-warden, or /plugin in Claude Code), then run this again." >&2
  exit 2
fi

echo "ℹ️  running the doctor of the recorded plugin install → $PLUGIN"
exec bash "$DOCTOR" "$@"
