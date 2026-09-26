---
description: Draft a new Markdown+YAML spec for one feature via the planner subagent. Runs LAST in the authoring chain (intake → ideate → approve → new-spec) — PRECONDITIONS — the area's context (specs/_context/app.context.md + <site>/<area>.md) must exist and be fresh, and if a .cases.md exists it must be APPROVED. The planner STOPs (handoff) on missing/stale context or un-approved cases.
argument-hint: "<area/feature> [site=<id>] [basis=<area>/<feature>]"
disable-model-invocation: true
---

Delegate to the `planner` subagent (uses `@playwright/cli`) to draft a new spec.

**No argument given?** If `$ARGUMENTS` is empty, do **NOT** proceed and do **NOT** guess a
feature — print the block below verbatim and stop:

```
Usage:  /qa-warden:new-spec <area/feature> [site=<id>] [basis=<area>/<feature>]
Draft a spec for ONE feature. <area/feature> is a path you choose — for example:

  /qa-warden:new-spec auth/login          test the sign-in flow
  /qa-warden:new-spec tasks/update-task   test editing a task
  /qa-warden:new-spec checkout/coupon     test applying a discount code

First time? Follow ${CLAUDE_PLUGIN_ROOT}/reference/tutorial-first-test.md (a ~10-minute walkthrough).
```

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh` first — STOP and ask the user to confirm in-chat if it exits non-zero. The subagent's live-snapshot steps drive `playwright-cli` against `$BASE_URL_<SITE>` — only the `npx playwright test` half is covered by the enforced `globalSetup` guard; the CLI-driving half has no backstop but this check.

**Parse `$ARGUMENTS` into the path token vs `key=val` flags FIRST** — the spec
path is only the first bare (non-`key=val`) token; everything of the form
`site=…` is a flag, not part of the filename. Building `specs/$ARGUMENTS.md`
verbatim produces a broken name like `specs/checkout/coupon site=app.md` when a
flag is passed inline:
```bash
# zsh (this host's default Bash-tool shell) doesn't word-split unquoted vars —
# force it so the site= flag separates from the path; no-op in bash.
[ -n "${ZSH_VERSION:-}" ] && setopt shwordsplit 2>/dev/null
set -- $ARGUMENTS
FEATURE=""; SITE=""; BASIS=""
for tok in "$@"; do
  case "$tok" in
    site=*)  SITE="${tok#site=}" ;;
    basis=*) BASIS="${tok#basis=}" ;;   # parent checklist of a fanned spec (from /qa-warden:approve)
    *)      [ -z "$FEATURE" ] && FEATURE="$tok" ;;   # first bare token = <area/feature>
  esac
