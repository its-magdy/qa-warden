# How-to recipes

Short, goal-titled recipes: find your goal, run the commands. Each links to the fuller detail
rather than repeating it. New here? Do the **[tutorial](tutorial-first-test.md)** first; unfamiliar
words are in the **[glossary](glossary.md)**.

---

## I already have manual test cases (TestRail / Zephyr / Xray / a spreadsheet)

Turn them into running tests without re-writing them.
→ `/qa-warden:import-cases <area/feature> [source=<name>] [<file-path>]` → review → `/qa-warden:approve` →
`/qa-warden:new-spec` → `/qa-warden:gen` → `/qa-warden:run mode=smoke`. See
**[how-to-import-manual-cases.md](how-to-import-manual-cases.md)** for the full walkthrough.

## A test is failing — how do I fix it?

Don't hand-edit the test. Pick by the shape of the failure:

- **One test red** → `/qa-warden:heal <test-id>` — triages from the trace, patches the [locator](glossary.md)/wait, or files a bug.
- **Many red, same cause** (one selector/copy change) → `/qa-warden:batch-fix <path-or-substring>` — diagnose once, patch everywhere (it shows the pattern and waits for your OK).
- **Passes on retry / flaky** → `/qa-warden:run mode=repeat <spec> [N]` — repeatability probe; quarantine if the worst per-test rate < 95%.
- **Everything red / won't start** → check `.env` + host reachability (VPN?), then `/qa-warden:doctor` — don't heal tests when the harness is the problem.

The [healer](glossary.md) never weakens what a test checks; a genuine app bug becomes a filed bug
you see. See **[reviewing-without-code.md](reviewing-without-code.md)** for reading a failure.

## Adopt this on an app that already exists (brownfield)

Coverage is **triaged, not backfilled** — start with one high-risk area, expand in risk order:

1. `/qa-warden:explore` (hot) → enumerate areas.
2. Risk-rank (money / auth / the 2am-page flow); pick **ONE** P1 area.
3. Run the full rigor chain on it (`explore area → intake → ideate → approve → new-spec → gen`),
   happy path tagged `@smoke`.
4. Park any existing suite at `tests-legacy/` (outside `testDir` — keeps running as a fallback,
   not a gate); record `covered_by: legacy:` in the basis so [coverage](glossary.md) shows
   LEGACY-with-caveat, not a false gap.
5. Nightly from day one — 5 smoke tests replayed at $0 beat a plan.

Full playbook (incl. `kind: characterization` for unspecifiable behavior): see
**`DOCUMENTATION.md` §6.1** at the root of the toolkit's marketplace repo. (An installed
plugin can't open a `../` path outside its own directory, so read it on the repo, not via
a relative link.) **Plugin-only reader (no repo checkout)?** Ask `/qa-warden:help characterization`
(or `/qa-warden:help <topic>`) from inside your project for the in-plugin answer.

## Make sure every test got reviewed

**Locally — the default, nothing to set up.** Run `/qa-warden:review` after `/qa-warden:gen`. On a PASS it writes
`reports/review/<area>/<feature>.reviewed`, pinned to the hashes of that spec and test. `/qa-warden:doctor`
(Check 15) then flags any test with no marker, or whose spec or code changed since — so a
forgotten review shows up the next time anyone runs doctor.

## Run the suite nightly in CI (~$0, no AI)

The scaffold ships `.github/workflows/qa-nightly.yml.example`. Arming it is a **deliberate act**:

1. Rename `qa-nightly.yml.example` → `qa-nightly.yml`.
2. Add the secrets that mirror your `.env` (`QA_BASE_URL_APP`, `QA_USER_EMAIL`/`QA_USER_PASSWORD` if the app has a login, …).
   The prod-guard **fails closed** on a missing/placeholder/prod URL — a workflow armed before its
   secrets exist goes **red, never silently green**.
3. On failure: on a **private** repo, download the `qa-nightly-<n>` artifact; on a **public** repo nothing is
   uploaded (traces hold credentials in plain text), so re-run the failing spec locally. Then triage with
   `/qa-warden:heal <test-id>`.

Details (secrets table, sharding): see **`DOCUMENTATION.md`
§16.1** at the root of the toolkit's marketplace repo — read it on the repo, not via a
`../` path (an installed plugin can't follow one). No repo checkout? Ask
`/qa-warden:help ci` / `/qa-warden:help nightly` from inside your project for the in-plugin summary.

## Add rigor to a P1 / money / compliance flow

For a flow where "correct" must be pinned *before* any test is written, insert the **rigor lane**
between explore and new-spec:

```
/qa-warden:explore mode=area site=<id> area=<area>  → map the area first (intake needs it)
/qa-warden:intake <area/feature>                    → capture what "correct" means (the basis)
/qa-warden:ideate <area/feature>                    → a checklist of candidate cases (SFDIPOT lenses)
/qa-warden:approve <area/feature>                   → you approve/prune the checklist  ← mandatory human gate
```
Then continue with `/qa-warden:new-spec` → `/qa-warden:gen` as usual. The fast lane skips no FAIL-level gate;
the rigor lane adds *what-to-test* discipline on top.
