# scripts/

Orchestration scripts for the AI-QA stack.

## `init.sh` — one-shot bootstrap (plugin-free fallback)

Idempotent setup for a fresh clone. Verifies Node ≥ 22 and Claude Code,
creates runtime dirs, copies `.env.example` → `.env` if missing, runs
`npm install` + `npx playwright install chromium` (chromium only — the config's
active projects are all Desktop Chrome). Prints next steps.

Invoke via `npm run init` or `bash scripts/init.sh`.

> **Relationship to `/qa-warden:init`:** the canonical bootstrap is the plugin's
> `bin/qa-scaffold` (run by `/qa-warden:init`) — it stamps the full substrate, merges
> `.claude/settings.json` permissions, and installs the official `playwright-cli`
> skill. `init.sh` is the equivalent **plugin-free fallback** for a plain
> `git clone` with no plugin installed; it does the dir/`.env`/npm/browser
> bootstrap only. Canonical output sinks are `artifacts/` (machine — incl.
> `last-run.json`) and `reports/` (human).

## `prod-guard.sh` — canonical shell prod-guard (layer 1 of 2)

`bash scripts/prod-guard.sh [url ...]` — run before any browser-driving or
test-running step; every `/qa-warden:*` command's safety rail calls it. Loads `.env`
itself, screens **every** exported `BASE_URL_*` / `API_URL`, and exits 1 on a
word-boundary `prod`/`production` host marker (`QA_ALLOW_PROD=1` overrides).
Any URL passed as an **argument** goes through the same screening body — that is
how a command whose target comes from its arguments rather than `.env`
(`/qa-warden:review url=<url>`) screens it, instead of re-implementing the host match in prose. Layer 2 is
`prod-guard.ts` — the enforced Playwright `globalSetup` that throws before any
browser opens. **Keep the marker regex in the two files in lockstep.** Both are
deny-listed from agent edits in `.claude/settings.json`.

## `prod-guard.ts` — enforced globalSetup prod-guard (layer 2 of 2)

Wired as `globalSetup` in `playwright.config.ts`; same word-boundary logic via a
WHATWG URL parse. Protects even a bare `npx playwright test` that never ran the
shell guard.

## `resolve-spec-path.sh` — canonical spec/test path mapping

`scripts/resolve-spec-path.sh spec|test <arg>` maps every argument form the
`/qa-warden:*` commands accept (bare `<area>/<feature>`, `<area>/<feature>.md`,
`specs/….md`, `tests/….spec.ts`) to the spec or compiled-test path. `test` mode
verifies the file exists (exit 2 if not) so a mis-mapped path can never become a
phantom zero-test "green" run. Used by `/qa-warden:gen`, `/qa-warden:new-spec`,
`/qa-warden:run mode=single`, `/qa-warden:run mode=repeat`, and `/qa-warden:review` — the mapping lives here
and only here.

## `doctor.sh` — launcher for the deterministic self-check pass

The checks behind `/qa-warden:doctor` (0–21 + rollup, all read-only: reruns no tests, heals
nothing, hits no network, writes nothing) ship in the plugin as `skills/doctor/scripts/doctor.sh`,
so they are always the same build as the templates they compare this project against. They verify
the substrate itself: `last-run.json` freshness/zero-test (via `check-last-run.sh`), oracle-vocab
lockstep (`oracle-keys.txt` vs the plugin's `test-case-contract` skill), prod-guard presence + regex lockstep, substrate drift,
sentinel files, context staleness, `bugs/` Status hygiene, site-id↔config match, and more. Exit 1
on any ❌.

This file is only a launcher for running it from a terminal: `bash scripts/doctor.sh` finds the
plugin install Claude Code recorded (`~/.claude/plugins/installed_plugins.json`) and runs that
plugin's doctor here: this project's install, else your user install, else one not tied to a
project. It never runs another project's local- or project-scope install, since that scope
applies only to its own repository. It exits 2, having run nothing, when no usable install is
recorded, and names any other projects' installs with the command to run their doctor. In CI,
where no plugin is installed, check out the plugin at the tag you use and run its doctor from
this directory: `bash <checkout>/qa-warden/skills/doctor/scripts/doctor.sh`.

## `check-last-run.sh` — canonical last-run.json gate

`bash scripts/check-last-run.sh [file] [max_age_seconds]` (defaults:
`artifacts/last-run.json`, 900) — the single source for `/qa-warden:doctor` Check 1
AND `/qa-warden:report`'s pre-aggregation check (they used to mirror this logic in
prose and drifted). Prints one parseable line
(`last-run: <fresh|missing|corrupt|zero-test|stale> total=… age=…`) and exits
distinctly per state, distinguishing corrupt from zero-test — the two
false-green shapes a naive freshness check conflates.

## `bug-status.sh` — canonical `bugs/*.md` Status parser

