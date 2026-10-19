#!/bin/sh
# prod-guard.sh — the canonical SHELL prod-guard (layer 1 of two; see CLAUDE.md
# §Environment). Screens EVERY exported BASE_URL_* — not just the primary target,
# because a multi-site run can hit BASE_URL_ADMIN too — PLUS API_URL / *_API_URL
# (the test-data-seed skill's create/delete-users path drives API_URL directly, and
# a prod API_URL with a real admin token would seed/delete PRODUCTION rows outside
# the BASE_URL-only guard — B-3). Extracts each host, and
# refuses on a word-boundary prod marker. NOT a bare `prod` substring match: that
# false-positives on `product`/`reproduction` and false-negatives on prod hosts
# without "prod" in the name. QA_ALLOW_PROD=1 overrides the prod-marker check ONLY;
# placeholder / empty-target refusals are config errors with NO env escape (fix .env).
#
# Layer 2 is scripts/prod-guard.ts — the ENFORCED globalSetup that throws before
# any browser opens on a bare `npx playwright test`. Neither layer decides anything
# itself: both ask scripts/prod-guard-core.mjs (see below), so they cannot drift apart.
#
# Usage:  bash scripts/prod-guard.sh [url ...]
# Any URL passed as an argument is screened by the SAME logic as the env vars — for
# commands whose target comes from their arguments instead of .env (/qa-warden:review url=<url>).
#
# Exit 0 = safe to proceed; exit 1 = REFUSED (the calling command must STOP and
# ask the user). Loads .env itself (set -a export), so it is safe to run as the
# first step of any command — but remember the Bash tool starts a fresh shell per
# call: vars this script exports do NOT reach the caller's next invocation.
set -a; [ -f "${CLAUDE_PROJECT_DIR:-.}/.env" ] && . "${CLAUDE_PROJECT_DIR:-.}/.env"; set +a

# The verdict lives in ONE place: scripts/prod-guard-core.mjs, plain ESM with no dependencies,
# which scripts/prod-guard.ts imports too. This script keeps what is shell-shaped — the .env load
# above, `--list-targets`, `--probe`, mask() and every line it prints — and asks the core for the
# rest with ONE `node` call per run. Before the core each layer parsed hosts its own way, and the
# sed strip this file used PASSED `https://prod.acme.com\@staging.acme.dev`,
# `https://PROD%2Eacme.com` and a fullwidth `https://ｐｒｏｄ.acme.com` — three URLs a browser
# resolves to prod.acme.com.
# Fail CLOSED when the core cannot run: no node on PATH, or a stamp that has this script but not
# the core (a partial copy). Node ≥22 is a project requirement already (scripts/init.sh checks the
# version); this guard only needs `node` to exist.
CORE="$(dirname "$0")/prod-guard-core.mjs"
refuse_early() {
  echo "REFUSING: $1"
  echo "prod-guard: REFUSED (exit 1) — STOP"
  exit 1
}
if ! command -v node >/dev/null 2>&1; then
  refuse_early "Node ≥22 required — this guard runs scripts/prod-guard-core.mjs with node, and there is no node on PATH. Install Node ≥22 (the project needs it for npx playwright anyway), then re-run."
fi
if [ ! -f "$CORE" ]; then
  refuse_early "scripts/prod-guard-core.mjs is missing — this prod-guard.sh cannot decide without it (a partial stamp). Run /qa-warden:init --resync to restore the toolkit-owned scripts."
fi

# The ONE definition of "every target a run could touch" is the core's TARGET_NAME_RE: BASE_URL*
# (including the bare BASE_URL single-site forks use), API_URL and *_API_URL (the test-data-seed
# create/delete-users path drives the API host directly, so a prod API with a real admin token
# would mutate production rows outside a BASE_URL-only guard). `--list-targets` prints this set as
# `NAME<TAB>value` and exits WITHOUT screening — it is how /qa-warden:explore's reachability probe
# enumerates the same targets instead of re-typing the regex. That copy had already drifted
# narrower (`^BASE_URL_[A-Z0-9_]*`), so a target could be prod-GUARDED but never
# reachability-probed and a down seed API surfaced later as a mystery red instead of a STOP.
# `names` prints only the names (never a value); `$v` is then a var NAME matched by that fixed
# regex ([A-Z0-9_] only), so eval-ing it is safe. `eval "val=\$$v"`, NOT `printenv` — printenv is
# not POSIX-guaranteed.
# A core that fails here would read as "no targets set" — refuse instead: a non-zero node exit,
# or any line that is not a bare var name, is a refusal, never a shorter list.
# `NODE_OPTIONS=''` (empty, for this one command) on EVERY core call: an inherited
# NODE_OPTIONS=--import=<file> / --require preload runs before the core and could print a
# verdict-shaped line of its own. Clearing it means only the core's code writes the output.
if [ "${1:-}" = "--list-targets" ] || [ "${1:-}" = "--probe" ]; then
  TARGET_NAMES=$(NODE_OPTIONS='' node "$CORE" names) \
    || refuse_early "scripts/prod-guard-core.mjs failed to list the targets (its error, if any, is printed above) — is node ≥22? Run /qa-warden:init --resync if the core was edited."
  printf '%s\n' "$TARGET_NAMES" | awk '$0 != "" && $0 !~ /^[A-Z0-9_]+$/ { bad = 1 } END { exit bad }' \
    || refuse_early "scripts/prod-guard-core.mjs printed something that is not a var name — run /qa-warden:init --resync if the core was edited."
