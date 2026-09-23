# scripts/

Orchestration scripts for the AI-QA stack.

## `init.sh` — one-shot bootstrap (plugin-free fallback)

Idempotent setup for a fresh clone. Verifies Node ≥ 22 and Claude Code,
creates runtime dirs, copies `.env.example` → `.env` if missing, runs
`npm install` + `npx playwright install chromium` (chromium only — the config's
active projects are all Desktop Chrome). Prints next steps.

Invoke via `npm run init` or `bash scripts/init.sh`.

> **Relationship to `/qa:init`:** the canonical bootstrap is the plugin's
> `bin/qa-scaffold` (run by `/qa:init`) — it stamps the full substrate, merges
> `.claude/settings.json` permissions, and installs the official `playwright-cli`
> skill. `init.sh` is the equivalent **plugin-free fallback** for a plain
> `git clone` with no plugin installed; it does the dir/`.env`/npm/browser
> bootstrap only. Canonical output sinks are `artifacts/` (machine — incl.
> `last-run.json`) and `reports/` (human).

## `prod-guard.sh` — canonical shell prod-guard (layer 1 of 2)

`bash scripts/prod-guard.sh [url ...]` — run before any browser-driving or
test-running step; every `/qa:*` command's safety rail calls it. Loads `.env`
itself, screens **every** exported `BASE_URL_*` / `API_URL`, and exits 1 on a
word-boundary `prod`/`production` host marker (`QA_ALLOW_PROD=1` overrides).
Any URL passed as an **argument** goes through the same screening body — that is
how a command whose target comes from its arguments rather than `.env`
(`/qa:review url=<url>`) screens it, instead of re-implementing the host match in prose. Layer 2 is
`prod-guard.ts` — the enforced Playwright `globalSetup` that throws before any
browser opens. **Keep the marker regex in the two files in lockstep.** Both are
deny-listed from agent edits in `.claude/settings.json`.

## `prod-guard.ts` — enforced globalSetup prod-guard (layer 2 of 2)

Wired as `globalSetup` in `playwright.config.ts`; same word-boundary logic via a
WHATWG URL parse. Protects even a bare `npx playwright test` that never ran the
shell guard.

## `resolve-spec-path.sh` — canonical spec/test path mapping

`scripts/resolve-spec-path.sh spec|test <arg>` maps every argument form the
`/qa:*` commands accept (bare `<area>/<feature>`, `<area>/<feature>.md`,
`specs/….md`, `tests/….spec.ts`) to the spec or compiled-test path. `test` mode
verifies the file exists (exit 2 if not) so a mis-mapped path can never become a
phantom zero-test "green" run. Used by `/qa:gen`, `/qa:new-spec`,
`/qa:run mode=single`, `/qa:run mode=repeat`, and `/qa:review` — the mapping lives here
and only here.

## `doctor.sh` — deterministic self-check pass

`bash scripts/doctor.sh` (what `/qa:doctor` runs) — checks 0–21 + rollup, all
read-only: reruns no tests, heals nothing, hits no network, writes nothing.
Verifies the substrate itself: `last-run.json` freshness/zero-test (via
`check-last-run.sh`), oracle-vocab lockstep (`oracle-keys.txt` vs `CLAUDE.md`),
prod-guard presence + regex lockstep, sentinel files, context staleness,
`bugs/` Status hygiene, site-id↔config match, and more. Exit 1 on any ❌ —
wire it as a cheap CI pre-step or run it whenever the project "feels off".

## `check-last-run.sh` — canonical last-run.json gate

`bash scripts/check-last-run.sh [file] [max_age_seconds]` (defaults:
`artifacts/last-run.json`, 900) — the single source for `/qa:doctor` Check 1
AND `/qa:report`'s pre-aggregation check (they used to mirror this logic in
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
`/qa:run mode=smoke`, `/qa:run mode=single`, `/qa:report`, and `/qa:doctor` (Checks 11b/11c);
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

