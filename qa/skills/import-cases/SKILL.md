---
description: Import existing manual test cases (TestRail/Zephyr/Xray CSV, markdown, or pasted table) into the plugin's cases.md + a minimal basis — provenance-stamped, deduped
argument-hint: "<area/feature> [source=<name>] [<file-path>]"
disable-model-invocation: true
---

Import an existing manual test-case export into the plugin's checklist format.
This runs **in the main session** (it is interactive — `AskUserQuestion`, with the
same plain-prose fallback as `/qa:intake`); it does NOT delegate to a subagent.

## What to do

1. **Parse args.** `<area/feature>` (validate `<area>` against `naming.area_dirs` in
   `specs/_context/app.context.md` — mirror intake's F-18 rule: on a mismatch, list the
   valid `area_dirs` and stop), optional `source=` (name for provenance stamps, e.g.
   `testrail`), optional file path. No file given → ask the user to paste the export.
2. **Recognize the export shape.** The big-3:
   - **TestRail** — ID `C####`, Title, Section, Preconditions, Steps, Expected Result,
     Priority; steps possibly one-row-per-step.
   - **Zephyr Scale** — Key `PROJ-T###`, Name, Precondition, Objective, paired
     Step/Expected columns one-row-per-step.
   - **Xray** — TCID first column groups rows; Summary; last three cols
     Action/Data/Expected.
   But accept ANY CSV/markdown/pasted table with title+steps+expected. **Group
   multi-row exports by ID/Key/TCID before structuring**; parse quoted-newline CSV
   cells with the model, not shell awk.
3. **Map each case to the closed oracle vocabulary.** Map its expected result to
   closed-vocab oracle key(s), or the existing
   `→ oracle: OUT-OF-VOCAB (<reason>) coverage: partial` marker. A case with NO stated
   expected result gets `→ oracle: OUT-OF-VOCAB (no expected result in source)
   coverage: none` + an open question — NEVER an invented oracle. Row format
   (MANDATORY — coverage counts rows via `oracle:.*risk:`):
   ```
   ☐ [imported/<source> <ext-id>] <title> → oracle: <key(s)>  risk: <lvl>  @smoke|@regression
   ```
   The external id IS the row id.
4. **Dedupe.** If `<feature>.cases.md` exists, a row asserting the same behavior on the
   same surface gets the external id APPENDED to the existing row
   (`… [also: <source> <id>]`), not a duplicate row.
5. **Minimal basis.** If no `<feature>.basis.md` exists, write a MINIMAL one:
   `story:` from the import context; `rules:` reverse-derived from the imported
   Expected Results, each stamped `[imported: <source> <ext-id>]`; plus one 🔴 open
   question: "oracle derived from imported expected-results, not from intent — verify
   rules with the feature owner."
6. **Flag mutating cases — seed/reset readiness (F-36).** Scan the imported cases for
   **mutating** intent (create / add / edit / update / delete / cancel / archive — anything that
   changes server state). If any exist AND `specs/_context/app.context.md` declares no seed/reset
   hook (no `seed:` / reset-adapter wiring, no `test-data-seed` skill setup in the project), emit a
   visible WARN naming the mutating case ids:
   > ⚠️ N imported cases mutate state (create/edit/delete) — e.g. `<ext-id>`, `<ext-id>`. These
   > cannot generate to a runnable green test until a **seed/reset hook** exists (see the
   > `test-data-seed` skill). Read-only / assertion-only cases are generate-ready now.

   Advisory, not a stop — approval still proceeds. This is the single most common blocker between an
   imported case and a passing test for the "I already have test cases" persona, so surface it here
   (at import) rather than letting the QA discover it only when `/qa:gen` has nothing to seed.
7. **Close:** `→ run /qa:approve <area/feature>` — the human gate; import ≠ approval.

## Edge cases
- **>~40 cases** → split by Section→area with a confirmation round.
- **Section/Folder→area mapping** is asked, not guessed.
- **Duplicate external ids** in the export → warn, keep the first.
- **Preconditions** → note under the rule group (feeds the planner's Preconditions).

## Stance
Import-once + provenance stamp as the permanent back-pointer; NO ongoing sync —
results flow back to the tracker via JUnit export — from the nightly blob, no rerun:
`npx playwright merge-reports --reporter junit ./blob-report > reports/junit-results.xml`,
then the tracker's JUnit importer (TestRail `trcli parse_junit`; Xray
`POST /api/v2/import/execution/junit`; Zephyr Scale
`POST /automations/executions/junit?autoCreateTestCases=true`).

See also `reference/how-to-import-manual-cases.md` for the narrative walkthrough
(same workflow, framed for a human reading it end-to-end rather than as agent steps).
