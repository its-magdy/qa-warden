# QA-Toolkit — merge notes (design lineage)

> **Historical record.** This file preserves the original merge decisions as made; some
> details below have been superseded by later passes. Consult `qa/reference/DESIGN.md`
> and the agent files for current behavior.

This toolkit combines two earlier efforts:

- **Base: `Test-Browser/qa-plugin`** — the sophisticated one. Markdown+YAML oracle specs
  compiled to `.spec.ts`, 5 subagents (planner/generator/healer/reviewer/exploration), deep
  **oracle defense** (closed-vocab, mutation testing, metamorphic relations, a11y, visual),
  zero-LLM deterministic nightly, `settings.json` permission guardrails, route-manifests +
  `/qa:impact`, Zod schemas + factories, two-config CLI/MCP. Kept essentially whole.
- **Contributed from `QA-Automation/qa-automation-toolkit`** — the lean one. Its one genuinely
  additive idea: a **Page Object Model + component reuse layer**. Woven in here.

## Decisions (locked with the user)

1. **No hooks.** The lean toolkit had PreToolUse hooks (real-time assertion-edit block); they
   were dropped. **Consequence folded in everywhere:** the **reviewer is now load-bearing** —
   its **Check 6 (mutation survival)** *(historical — today's Check 6 is metamorphic-twin
   verification; the mutation-style gate became `must_fail_when` + generator step-8b fault
   injection)* is the backstop that catches a weakened/tautological
   assertion, plus the `.claude/settings.json` permission deny rules. The healer/CLAUDE.md no
   longer reference a hook (an earlier Test-Browser doc wrongly said "the hook blocks it").

2. **POM + component reuse layer — added, AI-maintained.** The QA engineer never hand-writes,
   so POM is infrastructure the agents own, not human-authored code:
   - `page-objects/<area>/<page>.page.ts` + `components/<widget>.ts`, wired into `fixtures/test.ts`.
   - **Live-validate, then centralize** — resolves the tension with Test-Browser's "never cache
     locators" rule: page objects hold only **semantic** locators (`getBy*`), validated live at
     compile time, then stored once instead of copy-pasted into N specs.
   - **Earn the abstraction** — promote a flow on its 2nd–3rd reuse; reviewer WARNs on single-use.

3. **Healer heals AND verifies (kept from Test-Browser), + page-object-level healing (new).**
   When a shared locator breaks, the healer fixes the **one** page-object method and re-runs
   **every consumer** — the maintenance payoff of POM. Still: selectors/waits only, never
   assertions; no auto-commit (emits diff, human merges); turn budget + Sonnet→Opus escalation.

4. **`qa-init` = init only.** Pure substrate bootstrap (dirs/configs/deps/fixtures), no test
   generation — exactly what Test-Browser's `bin/qa-scaffold` already did. Added: it now also
   creates `page-objects/` and stamps `fixtures/test.ts` + `page-objects/README.md`.

## Where the POM weave lives (files touched)

| File | Change |
|---|---|
| `qa/agents/generator.md` | New §"Page-object reuse layer": consume/create page objects; **parallel-safety rule** — may create new, may NOT modify existing (worktree isolation); reuse pass in process. |
| `qa/agents/healer.md` | New §"Heal at the page-object level"; writable `page-objects/**`; re-run all consumers after a shared fix; removed stale "hook blocks it" line. |
| `qa/agents/reviewer.md` | Load-bearing note; Check 10 locator policy now scans `page-objects/**`; new Check 13 (abstraction sanity, WARN). *(historical numbering — today locator policy is Check 9, abstraction sanity is Check 12, and Check 13 is parallel-safety)* |
| `qa/templates/CLAUDE.md` | New §"Page-object reuse layer"; no-hooks note; roster + allowed-paths updated. |
| `qa/templates/settings.json` | `Write/Edit(page-objects/**)`, `Edit(fixtures/**)` added to allow. |
| `qa/templates/tsconfig.json` | `page-objects/**/*.ts` added to `include`. |
| `qa/templates/fixtures/test.ts` | New fixtures barrel (page-object wiring point). |
| `qa/templates/page-objects/README.md` | The POM-layer rules. |
| `qa/bin/qa-scaffold` | Stamps the barrel + page-objects README; ensures `page-objects/` dir. |

## What we deliberately did NOT take from the lean toolkit
- Its plain-`expect()` oracle model (Test-Browser's closed-vocab + mutation/metamorphic is stronger).
- Its suggest-only read-only healer (superseded by the heal-and-verify healer + reviewer gate).
- Its `data/seed` contract (Test-Browser's Zod schemas + factories + `test-data-seed` skill is richer).
- Its PreToolUse hooks (dropped per decision #1).

## Open risk to manage operationally
"AI writes everything, human only approves" maximizes exposure to plausible-but-wrong tests.
The defenses (mutation survival, metamorphic twins, reviewer gate) are now **load-bearing, not
optional** — keep the human reviewing at the **spec** level and never let the reviewer be
skipped. A bad *spec* is the one thing no gate fully validates.
