# Behavioural evals

`bin/qa-selfcheck` proves the plugin's files agree with each other; `bin/qa-hooktest` proves the
hooks deny what they should. Neither proves an **agent still behaves** after its prompt is
edited. These cases do: each one plants ONE known defect in an otherwise-correct project and
requires the agent's report to name it.

```bash
cd qa
claude plugin eval . --tag reviewer --runs 1 --ablation none \
  --scaffold --trust-plugin --no-publish --max-cost-usd 10
```

- `--scaffold` is REQUIRED — every case builds its workspace with `fixture.sh`, which sources
  `_lib/base-project.sh` (a real `qa-scaffold` project + one correct failed-login spec/test) and
  then applies its single mutation.
- `--no-publish` keeps the HTML report local. `--ablation none` skips the no-plugin arm (the
  reviewer subagent does not exist without the plugin, so that arm measures nothing here).
- **No Bash grant, on purpose.** Cases ask for a static review of two named files, which the
  reviewer can do with `Read` alone — so the suite runs on machines where the eval Bash sandbox
  refuses to start. Checks that need execution (Check 6 twins) are therefore NOT graded.
- Measured 2026-09-21: ~\$1.6 and ~6 min per run (the reviewer is pinned to opus). Run it
  before committing an edit to `agents/reviewer.md`, not on every commit.

**Status 2026-09-21:** `reviewer-value-drift` was run end-to-end and scored 1.00. The other four
cases' fixtures are verified (each plants exactly its one defect) but their graders have NOT yet
been run against a real report — expect to adjust a regex on first run, the control case most of all.

## Cases (`reviewer/`)

| case | planted defect | graded line |
|---|---|---|
| `reviewer-control-correct` | none — guards against a reviewer that FAILs everything | Check 1 PASS, Check 2d PASS |
| `reviewer-no-expect` | test performs the steps, asserts nothing | Check 1 FAIL |
| `reviewer-orphan-oracle` | spec declares `url_matches`, test never asserts it | Check 2 FAIL |
| `reviewer-value-drift` | asserted text ≠ the oracle's text | Check 2d FAIL |
| `reviewer-wait-for-timeout` | hard `waitForTimeout` sleep | Check 5 FAIL |

Graders are `regex` over the trace (free, deterministic) keyed on the reviewer's own report
lines — `Check N (…): PASS|FAIL` — so a reworded explanation never flips a grade, and a change
to the report TEMPLATE in `agents/reviewer.md` must update these patterns in the same commit.

## Adding a case

Copy a case directory, change the mutation in `fixture.sh`, and point the grader at the check
that must catch it. One defect per case: a case that plants two cannot say which one was caught.
Every past example-run finding of the form "the reviewer passed X" is a candidate.
