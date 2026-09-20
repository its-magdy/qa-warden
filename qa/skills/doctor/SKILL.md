---
description: Read-only health check — scripts every freshness / consistency / zero-test / hygiene guard the toolkit otherwise leaves to human memory. Turns "discipline" into "enforcement" without a hook.
argument-hint: "[--verify-invariants specs/<area>/<feature>.md]"
context: fork
background: false
---

`/qa:doctor` runs the deterministic self-checks (checks 0–21) the rest of the toolkit describes
in **prose** ("confirm the run resolved tests", "verify freshness", "the 16-key vocab must
match byte-for-byte", "every `@smoke` test must carry the tag"). The plugin's `PreToolUse`
hooks cover only what is decidable from a single write (CLAUDE.md §Oracle defense); for
everything else, correctness rides on an agent remembering those sentences. `doctor` collapses them into one scripted pass so a
human (or CI) can *run* the guard instead of *remembering* it. It is **read-only**:
it reruns no tests by default, heals nothing, hits no network, writes nothing.

Run from the QA project root (the dir with `playwright.config.ts` + `CLAUDE.md`).

## Run the scripted pass

The entire deterministic check suite (checks 0–21 + rollup) lives in
`scripts/doctor.sh`, stamped into the project by `/qa:init`. Run it — do not
re-derive the checks inline:

```bash
if [ ! -f scripts/doctor.sh ]; then
  if [ ! -f playwright.config.ts ] && [ ! -f package.json ]; then
    # never scaffolded — no substrate at all → plain /qa:init (NOT --resync, which repairs a STALE substrate)
    echo "scripts/doctor.sh missing and no playwright.config.ts/package.json — this project was never scaffolded; run /qa:init to stamp the runtime substrate (never silently pass)"
  else
    # scaffolded before doctor.sh shipped — substrate present but stale → repair with --resync
    echo "scripts/doctor.sh missing but a substrate exists — it predates doctor.sh; re-run /qa:init --resync to stamp it (never silently pass)"
  fi
  exit 2
fi
# Pass CLAUDE_PLUGIN_ROOT EXPLICITLY. Per the plugins reference, the three path placeholders are
# exported as environment variables only "to hook processes and to MCP and LSP server subprocesses"
# — NOT to the Bash tool — but they ARE substituted inline in "skill and agent content, anywhere the
# placeholder appears". So the literal path below is baked into this skill's text before the shell
# ever sees it (same pattern as `skills/init/SKILL.md`'s qa-scaffold call). Without this, doctor.sh's Check 9
# `${CLAUDE_PLUGIN_ROOT:+…}` baseline is always EMPTY and the substrate-drift check silently falls
# back to the installed_plugins.json record, or worse to the newest-mtime GUESS — which can compare
# against a stale orphaned plugin version. The `Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)`
# allow rule in settings.json exists for exactly this form: the permission matcher does NOT strip a
# leading assignment, so this would otherwise miss `Bash(bash scripts/doctor.sh*)` and prompt.
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" bash scripts/doctor.sh
```

The script prints ✅ / ⚠️ / ❌ per check plus a rollup line, and exits 1 on any ❌
(0 on healthy or warnings-only). If the script is missing, that is itself a finding —
**never silently pass**. Distinguish the two states: **no `playwright.config.ts`/`package.json`
at all** means the project was *never scaffolded* → `/qa:init`; a substrate that *exists but
lacks `doctor.sh`* predates it → `/qa:init --resync` (the repair path for a stale substrate).

## Interpreting the output (what to run per failure)

Print a compact report to chat: one line per check, blocking ❌ first. `doctor`
does not fix anything — each finding names its repair:

- **Check 0/1 (jq / last-run.json):** the freshness + zero-test gate is single-sourced
  in `scripts/check-last-run.sh` (shared with `/qa:report` — they used to mirror it in
  prose and drifted). `total` there = expected+unexpected+skipped+flaky — every
  *resolved* test, so an **all-red run is fresh, not zero-test** (`expected` alone
  counts only PASSED tests). Corrupt/zero-test → fix the run and refresh via
  `/qa:run mode=smoke`; stale/missing → confirm which run you mean or re-run.