`bash scripts/bug-status.sh <bugfile>` — the single source for reading a bug
file's lifecycle value. Prints the lowercased `Status` value (`open`,
`fixed — …`, `reverted`, …), tolerating all three authored forms (the two-line
`## Status`\n`open` heading, the inline `## Status: open`, and a bare
`Status: open` line); prints nothing when no marker is present. Used by
`/qa-warden:run mode=smoke`, `/qa-warden:run mode=single`, `/qa-warden:report`, and `/qa-warden:doctor` (Checks 11b/11c);
the parser lives here and only here (it was copy-pasted across those five spots
and drifted — the same single-sourcing rationale as `check-last-run.sh`).

`bash scripts/bug-status.sh --class <bugfile>` prints the **classification** —
`resolved` or `open` — instead of the raw value. Prefer it over re-typing a
`case … in fixed*|reverted*|resolved*|closed*)` alternation: that alternation had
itself been copy-pasted into all five callers, so single-sourcing only the
*parser* still left a fifth resolved keyword needing five hand edits. An absent or
free-text value classifies as `open` — the fail-safe direction (over-surface a
defect, never hide one).

## `spec-links.sh` — canonical basis/feature ↔ spec relation

`scripts/spec-links.sh feature <basisfile> | index | match <feat> | tests | specs | smoke | unmanifested`
— the one place the spec relation's mechanical rules live: the **indent-tolerant `feature:` extractor** (a col-0-only `^feature:`
anchor silently drops indented YAML, leaving the caller with `specs/.md` and a no-op check
instead of an error) and the **fanned-spec back-link anchor** (which must tolerate the trailing
`# comment` the plugin's own fanned-spec convention writes). Both were hand-copied across
`doctor.sh`, `/qa-warden:coverage` and `/qa-warden:impact`, each site carrying a "LOCKSTEP with …" comment
rather than a mechanism — and the anchor had already needed one fix applied by hand in three
places. `match` reads an `index` on **stdin** so a caller looping over N features stays one tree
walk, not N. The third rule is the **unmanifested walk** (`unmanifested` — every compiled
`tests/<base>.spec.ts` with no `artifacts/route-manifests/<base>.json`, printed as
`<testpath>\t<base>`). `/qa-warden:impact` renders it as `### BLIND SPOTS`; `/qa-warden:coverage` dim 0 needs
the same set because, without it, a withheld manifest made the routes of a compiled spec print
under "touched by NO compiled test (planned, untested)" — false, and the wrong remedy. Its
load-bearing half is the **metamorphic-twin exclusion**: a twin never carries a manifest by
design, so a copy that forgets it reports every twin as a blind spot. Doctor **Check 9k**
enforces the ownership (and, per its arm 3, scans code rather than comments — an ownership
check must name the construct it bans, so it matches its own documentation otherwise).

That walk is the **collected-test inventory** (`tests` — one TAB-separated row per test
Playwright collects: `<test> <base> <spec|twin> <spec path|-> <manifest|->`), the one place
`playwright.config.ts`'s `testIgnore` is applied: a `_`-prefixed basename AND a `_`-prefixed
directory are both dropped. Three walks used to disagree on that (the unmanifested one applied
neither, so `/qa-warden:impact` and `/qa-warden:coverage` listed `tests/_demo/…` files Playwright never
runs). A test path with a TAB in it cannot be one column, so it is left out of the rows and
named on stderr (`spec-links: skipped …`). Its specs-side twin is `specs` (`<spec> <base> <test|-> <smoke|-> <basis|->`), and
`smoke` lists the specs that put a scenario on the `@smoke` gate — the YAML `tags:` key in its
inline, per-scenario (`scenarios: [{ …, tags: [smoke] }]`) and block-list forms, never a prose
mention. Doctor, `/qa-warden:coverage`, `/qa-warden:impact` and `post-run-checks.sh` all read these rows
instead of walking `tests/` or `specs/` themselves.

## `post-run-checks.sh` — the canonical "is this green actually all-clear?" scans

`bash scripts/post-run-checks.sh [--prefix <str>] [--only sentinels,stray,bugs]` — three
advisory scans a run's verdict depends on: unprocessed healer sentinels, stray/unmanaged specs
a full `npx playwright test` would collect but the smoke lane never touched, and still-open
`bugs/*.md` a parked xfail may be hiding behind an "expected" count. Always exits 0 (advisory)
and ends with a parseable `post-run: sentinels=<n> stray=<n> open-bugs=<n> test-gaps=<n>` trailer for the
caller's roll-up. Called by `/qa-warden:run mode=smoke`, `/qa-warden:report`, `/qa-warden:run mode=single` (`--only bugs`) and
`doctor.sh` Checks 4/14 (`--only sentinels,stray`) — each of which used to inline all three,
byte-identically in places, with its own copy of the `testIgnore` lockstep filter. When
`spec-links.sh` has no `tests` inventory (a stamp older than it), the stray scan says it could
NOT run and counts that in `stray`, rather than reporting 0; doctor passes it the plugin's copy
(`QA_SPEC_LINKS`) so its Check 14 still answers.

## `oracle-keys.txt` — the oracle vocabulary as data

Not a script: the closed oracle vocabulary, one key per line. The plugin's `test-case-contract`
skill remains the human SoT (it owns the semantics and the per-key argument-shape table); this is
the machine-readable key **set** that `doctor.sh` Check 2 compares against that skill (the plugin's own
`bin/qa-selfcheck` Check 9b compares the plugin's agents against the shipped copy). Doctor
used to hold a hand-typed copy and police its peers with that copy as the baseline — a checker
that needed a cardinality self-check on its own mirror. Same pattern as the toolkit-owned
file list (`resync-set.txt`, in the plugin's `manifests/`).

## `retire-delete.sh` — sanctioned scoped-delete wrapper

The only path by which `/qa-warden:retire` removes a spec/test pair, so deletion is
scoped and auditable rather than an open-ended `rm` in an agent's hands.
It refuses (exit 2) a path whose directory, once every symlink is resolved, leaves the
project or the retire-able dirs, so `tests -> /tmp/outside` cannot turn into a delete
outside the repo.

## `cli-fill-env.sh` — type a `.env` value into a field without exposing it

`bash scripts/cli-fill-env.sh <session> <target> <ENV_VAR>` — the only sanctioned way for an
agent to enter a credential through `playwright-cli`. Every Bash tool call is a fresh shell, so a
sourced `.env` never reaches the next call; without this wrapper an agent either types the
literal password into `fill` (it lands in the transcript) or skips the login. Takes the variable
NAME, suppresses the CLI's echo of the value, and refuses to put a secret-looking variable into
anything but an `<input type="password">`.

## `runtime-dirs.txt` — the runtime-directory manifest

Also not a script: the single list of directories the subagents write into
(`artifacts/`, `bugs/`, `specs/_context/`, `steps/`, …). Both bootstrap entry
points read it — `bin/qa-scaffold` (the `/qa-warden:init` path) and `init.sh` (the
plugin-free `npm run init` path) — so the two provably stamp the **same** tree.
It replaced a pair of hand-kept `mkdir -p` lists held together only by matching
"keep this list IDENTICAL" comments, which nothing enforced. Adding a runtime
directory is a one-line edit here; keep it consistent with the `Edit(...)`
allowlist in `.claude/settings.json` and CLAUDE.md §"Tooling allowed paths",
or the first agent write into the new directory hits an approval wall.

## Manifests that are NOT here

Three manifests used to be stamped into this directory and no longer are, because
nothing in a project ever read them: `resync-set.txt` (the toolkit-owned file list that
`/qa-warden:init --resync` refreshes and doctor Check 9 byte-compares), `claude-md-vocab.txt`
(the symbols doctor Check 9 requires in your `CLAUDE.md`) and `prod-guard-rails.txt` (the
skills the plugin's own self-check requires to carry a prod-guard rail). `qa-scaffold` and
`doctor.sh` read the plugin's copies, so they live in the plugin's `manifests/` directory,
each documented in its own header. If this project was stamped before that move, the
old copies here are inert and safe to delete; doctor names any it finds.

## Running the suite

There is no orchestrator script — the suite is plain `npx playwright test`,
run by hand (or on your own CI schedule), at zero LLM cost. Parallelism is
Playwright's job (`workers:` in `playwright.config.ts`), not the shell's.

Run it in two waves, smoke as a gate:

```bash
# Wave 1 — smoke gate. If this fails, stop before regression.
# QA_RUN_OF_RECORD=1 makes this the run-of-record: the config's json sink is
# GATED (fires only in CI or with this var), so artifacts/last-run.json refreshes
# here and can't be clobbered by agent-side verification runs. Do NOT pass an
# inline --reporter (it REPLACES the config array and stops last-run.json updating).
QA_RUN_OF_RECORD=1 npx playwright test --grep @smoke

# Wave 2 — full regression (everything not tagged @smoke).
# An explicit reports/regression.json is fine here; prefer the config reporters when you can.
npx playwright test --grep-invert @smoke --reporter=json > reports/regression.json
```

`/qa-warden:report` turns the JSON into `reports/summary.md`
for a PR comment or Slack post. Triage is a separate, human-initiated action:
`/qa-warden:heal <failing-test-id>` in an interactive Claude Code session, respecting
CLAUDE.md's 5-turn healer budget.

### Tagging contract

Smoke specs declare `tags: [smoke, ...]` in their YAML oracle block. The
generator surfaces each entry via Playwright's structured tag API —
`test('<name>', { tag: ['@smoke', '@site:app'] }, ...)` — and Playwright folds
those tags into the grep-matched title, so `--grep @smoke` / `--grep-invert @smoke`
partition the suite cleanly (the reviewer's Check 11 FAILs any test missing its
`@smoke`/`@regression` tag, so the gate can't silently match zero tests).