fi
target_names() { printf '%s\n' "$TARGET_NAMES" | grep -E '^[A-Z0-9_]+$'; }
if [ "${1:-}" = "--list-targets" ]; then
  for v in $(target_names); do
    eval "envval=\$$v"
    [ -n "$envval" ] && printf '%s\t%s\n' "$v" "$envval"
  done
  exit 0
fi

# `--probe` — reachability of that SAME target set, as one allow-listed call. It used to be a
# multi-line loop printed in /qa-warden:explore's skill; a permission rule has to match every subcommand
# of a compound command, so under the shipped allow-list that loop prompted (and was flatly denied
# headless — Test-35, 2026-09-21) while this script's own invocation never does. Reachability ONLY:
# any HTTP status means the host is up; DNS failure / timeout / refused is the STOP. Screens
# nothing — run the plain guard first. Exit 1 if any target is unreachable.
if [ "${1:-}" = "--probe" ]; then
  prc=0
  for v in $(target_names); do
    eval "envval=\$$v"
    [ -n "$envval" ] || continue
    if code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$envval" 2>/dev/null); then
      echo "$v reachable (HTTP $code)"
    else
      echo "STOP: $v=$(printf '%s' "$envval" | sed -E 's#^([a-zA-Z]+://)?[^/?#]*@#\1***@#') UNREACHABLE (DNS/timeout/refused) — check VPN, tunnel, .env before exploring"
      prc=1
    fi
  done
  exit $prc
fi

# mask userinfo credentials before ANY echo of a URL value — `.env` can carry
# `https://user:pass@host` targets and this script's output lands in agent
# transcripts / CI logs. Display-only: guard logic always uses the raw value.
mask() { printf '%s' "$1" | sed -E 's#^([a-zA-Z]+://)?[^/?#]*@#\1***@#'; }  # greedy to the LAST pre-path @ — a password containing @ must not leak a fragment

# `-` (not `:-`) on the primary: a SET-but-EMPTY BASE_URL_APP must NOT fall through to
# BASE_URL (the core uses `??`, which treats '' as set). This line only DISPLAYS the target;
# the empty-primary refusal comes from the core's `primary empty` record below.
URL="${BASE_URL_APP-${BASE_URL:-}}"
if [ -n "$URL" ]; then
  echo "effective target: $(mask "$URL")"
else
  echo "effective target: <empty — BASE_URL_APP unset; is .env filled in?>"
fi
rc=0

# ONE node call screens every env target AND every positional URL argument. A command whose
# TARGET comes from its arguments rather than from .env (`/qa-warden:review url=<url>`) passes it
# here — `bash scripts/prod-guard.sh "$URL"` — and it gets the same screening as the env vars;
# args are additive, the env sweep always runs too. The core prints one TAB-separated record per
# line (see its CLI comment) and `verdict` LAST. The output is accepted only WHOLE, or the run is
# refused — never read leniently:
#   • node must exit 0 (a crash after a verdict-shaped line is a crash);
#   • line 1 is `primary set|empty`; every other line but the last is a well-formed `target` or
#     `argument` record; the LAST line is exactly `verdict PASS` or `verdict REFUSED`, once;
#   • a PASS verdict next to a non-ok record or an empty primary is a contradiction → refuse.
# NODE_OPTIONS is cleared for the call (see the `names` call above for why).
CORE_OUT=$(NODE_OPTIONS='' node "$CORE" screen "$@")
core_rc=$?
TAB=$(printf '\t')
if [ "$core_rc" -ne 0 ]; then
  refuse_early "scripts/prod-guard-core.mjs exited $core_rc (its error, if any, is printed above) — is node ≥22? Run /qa-warden:init --resync if the core was edited."
