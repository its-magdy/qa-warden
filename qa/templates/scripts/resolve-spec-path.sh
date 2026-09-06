#!/bin/sh
# resolve-spec-path.sh — the ONE place the <arg> → specs/….md / tests/….spec.ts
# mapping lives. Every /qa:* command that takes a spec-or-test argument accepts
# the same forms (bare <area>/<feature>, <area>/<feature>.md, specs/….md,
# tests/….spec.ts); resolve them here so a layout change or a new accepted form
# is a one-file edit, not a per-command grind. A mis-mapped path matches ZERO
# tests (testDir is ./tests) and reads as a phantom green run — the false-green
# this toolkit exists to prevent.
#
# Usage:
#   scripts/resolve-spec-path.sh spec <arg>        # prints specs/<area>/<feature>.md
#   scripts/resolve-spec-path.sh test <arg>        # prints tests/<area>/<feature>.spec.ts
#   scripts/resolve-spec-path.sh reportname <arg>  # prints area-qualified <area>-<feature>
#
# `test` mode VERIFIES the compiled test exists (exit 2 + stderr message if not);
# `spec` mode prints the normalized path with no existence check (the caller may
# be about to create it). `reportname` mode is `test` mode's path flattened to a
# single filename-safe token (auth/login → auth-login) for the per-command report
# sinks — `reports/headless-<name>.json`, `artifacts/flake-<name>.json`. It lives
# here, not in each command, because it is the same tests/… → identifier mapping
# this script already owns: /qa:run mode=single and /qa:run mode=repeat carried byte-identical
# copies of the slug expression on the line right after their resolve call, so an
# area-qualification change (added precisely so two areas' same-named specs cannot
# clobber each other's report file) had to be made twice.
MODE="${1:?usage: resolve-spec-path.sh spec|test|reportname <arg>}"
ARG="${2:?usage: resolve-spec-path.sh spec|test|reportname <arg>}"

# Tolerate a stray inline `key=val` flag (e.g. `site=app`) passed alongside the
# path — the spec/test path is the FIRST bare (non key=val) token. Callers learn
# `site=` from /qa:new-spec and carry it over to /qa:gen out of habit; without
# this, `resolve-spec-path.sh spec "checkout/coupon site=app"` would emit the
# broken `specs/checkout/coupon site=app.md` (matches ZERO tests → phantom green).
# Keeping the strip HERE — the one place the arg→path mapping lives — means every
# caller (/qa:gen, /qa:new-spec, /qa:run mode=single, /qa:run mode=repeat, /qa:review…) is safe
# without duplicating the parse. A real spec/test path never contains '='.
for tok in $ARG; do
  case "$tok" in
    *=*) ;;                    # key=val flag → not the path (site: comes from the spec YAML)
    *)   ARG="$tok"; break ;;  # first bare token = the spec/test path
  esac
done
# If EVERY token was a key=val flag, ARG still holds the original flag string and
# would normalize to garbage (`spec "site=app mode=x"` → `specs/site=app mode=x.md`
# — matches ZERO tests, the phantom-green this script exists to prevent). A real
# spec/test path never contains '=', so refuse instead of emitting a broken path.
case "$ARG" in
  *=*) echo "No spec/test path in '$2' — every token is a key=val flag. Pass the path too, e.g. 'checkout/coupon site=app'." >&2
       exit 2 ;;
esac
# NOTE (off-contract input): a path containing SPACES ('my area/log in') truncates at
# the first token — spec/test paths are kebab-case single tokens by contract; `test`
# mode's existence check catches the mistake, `spec` mode may emit a wrong path.

case "$MODE" in
  spec)
    case "$ARG" in
      specs/*.md) SPEC="$ARG" ;;                       # full path passes through unchanged
      *.md)       STEM="${ARG#specs/}"; STEM="${STEM#tests/}"   # strip a leading specs/ OR tests/ (T-07:
                  SPEC="specs/${STEM}" ;;                       # a bare `specs/` strip mapped tests/x.md → specs/tests/x.md, zero matches)
      *.spec.ts)  STEM="${ARG#tests/}"; STEM="${STEM%.spec.ts}"   # a compiled-test path maps back
                  SPEC="specs/${STEM}.md" ;;                      # to its paired spec
      *)          STEM="${ARG#specs/}"; STEM="${STEM#tests/}"; STEM="${STEM%.md}"  # bare <area>/<feature> — strip any
                  SPEC="specs/${STEM}.md" ;;                      # dir prefix first, else it doubles to specs/specs/…
    esac
    printf '%s\n' "$SPEC"
    ;;
  test|reportname)
    case "$ARG" in
      *.spec.ts)  TEST="$ARG" ;;
      specs/*.md) TEST="tests/${ARG#specs/}"; TEST="${TEST%.md}.spec.ts" ;;
      *.md)       TEST="tests/${ARG%.md}.spec.ts" ;;   # keep the <area>/ dir — `basename` would flatten tasks/crud.md → tests/crud.spec.ts (wrong)
      */*)        STEM="${ARG#tests/}"; STEM="${STEM#specs/}"     # bare <area>/<feature> (tab-completed specs/… or
                  TEST="tests/${STEM}.spec.ts" ;;                 # tests/… prefixes without extension land here too)
      *)          TEST="tests/${ARG}.spec.ts" ;;       # bare no-slash <feature> — map like spec mode does (a literal pass-through here errored with the UNMAPPED path in the message); the existence check below still guards
    esac
    if [ ! -f "$TEST" ]; then
      echo "No compiled test at '$TEST' (from '$ARG'). Run /qa:gen <spec> first, or pass the tests/*.spec.ts path." >&2
      exit 2
    fi
    if [ "$MODE" = reportname ]; then
      # Flatten to one filename-safe token, AREA-QUALIFIED (auth/login → auth-login):
      # a bare basename would let specs/auth/login.md and specs/admin/login.md write the
      # same reports/headless-login.json and clobber each other.
      NAME="${TEST#tests/}"; NAME="${NAME%.spec.ts}"
      printf '%s\n' "$(printf '%s' "$NAME" | tr '/' '-')"
    else
      printf '%s\n' "$TEST"
    fi
    ;;
  *) echo "usage: resolve-spec-path.sh spec|test|reportname <arg>" >&2; exit 2 ;;
esac