- **Check 0b (ripgrep missing, WARN):** `rg` is an undeclared plugin-wide dependency. Install it
  (`brew install ripgrep`) *before* running `/qa:retire` — a missing `rg` makes retire's
  "is this shared?" consumer query return empty, which false-reads as "unused ⇒ safe to DELETE".
  A fail-OPEN on a destructive path, so treat it as blocking for retire even though it is a WARN.
- **Check 9bb (arg-shape drift):** a key's argument shape diverged between
  `templates/CLAUDE.md` and `agents/planner.md` — reconcile to CLAUDE.md (the stamped SoT).
  Only the shape expression is compared; rewording the trailing prose never fires this.
  A `did not parse` FAIL means the table format moved and shapes are UNCHECKED, not in sync.
  It also pins `invariant_holds_when:` to the LIST form (`- invariant:`/`holds_when:` pairs) in
  both mirrors — a bare scalar FAILs. That key is in the YAML schema block, not the table, so
  the shape extractor cannot see it; it shipped scalar in CLAUDE.md and list in planner.md,
  and the reviewer reads shapes from the stamped CLAUDE.md.
- **Check 9bc (turn-budget ordering):** an agent's `maxTurns` ceiling is at or below its own
  prose turn budget. Raise the ceiling, don't lower the prose number: `maxTurns` hard-stops and
  returns PARTIAL output, running NO fallback, so pinned at the budget it preempts the behavior
  the budget exists to trigger (file a bug and revert; emit `PARTIAL REVIEW` + FAIL). A
  `no prose turn budget found` FAIL means the declaration was reworded and the invariant is
  UNCHECKED, not satisfied. For the healer, remember `HEALER_TURN_BUDGET` raises the prose
  budget at runtime and cannot raise the ceiling with it.
- **Check 9bd (prod-guard rail coverage):** a skill listed in `scripts/prod-guard-rails.txt`
  either lost its `bash scripts/prod-guard.sh` invocation or stopped acting on the exit code.
  **Restore the rail; never delete one to make this pass** — on the `gen`/`new-spec`/`intake`/
  `explore`/`review` CLI-driving paths that prose is the only prod rail, because the enforced
  `prod-guard.ts` globalSetup fires only under `npx playwright test`. Only invocation + the STOP
  clause are compared, so rewording a rail body never fires this. A WARN naming a skill missing
  from the manifest means a new rail shipped unpoliced — add the line.
- **Check 9be (arg-shape drift, remaining mirrors):** an argument NAME diverged between
  `templates/CLAUDE.md` and `agents/generator.md` or `DOCUMENTATION.md` — reconcile to CLAUDE.md
  (the stamped SoT). Only arg-name SETS are compared, so wording, note length, and instantiated
  example values never fire this. A `produced no rows` FAIL means that mirror's format moved and
  its shapes are UNCHECKED, not in sync. `DOCUMENTATION.md` absent is a WARN — it lives outside
  the plugin dir and is unreachable from a scaffolded project. reviewer Check 4 is deliberately
  NOT compared: it quotes wrong shapes as counter-examples beside right ones.
- **Check 9c (retired permission rule still in settings.json):** `.claude/settings.json` is
  excluded from Check 9's byte-compare and from `--resync` (shared ownership — users add their own
  rules), and the scaffold's jq merge is an additive UNION that can only ADD. So a rule the toolkit
  **retracts** is stranded in every already-scaffolded project forever with nothing to notice it.
  Delete the named rule by hand; `/qa:init --resync` will not do it for you.
- **Check 9d (plugin layout regression):** a `commands/` directory reappeared. `commands/x.md` and
  `skills/x/SKILL.md` BOTH produce `/qa:x` and coexist silently — nothing upstream complains. This
  toolkit is skills-only so it can rely on `context: fork`, `allowed-tools` and bundled
  `scripts/`+`reference/`, none of which exist on the command side. Port the command into a skill;
  a split surface quietly ends those guarantees.
