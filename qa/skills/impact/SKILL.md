---
description: Test-impact analysis — given a route, field, factory, area, GraphQL operation, or business source, list every spec that would be affected by a change to it. Reads artifacts/route-manifests/ (and specs/_context for source=).
argument-hint: "<route=<path> | field=<name> | factory=<name> | area=<name> | operation=<name> | source=<name>>"
context: fork
background: false
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/impact.sh *)
---

Find every spec affected by a change to `$ARGUMENTS` by intersecting against
the per-spec route manifests under `artifacts/route-manifests/`.

This is the "home-rolled test-impact analysis" — Move 2 of the change-cascade
playbook. No vendor ships an E2E impact graph in 2026 — this is the gap-filler.

## Usage

```
/qa:impact route=/signup
/qa:impact field=full_name
/qa:impact factory=user
/qa:impact area=auth
/qa:impact operation=CreateOrder
/qa:impact source=pricing-wiki §3.2
```

## Run the query

Run from the **project root** (every path it reads is project-relative) and pass
`$ARGUMENTS` through verbatim:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/impact.sh "$ARGUMENTS"
```

The script is the single source of the query recipes and their rationale — **do not
re-derive, re-implement, or inline any of it here.** It is pre-approved by this skill's
`allowed-tools`, so it runs without a permission prompt; run it exactly as written above
(a rewritten invocation loses the grant and prompts).

**Non-interactive fallback (F-29):** `$ARGUMENTS` is interpolated for a real typed
slash-command, but when this skill is reached via the Skill tool / a subagent it can arrive
**empty**. On that path pass the literal key=val as the script's argument instead
(`bash ${CLAUDE_SKILL_DIR}/scripts/impact.sh route=/login`) — otherwise you get a usage
error, not a result.

**Exit codes:** `2` = usage error, `3` = no manifests on disk (run `/qa:gen` on a spec
first). **Neither is a zero-match result** — never report either as "not impacted".

For the five manifest-backed keys the script emits two sections. `### MATCHES` is
`<area>\t<spec>`; `### BLIND SPOTS` lists
compiled tests that have **no manifest** and are therefore invisible to the query. If BLIND
SPOTS is non-empty the result is INCOMPLETE — report those specs as "possibly affected but
unanalyzed" alongside the matches; do not present the table as exhaustive. If stderr carries
`[jq parse error …]`, a manifest is corrupt — report it and do not treat the (possibly
short) match list as complete.

Your job from here is **formatting only** — do not recompute or estimate anything it emitted.

## Output format

(`source=` is the odd one out — it queries the intake `[grounded: …]` stamps in
`specs/_context`, not the manifests, so it returns its own pre-formatted
`area | spec | test | rules_grounded=N` lines plus a caveat footer. Pass those through; the
table below does not apply.)

Group `### MATCHES` by area as a Markdown table:

```
| Area     | Spec                              |
| -------- | --------------------------------- |
| auth     | specs/auth/signup.md              |
| profile  | specs/profile/edit-profile.md     |
```

Then a one-line summary: `N specs across M areas reference <argument>.`

**When N=0, never stop at a bare "0 matches"** — a silent 0 reads to the user as "not
impacted", which is impact's cardinal sin. Always add that the manifest is verifier-emitted,
so newly-added specs that haven't been compiled yet won't appear. And when the key is
`field=`, print this **instead of** the generic uncompiled note, so it can't misdirect:

> `field=` matches schema/form field names only (the factory's `.fields` array — `email`,
> `password`), **not** UI/oracle testids (`stat-open`, `order-total`). A 0 here does NOT mean
> "not impacted" — for a UI element, grep `tests/` for the testid, or use `route=`/`operation=`. (F-14)

## Returning your result

This skill runs as a forked subagent, so the caller sees only what you return: return the FULL
affected-spec table, never a count or a prose summary of it. The enumerated list IS the
deliverable — "5 specs affected" tells the caller nothing they can act on.

## When to use

- Before editing `fixtures/schemas/<entity>.ts`: `/qa:impact field=<old-field-name>` shows everything that will compile-break.
- After a product RFC lands: `/qa:impact route=/<new-route>` shows which specs need to start covering it.
- Before deprecating a feature: `/qa:impact area=<area>` shows the suite-level footprint.
- During a healer triage: `/qa:impact field=<failing-field>` reveals whether the failure is local or systemic.
- Before deprecating/replacing a business source (a wiki page, a policy doc): `/qa:impact source=<name>` shows every basis rule grounded in it.
- GraphQL apps: `/qa:impact operation=<OperationName>` — route-level impact collapses to `/graphql`, so the operation key is the discriminating one.

## What this does NOT do

- It does not regenerate tests. Use `/qa:gen` after editing affected specs.
- It does not handle transitive references (spec → step fragment → other spec). The manifest is per-spec only.
- It does not catch fields referenced in raw test code that bypass the factory (Reviewer Check 10 enforces factory-only).
- It does not query a live DB. Manifests are derived from the spec + AX-tree snapshot at generate time.

## Refresh policy

If `/qa:impact` returns stale or zero matches you expect to see, the manifest is out of date. Run `/qa:gen <spec-path>` to regenerate. A future enhancement could auto-warn when a spec's `.md` mtime is newer than its manifest.