fi
printf '%s\n' "$CORE_OUT" | awk -F'\t' '
  NR == 1 { if ($0 != "primary\tset" && $0 != "primary\tempty") bad = 1; if ($0 == "primary\tempty") refusing = 1; next }
  ($1 == "target" && $2 ~ /^[A-Z0-9_]+$/) || ($1 == "argument" && $2 ~ /^[0-9]+$/) {
    if (NF != 4 || $3 !~ /^(ok|placeholder|prod)$/) bad = 1
    if ($3 != "ok") refusing = 1
    next
  }
  $0 == "verdict\tPASS" || $0 == "verdict\tREFUSED" { verdicts++; last = NR; verdict = $2; next }
  { bad = 1 }
  END {
    if (bad || NR < 2 || verdicts != 1 || last != NR) exit 1
    if (verdict == "PASS" && refusing) exit 1
  }' \
  || refuse_early "scripts/prod-guard-core.mjs returned no well-formed verdict (its error, if any, is printed above) — is node ≥22? Run /qa-warden:init --resync if the core was edited."

# Fail-CLOSED on an UNCONFIGURED target (F-08, per-var). The shipped `.env.example` uses a
# `CHANGEME` sentinel; an empty or placeholder host means the user copied `.env` but never
# set a real target. A green guard against a host the user never chose (the old
# `staging.example.com` default passed silently) is worse than a STOP. The PRIMARY must be
# non-empty (this check); placeholder detection runs PER-VAR, so a CHANGEME left in a
# SECONDARY (BASE_URL_ADMIN) also refuses — an unset/empty secondary stays fine (only the
# primary is mandatory). NO env escape here: an empty/placeholder target is a CONFIG ERROR
# whose only remedy is editing .env — QA_ALLOW_PROD covers the prod-marker check ONLY (one
# semantic per override; a false placeholder refusal must never train users to disable the
# prod guard to get past it).
if printf '%s\n' "$CORE_OUT" | grep -q "^primary${TAB}empty\$"; then
  echo "REFUSING: BASE_URL_APP is empty — edit .env and set it to your staging/QA target before running QA."
  rc=1
fi

# One record per screened value, in the core's order. Each line names the value by its var NAME
# (env) or its 1-based POSITION (argument) — never the value itself — so the value is read back
# here and only ever printed through mask(). The NAME is checked before it reaches eval: a var
# name is [A-Z0-9_] only (the core's fixed regex), a position is digits only.
while IFS="$TAB" read -r kind name verdict host; do
  val=""
  case "$name" in
    ''|*[!A-Z0-9_]*) continue ;;
  esac
  case "$kind" in
    target)
      v="$name"
      eval "val=\$$name"
      remedy="edit .env and set it to a real staging/QA target"
      ;;
    argument)
      case "$name" in *[!0-9]*) continue ;; esac
      v="argument"
      eval "val=\${$name}"
      remedy="pass a real staging/QA URL"
      ;;
    *) continue ;;
  esac
  echo "guard: $v → $(mask "$val")"
  case "$verdict" in
    placeholder)
      echo "REFUSING: $v is a placeholder ('$(mask "$val")') — $remedy."
      rc=1
      ;;
    prod)
      echo "REFUSING: '$host' ($v) looks like production. Set QA_ALLOW_PROD=1 only if you are certain."
      rc=1
      ;;
  esac
done <<EOF
$CORE_OUT
EOF
# The core's own verdict must agree; if it says REFUSED for a reason this loop did not print,
# refuse anyway (fail closed).
case "$CORE_OUT" in
  *"verdict${TAB}REFUSED") rc=1 ;;
esac
# Residual limit: a prod host with NO telltale name (www.acme.com) cannot be
# auto-detected — keep every BASE_URL_* on staging/QA explicitly and treat an
# empty/unexpected host as STOP-and-ask.

# Say the verdict in words. Agents kept appending `; echo "exit=$?"` to read the status, and that
# compound form no longer matches the `Bash(bash scripts/prod-guard.sh*)` allow rule — one denied
# call per run, in every Test-35 trace (2026-09-21). With the verdict printed there is nothing
# to append.
if [ "$rc" -eq 0 ]; then echo "prod-guard: PASS (exit 0)"; else echo "prod-guard: REFUSED (exit $rc) — STOP"; fi
exit "$rc"
