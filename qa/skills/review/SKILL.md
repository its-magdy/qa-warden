---
description: Run the load-bearing reviewer subagent over the current diff (or a named spec/path) — the shipped trigger for the full assertion-contract check suite. Pass url=<x> instead for a full a11y + visual + closed-vocab audit of a live URL.
argument-hint: "[spec-or-path — default: the working diff vs origin/main] | url=<url> [site=<id>]"
---

**Two modes, same command.** No `url=` argument → diff-review mode (below, the default).
An argument that IS or STARTS WITH `url=<x>` (or is a bare URL) → **URL-audit mode**: skip
straight to the "URL-audit mode" section further down; everything between here and there is
the diff-review path and does not apply.

## Diff-review mode

Delegate to the **`reviewer`** subagent — the read-only gatekeeper that is the
**backstop** for the assertion contract (the `PreToolUse` hooks in `hooks/` catch
only the lexical FAILs and the healer/verifier assertion prohibition; every check
needing the paired spec, the `bugs/` tree or a judgment call rides on the reviewer
running, and this skill is what runs it). Without a shipped trigger the single most important quality
gate is the easiest one to forget — invoke it on **every PR that touches
`tests/**`, `specs/**`, or `page-objects/**`**, and wire it into CI (below).

**Scope.** With no argument, the reviewer resolves the scope itself: the
`$BASE...HEAD` commit diff **unioned with the working tree and untracked files**,
with the fresh-repo / non-`main` / diverged-branch fallbacks in
`agents/reviewer.md` §Inputs — it never reviews an empty scope as PASS. The union
is what makes the local `/qa:gen` → `/qa:review` path work at all: the generator
never self-commits, so a just-authored spec+test are **untracked** and a
commit-range diff alone cannot see them. Pass `$ARGUMENTS` to narrow the review to
a single spec/test or an explicit path:

```bash
# Optional: normalize a bare <area>/<feature> to its spec path (same resolver as /qa:gen).
[ -n "$ARGUMENTS" ] && TARGET=$(bash scripts/resolve-spec-path.sh spec "$ARGUMENTS" 2>/dev/null || echo "$ARGUMENTS")
```

Tell the reviewer explicitly: *"Use the `reviewer` subagent to review
`${TARGET:-the working diff}` and its imported page objects."*

**What it enforces** (full list + rationale in `agents/reviewer.md`): failable
`expect` (Check 1), YAML-step→assertion coverage (2), `must_fail_when`/`fail_if`
reified-or-waived (2b), oracle discriminating-power (2c, WARN + 2 mechanical FAIL sub-cases), oracle value
fidelity (2d), equality-invariant precondition scope (2e, WARN), no unlinked
`test.fixme`/`skip`/`fail` (3), closed 16-key vocab +
arg-shapes (4), no `waitForTimeout`/`networkidle` (5), metamorphic-twin
verification (6), context freshness (7, WARN), `@site:` validity against the
hot-tier `sites:` table (8), locator policy across `tests/**` **and**
`page-objects/**` (9), factory enforcement (10), hygiene (11), POM-abstraction
sanity (12, WARN), parallel-safety (13), approved-case traceability (14, WARN —
green-but-incomplete: an approved `.cases.md` row with no scenario and no
waiver), healed-locator drift (15, WARN). **Any FAIL blocks the PR**
(2e/7/12/14/15 are WARN-level; 2c is WARN except its two mechanically-decidable
FAIL sub-cases — otherwise surfaced, not blocking).

**Read-only.** The reviewer has no Write/Edit tools: it runs the checks
(including running metamorphic twins with `--reporter=line` so it never clobbers
the run-of-record) and emits **one PR comment** — blocking ❌ first, then WARNs,
then PASS summary. It fixes nothing; on a FAIL, kick the spec back to the
`generator` (or planner) named in the finding. It reruns no product tests beyond
the twins and hits no network.

**CI wiring (recommended).** The reviewer's competence is not the gap — its
*triggering* is. Run it on every PR that touches the QA suite. A minimal GitHub
Actions step:

