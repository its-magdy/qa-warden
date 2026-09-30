# How-to: turn your existing manual test cases into running tests

**Goal:** you already have manual test cases — in TestRail, Zephyr, Xray, or just a
spreadsheet — and you want them running as real Playwright tests without re-writing them by
hand.

This is the fastest on-ramp if you're **not** starting from scratch. It assumes you've done
`/qa-warden:init` and one `/qa-warden:explore` (if not, do the **[tutorial](tutorial-first-test.md)** first).
New terms link to the **[glossary](glossary.md)**.

**This is a recipe, not a slash command.** Paste (or paraphrase) the "Import the export" section
below to Claude along with your export file/paste, and it will follow the steps — there's no
`/qa-warden:import-cases` command; this is a one-time, per-onboarding task, not something worth a
standing command surface for.

---

## The path

```
(paste your export + this recipe to Claude)   →   review the result   →
/qa-warden:approve <area/feature>   →   /qa-warden:new-spec <area/feature>   →   /qa-warden:gen …   →   /qa-warden:run mode=smoke
```

## 1. Import the export

Tell Claude the target `<area/feature>` (e.g. `tasks/update-task`), optionally the tracker
`source=` name (`testrail`, `zephyr`, `xray`, …, used to stamp provenance), and either paste
the export or point at the file. Ask Claude to follow these steps:

1. **Validate the area.** Check `<area>` against `naming.area_dirs` in
   `specs/_context/app.context.md` (same rule `/qa-warden:intake` uses) — on a mismatch, list the
   valid `area_dirs` and stop rather than write under a typo'd path.
2. **Recognize the export shape.** The big-3, but accept ANY CSV/markdown/pasted table with
   title + steps + expected result:
   - **TestRail** — ID `C####`, Title, Section, Preconditions, Steps, Expected Result,
     Priority; steps possibly one-row-per-step.
   - **Zephyr Scale** — Key `PROJ-T###`, Name, Precondition, Objective, paired
     Step/Expected columns one-row-per-step.
   - **Xray** — TCID first column groups rows; Summary; last three cols
     Action/Data/Expected.
   Group multi-row exports by ID/Key/TCID before structuring; parse quoted-newline CSV cells
   with the model, not shell awk.
3. **Map each case to the closed oracle vocabulary.** Map its expected result to closed-vocab
   oracle key(s), or the `→ oracle: OUT-OF-VOCAB (<reason>) coverage: partial` marker. A case
   with NO stated expected result gets `→ oracle: OUT-OF-VOCAB (no expected result in source)
   coverage: none` + an open question — NEVER an invented oracle. Row format (coverage tooling
   counts rows via `oracle:.*risk:`):
   ```
   ☐ [imported/<source> <ext-id>] <title> → oracle: <key(s)>  risk: <lvl>  @smoke|@regression
   ```
   The external id IS the row id.
4. **Dedupe.** If `<feature>.cases.md` already exists, a row asserting the same behavior on the
   same surface gets the external id APPENDED to the existing row (`… [also: <source> <id>]`),
   not a duplicate row.
5. **Write a minimal basis.** If no `<feature>.basis.md` exists, write a MINIMAL one:
   `story:` from the import context; `rules:` reverse-derived from the imported Expected
   Results, each stamped `[imported: <source> <ext-id>]`; plus one 🔴 open question: "oracle
   derived from imported expected-results, not from intent — verify rules with the feature
   owner."
6. **Flag mutating cases — seed/reset readiness.** Scan the imported cases for mutating intent
   (create / add / edit / update / delete / cancel / archive — anything that changes server
   state). If any exist AND `specs/_context/app.context.md` declares no seed/reset hook, WARN
   naming the mutating case ids — they can't generate to a runnable green test until a
   seed/reset hook exists (see the `test-data-seed` skill). Advisory, not a stop; read-only
   cases are generate-ready now.