done
# Canonical resolver accepts bare <area>/<feature>, <area>/<feature>.md, or a full
# specs/… path (missing script → re-run /qa-warden:init to stamp it).
SPEC_PATH=$(bash scripts/resolve-spec-path.sh spec "$FEATURE")   # e.g. specs/checkout/coupon.md
```
So `/qa-warden:new-spec admin/refund-partial site=admin` → `specs/admin/refund-partial.md` with
`site=admin` handed to the planner, never baked into the filename. With no `site=`, the planner
infers from the story and raises an Open Question if ambiguous. `basis=<area>/<feature>` names the
parent checklist when `/qa-warden:approve` fanned one feature into several specs; hand it to the
planner verbatim ("basis=checkout/coupon") — it reads `<parent>.basis.md`/`.cases.md` under that
name and stamps `basis:` in the YAML. Without it a fanned spec has no approved rows to compile
from and the planner, seeing no `.cases.md`, takes the fast lane past the approval gate.

**Area-name sanity check (WARN — the fast lane is deliberately lighter than
`/qa-warden:intake`) (F-20).** After resolving the `<area>` segment, check it against
`naming.area_dirs` in `specs/_context/app.context.md` — the same list `/qa-warden:intake`
**hard-stops** on. The fast lane does NOT hard-stop (it is the lighter path), but if
`<area>` is not a declared `area_dir` (e.g. `catalog` when the declared area is
`products`), **WARN**: "area `<area>` is not in `naming.area_dirs` — this creates a
mismatched `specs/<area>/` tree that `/qa-warden:coverage` will later flag as an orphan area;
add it to `area_dirs` or use the declared name." Then proceed — the operator may be
intentionally introducing a new area.

**`site=` is auth/context only — it is NOT folded into the spec path.** The area
directory comes from the **bare `<area>/<feature>` token**. The shipped `admin`
Playwright project routes by the **`@site:admin` tag** the generator always emits — NOT
by a `tests/admin/**` path — so `site=admin` alone sends the spec to the admin baseURL
wherever its area folder lives: `/qa-warden:new-spec refund-partial site=admin` routes
correctly. Group admin specs under an `admin/` area only for organization
(`/qa-warden:new-spec admin/refund-partial site=admin`), never because routing requires it.
`site=` flows to the planner for context/auth and to the generator as the `@site:` tag.
(Why routing is tag-based, and the trap in re-introducing a path-routed project:
`reference/DESIGN.md` §"Site routing is tag-based, not path-based".)

**Existing spec? Delegate it as a REVISION (⛔ data loss).** After `SPEC_PATH` resolves:
```bash
[ -f "$SPEC_PATH" ] && echo "EXISTS — revision, not authoring: $SPEC_PATH"
```
If it exists, say so in the delegation — tell the planner it is **revising `$SPEC_PATH`** and
name the specific change. Its Process 4c then takes the `Read`+`Edit` path instead of
overwriting: a one-pass rewrite silently drops hand-added scenarios, `# waived:` lines and the
`basis:` pairing with every downstream check still green. Same path `.healer-needs-spec-update`
uses. If the story replaces the oracle wholesale rather than amending it, the planner STOPs and
hands the decision back — `/qa-warden:retire` the old spec first, then re-run this command clean.

The planner reads:

1. **Hot tier** — `specs/_context/app.context.md` for the `sites:` table.
2. **Specialist tier** — `specs/_context/<site>/<area>.md` for the chosen
   (site, area). If missing or stale (past the area's `volatility:`-tier
   threshold in `staleness_tiers:`), the planner **cannot spawn exploration
   itself** (a subagent can't invoke another subagent). It STOPS and returns a
   handoff asking for area context; THIS command then runs
   `/qa-warden:explore mode=area site=<id> area=<name>` and re-invokes the planner.
   (This block is deliberate and has no escape hatch: the planner's own prompt
   forbids drafting from the hot tier alone — guessed area vocabulary is the
   failure mode this gate exists to prevent, and no downstream check reads a
   `draft:` flag on a *spec*, so a "flagged" draft would flow into `/qa-warden:gen`
   unmarked in effect.)

It produces Markdown narrative with a fenced ```yaml oracle block containing:
`{name, tags, site, data, steps, oracle, must_fail_when, output_schema}`.
The `site:` field is REQUIRED and MUST match a `sites[].id` in the hot tier
(reviewer Check 8 fails the PR on unknown ids).

**Use the closed oracle vocabulary only** — the canonical 16-key set defined in
CLAUDE.md §"Test case format contract" (the stamped single source of truth; the
planner and reviewer Check 4 mirror it — do not restate the list here, defer to
CLAUDE.md). No free-form "should look right". **Include `must_fail_when` and `output_schema`**
— `must_fail_when` documents the defects the test must catch; `output_schema` gates
the evidence. `must_fail_when` is **advisory in the sense that the author isn't forced
to *declare* one — but once declared it IS enforced**: reviewer **Check 2b** FAILs any
spec whose `must_fail_when:`/`fail_if:` invariant isn't reified as an oracle (or
explicitly waived), and the verifier's post-green **step 8b** fault-injects each one to
prove the oracle actually goes red (`/qa-warden:doctor --verify-invariants` re-runs this). So a
declared invariant that you drop from the oracle is a merge blocker, not a silent pass.
Only `output_schema` lacks a reviewer presence-check. (See CLAUDE.md §"Oracle defense".)

Negative/error-path specs also need `fail_if:` + `prompt_guardrail:` stanzas
(see CLAUDE.md §Test case format).

**Every APPROVED `.cases.md` case must become a scenario — or be explicitly waived.** When you
scope an approved checklist into `scenarios:`, do not silently drop an approved row: if you
consciously leave one out (deferred to a follow-up spec, out of this spec's scope), add a
`# waived: <case> — <reason>` line to the spec (in `# Open questions` or a `waiver:` note) naming the
specific case. An approved case that is neither a scenario nor a named waiver is flagged by reviewer
**Check 14** (approved-case traceability, WARN — the green-but-incomplete catch) and shows up in
`/qa-warden:coverage` dim-5's count. Naming it "Deferred"/"pruned" back in the `.cases.md` banner also
counts as a waiver. This keeps the human approval gate load-bearing rather than advisory.
When approved groups fan out into separate specs (one `/qa-warden:new-spec` per group), approve
prints `basis=<area>/<feature>` on each line and this skill forwards it, so the planner reads the
parent checklist and sets `basis: <area>/<feature>` on every fanned spec — which is how Check 14 and
`/qa-warden:coverage` pair it back.

**Naming a fanned spec — deriving the `<feature-case>` the chain hands you.** After `/qa-warden:approve`,
`/qa-warden:ideate` and `/qa-warden:approve` point you at `/qa-warden:new-spec <area/feature-case>` "for each approved
group." The `-case` suffix is a **human-readable slug of the approved rule-GROUP, not the raw row id**
(R1, R2, NF.a11y…). Derive it from the group's subject:
- one spec for the whole feature → just `/qa-warden:new-spec auth/login` (no suffix)
- a scoped group, e.g. approved rows about coupon-stacking → `/qa-warden:new-spec checkout/coupon-stacking basis=checkout/coupon`
- a non-functional group, e.g. `NF.a11y` → `/qa-warden:new-spec checkout/coupon-a11y basis=checkout/coupon`

Keep the slug kebab-case and stable; the planner stamps `basis: <area>/<feature>` (above) so
coverage/Check 14 pair every fanned spec back to the same checklist regardless of the suffix.

Do NOT emit `.spec.ts` here — that is `/qa-warden:gen`'s job.
