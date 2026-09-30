---
description: Read-only scripted health check of a scaffolded QA project — last-run freshness and zero-test guards, substrate drift, vocab mirrors, stale context and manifests, orphan sentinels, unreviewed or uncompiled specs. Use when something looks off, before trusting a green run, after a plugin upgrade, or when another command points here. Writes nothing; `--verify-invariants <spec>` is the only mode that runs tests.
argument-hint: "[--verify-invariants specs/<area>/<feature>.md]"
context: fork
background: false
---

`/qa-warden:doctor` runs the deterministic self-checks (checks 0–21) the rest of the toolkit describes
in **prose** ("confirm the run resolved tests", "verify freshness", "the 16-key vocab must
match byte-for-byte", "every `@smoke` test must carry the tag"). The plugin's `PreToolUse`
hooks cover only what is decidable from a single write (CLAUDE.md §Oracle defense); for
everything else, correctness rides on an agent remembering those sentences. `doctor` collapses them into one scripted pass so a
human (or CI) can *run* the guard instead of *remembering* it. It is **read-only**:
it reruns no tests by default, heals nothing, hits no network, writes nothing.

Run from the QA project root (the dir with `playwright.config.ts` + `CLAUDE.md`).

## Run the scripted pass

The entire deterministic check suite (checks 0–21 + rollup) lives in
`scripts/doctor.sh`, stamped into the project by `/qa-warden:init`. Run it — do not
re-derive the checks inline:

Run this ONE command, as its own Bash call (an `if …; fi` wrapper matches no allow rule and is
denied headless). If it fails with "No such file" for `scripts/doctor.sh`, the script is missing:
see the two cases below (Glob for `playwright.config.ts` / `package.json` to tell them apart).

```bash
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
at all** means the project was *never scaffolded* → `/qa-warden:init`; a substrate that *exists but
lacks `doctor.sh`* predates it → `/qa-warden:init --resync` (the repair path for a stale substrate).

## Interpreting the output (what to run per failure)

Print a compact report to chat: one line per check, blocking ❌ first. `doctor`
does not fix anything — each finding names its repair:

- **Check 0/1 (jq / last-run.json):** the freshness + zero-test gate is single-sourced
  in `scripts/check-last-run.sh` (shared with `/qa-warden:report` — they used to mirror it in
  prose and drifted). `total` there = expected+unexpected+skipped+flaky — every
  *resolved* test, so an **all-red run is fresh, not zero-test** (`expected` alone
  counts only PASSED tests). Corrupt/zero-test → fix the run and refresh via
  `/qa-warden:run mode=smoke`; stale/missing → confirm which run you mean or re-run.
- **Check 0b (ripgrep missing, WARN):** `rg` is an undeclared plugin-wide dependency (the healer,
  reviewer and planner greps use it). `/qa-warden:retire` checks for it and falls back to
  `grep -rlE` for its consumer checks; install it anyway (`brew install ripgrep`).
- **Check 9bb (arg-shape drift):** a key's argument shape diverged between
  `templates/CLAUDE.md` and `agents/planner.md` — reconcile to CLAUDE.md (the stamped SoT).
  Only the shape expression is compared; rewording the trailing prose never fires this.
  A `did not parse` FAIL means the table format moved and shapes are UNCHECKED, not in sync.
  It also pins `invariant_holds_when:` to the LIST form (`- invariant:`/`holds_when:` pairs) in
  both mirrors — a bare scalar FAILs. That key is in the YAML schema block, not the table, so
  the shape extractor cannot see it; it shipped scalar in CLAUDE.md and list in planner.md,
  and the reviewer reads shapes from the stamped CLAUDE.md.
- **Check ids 9b / 9bc / 9be / 9d / 9e / 9h / 9j belong to `bin/qa-selfcheck`, not doctor.** They read only the
  plugin's own source, so nothing in a project could fix one; they run from the toolkit repo as
  `bin/qa-selfcheck` (same ids, same messages). If a user reports one of those ids, the fault is in
  the plugin build, not their project — the remedy is updating the plugin, not editing anything here.
- **Check 9bd (prod-guard rail coverage):** a skill listed in `scripts/prod-guard-rails.txt`
  either lost its `bash scripts/prod-guard.sh` invocation or stopped acting on the exit code.
  **Restore the rail; never delete one to make this pass** — on the `gen`/`new-spec`/`intake`/
  `explore`/`review` CLI-driving paths that prose is the only prod rail, because the enforced
  `prod-guard.ts` globalSetup fires only under `npx playwright test`. Only invocation + the STOP
  clause are compared, so rewording a rail body never fires this. A WARN naming a skill missing
  from the manifest means a new rail shipped unpoliced — add the line.
- **Check 9c (retired permission rule still in settings.json):** `.claude/settings.json` is
  excluded from Check 9's byte-compare and from `--resync` (shared ownership — users add their own
  rules), and the scaffold's jq merge is an additive UNION that can only ADD. So a rule the toolkit
  **retracts** is stranded in every already-scaffolded project forever with nothing to notice it.
  Delete the named rule by hand; `/qa-warden:init --resync` will not do it for you.
  A second arm raises ONE warning for any path-scoped `Write(<path>)` rule: Claude Code checks
  file permissions against `Edit(...)`/`Read(...)` rules only, so such a rule is never consulted
  (and is warned about at startup). The template shipped 30 of them, each with an `Edit` twin,
  until 0.4.0. Delete them; give any rule without an `Edit` twin one.
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
  scaffolded earlier. Repair is a plain `/qa-warden:init` (the permission merge is additive and runs
  every time), not a hand edit. Scoped to the `mcp__` entries on purpose: those are capability
  grants with one right answer, whereas a user may legitimately delete a policy rule, and a
  whole-allow-list check would nag them forever. (`scripts/doctor.sh` is itself a resynced file, so a
  wider check here could only reach a project through the same command that repairs the gap.)
  **Arm 3 (WARN)** covers what the repair cannot: the merge needs `jq`, and without it the
  scaffold parks the shipped rules in `.claude/settings.qa-suggested.json`. That file's presence
  is proof the merge never ran — unlike a subset check it cannot confuse *undelivered* with
  *declined* — so doctor names it, counts the rules still missing, and says what they cost. A
  successful merge deletes the file, so the signal cannot go stale; a hand-merged leftover is
  reported separately as stale. The presence test sits outside the `jq` gate, because the state
  it detects is `jq` being absent.
- **Check 9g (`/qa-warden:gen`'s compiler → verifier chain + the manifest gate):** `generator` and
  `verifier` are two agents on purpose — the agent that wrote an `expect(...)` never decides
  at steps 8b/8c whether it catches an injected defect, because its cheapest path is to claim
  it does. No subagent can spawn another, so the chain exists **only** as prose in
  `skills/gen/SKILL.md`; if that prose drops the second call, `/qa-warden:gen` goes green with every
  spec compiled but ungraded. **FAIL** if
  `agents/verifier.md` is gone, or if that prose stops naming either agent (presence, not
  wording — same doctrine as 9bd). The third arm is the load-bearing one: the route manifest is
  the *ship* signal (`/qa-warden:impact` counts a spec as live coverage only once its manifest exists)
  and it is gated on verification passing, so **exactly one agent may declare
  `Write(artifacts/route-manifests/**)`, and it must be the verifier.** If the generator ever
  reclaims that write, the gate detaches from the thing it gates and a never-verified spec ships
  looking covered. Fix by restoring the two-call chain in `skills/gen/SKILL.md` and leaving the
  manifest grant with the verifier — never by re-adding it to the generator to make the check
  pass.
- **Check 9, CLAUDE.md vocabulary containment:** the delivery half of the upgrade path.
  `CLAUDE.md` is shared-ownership, so it is excluded from `--resync` *and* from Check 9's
  byte-compare — yet it is where every new authoring feature is documented, and the in-project
  agents read it rather than the plugin. After a clean, green, exit-0 `/qa-warden:init --resync` the
  stamped `CLAUDE.md` can therefore lack every new authoring feature (`fault:`, `clock:`,
  `lock:`, `verifier`) while doctor says nothing else. The symbols come from
  `scripts/claude-md-vocab.txt` and are gated on the shipped template, the same derive-don't-
  hand-enumerate shape as the `.env.example` stock-var containment beside it. The check is
  symbol-level, not section-level: new rules land inside pre-existing sections, so a heading
  diff reports green on exactly the release it was built for. **WARNs, never FAILs:** alone among
  Check 9's findings the repair is a hand-merge against the shipped template, not a command, and
  a repair the toolkit cannot perform must not be louder than the ones it can.
- **Check 9i (the situation-step chain — `fault:` / `clock:`):** the two structured `steps:`
  forms that make the SFDIPOT Interfaces/Operations and Time lenses generatable. They are
  deliberately **not** oracle keys, so `scripts/oracle-keys.txt` does not carry them — the whole
  contract is prose across four files. **Arm 1, chain
  completeness:** the planner AUTHORS the step, the generator COMPILES it, the reviewer
  VALIDATES it, and `templates/CLAUDE.md` is what gets STAMPED into a project (the in-*project*
  reviewer reads its own copy and cannot read the plugin). Each link, dropped, fails in its own
  silent direction — a missing planner mirror is the audit's own *"a capability that only lands
  in the generator is one the planner can never ask for"*. Keyed on the step SYMBOLS, never on
  wording. **Read arm 1 as the shipping SOURCE, not delivery:** all four links are plugin-side
  files, so it stays green however stale an already-scaffolded project's own `CLAUDE.md` is. The
  delivered copy is Check 9's CLAUDE.md containment sub-check (below), which is where `fault:`
  and `clock:` are actually policed downstream. **Arm 2, scope
  ownership:** the healer's prohibition on *introducing* a stub or a clock call is enforced by
  `assertion-contract.sh`, and that arm must scope to the **healer alone** — widen it to the
  verifier and its step-8b fault injection (which *is* a `page.route`) gets denied, breaking the
  negative control the oracle-defense layer rests on; narrow it to nobody and the healer can stub
  a genuinely-broken backend green. **Arm 3, stranded contract** (the 9c shape): the fired-proof
  for a response-fabricating `fault:` is a paired `network_response_status` oracle — chosen so the
  feature needs no 17th key, which makes the rule depend on a key it does not own. Retire that key
  and every `fault:` spec becomes unauthorable while four files still demand the pairing.
- **Check 9k (unmanifested-walk ownership):** "which compiled tests carry no route manifest" is
  one rule with two consumers that must never disagree — `/qa-warden:impact` prints it as
  `### BLIND SPOTS` (a zero-match there is only honest if the caller is told which specs were
  invisible) and `/qa-warden:coverage` dim 0 needs it to avoid the label it used to print, where an
  unmanifested test's routes landed under "touched by NO compiled test (planned, untested)" —
  false for a spec that was authored and compiled, and it sent the reader to write a second
  spec instead of clearing the blocker the verifier withheld the manifest for. **Arms 1 and 2
  key on SYMBOLS** — the `unmanifested)` mode name and the `*.metamorphic.spec.ts` exclusion
  glob. Arm 2 is the one that matters: a twin never carries a manifest BY DESIGN (verifier V4
  emits one per spec), so a copy that drops the exclusion makes both consumers cry wolf on
  every twin until someone deletes the section. **Arm 3 keys on the CONSTRUCT** — an existence
  test on a manifest path built from a variable — and scans **code, not comments**, because an
  ownership check has to name the construct it bans and so matches its own documentation
  otherwise. Fix by calling `scripts/spec-links.sh unmanifested`; never re-derive the walk.
- **Check 9l (`test lock:` pairing + shard voidance):** `lock?: string | string[]` on
  `TestDetails` (Playwright 1.63+) is the only cross-file mutual-exclusion primitive the runner
  ships, and reviewer Check 13 offers it for the cross-FEATURE mutator/consumer case. It is a
  hand-mirrored cross-file **string with no runtime signal**, so this is its deterministic half.
  **Arm 1** — a lock name at exactly **one** site under `tests/**` is silently inert: nothing to
  exclude, the pair races exactly as before, every oracle still green. The consumer side carries
  the name for no reason of its own, so it is the side a typo or a later edit drops. Fix by
  naming the same literal on the other side of the contention, or by dropping the lock and
  folding into one file's serial `describe`. Counted per **site**, not per file — two same-lock
  tests in one file genuinely do exclude each other. **Arm 2** — locks plus a sharding workflow
  is a void remedy: the shard filter splits by test count and never reads `group.locks`, so the
  pair can land in two shard processes that share no lock table. Fix by dropping the sharding or
  by taking the shard-safe fix (fold into one file, or give the mutator a throwaway entity).
  Both arms scan **code, not comments** (the 9k lesson).
- **Check 2 / 9b (vocab drift):** re-sync the 16-key mirror with CLAUDE.md (and, for
  9b, upgrade/re-stamp the plugin agents) in the same commit as any vocab change.
- **Check 3 (vacuous smoke):** tag at least the P1 happy path `@smoke`, then
  `/qa-warden:run mode=smoke`.
- **Check 4 (orphaned sentinels):** close the loop per the sentinel→action table in
  `${CLAUDE_PLUGIN_ROOT}/reference/sentinel-actions.md` — re-seed / re-explore / migrate as the sentinel names.
- **Check 5/5b (stale or draft context):** `/qa-warden:explore mode=area site=<id> area=<name>` to refresh
  (both keys — exploration STOPs on either one missing rather than guessing; Check 5b prints the
  exact command for each stale file),
  then clear `draft:` / bump `last_verified:`.
- **Check 6 (undeclared env):** declare the variable in `.env.example` (commented is
  fine for optional-with-fallback vars).
- **Check 7/7d (pins / idiom):** fix `package.json` / regenerate the offending
  `fixtures/schemas/` file in the pinned major's idiom.
- **Check 8b (Playwright FOUR-SITE paired-bump lockstep):** `package.json`'s `overrides_comment`
  mandates four sites move together, and the check enforces all of them. **Inside
  `package.json`:** `@playwright/test` must equal `overrides.playwright` must equal
  `overrides.playwright-core`, and `@playwright/test` must be **exact** (no `^`/`~`). Skew the
  runner above the forced core and `overrides` drag core back down (T-01); pin `playwright`
  without `playwright-core` and a nested **alpha** core survives, needing a browser revision
  `playwright install` never fetches (F-002). A caret on the runner makes the equality arm a false
  green, because a lockfile-less install floats it. **Across files:** `.mcp.explore.json`'s
  `npx -y playwright@X.Y.Z mcp` version must equal `overrides.playwright` — since 1.62 the MCP
  server ships bundled with `playwright`, so these are one version mirrored in two files. A
  **bare, unpinned** `playwright` npx arg is itself a FAIL: with no `node_modules` (fresh clone,
  lockfile-less CI) npx silently fetches the LATEST Playwright, recreating the same skew from the
  explore config, where `overrides` cannot reach it. Fix by bumping **all four** sites in one
  change, never by unpinning. Note Check 7 does **not** cover this: 7a screens only for
  `alpha`/`beta`/`rc` strings and 7c screens only the lockfile's resolved core for alpha, so a
  clean, stable, *skewed* set passes both. A missing site is reported, not failed — `package.json`
  is in `resync-set.txt`, so Check 9 owns the deleted-block case.
- **Check 8/9 (canonical scripts / substrate drift):** `/qa-warden:init --resync` (backs up
  drifted files to `*.qa-bak`). A missing stock var in `.env.example` → restore it from
  the shipped template, or park it commented (`# VAR=`) — the stock list is derived from
  the template, and the file itself is shared-ownership and never byte-compared. The
  drift baseline is the RECORDED active plugin install; a "baseline GUESSED by newest
  mtime" ⚠️ means the install record didn't resolve — re-run via `/qa-warden:doctor` (which
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
- **Check 12 (stale manifest):** `/qa-warden:gen <spec>` to regenerate the route manifest.
- **Check 13 (declared-mutation isolation, WARN):** the basis declares
  `mutates_server_state: true` but a resolved test shows no isolation marker
  (parallelIndex / serial / seeded fixture) — un-isolated mutation is green at 1 worker,
  flaky at scale. Resolution mirrors `/qa-warden:coverage` dim 1: the direct
  `tests/<feature>.spec.ts` PLUS every fanned spec linking back via `basis:` (twins
  included); a mutating feature that resolves to ZERO tests is its own WARN, never a
  silent skip. Wire the isolation (see the basis `test_data:` block) or regenerate via
  `/qa-warden:gen`. The reviewer's code-level Check 13 remains the enforcing gate.
- **Check 14 (unmanaged test, WARN):** a `tests/**/*.spec.ts` with no paired
  `specs/<area>/<feature>.md` sits outside the assertion contract — write the spec
  (`/qa-warden:new-spec`) or consciously exempt it (move to `tests-legacy/`).
- **Check 15/15b (review attestation, WARN):** the spec/test pair changed since its
  `reports/review/<area>/<feature>.reviewed` marker (or was never reviewed), or a
  `// verified: must_fail_when "…"` stamp no longer matches the spec's invariant text —
  re-run `/qa-warden:review` (and `--verify-invariants` for a stale stamp). Markers are
  agent-writable convenience — this catches *forgotten* reviews, not malicious ones.
- **Check 16 (smoke-tagged spec with no test, WARN):** a spec declares a `tags: [… smoke …]`
  scenario but was never compiled — `/qa-warden:run mode=smoke`'s `--grep @smoke` is blind to that P1 flow, so a
  fully-broken governed path (admin RBAC, checkout charge==total) passes the smoke gate because no
  test exists to fail. Complements Check 3 (which only proves *some* test carries the tag). Compile
  it (`/qa-warden:gen`) or drop the smoke tag from the spec.
- **Check 17 (spec with no compiled test — ANY tag, WARN):** the complement to Check 16 — a
  `@regression`-only spec authored but never generated sits outside the assertion contract and no
  run exercises it (Check 15 `continue`s past it, Check 16 is smoke-only). `/qa-warden:gen` it, or
  `/qa-warden:retire` / `# waived:` it if its scenarios are intentionally folded into a sibling.
- **Check 18 (abandoned authoring chain, WARN):** a `.cases.md` (the approval artifact) with no
  downstream spec — the intake→ideate→approve chain ran but never produced a spec, so the intended
  coverage silently never shipped. `/qa-warden:new-spec <area/feature>` or `/qa-warden:retire` the chain.
- **Check 19 (unattested interview, WARN):** a `.basis.md` with `[human-answered]` oracle rules but
  `interview: none`/absent — the human grounding is unattested (a fabricated basis looks identical).
  `/qa-warden:intake` should stamp the real question count in the basis `interview:` field.
- **Check 20 (`.env`-load idiom drift, WARN):** the canonical `.env`-load one-liner is duplicated
  verbatim across several plugin skill/agent files (a run-verbatim command belongs at its point
  of use); this WARNs only if more than one distinct form exists. Re-sync every
  copy to the canonical `${CLAUDE_PROJECT_DIR:-.}`-anchored form in CLAUDE.md §Environment.
- **Check 21 (fresh-project readiness, INFO):** not a warning — on a brand-new project (no
  `app.context.md`/specs) it prints a "setup looks healthy — next run `/qa-warden:explore`" verdict so the
  expected empty-project WARNs read as "expected at this stage", not "something's broken".
  **21a (unconfigured target, WARN):** runs `scripts/prod-guard.sh` in its offline default mode and
  WARNs on each empty/placeholder refusal (`BASE_URL_APP` empty, or any `BASE_URL_*`/`API_URL` still
  `CHANGEME`, `<…>`, or an `example.com`/`.example` host) — while one stands, the readiness verdict
  says "NOT ready yet — fill in .env" instead of "setup looks healthy". Remedy: edit `.env` to a real
  staging/QA host. Empty `QA_USER_*` is not flagged (a site without a login has none).

## Optional: `--verify-invariants specs/<area>/<feature>.md` (executable `must_fail_when`)

Only when `$ARGUMENTS` contains `--verify-invariants`: read
`${CLAUDE_SKILL_DIR}/reference/verify-invariants.md` and follow it. That file is THE single
source of the injection mechanism (the verifier's Process step 8b runs the same one); do not
re-derive it here. In the default read-only pass, skip this section entirely — it is the only
mode that runs tests.

This skill runs as a forked subagent, so the caller sees only what you return: report the
per-check ✅/⚠️/❌ lines and the rollup, then the interpretation above for each ❌/⚠️. Never
return a bare "healthy" while any ❌ stands.

This skill reruns nothing in default mode, invokes no healer, and writes nothing (the opt-in mode's TEMP probe is reverted, so it too leaves the tree unchanged).
