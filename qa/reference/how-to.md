# How-to recipes

Short, goal-titled recipes: find your goal, run the commands. Each links to the fuller detail
rather than repeating it. New here? Do the **[tutorial](tutorial-first-test.md)** first; unfamiliar
words are in the **[glossary](glossary.md)**.

---

## I already have manual test cases (TestRail / Zephyr / Xray / a spreadsheet)

Turn them into running tests without re-writing them.
→ `/qa:import-cases <area/feature> [source=<name>] [<file-path>]` → review → `/qa:approve` →
`/qa:new-spec` → `/qa:gen` → `/qa:run mode=smoke`. See
**[how-to-import-manual-cases.md](how-to-import-manual-cases.md)** for the full walkthrough.

## A test is failing — how do I fix it?

Don't hand-edit the test. Pick by the shape of the failure:

- **One test red** → `/qa:heal <test-id>` — triages from the trace, patches the [locator](glossary.md)/wait, or files a bug.
- **Many red, same cause** (one selector/copy change) → `/qa:batch-fix <path-or-substring>` — diagnose once, patch everywhere (it shows the pattern and waits for your OK).
- **Passes on retry / flaky** → `/qa:run mode=repeat <spec> [N]` — repeatability probe; quarantine if the worst per-test rate < 95%.
- **Everything red / won't start** → check `.env` + host reachability (VPN?), then `/qa:doctor` — don't heal tests when the harness is the problem.

The [healer](glossary.md) never weakens what a test checks; a genuine app bug becomes a filed bug
you see. See **[reviewing-without-code.md](reviewing-without-code.md)** for reading a failure.

## Adopt this on an app that already exists (brownfield)

Coverage is **triaged, not backfilled** — start with one high-risk area, expand in risk order:

1. `/qa:explore` (hot) → enumerate areas.
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
a relative link — C-1.) **Plugin-only reader (no repo checkout)?** Ask `/qa:help characterization`
(or `/qa:help <topic>`) from inside your project for the in-plugin answer — F-012.

## Make sure every test got reviewed

**Locally — the default, nothing to set up.** Run `/qa:review` after `/qa:gen`. On a PASS it writes
`reports/review/<area>/<feature>.reviewed`, pinned to the hashes of that spec and test. `/qa:doctor`
(Check 15) then flags any test with no marker, or whose spec or code changed since — so a
forgotten review shows up the next time anyone runs doctor.

**In CI — optional hardening for teams.** A local marker is written by an agent, so it catches
*forgotten* reviews, not forged ones. If you need a gate nobody can skip, the scaffold ships
`.github/workflows/qa-review.yml.example`: rename it, add an `ANTHROPIC_API_KEY` secret, point
`plugin_marketplaces` at a **Git URL** of the marketplace repo (the `reviewer` ships inside the
plugin — a runner that cannot install it has no reviewer, and a local-directory marketplace
cannot be used from CI), then make the job a required status check.

## Run the suite nightly in CI (~$0, no AI)

The scaffold ships `.github/workflows/qa-nightly.yml.example`. Arming it is a **deliberate act**:

1. Rename `qa-nightly.yml.example` → `qa-nightly.yml`.
2. Add the secrets that mirror your `.env` (`QA_BASE_URL_APP`, `QA_USER_EMAIL`/`QA_USER_PASSWORD`, …).
   The prod-guard **fails closed** on a missing/placeholder/prod URL — a workflow armed before its
   secrets exist goes **red, never silently green**.
3. On failure: download the `qa-nightly-<n>` artifact and triage locally with `/qa:heal <test-id>`.

Details (secrets table, the opt-in in-CI heal step, sharding): see **`DOCUMENTATION.md`
§16.1** at the root of the toolkit's marketplace repo — read it on the repo, not via a
`../` path (an installed plugin can't follow one — C-1). No repo checkout? Ask
`/qa:help ci` / `/qa:help nightly` from inside your project for the in-plugin summary (F-012).

## Add rigor to a P1 / money / compliance flow

For a flow where "correct" must be pinned *before* any test is written, insert the **rigor lane**
between explore and new-spec:

```
/qa:intake <area/feature>    → capture what "correct" means (the basis)
/qa:ideate <area/feature>    → a checklist of candidate cases (SFDIPOT lenses)
/qa:approve <area/feature>   → you approve/prune the checklist  ← mandatory human gate
```
Then continue with `/qa:new-spec` → `/qa:gen` as usual. The fast lane skips no FAIL-level gate;
the rigor lane adds *what-to-test* discipline on top.
