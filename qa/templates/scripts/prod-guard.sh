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
# any browser opens on a bare `npx playwright test`. Keep the marker regex in the
# two files in lockstep.
#
# Usage:  bash scripts/prod-guard.sh [url ...]
# Any URL passed as an argument is screened by the SAME logic as the env vars — for
# commands whose target comes from their arguments instead of .env (/qa:review url=<url>).
#
# Exit 0 = safe to proceed; exit 1 = REFUSED (the calling command must STOP and
# ask the user). Loads .env itself (set -a export), so it is safe to run as the
# first step of any command — but remember the Bash tool starts a fresh shell per
# call: vars this script exports do NOT reach the caller's next invocation.
set -a; [ -f "${CLAUDE_PROJECT_DIR:-.}/.env" ] && . "${CLAUDE_PROJECT_DIR:-.}/.env"; set +a

# The ONE definition of "every target a run could touch": BASE_URL* (including the bare BASE_URL
# single-site forks use), API_URL and *_API_URL (the test-data-seed create/delete-users path drives
# the API host directly, so a prod API with a real admin token would mutate production rows outside
# a BASE_URL-only guard). `--list-targets` prints this set as `NAME<TAB>value` and exits WITHOUT
# screening — it is how /qa:explore's reachability probe enumerates the same targets instead of
# re-typing the regex. That copy had already drifted narrower (`^BASE_URL_[A-Z0-9_]*`), so a target
# could be prod-GUARDED but never reachability-probed and a down seed API surfaced later as a
# mystery red instead of a STOP.
target_names() { env | sed -n -E 's/^(BASE_URL[A-Z0-9_]*|API_URL|[A-Z0-9_]*_API_URL)=.*/\1/p' | sort -u; }
if [ "${1:-}" = "--list-targets" ]; then
  for v in $(target_names); do
    eval "envval=\$$v"
    [ -n "$envval" ] && printf '%s\t%s\n' "$v" "$envval"
  done
  exit 0
fi

# mask userinfo credentials before ANY echo of a URL value — `.env` can carry
# `https://user:pass@host` targets and this script's output lands in agent
# transcripts / CI logs. Display-only: guard logic always uses the raw value.
mask() { printf '%s' "$1" | sed -E 's#^([a-zA-Z]+://)?[^/?#]*@#\1***@#'; }  # greedy to the LAST pre-path @ — a password containing @ must not leak a fragment

# `-` (not `:-`) on the primary: a SET-but-EMPTY BASE_URL_APP must NOT fall through to
# BASE_URL — scripts/prod-guard.ts uses `??` (nullish), which treats '' as set, and the
# two layers must refuse the same inputs. Empty primary → empty URL → the refusal below.
URL="${BASE_URL_APP-${BASE_URL:-}}"
if [ -n "$URL" ]; then
  echo "effective target: $(mask "$URL")"
else
  echo "effective target: <empty — BASE_URL_APP unset; is .env filled in?>"
fi
rc=0

# Fail-CLOSED on an UNCONFIGURED target (F-08, per-var). The shipped `.env.example` uses a
# `CHANGEME` sentinel; an empty or placeholder host means the user copied `.env` but never
# set a real target. A green guard against a host the user never chose (the old
# `staging.example.com` default passed silently) is worse than a STOP. The PRIMARY must be
# non-empty (this check); placeholder detection runs PER-VAR in the loop below, so a
# CHANGEME left in a SECONDARY (BASE_URL_ADMIN) also refuses — an unset/empty secondary
# stays fine (only the primary is mandatory). NO env escape here: an empty/placeholder
# target is a CONFIG ERROR whose only remedy is editing .env — QA_ALLOW_PROD covers the
# prod-marker check ONLY (one semantic per override; a false placeholder refusal must
# never train users to disable the prod guard to get past it).
if [ -z "$URL" ]; then
  echo "REFUSING: BASE_URL_APP is empty — edit .env and set it to your staging/QA target before running QA."
  rc=1
