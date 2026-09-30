---
description: Invoke the exploration subagent — hot mode (refresh app.context.md) or area mode (write specs/_context/<site>/<area>.md). Default = hot ONLY on a bare invocation; an area invocation missing mode=/site=/area= STOPs rather than defaulting. Use when a site's auth/env has changed, an area's context file is missing or past its staleness tier, or planner/healer reports stale/missing context and hands off here.
argument-hint: "[mode=hot | mode=area site=<id> area=<name>]"
---

Delegate to the `exploration` subagent (uses `@playwright/cli`).

Primary discovery is **black-box** — drive the live app and read its AX tree. But exploration
**may also read product source as a grey-box tiebreaker** (F-10): to disambiguate a route/field/API
or find a stable `data-testid` hint, per CLAUDE.md's grey-box sanction (`agents/exploration.md`).
Locators still always come from the live AX tree at generate time — source reading only resolves
ambiguity, it never becomes the selector authority.

Two modes:

- **`mode=hot`** (the default only on a *bare* invocation — see the dispatch guard below) — refresh `specs/_context/app.context.md`: verify `sites:` table, auth flows per site, env vars, naming conventions. Updates `last_verified:` to today. Keep the hot tier tight (~80 lines, a tunable target). **First run (no `app.context.md` yet):** the exploration agent scaffolds a populated `draft: true` context and STOPS for a human to confirm before it counts as verified — the reviewer treats a `draft: true` hot tier as unverified. So the first `/qa-warden:explore` produces a draft to review, not a finalized file.
- **`mode=area site=<id> area=<name>`** — discover one product area on one site. Writes `specs/_context/<site>/<area>.md` with routes in scope, domain vocab, observed flakes, and cross-site contracts (if any). Selectors are NOT cached — the generator pulls them live at compile time.

**Dispatch before you delegate — the default is a guard, not a fallback.** Check the arguments
first; `agents/exploration.md` §"Mode selection" carries the same arms, and this is the
layer where a mistyped command can still be corrected for free:

- **Nothing passed** → `mode=hot`, and say so (`mode=hot (defaulted — no mode given)`) so a
  defaulted run is never mistaken for the area refresh someone meant to ask for.
- **BOTH `site=` and `area=` present without `mode=area`** → run it as `mode=area` and say so
  (`mode=area (inferred — site= and area= given)`). Nothing is guessed: both keys were typed,
  and no other mode consumes them.
- **Only ONE of `site=` / `area=` present without `mode=area`** → **STOP** and echo the corrected
  command. Do **not** fall through to hot.
- **`mode=area` without both `site=` and `area=`** (including a positional `mode=area <area>`)
  → **STOP** and name the missing key. Do not infer it.

Why a STOP beats a best guess: hot mode's last step stamps `last_verified: <today>` on
`app.context.md`, and reviewer Check 7 / doctor Check 5b read that date as "verified accurate as
of". So a wrong-mode run does not merely do the wrong work — it marks context fresh that nobody
verified, and reports the area the caller actually asked about as handled. (`bin/qa-selfcheck` Check 9j
keeps this repo's own printed invocations well-formed for the same reason.)

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh` first — STOP and ask the user to confirm in-chat if it exits non-zero. Run it exactly as written — its last line states the verdict, and an appended `; echo $?` stops the command matching its allow rule.

```bash
# Reachability probe (AFTER prod-guard passes) — the SAME target set the guard screens, as one
# allow-listed call (it was an inline loop; a compound command needs a rule per subcommand, so it
# prompted, and was denied outright headless). Reachability ONLY — any HTTP status (200, 302,
# 401, 500…) means the host is up; it does NOT prove the app works. Only DNS failure / timeout /
# connection-refused count as unreachable: a `STOP:` line / exit 1 → stop and relay it.
bash scripts/prod-guard.sh --probe
```

Examples:

```
/qa-warden:explore                                          # refresh hot tier
/qa-warden:explore mode=hot                                 # same
/qa-warden:explore mode=area site=admin area=refunds        # write specs/_context/admin/refunds.md
/qa-warden:explore mode=area site=app area=checkout         # write specs/_context/app/checkout.md
```

When to re-run:
- **Hot**: site added/removed, auth provider change, env-var change, naming-convention change.
- **Area**: planner/reviewer reports the area file is missing or stale (past its `volatility:`-tier threshold in `staleness_tiers:`); healer classified a failure as "Stale specialist context".

Do not write `.spec.ts` — exploration only writes under `specs/_context/`.
