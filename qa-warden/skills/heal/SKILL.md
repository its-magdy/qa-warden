---
description: Triage a failing Playwright test via the healer subagent; patch selectors/waits or file a bug.
argument-hint: <failing-test-id>
disable-model-invocation: true
---

**No argument given?** If `$ARGUMENTS` is empty, do **NOT** proceed — an empty id resolves to
the whole `artifacts/test-results/` dir and the healer would pick a failure itself. Print the
block below verbatim and stop:

```
Usage:  /qa-warden:heal <failing-test-id>
Triage ONE failing test. The id is its results directory name — list them with:

  ls artifacts/test-results/

Several tests red with the same root cause? Use /qa-warden:batch-fix instead.
```

**Guard first (prod-safety).** Before delegating, run the canonical shell prod-guard —
`bash scripts/prod-guard.sh` — and **STOP if it exits non-zero.** Healing drives a live
browser (interactive MCP replay, step 3) *before* any `npx playwright test`, so the enforced
`globalSetup` prod backstop has **not** engaged yet — a healer pointed at a prod-marked
`BASE_URL` would otherwise open a live prod browser session with no STOP. (If the script is
missing, re-run `/qa-warden:init` to stamp it.) Like every command whose first action can be a
live-browser step, it cannot leave the guard to `globalSetup`.

Delegate to the `healer` subagent (pinned `model: sonnet` in its frontmatter, so it
runs at that tier in place of the session model and cannot raise it mid-run — it
signals for a stronger model on second re-fail and the OPERATOR re-runs it higher;
Playwright MCP enabled) to triage
`artifacts/test-results/$ARGUMENTS/` (the configured `outputDir` — NOT
repo-root `test-results/`).

The healer must:

1. Read the trace with the first-class **`npx playwright trace`** CLI (Playwright
   1.59+) — the primary, headless/CI-safe recipe (do NOT use `npx playwright
   show-trace`; it only opens a GUI and hangs in CI). The zip is at
   `artifacts/test-results/$ARGUMENTS/trace.zip`. Full command sequence
   (`trace open`/`actions`/`action`/`snapshot`) is in `healer.md` step 1; the old
   `unzip -Z1` + `grep` + `unzip -p` extraction is only the **fallback** when
   `npx playwright trace` is unavailable on the install.
2. Read the failing `.spec.ts` and pre-failure DOM snapshot.
3. **If invoked interactively** (started with `--mcp-config .mcp.explore.json`), replay via
   Playwright MCP to observe the actual DOM state. **In a scheduled/CI run MCP is absent**
   (`healer.md` §"Tooling mode — CLI-first, MCP-optional") — there, work from `trace.zip` + the pre-failure
   snapshot + `error-context.md` alone; do not assume live MCP replay is available.
4. Classify the failure into one of the healer's **10 buckets** (`healer.md`
   step 4) — broken locator | missing wait | changed text | stale
   specialist context | auth stale | data drift | env/infra down | contract
   change | expected-failure (`must_fail_when`) still red | product defect. Only
   broken-locator and missing-wait are patched in-place; the rest escalate
   (sentinel/bug/planner/leave-red) rather than editing the test.
5. **Patch selectors/waits only — NEVER assertions.** The oracle contract is
   immutable from the healer's side.
6. **If the root cause is a product defect, file
   `bugs/<YYYY-MM-DD>-<slug>.md`** (CLAUDE.md §Bug-report schema) and revert
   any patch attempt. Do not mutate the test to make the bug disappear.
   **Which marker, if any:** when the failing scenario's spec documents the defect
   (`must_fail_when:`/`fail_if:`/`prompt_guardrail:`, the expected-failure bucket), the test
   stays **red**: revert any `test.fail`/`test.fixme`/`test.skip` the healer added, even a
   conditional one. Only an **undocumented** product bug (the product-bug bucket) may be parked
   with the conditional `test.fail(<observed> === <buggyValue>, 'bugs/…')` that `healer.md`
   prescribes.
7. Re-run: `npx playwright test <spec> --retries=0 --reporter=line`. Green → write
   the diff as a PR comment. (`--reporter=line` is load-bearing: in CI, or with an inherited
   `QA_RUN_OF_RECORD=1`, a bare re-run fires the config's gated `json` reporter and
   overwrites `artifacts/last-run.json` — the run-of-record `/qa-warden:report` reads; see `healer.md` step 6 / reviewer.md.)

**Hard turn budget: 14.** After 14 turns on the same failure, stop and signal that
a stronger model is required (per the pin above, that signal is for the operator to
act on — the healer cannot act on it itself). If still red after that re-run, give up,
file a bug, and revert. Never silently retry past the budget (CLAUDE.md §Escalation rules).

**Close the sentinel loop (YOU are the orchestrator the healer hands off to).**
If the healer returns with a sentinel under `artifacts/`, perform its action and
re-invoke the healer — never delete a sentinel without acting on it (`/qa-warden:doctor`
check 4 flags orphans). The sentinel→action table is single-sourced in
`${CLAUDE_PLUGIN_ROOT}/reference/sentinel-actions.md` — read it and follow the row
matching the sentinel you got.