fi
# screen_target <label> <url> — the ONE screening body: host extraction + placeholder sentinel
# + word-boundary prod marker. Sets rc=1 on refusal. Used for every BASE_URL_*/API_URL in the
# environment AND for any URL passed as a positional argument (see the arg loop below), so a
# caller that takes a bare URL — /qa:review url=<url> — no longer has to re-implement this screening by
# hand in prose. Prose can't reproduce the scheme strip, the greedy userinfo strip, or the
# placeholder sentinels correctly, and a hand-rolled copy drifts from the .ts layer.
screen_target() {
  v="$1"; val="$2"
  [ -z "$val" ] && return 0
  # Host extraction — 3-rule scheme strip, then userinfo/port/path cut:
  #   (1) any `scheme://` — the `//` is REQUIRED, so a bare host:port like
  #       `prod:8080` / `localhost:3000` is never eaten as a scheme;
  #   (2) no-slash `http:` / `https:` ONLY (WHATWG parses `https:prod.acme.com`
  #       as a host — mirror it);
  #   (3) protocol-relative `//host`.
  # Then a GREEDY userinfo strip to the LAST `@` before any `/ ? #` (a first-`@`
  # strip leaves `ss@prod…` for `user:p@ss@prod…`, which defeats the word-boundary
  # match), then cut port/path/query/fragment. `|` as the sed delimiter because
  # `/ ? # @ :` all occur in the patterns.
  host=$(printf '%s' "$val" | sed -E 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||; s|^[hH][tT][tT][pP][sS]?:||; s|^//||; s|^[^/?#]*@||; s|[:/?#].*$||')
  echo "guard: $v → $(mask "$val")"
  # Placeholder sentinel per-var (F-08): CHANGEME / <angle-brackets> anywhere in the VALUE;
  # RFC 2606/6761 reserved example domains LABEL-ANCHORED on the extracted HOST (exact or
  # `.`-suffix) — an unanchored *example.com* substring falsely refused real hosts like
  # qa.example.company.com. NO env escape: example.com/net/org and *.example are
  # IANA-reserved and unregistrable, so no real target can live there — the fix is editing
  # .env, and QA_ALLOW_PROD covers the prod-marker check ONLY. Keep these two case patterns
  # in lockstep with prod-guard.ts's PLACEHOLDER_VALUE_RE / PLACEHOLDER_HOST_RE.
  placeholder=0
  case "$(printf '%s' "$val" | tr 'A-Z' 'a-z')" in *changeme*|*'<'*|*'>'*) placeholder=1 ;; esac
  case "$(printf '%s' "$host" | tr 'A-Z' 'a-z')" in
    example.com|*.example.com|example.org|*.example.org|example.net|*.example.net|example|*.example) placeholder=1 ;;
  esac
  if [ "$placeholder" -eq 1 ]; then
    # Name the right remedy: an env var is fixed in .env, an argument by the caller.
    if [ "$v" = argument ]; then remedy="pass a real staging/QA URL"; else remedy="edit .env and set it to a real staging/QA target"; fi
    echo "REFUSING: $v is a placeholder ('$(mask "$val")') — $remedy."
    rc=1
    return 0
  fi
  if printf '%s' "$host" | grep -qiE '(^|[.-])(prod|production)[0-9]*($|[.-])' && [ "${QA_ALLOW_PROD:-0}" != "1" ]; then
    echo "REFUSING: '$host' ($v) looks like production. Set QA_ALLOW_PROD=1 only if you are certain."
    rc=1
  fi
}

for v in $(target_names); do
  # `eval "val=\$$v"`, NOT `printenv` — printenv is not POSIX-guaranteed; on a minimal
  # image without it every `val` would be empty, the loop would skip every var, and the
  # prod-MARKER check (which lives ONLY in screen_target) would silently perform zero checks —
  # a fail-OPEN on the advisory layer. `$v` is a var NAME extracted by the fixed regex above
  # (BASE_URL*/…_API_URL — [A-Z0-9_] only), so eval-ing it is safe here.
  eval "envval=\$$v"
  screen_target "$v" "$envval"
done

# Positional URL arguments — screened by the SAME body as the env vars. A command whose TARGET
# comes from its arguments rather than from .env (`/qa:review url=<url>`) passes it here:
#   bash scripts/prod-guard.sh "$URL"
# This script's header promises to screen "every target a run could touch", and an argument URL
# is exactly that. Args are additive: the env sweep above always runs too.
for arg in "$@"; do
  screen_target "argument" "$arg"
done
# Residual limit: a prod host with NO telltale name (www.acme.com) cannot be
# auto-detected — keep every BASE_URL_* on staging/QA explicitly and treat an
# empty/unexpected host as STOP-and-ask.
exit "$rc"