7. **Close:** point back to `→ run /qa-warden:approve <area/feature>` — import ≠ approval, that's still
   the human gate.

**What this gets you:** multi-row exports grouped by case id, each expected result mapped to a
closed-vocabulary [oracle](glossary.md) key, de-duping against any cases you already have, and
provenance stamps (`[imported/testrail C123]`) so every case keeps a back-pointer to its origin.

**Edge cases:** an export **>~40 cases** should be split by Section→area with a confirmation
round; Section/Folder→area mapping is asked, not guessed; duplicate external ids in the export
get a warning, first one wins; Preconditions get noted under the rule group (feeds the
planner's Preconditions).

## 2. Review what it produced — this is the important part

Open `<feature>.cases.md`. Two things to check honestly:

- **`OUT-OF-VOCAB` rows.** A case whose expected result doesn't map to the 16-key vocabulary is
  marked `→ oracle: OUT-OF-VOCAB (<reason>)` rather than given an invented assertion. A case with
  **no** stated expected result gets `coverage: none` and an open question. These are correct,
  honest outcomes — decide what each should really assert.
- **The reverse-derived oracle.** The minimal basis carries a 🔴 open question by design:
  *"oracle derived from imported expected-results, not from intent — verify rules with the
  feature owner."* Imported "expected results" describe what someone *observed*, which isn't
  always what the feature *should* guarantee. **Confirm the rules with whoever owns the
  feature** before trusting them.

## 3. Approve — import is not approval

```
/qa-warden:approve tasks/update-task
```
Importing cases doesn't mean they're accepted. `/qa-warden:approve` is the human gate — you approve,
prune, or defer each case (and it mints the stable ids the [reviewer](glossary.md) later checks
against). Nothing gets built from an unapproved checklist.

## 4. Generate and run

```
/qa-warden:new-spec tasks/update-task     # draft the spec from the approved cases
/qa-warden:gen specs/tasks/update-task.md # compile it to a runnable test
/qa-warden:run mode=smoke                      # run the @smoke gate
```
From here it's the normal flow — see the **[tutorial](tutorial-first-test.md)** and
**[reviewing-without-code](reviewing-without-code.md)** for reading the result.

> **Mutating cases need a seed/reset hook first.** A read-only/assertion case (e.g. "the list
> shows X") generates and runs immediately. A **mutating** case — create / edit / **delete** a
> task, like the `update-task` example above — cannot reach a stable green until your project has a
> **seed/reset hook** so each run starts from known data (see the `test-data-seed` skill). Step 6 above
> flags this at import time (it names the mutating case ids); if you see that warning, wire the seed
> hook before `/qa-warden:gen`, or start with the read-only cases which are ready now.

---

## Results flow back to your tracker (no re-sync)

This is **import-once**, not a live two-way sync — the provenance stamp is the permanent
back-pointer. *(This part is for whoever wires up CI — it's the one place the flow touches
command lines.)* To report nightly results back into your tracker, export JUnit from the run
(no re-run needed):

```bash
npx playwright merge-reports --reporter junit ./blob-report > reports/junit-results.xml
```
Then feed `reports/junit-results.xml` to your tracker's JUnit importer (TestRail, Xray, or Zephyr
Scale). The exact per-tracker import commands live in **`DOCUMENTATION.md` §16.2** at the root of
the toolkit's marketplace repo — kept there as the single source so they can't drift out of sync.
No repo checkout (plugin-only)? Ask `/qa-warden:help` from inside your project for the in-plugin
pointer, or open your tracker's own JUnit-import docs (F-012).
(Read it on the repo, not via a `../` path: an installed plugin can't open a file outside its own
directory — C-1.)

## Good to know

- **Big export (>~40 cases)?** It splits by section→area with a confirmation round — you're
  asked how folders map to areas, never guessed.
- **The area must be real.** `<area>` is checked against your declared areas; a typo is caught,
  not silently turned into a stray folder.
- **Duplicate ids in the export** are warned about; the first wins.
