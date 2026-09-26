# `/qa-warden:report` output template — the report's output contract

This is the **sole owner** of the PR/Slack summary shape (totals, failures table, signature
grouping, value ledger). `skills/report/SKILL.md` §Inputs renders everything below the SCOPE
line from this file, and `reference/DESIGN.md` §"Where the operational facts live" points here.

It lives outside `SKILL.md` because the skill was over the ~5,000-token ceiling recorded in
`reference/knowledge-map.md` — past which Claude Code re-attaches only the first 5k after a
compaction, which would have put this contract in the truncation zone while the skill still
told the model to render from it. Read this file when building the report; do not re-derive
the shape from memory or paraphrase the section headings, since consumers grep them.

```markdown
# QA run — <lane> — <YYYY-MM-DD HH:MM>
<Append ` (<commit-sha-short>)` ONLY when `config.metadata` carries it — see Inputs. A Playwright
JSON report has no SHA on its own, so never fabricate one and never emit an empty `()`.>

**SCOPE:** <the lane that actually ran — e.g. "smoke run-of-record — N smoke tests (a SUBSET;
full suite NOT measured)". Derived from `--grep` in `.config.argv` above; render it FIRST and never present a filtered run as full-suite green (F-27).>

**Verdict:** <the one-paragraph go/no-go lead for the PR comment / Slack post. It MUST inherit the
SCOPE qualification above — "N smoke tests passed" never "all tests passed" — and MUST be qualified
rather than an unqualified "green to merge" whenever the Parked / known defects section below is
non-empty (F-19), an audit reported violations, or SCOPE is NOT ESTABLISHED.>

**Totals:** <N> specs · <P> passed · <FAILED> failed · <S> skipped · <RETRIED> retried · <FLAKY> flaky · wall-clock <hh:mm:ss>
<Map each to `stats` in `last-run.json`: passed=`expected`, failed=`unexpected`, skipped=`skipped`,
flaky=`flaky` (retried-then-passed). `<RETRIED>` counts retry ATTEMPTS and is NOT `<FLAKY>`.>
**Flake budget:** <FLAKY>/<N> this run (this run ONLY — no history is kept, so this is not a trend. CLAUDE.md §"Escalation rules": confirm a suspect with `/qa-warden:run mode=repeat`; worst per-test pass rate <95% → a human tags it `@quarantine`)
**Durations:** p50 <s>s · p95 <s>s · vs prior run <±N%> · slowest 5: <spec> (<s>s), <spec> (<s>s), … (healer candidates if ALSO flaky)
<Omit the `vs prior run` clause entirely when no prior local `reports/summary.md` exists — never
render 0% from comparing the run to itself. Flag >20% regression explicitly.>

## Failures (<FAILED>)
| Spec | Signature | Retries |
|---|---|---|
| tests/checkout/new-address.spec.ts | `TimeoutError: locator.click` | 2 |
| ... | ... | ... |

## Passed with retries (<FLAKY>)
<Every test that FAILED at least once and then passed. It is flaky, not passing — the flake SLO
enforces against this table. Omit the section only when <FLAKY> is genuinely 0.>

| Spec | Signature of the failed attempt(s) | Attempts |
|---|---|---|
| tests/settings/save.spec.ts | `TimeoutError: locator.click` | 3 (passed on 3rd) |

## Top-3 failure signatures (grouped by message substring)
1. **`TimeoutError: locator.click`** — 4 specs (checkout, login-mfa, settings-save, org-switch). Likely root cause: target rendered after an un-awaited async update (assert the settled post-condition, not the network). Owner suggestion: healer + test-data-seed review.
2. **`expect(received).toHaveText(expected)`** — 2 specs (cart-empty-state, error-banner). Content drift, not a flake.
3. **`net::ERR_CONNECTION_REFUSED`** — 1 spec (staging-smoke). Infra, not test.

<details>
<summary>Full failure details (<FAILED>)</summary>

### tests/checkout/new-address.spec.ts
- Attempts: 3 (2 retries, final: fail)
- Duration: 42.1s
- Error: `TimeoutError: locator.getByRole('button', { name: 'Pay' }).click()` timed out after 30000ms
- Trace: `artifacts/test-results/<test-id>/trace.zip`
- Screenshot: `artifacts/test-results/<test-id>/test-failed-1.png`
- Healer verdict: <from triage notes or "not yet triaged">

### ...
</details>

## Audit findings (a11y / visual)
<Headline numbers from any `reports/audit-*.md` written by `/qa-warden:review url=<url>` — WCAG violation
counts by impact, and visual-diff count. Omit the section when no audit report exists. This is the
one place a reviewer looks, so an audit that ran and found violations must not be invisible here.>

## Parked / known defects (<n> open)
<Every `bugs/*.md` still `Status: open`, from the `post-run-checks.sh` scan run above.
When any is open the go/no-go lead MUST be qualified — never an unqualified "green to merge"
over a standing, human-confirmed defect (F-19). "All N tests passed" describes *what ran*;
this section describes *quality state*. Omit the section only when the count is truly zero.>

## Value ledger (running counts — not a score)
- App defects caught: <O> open, <FIXED> fixed (`bugs/*.md` minus test-gap records — <slugs>; found-by: healer <n> · generator <n> · planner <n> · exploration <n> · manual <n> · unrecorded <n>)
- Test-contract gaps (verifier): <G> open, <GF> fixed (`bugs/*-blind-*.md`, `bugs/*-unverified.md` — an oracle that is decorative or unprobed, not an app defect)
- Test-side heals: <K> (heal-log: broken-locator <a> · missing-wait <b> · auth-stale <c> · data-drift <d> · stale-context <e>)
- Spec-drift escalations owed/processed: <E> (changed-text <x> · contract-change <y>)
_Counts since install. No rates, no percentages — a count you can audit beats a score you can game._

## Run metadata   <!-- only when CI injects config.metadata — omit this section otherwise (see §Inputs) -->
- Commit: <sha> (<branch>)
- Triggered by: <actor> via <workflow>
- Workers: <N>
- Started: <iso8601> · Ended: <iso8601>
```