- **Check 9e (`/qa:help` catalog vs the real skill set):** a user-invocable skill has no
  **slash-form** row in `reference/knowledge-map.md`, or a row names something that no longer
  exists. Add/remove the row. Note the two row shapes are not interchangeable: a capability skill
  (`user-invocable: false`) is catalogued by a bare `| **name** |` row, but a real command needs
  the `| `/qa:name`` |` form — that is the invocation `/qa:help` owes the user, and accepting the
  bare shape for commands is how `metamorphic-relations` stayed uncatalogued while this check
  read green.
- **Check 9f (healer MCP grant ↔ settings.json mirror):** the 17 `mcp__playwright__*` entries
  are hand-typed twice — as `agents/healer.md`'s `tools:` list and as `templates/settings.json`'s
  `permissions.allow[]` — and were the last hand-mirrored pair in the substrate with no check.
  **FAIL, either direction.** Declared but not allowed: the healer is a SUBAGENT, so the tool
  prompts with nobody to answer and a step its own prose mandates (HEAL01's `browser_evaluate`
  re-probe) silently cannot run. Allowed but not declared: a standing pre-approval no agent can
  reach, since an explicit `tools:` list is a restriction. Fix by editing both files together.
  A separate **WARN** arm compares the shipped MCP grants against this project's
  `.claude/settings.json`: this is the complement of 9c — 9c catches a rule the toolkit
  RETRACTED and stranded downstream, this catches one it ADDED that never reached a project
  scaffolded earlier. Repair is a plain `/qa:init` (the permission merge is additive and runs
  every time), not a hand edit. Scoped to the `mcp__` entries on purpose: those are capability
  grants with one right answer, whereas a user may legitimately delete a policy rule, and a
  whole-allow-list check would nag them forever.
- **Check 9g (`/qa:gen`'s compiler → verifier chain + the manifest gate):** `generator` and
  `verifier` are two agents on purpose — until the split, the agent that wrote an `expect(...)`
  also decided at steps 8b/8c whether that `expect` catches an injected defect, and its cheapest
  path was to claim it does. No subagent can spawn another, so the chain exists **only** as
  prose in `skills/gen/SKILL.md`, which is an active trim candidate; a trim that drops the
  second call leaves `/qa:gen` green with every spec compiled but ungraded. **FAIL** if
  `agents/verifier.md` is gone, or if that prose stops naming either agent (presence, not
  wording — same doctrine as 9bd). The third arm is the load-bearing one: the route manifest is
  the *ship* signal (`/qa:impact` counts a spec as live coverage only once its manifest exists)
  and it is gated on verification passing, so **exactly one agent may declare
  `Write(artifacts/route-manifests/**)`, and it must be the verifier.** If the generator ever
  reclaims that write, the gate detaches from the thing it gates and a never-verified spec ships
  looking covered. Fix by restoring the two-call chain in `skills/gen/SKILL.md` and leaving the
  manifest grant with the verifier — never by re-adding it to the generator to make the check
  pass.
- **Check 9h (the `hooks/` enforcement layer):** the only part of the toolkit that can block a
  write in real time, and all three of its failure modes are invisible from inside a session.
  **Arm 1, provisioning:** a hook whose `command` does not resolve, or is not executable, does
  **not** block — Claude Code logs a hook error and the write proceeds, so the gate reads as
  shipped while enforcing nothing. **FAIL** on a missing/unparseable `hooks.json` or a dangling
  or non-executable command. **Arm 2, scope ownership** (the 9g arm-3 shape):
  `assertion-contract.sh` fires only for the agents named in its `case` — today `healer` and
  `verifier`, the two whose files forbid touching an assertion — so retiring or renaming one of
  them leaves a syntactically-fine hook scoped to nobody. **Arm 3, stranded deny** (the 9c
  shape): `spec-lint.sh` denies on reviewer Checks 1/5/9/11, and if the reviewer ever retires or
  renumbers one, the hook keeps blocking a construct nothing else objects to, with no path to a
  green write except `QA_HOOKS_OFF=1`. Arms 2 and 3 key on symbols — an agent filename, a check
  number — never on wording, so a reword stays green and a re-parenting does not. Fix by
  restoring the wiring, never by deleting the hook to make the check pass.
- **Check 2 / 9b (vocab drift):** re-sync the 16-key mirror with CLAUDE.md (and, for
  9b, upgrade/re-stamp the plugin agents) in the same commit as any vocab change.
- **Check 3 (vacuous smoke):** tag at least the P1 happy path `@smoke`, then
  `/qa:run mode=smoke`.
- **Check 4 (orphaned sentinels):** close the loop per the sentinel→action table in
  `${CLAUDE_PLUGIN_ROOT}/reference/sentinel-actions.md` — re-seed / re-explore / migrate as the sentinel names.
- **Check 5/5b (stale or draft context):** `/qa:explore mode=area <area>` to refresh,
  then clear `draft:` / bump `last_verified:`.
- **Check 6 (undeclared env):** declare the variable in `.env.example` (commented is
  fine for optional-with-fallback vars).
- **Check 7/7d (pins / idiom):** fix `package.json` / regenerate the offending
  `fixtures/schemas/` file in the pinned major's idiom.
- **Check 8b (MCP paired-bump lockstep):** `.mcp.explore.json`'s `npx -y playwright@X.Y.Z mcp`
  version must equal `overrides.playwright` in `package.json` — since 1.62 the MCP server ships
  bundled with `playwright`, so these are one version, mirrored in two files. A **bare, unpinned**
  `playwright` npx arg is itself a FAIL: with no `node_modules` (fresh clone, lockfile-less CI) npx
  silently fetches the LATEST Playwright, recreating the runner/core skew the `overrides` block
  exists to prevent — from the explore config, where `overrides` cannot reach it. Fix by bumping
  both sites together, never by unpinning.
- **Check 8/9 (canonical scripts / substrate drift):** `/qa:init --resync` (backs up
  drifted files to `*.qa-bak`). A missing stock var in `.env.example` → restore it from
  the shipped template, or park it commented (`# VAR=`) — the stock list is derived from
  the template, and the file itself is shared-ownership and never byte-compared. The
  drift baseline is the RECORDED active plugin install; a "baseline GUESSED by newest
  mtime" ⚠️ means the install record didn't resolve — re-run via `/qa:doctor` (which
  resolves `CLAUDE_PLUGIN_ROOT`) before trusting a drift verdict.
- **Check 10 (site↔project routing):** add the missing `playwright.config.ts` project
  or fix the `sites[].id`.
- **Check 11 (bug Status):** add the `## Status:` marker to the named `bugs/*.md`.
- **Check 11b (durable evidence, WARN):** an open `bugs/*.md` that cites its trace/screenshot
  under `artifacts/test-results/…` (volatile — wiped the next time the test runs green) or a
  path that is already gone. Copy the evidence into a durable `bugs/<slug>/` folder and cite
  that (healer HEAL03), or resolve the bug if its test is now green (HEAL04).
- **Check 11c (parked marker on a resolved bug, WARN):** a live `test.fail`/`test.fixme` marker
  whose linked `bugs/*.md` is already `Status: fixed`/`reverted` — a stale marker laundering a
  resolved defect into the green roll-up. Remove the marker, or reopen the bug if it regressed
  (mirrors reviewer Check 3).
- **Check 12 (stale manifest):** `/qa:gen <spec>` to regenerate the route manifest.
- **Check 13 (declared-mutation isolation, WARN):** the basis declares
  `mutates_server_state: true` but a resolved test shows no isolation marker
  (parallelIndex / serial / seeded fixture) — un-isolated mutation is green at 1 worker,
  flaky at scale. Resolution mirrors `/qa:coverage` dim 1: the direct
  `tests/<feature>.spec.ts` PLUS every fanned spec linking back via `basis:` (twins
  included); a mutating feature that resolves to ZERO tests is its own WARN, never a
  silent skip. Wire the isolation (see the basis `test_data:` block) or regenerate via
  `/qa:gen`. The reviewer's code-level Check 13 remains the enforcing gate.
- **Check 14 (unmanaged test, WARN):** a `tests/**/*.spec.ts` with no paired
  `specs/<area>/<feature>.md` sits outside the assertion contract — write the spec
  (`/qa:new-spec`) or consciously exempt it (move to `tests-legacy/`).
- **Check 15/15b (review attestation, WARN):** the spec/test pair changed since its
  `reports/review/<area>/<feature>.reviewed` marker (or was never reviewed), or a
  `// verified: must_fail_when "…"` stamp no longer matches the spec's invariant text —
  re-run `/qa:review` (and `--verify-invariants` for a stale stamp). Markers are
  agent-writable convenience; the unforgeable layer is the CI required-status
  (see `/qa:review` §CI wiring) — this catches *forgotten* reviews, not malicious ones.
- **Check 16 (smoke-tagged spec with no test, WARN):** a spec declares a `tags: [… smoke …]`
  scenario but was never compiled — `/qa:run mode=smoke`'s `--grep @smoke` is blind to that P1 flow, so a
  fully-broken governed path (admin RBAC, checkout charge==total) passes the smoke gate because no
  test exists to fail. Complements Check 3 (which only proves *some* test carries the tag). Compile
  it (`/qa:gen`) or drop the smoke tag from the spec.
- **Check 17 (spec with no compiled test — ANY tag, WARN):** the complement to Check 16 — a
  `@regression`-only spec authored but never generated sits outside the assertion contract and no
  run exercises it (Check 15 `continue`s past it, Check 16 is smoke-only). `/qa:gen` it, or
  `/qa:retire` / `# waived:` it if its scenarios are intentionally folded into a sibling.
- **Check 18 (abandoned authoring chain, WARN):** a `.cases.md` (the approval artifact) with no
  downstream spec — the intake→ideate→approve chain ran but never produced a spec, so the intended
  coverage silently never shipped. `/qa:new-spec <area/feature>` or `/qa:retire` the chain.
- **Check 19 (unattested interview, WARN):** a `.basis.md` with `[human-answered]` oracle rules but
  `interview: none`/absent — the human grounding is unattested (a fabricated basis looks identical).
  `/qa:intake` should stamp the real question count in the basis `interview:` field.
- **Check 20 (`.env`-load idiom drift, WARN):** the canonical `.env`-load one-liner is duplicated
  verbatim across several plugin skill/agent files (each subagent needs its own inline copy —
  it can't read CLAUDE.md); this WARNs only if more than one distinct form exists. Re-sync every
  copy to the canonical `${CLAUDE_PROJECT_DIR:-.}`-anchored form in CLAUDE.md §Environment.
- **Check 21 (fresh-project readiness, INFO):** not a warning — on a brand-new project (no
  `app.context.md`/specs) it prints a "setup looks healthy — next run `/qa:explore`" verdict so the
  expected empty-project WARNs read as "expected at this stage", not "something's broken".

## Optional: `--verify-invariants specs/<area>/<feature>.md` (executable `must_fail_when`)

Only when `$ARGUMENTS` contains `--verify-invariants`: read
`${CLAUDE_SKILL_DIR}/reference/verify-invariants.md` and follow it. That file is THE single
source of the injection mechanism (the verifier's Process step 8b runs the same one); do not
re-derive it here. In the default read-only pass, skip this section entirely — it is the only
mode that runs tests, and it still writes nothing.

This skill runs as a forked subagent, so the caller sees only what you return: report the
per-check ✅/⚠️/❌ lines and the rollup, then the interpretation above for each ❌/⚠️. Never
return a bare "healthy" while any ❌ stands.

This skill reruns nothing in default mode, invokes no healer, and writes nothing.