```yaml
# .github/workflows/qa-review.yml
on:
  pull_request:
    paths: ['tests/**', 'specs/**', 'page-objects/**']
jobs:
  qa-review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }        # full history so origin/main...HEAD resolves
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: "Use the reviewer subagent to review the PR diff and its imported page objects. Fail the job on any reviewer FAIL, and also fail the job if the reviewer's report contains no explicit verdict line (a report cut off before a verdict is written is not a PASS)."
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

Mark this job a **required status check** in branch protection — that is the only
attestation an agent cannot forge. Non-GitHub CI: install the CLI on the runner
(`npm install -g @anthropic-ai/claude-code`) and invoke `claude -p "…"` with
`ANTHROPIC_API_KEY` (or a `claude setup-token`-generated `CLAUDE_CODE_OAUTH_TOKEN`)
in the job env. The load-bearing part is that a PR touching `tests/`/`specs/`
cannot merge without the reviewer having run.

**Attestation marker (feeds `/qa:doctor` Check 15).** After the reviewer returns,
**first check that its report contains an explicit verdict line** (`PASS`, or
`FAIL` in any form including `FAIL (inconclusive-partial)`) for the reviewed pair.
**If it does not — a `maxTurns` cutoff, a crash, or any output with no verdict —
do NOT write a `.reviewed` marker at all**, and treat the invocation as if the
reviewer had not run (surface this to the human instead). A marker written from a
guess would launder a truncated review into a durable, doctor-trusted `PASS`
exactly the way the CI-gate hardening above exists to prevent — the marker file is
a second, unguarded consumer of the same verdict. Only once a verdict is
confirmed present, this skill writes `reports/review/<area>/<feature>.reviewed`
for each reviewed spec/test pair, containing:

```
commit: <git rev-parse HEAD>
spec_sha256: <sha256 of specs/<area>/<feature>.md>
test_sha256: <sha256 of tests/<area>/<feature>.spec.ts>
date: <YYYY-MM-DD>
result: PASS|FAIL
```

Compute the two digests portably — prefer `sha256sum <file>` (coreutils; present on minimal
Linux/CI), falling back to `shasum -a 256 <file>` (macOS/BSD); take the first field. The digest
value is identical either way, and `/qa:doctor` Check 15 reads them with the same fallback (T-05).

Commit the markers with the reviewed change; they are agent-writable convenience
for `/qa:doctor` Check 15 (which WARNs when a pair changed since its marker) — the
anti-forgery layer is the CI required-status above.

## URL-audit mode

Run a full audit of the URL by taking a direct AX-tree snapshot, then running the
`axe-a11y` and `visual-regression` skills plus the `reviewer` subagent (one subagent, two
skills). This mode does **not** use the `exploration` subagent — see step 1.

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh` first — STOP and ask the user to confirm in-chat if it exits non-zero. **Pass the audit URL as an argument** — `bash scripts/prod-guard.sh "<the URL from $ARGUMENTS>"`: the argument goes through the *same* screening body as the env vars, so do **not** re-implement that host match by hand here.

Pass `site=<id>` in `$ARGUMENTS` to scope the audit to one site (id must match
a `sites[].id` in `specs/_context/app.context.md`). If omitted, audit defaults
to `site=app`.

**Validate the site id BEFORE scanning.** If `site=<id>` (or the default `app`) is not present as a
`sites[].id` in `specs/_context/app.context.md`, STOP and print the valid ids — an absent or typo'd
`app` id would otherwise resolve a bare/empty base URL and return a hollow "clean". **Also nudge
toward yield:** a single-URL audit of an a11y-clean page (e.g. `/login`) produces a technically-true
but hollow "clean". Offer the area's key routes (from the area context / route manifests) and prompt
to audit **auth-gated states** (e.g. `/tasks`, `/projects`), where reused chrome defects actually surface.