`scripts/spec-links.sh feature <basisfile> | index | match <feat> | unmanifested` — the one
place three mechanical rules live: the **indent-tolerant `feature:` extractor** (a col-0-only `^feature:`
anchor silently drops indented YAML, leaving the caller with `specs/.md` and a no-op check
instead of an error) and the **fanned-spec back-link anchor** (which must tolerate the trailing
`# comment` the plugin's own fanned-spec convention writes). Both were hand-copied across
`doctor.sh`, `/qa:coverage` and `/qa:impact`, each site carrying a "LOCKSTEP with …" comment
rather than a mechanism — and the anchor had already needed one fix applied by hand in three
places. `match` reads an `index` on **stdin** so a caller looping over N features stays one tree
walk, not N. The third rule is the **unmanifested walk** (`unmanifested` — every compiled
`tests/<base>.spec.ts` with no `artifacts/route-manifests/<base>.json`, printed as
`<testpath>\t<base>`). `/qa:impact` renders it as `### BLIND SPOTS`; `/qa:coverage` dim 0 needs
the same set because, without it, a withheld manifest made the routes of a compiled spec print
under "touched by NO compiled test (planned, untested)" — false, and the wrong remedy. Its
load-bearing half is the **metamorphic-twin exclusion**: a twin never carries a manifest by
design, so a copy that forgets it reports every twin as a blind spot. Doctor **Check 9k**
enforces the ownership (and, per its arm 3, scans code rather than comments — an ownership
check must name the construct it bans, so it matches its own documentation otherwise).

## `post-run-checks.sh` — the canonical "is this green actually all-clear?" scans

`bash scripts/post-run-checks.sh [--prefix <str>] [--only sentinels,stray,bugs]` — three
advisory scans a run's verdict depends on: unprocessed healer sentinels, stray/unmanaged specs
a full `npx playwright test` would collect but the smoke lane never touched, and still-open
`bugs/*.md` a parked xfail may be hiding behind an "expected" count. Always exits 0 (advisory)
and ends with a parseable `post-run: sentinels=<n> stray=<n> open-bugs=<n>` trailer for the
caller's roll-up. Called by `/qa:run mode=smoke`, `/qa:report`, `/qa:run mode=single` (`--only bugs`) and
`doctor.sh` Checks 4/14 (`--only sentinels,stray`) — each of which used to inline all three,
byte-identically in places, with its own copy of the `testIgnore` lockstep filter.

## `oracle-keys.txt` — the oracle vocabulary as data

Not a script: the closed oracle vocabulary, one key per line. `CLAUDE.md` remains the human SoT
(it owns the semantics and the per-key argument-shape table); this is the machine-readable key
**set** that `doctor.sh` Check 2/9b compares CLAUDE.md and the plugin's agents against. Doctor
used to hold a hand-typed copy and police its peers with that copy as the baseline — a checker
that needed a cardinality self-check on its own mirror. Same pattern as `resync-set.txt`.

## `retire-delete.sh` — sanctioned scoped-delete wrapper

The only path by which `/qa:retire` removes a spec/test pair, so deletion is
scoped and auditable rather than an open-ended `rm` in an agent's hands.

## `cli-fill-env.sh` — type a `.env` value into a field without exposing it

`bash scripts/cli-fill-env.sh <session> <target> <ENV_VAR>` — the only sanctioned way for an
agent to enter a credential through `playwright-cli`. Every Bash tool call is a fresh shell, so a
sourced `.env` never reaches the next call; without this wrapper an agent either types the
literal password into `fill` (it lands in the transcript) or skips the login. Takes the variable
NAME, suppresses the CLI's echo of the value, and refuses to put a secret-looking variable into
anything but an `<input type="password">`.

## `review-marker.sh` — write the `/qa:review` attestation marker

`bash scripts/review-marker.sh <spec.md> <test.spec.ts> PASS|FAIL` writes
`reports/review/<area>/<feature>.reviewed` (commit, both sha256 digests, date, result) — the
file `/qa:doctor` Check 15 reads. One allow-listed call instead of an improvised compound
command; it records a verdict the caller already confirmed and judges nothing itself.

## `resync-set.txt` — the toolkit-owned file manifest

Not a script: the single list of files the **toolkit** owns (as opposed to the
shared-ownership files users edit — `.env`, `CLAUDE.md`, `settings.json`,
`fixtures/test.ts`, …, each documented inline). Both consumers read it, so
detection and repair can't drift apart: `qa-scaffold --resync` force-refreshes
exactly this set, and `doctor.sh` Check 9 byte-compares exactly this set against
the shipped templates. Adding a template file is a one-line edit here.

Two shared-ownership files are excluded from the *copy* but not from the *upgrade*, because
skipping the file turned out not to mean skipping its content: `--resync` also runs the
additive `.claude/settings.json` permission merge (it did not until a resync-only upgrade was
measured delivering 0 of 37 new rules, exit 0) and appends the single `*.qa-bak` pattern to
`.gitignore` (the rule that covers litter the resync itself writes, and which an older
`.gitignore` could not otherwise receive). Neither file is ever overwritten.

## `runtime-dirs.txt` — the runtime-directory manifest

Also not a script: the single list of directories the subagents write into
(`artifacts/`, `bugs/`, `specs/_context/`, `steps/`, …). Both bootstrap entry
points read it — `bin/qa-scaffold` (the `/qa:init` path) and `init.sh` (the
plugin-free `npm run init` path) — so the two provably stamp the **same** tree.
It replaced a pair of hand-kept `mkdir -p` lists held together only by matching
"keep this list IDENTICAL" comments, which nothing enforced. Adding a runtime
directory is a one-line edit here; keep it consistent with the `Write`/`Edit`
allowlist in `.claude/settings.json` and CLAUDE.md §"Tooling allowed paths",
or the first agent write into the new directory hits an approval wall.

## `claude-md-vocab.txt` — the CLAUDE.md delivery manifest

Also not a script: the list of toolkit-owned **symbols** that must survive in a project's own
`CLAUDE.md`. It closes the widest hole in the upgrade path. `CLAUDE.md` is shared-ownership, so
it is excluded from `--resync` *and* from Check 9's byte-compare — both correct in isolation, but
together they mean the file every new authoring feature ships in is the one file an upgrade
cannot deliver, and the in-project agents read that file rather than the plugin. Measured on a
real `0.2.0` → HEAD upgrade: after a clean, green, exit-0 `/qa:init --resync` the stamped
`CLAUDE.md` carried zero mentions of `fault:`, `clock:`, `lock:` or `verifier`, and doctor said
nothing.

Why symbols and not sections: across that same upgrade the `## ` heading set was **identical**
(19 before, 19 after) while the 93 new lines landed *inside* ten pre-existing sections — a
section-level diff would report green on exactly the release it would have been built for. So it
polices symbols, the way `prod-guard-rails.txt` polices an invocation rather than a wording.

The required set is derived (manifest × shipped template), so a symbol retired from the template
reports the *manifest* as stale instead of nagging consumers about a dead feature. Presence
anywhere in the file satisfies it — rewording and user additions are free, only a deletion is
reported — and it **WARNs**, because alone among Check 9's findings the repair is a hand-merge
rather than a command. Not the oracle keys: those are Check 2's, and `lock:` must never be added
to `oracle-keys.txt` (it is a `TestDetails` field, and that manifest also feeds Check 9b and
`/qa:coverage`). Shipping a feature documented in `CLAUDE.md` is a one-line edit here.

## `prod-guard-rails.txt` — the prod-guard rail manifest

Also not a script: the single list of skills that must carry a prod-guard rail in prose.
Doctor Check 9bd reads it and verifies each listed skill still **invokes**
`bash scripts/prod-guard.sh` **and** stops on a non-zero exit — and WARNs on the reverse, a
skill carrying a rail that nobody listed. It compares invocation + the STOP clause only, never
the wording: the eight sites deliberately carry two different lead forms and materially different
bodies, so a whole-text compare would fire on every edit and get the check switched off.

The clause it really guards is the STOP. `flake-check` once shipped running the guard and
ignoring its exit code — on a repeat-each run that multiplies the blast radius instead of
reducing it — and nothing detected it. Never delete a rail to make the check pass: on the
`gen`/`new-spec`/`intake`/`explore`/`review` CLI-driving paths this prose is the only prod rail,
since the enforced `prod-guard.ts` globalSetup fires only under `npx playwright test`.

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

`/qa:report` turns the JSON into `reports/summary.md`
for a PR comment or Slack post. Triage is a separate, human-initiated action:
`/qa:heal <failing-test-id>` in an interactive Claude Code session, respecting
CLAUDE.md's 5-turn healer budget.

### Tagging contract

Smoke specs declare `tags: [smoke, ...]` in their YAML oracle block. The
generator surfaces each entry via Playwright's structured tag API —
`test('<name>', { tag: ['@smoke', '@site:app'] }, ...)` — and Playwright folds
those tags into the grep-matched title, so `--grep @smoke` / `--grep-invert @smoke`
partition the suite cleanly (the reviewer's Check 11 FAILs any test missing its
`@smoke`/`@regression` tag, so the gate can't silently match zero tests).
