# Sentinel → action

The `healer` subagent returns a **sentinel** — a marker file under `artifacts/.healer-needs-*` —
when a failure cannot be fixed by patching the test, because something upstream of the test is
wrong (stale context, expired auth, missing data, a renamed field, changed product copy). The
sentinel is a handoff, not a diagnosis to file away: the healer has no way to perform these
actions itself, so the **caller** performs the action and re-invokes the healer.

**Never delete a sentinel without acting on it** — `/qa:doctor` Check 4 flags orphans, and an
orphaned sentinel means a failure everyone believes was triaged is still live.

| sentinel | action before re-invoking |
|---|---|
| `.healer-needs-exploration` | `/qa:explore mode=area site=<id> area=<name>` (site+area are in the sentinel) |
| `.healer-needs-seed` | re-run the auth setup project: `npx playwright test --project=setup --retries=0 --reporter=line` (rewrites `fixtures/auth.<site>.json`; `--reporter=line` so this setup-only side run can never pose as the run-of-record) |
| `.healer-needs-data` | re-run the data-seeding path (`test-data-seed` skill) or restore/re-create the entity named in the sentinel — auth setup will NOT fix this |
| `.healer-needs-migrate` | `/qa:impact field=<old-field>`, then hand-edit `fixtures/schemas/<entity>.ts` (the factory→fixture cascade propagates), then `/qa:gen` the affected specs |
| `.healer-needs-spec-update` | route the recorded old→new copy to the planner (`/qa:new-spec` revision of the named spec) — the oracle belongs to the spec; do NOT edit the test's assertion yourself |

This table is the single source for the sentinel contract. Its consumers are `/qa:heal` (the
primary loop), `/qa:batch-fix` (same loop around its representative-failure triage), and
`/qa:doctor` Check 4 (which reports orphans and points here for the remedy). It lives in
`reference/` rather than inside `/qa:heal` because those three read it and a table owned by one
command that two others reach into is a drift shape with no check policing it — the same failure
that made `report`/`report-summarizer` diverge.