Steps (2–3 and 4 are independent — after step 1's prod-guard, launch the
`reviewer` subagent (step 4) **first, in the background**, then run steps 2–3 in
the main session while it works; only step 5 needs all three results. The
reviewer reads `specs/**` on disk, not the snapshot or scan output, so
serializing it behind two live browser scans wastes the whole audit's wall-clock):

1. Take a one-shot AX-tree snapshot of the target URL **directly via
   `npx playwright-cli`** (`goto` + `snapshot`) — do NOT delegate to the
   `exploration` subagent here. Take the snapshot **in an isolated session** —
   `npx playwright-cli -s=audit-<timestamp> goto <url> && npx playwright-cli -s=audit-<timestamp> snapshot`
   (pass the same `-s=` to the storage-state/cookie subcommands when
   authenticating), and `npx playwright-cli close -s=audit-<timestamp>` after the
   final screenshot — the shared `default` session can be mutated by a concurrent
   run mid-audit. Exploration has only `mode=hot` / `mode=area`,
   each of which *writes* a context file; it has no non-clobbering "scratch"
   mode, and this audit must not overwrite hot-tier or specialist context (for a
   context refresh use `/qa:explore`). Keep the snapshot inline for steps 2–4;
   write nothing under `specs/_context/**`.

   **Auth-gated URLs — authenticate BEFORE the snapshot, or the audit false-cleans.**
   `playwright-cli open`/`goto` has **no `--storage-state` flag**, so an
   unauthenticated hit on an auth-gated route silently follows the redirect to
   `/login` and audits the *login* page — reporting a clean result for a page you
   never scanned (a false-clean is worse than friction). If the target is behind
   auth (resolve via the site's `storage_state_path` in
   `specs/_context/app.context.md`, e.g. `fixtures/auth.<site>.json`): first mint/load
   session state and inject it into the CLI context BEFORE `goto` — use the CLI's
   storage-state/cookie subcommands (exact names come from the binary: check
   `npx playwright-cli --help`, per the `playwright-cli` skill's no-stale-mirror
   policy), then `goto` the URL and CONFIRM you landed on it
   (assert the resolved URL is the target, not `/login`) before snapshotting. If you
   cannot confirm you're on the target page, STOP and report — do not audit the
   redirect target and call it clean.
2. Invoke the `axe-a11y` skill against the URL; record violations by severity.
   **Scan the ERROR/FAILURE states too, not just the default page (state-dependent-a11y gap).**
   A bare `goto` + scan only ever sees the pristine default state, so an a11y violation that
   **only renders after an interaction** — a low-contrast validation error alert after a failed
   submit, a toast/`role="status"`, an opened menu/modal, an empty-vs-populated list — is never
   reached (axe-core's own guidance: error messages aren't in the initial HTML; you must drive
   the interaction, THEN analyze). This is not hypothetical: the contrast defects these suites
   find live in the *error* state. So, for the target page's **documented failure/error states**
   (read the paired `specs/**` oracles + `_context/<area>.md` for the states that matter — e.g.
   the invalid-login error alert), drive the state via `playwright-cli` (fill an invalid value,
   submit, confirm the error surface is present) and re-run the `axe-a11y` scan **scoped to that
   state** before moving on. Record violations per state (default / error / …). If a state cannot
   be reached non-destructively, say so — do not silently scan only the default and call it clean.
3. Invoke the `visual-regression` skill; capture a baseline screenshot or diff.
   Note: `toHaveScreenshot()` baselines land under Playwright's default
   `tests/<spec>.spec.ts-snapshots/` (platform-suffixed, e.g. `-darwin`), per the
   `visual-regression` skill. `artifacts/visual/` is only an optional override path,
   not the default — follow the skill. macOS-authored baselines diff-fail on Linux CI;
   pin the runner OS or keep per-OS baselines before committing any real baseline.
   **If NO managed spec covers this URL and you must author a throwaway spec to host the
   `toHaveScreenshot()` call, name it `tests/_audit-<slug>.spec.ts` (underscore-prefixed)**
   so the nightly (`testIgnore: '**/_*.spec.ts'`) and `/qa:doctor` Check 3 both skip it
   (P-03/P-05). **Never** leave a committed, un-prefixed, nightly-running visual spec with an
   OS-locked baseline — that turns a read-only probe into a permanent Linux-CI red. Prefer
   `artifacts/visual/` (gitignored) for a one-off baseline you don't intend to keep.
4. **Resolve which specs reference this URL FIRST — the reviewer has no URL→spec mode.**
   The `reviewer` subagent scopes from a git diff, a whole-tree fallback, or an **explicit
   file list** (its documented third input mode, §Inputs); it cannot take a bare
   URL. So before delegating, resolve the spec set yourself: extract the URL's path (e.g.
   `/login`, `/admin`) and grep `specs/**/*.md` for specs whose `steps:`/`Navigate` reference
   it (`grep -rlE "<path>(/|[\"'[:space:]]|$)" specs --include='*.md'`, plus any spec whose
   `site:`+area maps to the route). Then branch on the result — **never return a bare PASS on an
   unresolved URL:**
   - **≥1 spec references the URL:** pass that explicit spec list to the reviewer as its
     explicit-file-list scope, and run the
     **closed-vocab audit** — confirm every assertion uses the canonical closed oracle
     vocabulary (**the 16-key set defined in CLAUDE.md §"Test case format contract"**; do NOT restate the key
     list — defer to reviewer Check 4). Flag free-form assertions and missing `must_fail_when` contracts.
   - **ZERO specs reference the URL:** emit a **structured `COVERAGE-GAP`** line in the report
     (`COVERAGE-GAP: no spec references <url> — this page is UNTESTED (vocab-clean ≠ covered)`),
     distinct from PASS. A wholly-untested page must read as an explicit gap, never a green
     closed-vocab audit — a vacuous PASS on a brand-new URL is the worst outcome for an audit.
5. Aggregate to `reports/audit-<timestamp>.md`: a11y findings, visual diff
   summary, vocab violations, and actionable remediation bullets.
