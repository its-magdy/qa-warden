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

**Status 2026-09-21:** all five cases have been run end-to-end once. Four scored 1.00;
`reviewer-no-expect` scored 0.25 twice while the reviewer's verdict was CORRECT — it wrote
`**Check 1** (failable expect): **❌ FAIL**`, closing the bold before the parenthesis, and the
grader's literal `Check 1 (` missed it. Patterns now allow `\W{0,4}` after the check id and
`\W{0,20}` before the verdict; the new pattern was replayed against both saved traces (matches
the FAIL, does not match a PASS, still passes the control). Report markdown VARIES between runs —
when a grader fails, re-run with `--keep-temp` and read the trace before suspecting the agent.
Not yet done: `--runs 3` for a variance figure.

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
