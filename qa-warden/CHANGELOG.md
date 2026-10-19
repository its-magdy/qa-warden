# Changelog

All notable consumer-facing changes to QA Warden (plugin id `qa-warden`; `qa` before 0.4.0).

The **last published build was `0.2.0` (2026-07-24)**. The **`0.3.0`** section below landed in
the repository since then: a feature release on the published `0.1.0 → 0.2.0`
line, with no breaking change to the spec format or the `/qa:*` surface. **`0.4.0`** adds only
the rename on top of it, and that one IS breaking (see its section). **`0.4.1`** is
documentation fixes only; **`0.5.0`** fixes what a fresh-install test and a re-check of the
2026-09-26 end-to-end run found; **`0.5.1`** is a one-line wording fix on top, **`0.5.2`** fixes what a full end-to-end run
of the README walkthrough found, **`0.5.3`** fixes what a whole-plugin code review found, **`0.5.4`** fixes what a
security review found, **`0.5.5`** hardens one step of it, and **`0.5.6`** brings the nightly in line with GitHub's and Playwright's CI guidance. `.claude-plugin/plugin.json` reads `0.5.6`; tag the build with `claude plugin tag ./qa-warden`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/). Versions are the
number in `plugin.json`, which is also the key the installer caches under
(`~/.claude/plugins/cache/<marketplace>/qa-warden/<version>/`) — so **two different builds must
never carry the same number**, or the second one has no way to announce itself.

---

## [Unreleased]

### A symlinked directory can no longer carry a delete or a review marker out of the project

- **`scripts/retire-delete.sh` refused a symlinked file but not a symlinked directory.** It checked
  the path as a string (relative, no `..`, under a retire-able dir) and refused a symlink only at
  the leaf, so in a project with `tests -> /tmp/outside`, `bash scripts/retire-delete.sh
  tests/x.spec.ts` deleted `/tmp/outside/x.spec.ts` and exited 0. It now resolves the target's
  directory with every symlink followed (`cd -P … && pwd -P`) and refuses (exit 2, nothing deleted)
  unless that directory is inside the project root and still under a retire-able dir. A dir symlink
  that resolves inside one (`tests/alias -> demo`) still works; one that resolves elsewhere in the
  project (`tests/src -> ../src`) is refused, because that is product source. This file is stamped:
  run `/qa-warden:init --resync` to get the fix (doctor reports the old copy as substrate drift).
- **The review skill's `review-marker.sh` wrote through a symlinked `reports/`.** It created the
  marker's directory with `mkdir -p` and wrote the marker without checking where either resolved.
  It now refuses (exit 2, nothing written) a marker that is itself a symlink, or whose directory
  (before the first write, its nearest existing ancestor) resolves outside the project. The spec
  and test it hashes get the same rule: a symlink at the leaf, or a symlinked dir under `specs/` or
  `tests/` that resolves outside the project, is refused. `check` mode applies it too, so doctor
  Check 15 says such a pair "could not be checked" instead of reading a marker from outside.
- **Both refuse a path with a newline or another control character.** A `$( )` strips trailing
  newlines, so beside a real `tests/safe/`, a symlink named `tests/safe<newline>` was checked as
  the real directory while the delete or write followed the link. Every `pwd -P` is now captured
  so that it keeps a trailing newline, and a project root or resolved directory containing a
  control character is refused too.
- **Not race-proof.** Both refuse a path that resolves outside the project. They are not hardened
  against another process rewriting the tree during the call. They narrow the window:
  retire-delete re-checks the target's directory from inside it and runs `rm` there, and
  review-marker creates the marker's directories one level at a time, re-checks each from inside,
  writes the marker in a private temp dir made with `mkdir` (which fails on a planted symlink), and
  renames it onto the marker. Swapping an ancestor directory after that no longer redirects them.
  A marker path that is a directory or a symlink is refused right before the rename; swapping one
  in after that check is still possible. A failed or interrupted write leaves no temp files.
  `check` mode only reads a hash and is not narrowed.
- The resolving function is the same few lines in both files (one is stamped into projects, the
  other runs from the plugin, so they cannot share it). `bin/qa-scaffoldtest` gains 122 cases
  (642 → 764): a new section 10 runs one path table against both scripts, covering a symlinked
  `tests/`, `specs/` and `reports/`, a symlinked intermediate dir, a leaf symlink, a dangling
  symlink, new marker dirs under a real and under a symlinked `reports/`, a sibling-prefix dir
  (`proj` vs `proj2`), dir symlinks back inside the project and `reports -> .`, trailing-newline
  and tab names, a sibling dir named `proj<newline>`, a project root named so, a marker path that
  is a directory, and the plain paths. Further cases swap the tree at a fixed point after the
  checks (a stub `rm` and a stub `sha256sum` on `PATH`), plant a symlink at the temp dir's name,
  and make the temp write fail with `ulimit -f 0`.

### The two hooks share one comment stripper

- `hooks/spec-lint.sh` and the healer arm of `hooks/assertion-contract.sh` each carried the same
  awk program that blanks comment lines before scanning. It now lives once in `hooks/hook-lib.sh`
  as `hook_strip_js_comments`, which both hooks already source. No behaviour change.
- `bin/qa-hooktest` gains 4 cases (58 → 62) that fail if the stripper stops stripping: a comment
  naming `networkidle` and a healer comment naming `page.route` are allowed, while code before a
  trailing comment and a `waitForTimeout` after an `https://` string are still denied.

### One prod-guard verdict: `scripts/prod-guard-core.mjs`, used by both guards

- The shell guard and the `globalSetup` guard parsed hosts differently, and the shell one PASSED
  three URLs a browser resolves to `prod.acme.com`: `https://prod.acme.com\@staging.acme.dev`,
  `https://PROD%2Eacme.com` and a fullwidth `https://ｐｒｏｄ.acme.com`. A new stamped file,
  `scripts/prod-guard-core.mjs` (plain ESM, no dependencies), now owns the whole verdict: the
  screened var-name set, host extraction with WHATWG `new URL()` plus the scheme-less `host:port`
  fallback, placeholder sentinels, the prod marker and `QA_ALLOW_PROD=1`. `prod-guard.ts` imports
  it; `prod-guard.sh` runs it with `node` once per call and keeps its `.env` load,
  `--list-targets`, `--probe`, credential masking and every line it prints.
- Two intentional verdict changes beyond the WHATWG parse: a scheme-less host now gets the same
  WHATWG host parse (so `PROD%2Eacme.com:8080` refuses), and `example.com.` (trailing dot) is a
  placeholder like `example.com`.
- Scheme-relative and scheme-less values are parsed WHOLE by WHATWG too (against an http base, or
  under `http://`); userinfo is never hand-stripped ahead of the parser, so `//prod.acme.com\@staging.acme.dev`,
  `/\prod.acme.com` and `prod.acme.com\@staging.acme.dev` refuse through both guards. A
  path-only reference (`/production/users`, `./x`, `?q`, `#f`) names no host and is screened as
  one, so `API_URL=/production/users` is not read as a host called "production".
- `prod-guard.sh` now needs `node` on PATH. With none it refuses ("Node ≥22 required"); with the
  core missing beside it (a partial stamp) it refuses and names `/qa-warden:init --resync`.
- `prod-guard.sh` accepts the core's output only whole: node must exit 0, every line must be a
  known record, and the last line must be exactly `verdict<TAB>PASS` or `verdict<TAB>REFUSED`; a
  PASS beside a refusing record is refused. The `names` list for `--list-targets`/`--probe` is held
  to the same rule. Both node calls run with `NODE_OPTIONS` cleared, so an inherited `--import`
  preload cannot print a verdict of its own.
- The nightly template runs `actions/setup-node` before the prod-guard step (still before `npm ci`).
- `tsconfig.json` sets `allowJs`, so `prod-guard.ts` can import the `.mjs` under `npm run typecheck`.
- `scripts/prod-guard-core.mjs` is edit-denied in `.claude/settings.json` and refreshed by
  `/qa-warden:init --resync`.
- Doctor Check 8: the four lockstep greps over `prod-guard.sh`/`.ts` are replaced by one compare
  of the stamped core against the plugin's copy (a difference is a ⚠️). A project stamped before the
  core keeps working and gets a resync ⚠️; a guard that needs the core when it is missing is a ❌.
  Check 9 leaves the core to Check 8. The doctor still has 32 numbered checks.
- `qa-scaffoldtest` gains section 9: a 45-row URL-to-verdict table that both guards must reproduce
  (`prod-guard.sh` through node, `prod-guard.ts` imported under node type stripping), the shell
  guard's fail-closed paths (no node, no core, a crash after a verdict-shaped line, a malformed
  record, a suffix-only verdict, a NODE_OPTIONS preload), `--list-targets`, and doctor on current,
  drifted, mixed, pre-core and resynced stamps. It now needs `node` on PATH. 642 cases (643 under mawk).

**Upgrade:** run `/qa-warden:init --resync`. Until then the old guards keep working and doctor
warns.

### `/qa-warden:batch-fix` no longer reads a crashed precheck as "nothing to fix"

- Step 1's precheck ignored Playwright's exit code (`|| true`), so a timeout or worker crash that
  recorded 0 failures landed in "nothing to fix" — a vacuous green on a batch that never finished.
  The precheck is now a mode of `/qa-warden:run`'s script, called as one command
  (`bash "${CLAUDE_SKILL_DIR}/../run/scripts/run.sh" precheck $ARGUMENTS`) under a new
  `allowed-tools` rule, instead of ~40 lines of inline shell that matched no allow rule. It exits
  `0` when there is something to fix (with the heal-log signature hint, as before), `1` when the
  filter matched nothing or nothing is failing, and `2` when the run did not complete or never
  started — and says which. "Did not complete" covers an interrupted or killed run too: Playwright
  exits only 0, 1 or 130 (interrupted), so any exit other than 0 or 1 reads as `incomplete` even
  when the report already recorded failures — a Ctrl-C'd precheck is no longer a batch to fix. Playwright's stderr now goes to `artifacts/batch-fix-precheck.log`
  instead of `/dev/null`.
- Step 5's re-run is `run.sh recheck $ARGUMENTS` under the same rule, replacing the last inline
  block. It still runs `--retries=0 --reporter=line`, so `artifacts/last-run.json` is never rewritten,
  and it refuses an empty filter. It exits `0` when green and `1` for anything else. Still red, a crash
  and "no tests found" all exit 1 from Playwright's line reporter, so it does not pretend to tell them apart.
- Every `/qa-warden:run` mode reads its run through one verdict (`skills/run/scripts/run-verdict.sh`):
  the exit code and the JSON become one word — green, red, incomplete, missing, corrupt, zero-test,
  stale or unchecked. This replaces four hand-kept tables and two copies of the "non-zero exit, 0
  failures" guard. The visible changes: `mode=repeat` now refuses a crashed probe (non-zero exit, 0
  failures) rather than reporting the repeats that ran as stable, and the `mode=single` /
  `mode=changed` status line ends in `(verdict=<word>)` instead of `(rc=<n>)`.
- No stamped file changed: `scripts/check-last-run.sh` keeps its CLI, so no `--resync` is needed.
- `precheck` and `recheck` take every argument after the mode word as the filter. A filter that
  starts with `mode=` (`precheck mode=smoke`) used to pick that mode instead; the other modes still
  accept `mode=<name>` anywhere on the line.
- `bin/qa-scaffoldtest` gains 88 cases (293 → 381). It runs every verdict on fixture JSONs and drives
  `run.sh`'s single, smoke, repeat, changed, precheck and recheck modes end to end against a stub
  `npx`.

### Doctor warns on a FAILED review; one script writes and checks the review marker

- **A review that FAILED no longer counts as attested.** `/qa-warden:doctor` Check 15 compared only
  the marker's hashes and never read its `result:` line, so `/qa-warden:review` recording `FAIL`
  silenced the "never reviewed" warning as well as a `PASS` would. A marker whose hashes are
  current but records `result: FAIL` now gets its own warning: "reviewed, FAILED — fix and re-run
  /qa-warden:review". A changed pair still gets "changed since last review", whatever its result.
  A marker with no `result:` line (the script always writes one; a marker improvised before it
  existed may not have one) is read as before: matching hashes attest it.
- **The marker format lives in one file.** The review skill's `review-marker.sh` gains a read-only
  `check <spec> <test>` mode that prints `current`, `stale`, `failed` or `missing`, and Check 15
  calls it from the same plugin instead of keeping its own digest function, path rule and field
  greps (the two digest copies had already drifted once). The writer's command line is unchanged.
- **The digest falls back on output, not only on exit status.** A `sha256sum` that exits 0 but
  prints nothing now falls through to `shasum -a 256` too. With no working tool at all, the script
  refuses (exit 2) instead of writing an empty hash, and doctor says the attestation could not be
  checked instead of comparing two empty strings. A pair with no marker is still reported as never
  reviewed: the script looks for the marker before it hashes anything.
- **Only a real digest counts.** A tool's output is accepted only if it is exactly 64 lowercase hex
  characters. A `sha256sum` that printed junk (`unavailable`, exit 1) used to be recorded as both
  hashes, and an edited test still read `current` afterwards (junk equals junk); it now falls
  through to `shasum -a 256` like the other broken cases, and if neither tool yields a digest the
  script refuses. A marker that already recorded a non-digest hash reads `stale`, never `current`.
  The file is hashed from stdin, so a backslash or newline in its name (which makes both tools
  prefix their line with `\`) cannot turn a valid file into a refusal.
- Doctor reads the script's answer from stdout only, so a shell warning on stderr (a setlocale
  warning under an `LC_ALL` naming a missing locale) cannot turn a reviewed pair into "could not be
  checked".
- `bin/qa-scaffoldtest` gains 69 cases (381 → 450): the script is tested directly (each of the
  four answers, the `sha256sum` fallbacks including one that prints junk, a backslash in a file name, and a table of every
  refusal in both write and check mode, each asserting exit 2, nothing on stdout and no file
  written or changed), and doctor through it (the FAILED warning apart from the changed one,
  stderr noise ignored, the no-tool reason).

### One inventory of collected tests and smoke-tagged specs

- **`/qa-warden:impact` and `/qa-warden:coverage` no longer report scratch tests Playwright never
  runs.** The `unmanifested` walk in `scripts/spec-links.sh` did not apply `playwright.config.ts`'s
  `testIgnore`, so `tests/_demo/failure-demo.spec.ts` (and any `_`-prefixed file or directory)
  showed up under impact's `### BLIND SPOTS` and coverage's "compiled but UNMANIFESTED" arm, and
  inflated coverage's "FLOOR, not the total" count. Doctor and `post-run-checks.sh` already
  excluded them; the three walks now share one.
- **Smoke tags are read one way everywhere.** Doctor Check 16 only saw a line-leading
  `tags: [… smoke …]`, so it missed the per-scenario `scenarios: [{ …, tags: [smoke] }]` form the
  test-case contract requires for a multi-scenario spec, and a block-list `tags:` / `- smoke`. Such a
  spec with no compiled test was reported by Check 17's generic "spec with no compiled test"
  instead of Check 16's smoke-gate warning. `/qa-warden:coverage` dim 1b had the opposite bug: it
  matched `smoke` anywhere, so a spec saying "this is not a smoke test" was flagged as blinding the
  smoke gate. The one parser now reads only a spec's ```` ```yaml ```` blocks (or the whole file when it
  has none), counts only the spec-level and per-scenario `tags:` keys (not one under `meta:` or a
  scenario's `data:`), and treats `#` inside quotes as text, so `name: "issue #3"` no longer hides
  the tag after it.
- **`scripts/spec-links.sh` gains `tests`, `specs` and `smoke`.** `tests` lists each collected test
  with its spec, its manifest and whether it is a metamorphic twin; `specs` lists each authored spec
  with its test, its smoke tag and its `basis:` link; `smoke` lists the smoke-tagged specs. Doctor,
  `/qa-warden:coverage`, `/qa-warden:impact` and `post-run-checks.sh` read these rows instead of walking
  `tests/` and `specs/` themselves. Doctor Check 9k now also checks that the shared walk keeps both
  `_` exclusions. Specs with a `_`-prefixed file name (not only directory) are now skipped by
  doctor's spec checks and by `index` too, matching the test side, so a scratch spec's `basis:`
  no longer satisfies doctor Check 18 or `/qa-warden:coverage` dims 1/5/6.
- **The smoke parser reads escaped quotes and split tag lists.** An escaped `\"` inside a
  double-quoted scenario name ended the quote early, so `name: "say \" #3"` lost its tag to a
  "comment" and an escaped `{` threw off the depth count. A `tags: [` list split over lines
  (`tags: [`, then `smoke, regression`, then `]`) was read as no tag at all, in both scenario
  forms and at the top level. Both now count.
- **The stray-spec scan no longer reports 0 when it could not run.** `post-run-checks.sh` read an
  older `spec-links.sh`'s empty answer to `tests` as "no stray specs". It now prints a warning
  that the scan could NOT run, naming `/qa-warden:init --resync`, and counts it in `stray`; doctor
  hands it the plugin's copy, so doctor's Check 14 still finds strays on such a stamp. A test file
  with a TAB in its path is left out of the `tests` rows (it would shift the columns and hide the
  stray) and named on stderr, which `post-run-checks.sh` prints and counts as a warning. It reads
  only those `spec-links: skipped` lines from stderr, kept apart from the rows, so no other
  diagnostic can be counted as a stray test.
- `bin/qa-scaffoldtest` covers all of this: +61 cases on top of the two entries above (450 → 511; 512 under mawk).
- **Upgrading:** run `/qa-warden:init --resync`. `scripts/spec-links.sh`, `scripts/post-run-checks.sh`,
  `scripts/README.md` and a comment in `playwright.config.ts` change, so doctor reports them as
  drifted until you do. Until then nothing fails: doctor, `/qa-warden:coverage` and `/qa-warden:impact`
  see the older `spec-links.sh` has no inventory and run the plugin's copy of it instead. Doctor
  adds an uncounted ℹ️ line, and coverage and impact print a `WARN:` line suggesting the resync.

### `/qa-warden:coverage` reads the oracle keys from the manifest

- `coverage.sh` builds its `KEYS_RE` at runtime from `scripts/oracle-keys.txt` instead of carrying a
  hand-typed copy of the 16 keys, so it is no longer a mirror to edit when the vocabulary changes.
  The regex is unchanged on the current key set. If the manifest is missing or empty the command now
  refuses (exit 2, "run `/qa-warden:init --resync`") rather than falling back to a baked-in list that
  could silently under-count assertions in dimensions 1 and 2.

### The scaffold and prod-guard.sh get a deterministic test

- **New `bin/qa-scaffoldtest`** (maintainer tool, not shipped to projects; runs in CI on Ubuntu and
  macOS). Until now nothing deterministic ran `bin/qa-scaffold`: the only caller was an eval
  fixture that needs `claude plugin eval`, so the byte-stable `settings.json` merge and the
  `--resync` backup and `.gitignore` behaviour its comments describe were asserted nowhere. It
  stamps into temp dirs (no network, no `npm install`) and checks a fresh stamp (file set derived
  from `templates/` and `resync-set.txt`, second run byte-identical), the settings merge (rules
  unioned, the project's rules and sibling keys kept, no duplicates, byte-stable), `--resync`
  (owned files restored with a `.qa-bak`, `*.qa-bak` gitignored once, `CLAUDE.md` and `.env`
  untouched), and a table of `prod-guard.sh` URL cases including `QA_ALLOW_PROD=1`. No plugin
  behaviour changes.

### Adding a site no longer means editing `playwright.config.ts`

- **Site projects come from `BASE_URL_<SITE>`; you no longer edit `playwright.config.ts` to add a
  site.** `playwright.config.ts` is toolkit-owned (it is in `resync-set.txt`), yet doctor Check 10
  told a user with a third site (say `shop`) to add its project by hand. Check 9 then flagged that
  edit as drift, and `/qa-warden:init --resync` replaced the file, which deleted the project; the
  site's `@site:shop` specs then ran in no project. Now `app` stays the one literal site project,
  and every set, non-empty `BASE_URL_<SITE>` registers project `<site>` (lowercased, `_` → `-`, so
  `BASE_URL_ADMIN_PORTAL` → `admin-portal`) with the same tag grep, `setup` dependency and ignore
  globs. With only `BASE_URL_APP`, or with `BASE_URL_ADMIN` too, the resolved projects are
  identical to before.
- **Doctor Check 10 checks the `sites[]` table against that rule** instead of grepping the config:
  ❌ when an id is not lowercase `[a-z0-9-]`, is `setup`, or its `base_url_env` is not exactly
  `BASE_URL_<ID>`; ⚠️ when `BASE_URL_<ID>` is unset or empty after loading `.env`. That warning is new for
  declared sites whose var is unset, `admin` included: before, a project-less run of those specs
  passed silently.
- **Upgrading:** run `/qa-warden:init --resync`. A project you added by hand is backed up to
  `playwright.config.ts.qa-bak` and replaced; if it used `BASE_URL_<ID>` and the matching id, it
  comes back on its own. Otherwise Check 10 names the id or variable to rename.

### Doctor stops running checks no project can fix; three manifests stop being stamped

- **Six more checks moved from `scripts/doctor.sh` to the plugin's own `bin/qa-selfcheck`:** 9bb
  (oracle arg-shape drift), 9bd (prod-guard rail coverage), arm 1 of 9f (healer `tools:` vs the
  shipped MCP grants), 9g (the generator → verifier chain), 9i (the `fault:`/`clock:` chain) and 20.
  Each one read only plugin files, so when one fired in a project there was nothing the user could
  do, and the repo's CI never ran doctor, so none of them gated a plugin change either. Their ❌
  findings now fail CI on every PR. Their ⚠️ arms still do not, because CI fails on ❌ only. Those
  arms are: the 9bb row-count mismatch, the 9bd skill-with-a-rail-but-not-listed direction, and the
  "UNVERIFIED" notices of 9f and 9i. Ids are unchanged. Doctor keeps 9f arms 2 and 3, which compare
  the plugin's grants with your `.claude/settings.json`. Doctor now runs 32 numbered checks,
  qa-selfcheck 14.
- **Check 20 has a new job under the same id.** It used to warn when the `.env`-load one-liner
  copied into agents and skills drifted into more than one form. Every copy has since been replaced
  by `prod-guard.sh --list-targets`, so it compared nothing and could not fire. It now **fails** if
  any file under `agents/` or `skills/` chains a `.env` load. That covers the canonical one-liner on
  any line, and a `set -a` + `. …/.env` in a fenced code block or a script line. CLAUDE.md
  §Environment already forbids this, because such a command prompts, is denied headless, and its
  exports die with the call.
- **`resync-set.txt`, `claude-md-vocab.txt` and `prod-guard-rails.txt` moved from
  `templates/scripts/` to the plugin's `manifests/`**, so `/qa-warden:init` no longer copies them
  into a project. Nothing in a project ever read them: `qa-scaffold` and doctor read the plugin's
  copies. Editing a stamped copy changed nothing and only raised a substrate-drift warning, and
  two doctor messages told you to run `/qa-warden:init --resync` to fix a manifest that resync
  cannot deliver. Those messages now say to update the plugin. `oracle-keys.txt` and
  `runtime-dirs.txt` stay stamped, because doctor, `coverage.sh` and `init.sh` read them in the project.
  `bin/qa-scaffoldtest` reads the resync set from `manifests/` and now also asserts that no
  plugin-only manifest is stamped and that the resync set lists none of them.
- **Already-stamped projects:** the three old files stay under `scripts/`. They do nothing and
  `--resync` no longer touches them. Doctor prints one ℹ️ line per leftover (not counted as a
  warning) saying it is safe to delete. A doctor stamped by 0.5.6 or earlier cannot find the moved
  manifests and would print a ❌ for `prod-guard-rails.txt` and two ⚠️ until `--resync`.
  `/qa-warden:doctor` no longer runs that stamped copy (next section), so this does not show up.

### `/qa-warden:doctor` runs from the plugin, not from a copy in your project

Ships together with the section above: it is what keeps that move from breaking doctor in existing
projects.

- **The checks moved from the stamped `scripts/doctor.sh` to the plugin's
  `skills/doctor/scripts/doctor.sh`,** and `/qa-warden:doctor` runs that file
  (`bash "${CLAUDE_SKILL_DIR}/scripts/doctor.sh"`, pre-approved by the skill's `allowed-tools`, as
  `/qa-warden:coverage`, `impact` and `run` already do). The doctor and the templates it compares
  your project against are now always the same build. Before, the stamped copy changed only on
  `/qa-warden:init --resync`, so every new check arrived one repair late, and a copy older than the
  plugin misread it: a 0.5.6 project run against the previous section's plugin printed
  1 ❌ + 2 ⚠️ until `--resync`. Measured on a 0.5.6-stamped scratch project: the plugin doctor
  prints no ❌, only the real substrate drift, and after `--resync` only the expected
  fresh-project warnings. On a fresh stamp its output is byte-identical to the old stamped doctor's.
- **No more guessing which plugin to compare against.** The stamped doctor had to find a plugin:
  `$CLAUDE_PLUGIN_ROOT`, else the install recorded in `installed_plugins.json`, else the newest cached
  version by mtime, which could be a stale orphaned one ("baseline GUESSED by newest mtime"). The
  plugin doctor uses the plugin it sits in and reads no environment variable for it.
- **`scripts/doctor.sh` is now a small launcher** for running doctor from a terminal. It reads the
  install Claude Code recorded (this project's install, then your user install, the newest record
  first within each), runs that plugin's doctor and passes its exit code through. With no recorded
  install it exits 2 and runs nothing, and it says which case it hit: no record, a record jq could
  not read (a broken jq, malformed JSON), an install path that no longer exists, or a plugin older
  than the launcher. It never guesses, and it ignores `$CLAUDE_PLUGIN_ROOT` (it executes what it finds, and older projects
  carry an allow rule for `CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh`). In CI, where no plugin is
  installed, check out the plugin and run `bash <checkout>/qa-warden/skills/doctor/scripts/doctor.sh`
  from the project root. It is still toolkit-owned (in `resync-set.txt`, edit-denied).
- **Two allow rules leave the shipped `settings.json`:** `Bash(bash scripts/doctor.sh*)` and
  `Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)`. Nothing Claude runs calls the stamped path
  any more. The merge never removes a rule, so existing projects keep both. The first is harmless
  (it pre-approves only the edit-denied launcher). The second is not, and doctor Check 9c now flags
  it: see "The doctor launcher stops running another project's install" below.
- **Upgrading:** update the plugin, then run `/qa-warden:init --resync`. Until then doctor reports
  `substrate drift: scripts/doctor.sh` (and `scripts/README.md`); `--resync` backs up the old full
  copy to `scripts/doctor.sh.qa-bak` and puts the launcher in its place. **Delete that backup**
  (`find . -name '*.qa-bak' -not -path './node_modules/*' -delete`, as the resync banner says): it is
  the old full doctor, and the `Bash(bash scripts/doctor.sh*)` rule your project still carries
  pre-approves running it, since that pattern also matches `scripts/doctor.sh.qa-bak`. A teammate whose plugin is
  older than this keeps running their own plugin's `/qa-warden:doctor`, which calls the stamped
  path. That now reaches the launcher, which finds no doctor in their plugin, exits 2 and tells
  them to update it (in a project first stamped by this version the call also prompts, because the
  allow rule it relied on is no longer shipped).
- `bin/qa-scaffoldtest` gains 25 cases: the plugin doctor finds its baseline (no drift on a fresh
  stamp, a real edit reported, `CLAUDE_PLUGIN_ROOT` ignored) and the launcher (a failing doctor's
  exit 1 passed through, project install before user install, newest record within a scope, and
  exit 2 with a distinct message for no record, a malformed record, a jq that cannot run, a missing
  install path and a doctor-less plugin).

### The spec format moves out of `CLAUDE.md` into a `test-case-contract` skill

- **`CLAUDE.md` §"Test case format contract" is now the plugin skill `test-case-contract`**: the
  YAML schema, the 16 oracle keys and their argument shapes, the `fault:`/`clock:` situation steps,
  the smoke-lane rule and the honest limits, moved with only pointer wording changed.
  `CLAUDE.md` is loaded into every session, subagent and forked skill on every turn, and this
  section was ~19 KB of it (~4.7k of ~15.6k tokens) that only the agents reading or writing specs
  use. A fresh `CLAUDE.md` is now ~44 KB (~11k tokens) and keeps a one-sentence pointer under
  `## Spec format`.
- **Rules first, explanation last.** The skill is ~20 KB, longer than the first ~5,000 tokens of a
  skill that Claude Code re-attaches after a compaction. The docs do not say whether that cap
  applies to a preload, so the skill is ordered as if it does: schema, keys, argument shapes, the
  duplicate-key rule and the situation-step rules (fired-proof, no `fault:` on `smoke`, the HAR ban,
  the `clock:` rules) come first, and the native-validation note and the two honest limits come last
  under `## Authoring notes and honest limits`. The text is unchanged; only its order is.
- **Who gets it:** the planner, generator, verifier, reviewer and ideation agents preload it
  (frontmatter `skills:`; a preload needs no `Skill` tool, so the reviewer keeps `Read, Bash`).
  `/qa-warden:import-cases`, the one main-session command that maps cases to oracle keys itself,
  invokes it explicitly. It is `user-invocable: false` (not in the `/` menu) and stays
  model-invocable, because a `disable-model-invocation: true` skill cannot be preloaded. Its
  description adds ~52 tokens to the skill listing (1,054 → 1,106).
- **Doctor:** Check 2 now compares the project's `scripts/oracle-keys.txt` with the plugin's
  skill instead of grepping `CLAUDE.md` for the 16 keys. It compares the two key SETS exactly
  (the skill's set is read from its argument-shape table), so a manifest that gains a word like
  `value` or `lock` now fails, where a substring scan let it through. A key in the manifest that
  the skill lacks is ❌; a skill key missing from the manifest is ⚠️ (run `--resync`). `fault:`
  and `clock:` leave `manifests/claude-md-vocab.txt`: their definition ships with the plugin now,
  so a `CLAUDE.md` without them is missing nothing. `test-case-contract` joins it, so a
  `CLAUDE.md` without the pointer is nudged to add it. **New Check 9 warning:** a `CLAUDE.md`
  that still has the `## Test case format contract` section is told to replace it with the
  pointer.
- **Upgrading — run `/qa-warden:init --resync` FIRST, then edit `CLAUDE.md`.** A project
  stamped before this change carries a full stamped doctor that still greps `CLAUDE.md` for the 16
  keys; delete the section before `--resync` and that doctor prints 11 false ❌ (one per key the
  section alone carried). `--resync` replaces it with the launcher and also refreshes four stamped
  files whose comments pointed at the old section (`scripts/oracle-keys.txt`, `scripts/README.md`,
  `specs/_context/_templates/app.context.md`, `specs/_context/_templates/basis.md`); doctor reports
  them as substrate drift until then. `--resync` does not touch `CLAUDE.md`, so doctor then warns
  about the old section (and the missing pointer) until you edit it by hand:
  - **Move any project-specific rules out of the section first.** Your agents did read your
    copy (subagents load the project `CLAUDE.md`), so customisations there were live, and they
    are lost when you delete it.
  - Replace the section (from its heading down to `## Assertion style`, `### Situation steps`
    included) with the shipped template's `## Spec format` section.
  - In `## Oracle defense`, change "Closed vocabulary — see above" to name the skill.
  - Your own `specs/_context/app.context.md` keeps
    `oracle_vocab_ref: CLAUDE.md#test-case-format-contract`. Nothing machine-reads that field;
    change it to `oracle_vocab_ref: test-case-contract` by hand if you like.
- `bin/qa-selfcheck` Checks 9b, 9bb, 9be and 9i read the skill where they read
  `templates/CLAUDE.md`. 9b gains two arms: one fails if any of the five agents drops the preload
  or the skill gains `disable-model-invocation: true`, the other fails if a normative rule starts
  past byte 17,500 of the skill (≈5,000 tokens at 3.5 chars/token). `bin/qa-scaffoldtest` gains 21
  cases (161 → 182): no warning on a fresh stamp, one warning and nothing else for the old section,
  no warning for a prose mention or a different heading, no `fault:`/`clock:` demand, a nudge for
  a missing pointer, Check 2 failures for `not_a_real_key`, `value` and `lock`, and a Check 2
  warning for a skill key missing from the manifest.

### `review-marker.sh` ships with the review skill, not in your project

- **`scripts/review-marker.sh` moved from `templates/scripts/` to the plugin's
  `skills/review/scripts/review-marker.sh`,** and `/qa-warden:review` runs that file
  (`bash "${CLAUDE_SKILL_DIR}/scripts/review-marker.sh" <spec> <test> PASS|FAIL`, pre-approved by
  the skill's `allowed-tools`, as `/qa-warden:doctor` does). Nothing else ever called it, so the
  stamped copy was one more toolkit-owned file to resync and two `settings.json` rules to keep in
  step. A plugin update now changes the marker writer without a `--resync`. Its README section
  became the script's header comment.
- **Leaving the shipped files:** the `scripts/review-marker.sh` line in `manifests/resync-set.txt`,
  and two rules in `settings.json`: `Bash(bash scripts/review-marker.sh*)` (allow) and
  `Edit(scripts/review-marker.sh)` (deny). The review skill no longer tells you to `--resync` when
  the script is missing: it cannot be missing now.
- **`/qa-warden:review` no longer points at a CI section that is gone.** Three sentences still
  referred to the "CI wiring" section removed in 0.5.3 ("wire it into CI (below)", "the CI-gate
  hardening above", "the CI required-status above"). They now say the review runs locally before
  a commit, that a marker written from a guessed verdict defeats the reviewer's fail-closed rule,
  and that the anti-forgery layer is a human reading the PR (a required approval in
  branch protection), because an agent-writable marker is not proof.
- **Already-stamped projects:** `scripts/review-marker.sh` and its two rules stay; nothing calls
  them, and `--resync` no longer touches the file. Doctor prints one ℹ️ line (not counted as a
  warning) naming the file and both rules as safe to delete together. Doctor Check 9c does not
  flag the rules, since they are harmless. `--resync` refreshes `scripts/README.md`, which doctor
  reports as substrate drift until then. Doctor still runs 32 numbered checks.
- **Doctor Check 15 no longer WARNs on every reviewed pair when `sha256sum` cannot run.** It
  chose `sha256sum` whenever `command -v` found one, so a binary that is on `PATH` but cannot
  execute (an x86-only `sha256sum` on Apple silicon: "Bad CPU type", exit 126) hashed every file
  to an empty string, and every pair read as "changed since last review". It now falls back to
  `shasum -a 256` per file when `sha256sum` fails, as `review-marker.sh` already did. The Check 15
  comment also stops naming the removed CI gate as the anti-forgery layer.
- `bin/qa-scaffoldtest` gains 13 cases (182 → 195):
  - the review skill carries the script, a fresh stamp neither has the file nor gets the ℹ️ line,
    and a planted `scripts/review-marker.sh` gets that line, naming both rules, as the only new
    output, with doctor still exiting 0;
  - every `manifests/resync-set.txt` entry exists under `templates/`, so a dead entry (a moved
    file left in the list, which qa-scaffold and doctor both skip silently) fails, with a copy
    carrying a dead entry as the vacuity guard;
  - Check 15 accepts a fresh marker with a `sha256sum` that exits 126 first on `PATH`, and still
    reports an edited test.
- Docs: `reference/how-to.md` says the marker is written for a PASS or a FAIL verdict (it said
  PASS only), and `DOCUMENTATION.md` says the reviewer's git commands work headless (`claude -p`)
  rather than "in CI", where Claude does not run.

### Doctor outside a project, a retired `printenv` rule, and two selfcheck gaps

- **Doctor run outside a project prints one line instead of ~31 ❌.** When the current directory
  has none of `playwright.config.ts`, `CLAUDE.md` or `scripts/`, doctor prints
  `❌ not a QA Warden project (run from the project root, or /qa-warden:init)` and exits 1. Before,
  it ran every check and reported each missing substrate file, which looks like a broken project
  rather than the wrong directory. Any one of the three present still runs the full pass, so a
  damaged project still gets every finding. The test runs before doctor loads `.env`, so a stray
  `.env` in the wrong directory is never executed, and before the jq check. The stamped launcher
  runs the doctor in your directory, so the same line appears through `bash scripts/doctor.sh`.
  Not a numbered check; doctor stays at 32. The doctor skill tells the agent what the line means.
- **`Bash(printenv *)` leaves the shipped `settings.json`, and doctor Check 9c now warns when a
  project still has it.** Nothing in the toolkit runs `printenv`: agents resolve base URLs with
  `bash scripts/prod-guard.sh --list-targets`, and doctor's own `printenv` is a shell call, not a
  tool call. The rule did pre-approve `printenv QA_ADMIN_PASSWORD` (or any other named secret in
  the shell's environment, such as a CI secret) with no prompt, which puts the value into the
  transcript. That is the reason the bare `Bash(printenv)` was retired earlier, so Check 9c treats
  this one the same way: the settings merge is a union and never removes a rule, so without the
  warning every existing project would keep the grant. The warning appears once, in projects
  stamped before this change, and the fix is deleting one line by hand. The ⚠️ for the bare rule no
  longer says `agents/exploration.md` mandates `printenv $base_url_env`; that file stopped using it
  when base URLs moved to `--list-targets`.
- **`bin/qa-selfcheck` Check 9b requires each oracle key in a key spelling.** It used a substring
  scan, so a key appended to `oracle-keys.txt` that occurs inside other text passed: `lock` was
  found inside `clock:`. A whole-word scan would not help, because the mirrors use `lock`, `value`
  and `state` as plain words. A key now counts only backticked on its own (`` `text_visible` ``) or
  backticked with a colon at the start of a list item (`` - `storage_state: {…}` → … ``), which is
  how `agents/generator.md` writes six of the keys. All 16 keys meet that in all four mirrors, and appending `lock` now fails 9b for all four.
- **Check 9bb compares the argument-shape table's key set with `oracle-keys.txt` and fails on a
  difference.** It compared row counts and only warned, so CI passed (it is one of the ⚠️ arms
  listed under "Doctor stops running checks no project can fix" above), and a table that swapped
  one key for another with the same count passed outright. Both files ship in the same commit and
  the manifest's header requires every enumerating mirror to change together, so a difference is
  always a bug. A key listed twice in the manifest, or a row repeated in the table, also fails.
  Doctor Check 2, which compares a project that may be older than the plugin, keeps its ⚠️ for a
  key the project lacks. qa-selfcheck stays at 14 checks.
- `reference/test-case-ideation.md` no longer calls the hooks rationale in `DESIGN.md` "the
  no-hooks decision". `bin/qa-scaffoldtest` gains 21 cases (195 → 216): doctor and the launcher in
  an empty directory (exit 1, that one ❌, no rollup), a stray `.env` not sourced, each of the
  three markers alone still running the full pass, and the `printenv` rule absent from the
  template and a fresh stamp and warned (exit 0) when added back.

### `qa-scaffoldtest` feeds doctor real input, and runs the bug scripts

- **Section 6 covers what a fresh stamp never reaches.** A fresh stamp has no sites, area files,
  review markers or bug files, so of doctor's five awk programs only the `spec-links.sh` arm
  extractor ran in CI (macOS BSD awk, the ubuntu-24.04 runner's gawk), and nothing ran `scripts/bug-status.sh`
  or the bug scan of `scripts/post-run-checks.sh`. The new section builds that project in the test
  (quoted site ids, one area file per volatility tier, current and stale review markers, CRLF and
  `## Status History` bug files) and asserts doctor's Check 5b, 9, 10, 11 and 15 lines, `--class`
  and `--list-open` (sorted), and the `post-run-checks.sh` titles and trailer. An `awk` stand-in
  logs each program doctor runs, so a guard that stops reaching one fails a case instead of
  passing on nothing. `bin/qa-scaffoldtest` goes from 216 to 270 cases. CI gains a Linux-only step
  that runs `qa-scaffoldtest` and `qa-hooktest` again with mawk first on PATH, because the runner's
  default awk is gawk and nothing else exercised mawk. Tests and CI only; no plugin behaviour changes.

### The generator's data-isolation rules get their own heading

- `agents/generator.md` gains a `## Data isolation, factories and invariants` heading before the
  worker-scoped seeding rule. Those rules (seeding, parallel and cross-run safety, `test lock:`,
  factory resolution, `must_fail_when:`/`fail_if:` invariants) sat under `## Situation steps ->
  page.route / page.clock`, which is about `fault:`/`clock:` only. Text unchanged; no behaviour change.

### The doctor launcher stops running another project's install; stale wording in stamped files

- **`scripts/doctor.sh` no longer runs another project's plugin install.** The launcher tried this
  project's local- or project-scope install, then the user-scope one, then every record. That last
  tier included local- and project-scope installs recorded for other directories, so on a machine
  where qa-warden was installed only for another project, `bash scripts/doctor.sh` ran that
  project's copy here. Claude Code applies a local- or project-scope install only to its own
  repository, so that copy is not the plugin this project runs, and its version can be older or
  newer than this project's stamp. The last tier now takes only records not tied to a project (a
  managed install, for example). When the only installs belong to other projects, the launcher
  exits 2 and runs nothing. It lists each of those projects with the
  `bash "<installPath>/skills/doctor/scripts/doctor.sh"` command that runs its doctor here, for
  anyone who wants that build anyway. A record whose `projectPath` matches this directory in either
  form (`pwd` or `pwd -P`), with or without a trailing `/`, still counts as this project.
- **Doctor Check 9c now warns on `Bash(CLAUDE_PLUGIN_ROOT=* bash scripts/doctor.sh*)`.** Projects
  stamped before `/qa-warden:doctor` moved into the plugin still carry it, because the settings
  merge never removes a rule. The earlier section called it harmless, and it is not. A `*` in a
  Bash rule matches any text, spaces included, so the rule also pre-approves
  `CLAUDE_PLUGIN_ROOT=x CLAUDE_CONFIG_DIR=artifacts/x bash scripts/doctor.sh`. The launcher reads
  `CLAUDE_CONFIG_DIR`, and `artifacts/` is agent-writable, so an install record written there
  chooses the doctor that runs. It also pre-approves
  `CLAUDE_PLUGIN_ROOT=x bash -c '<anything>' bash scripts/doctor.sh`. Nothing calls it any more.
  Like the `printenv` rules, it gets a counted ⚠️ that names both forms; delete the line by hand.
- **The plain `Bash(bash scripts/doctor.sh*)` is named as a leftover, not warned on.** It begins
  with the program, so an allow match cannot carry a variable assignment in front of it, and a
  compound command is matched one subcommand at a time. All it pre-approves is running the
  edit-denied launcher. Doctor prints one ℹ️ line (not counted as a warning) calling it safe to
  delete, the way it already names `scripts/review-marker.sh`. Delete the rule, not
  `scripts/doctor.sh`, which is the launcher.
- **Stale wording in four stamped files.** `playwright.config.ts` and `scripts/runtime-dirs.txt`
  pointed at `scripts/resync-set.txt`, which is no longer stamped; they now name the plugin's
  `manifests/resync-set.txt`. `scripts/runtime-dirs.txt` and `scripts/README.md` said the stamped
  settings have a `Write`/`Edit` allowlist, but they have only `Edit(...)` rules.
  `scripts/README.md` also describes the launcher's new order and exit. `scripts/retire-delete.sh`
  said its allow-listed wrapper pattern was the one used for `doctor.sh`, which no longer has an
  allow rule; it now names `prod-guard.sh` only. These edits change no behaviour.
- **Already-stamped projects:** until you run `/qa-warden:init --resync`, doctor reports one ⚠️
  `substrate drift` line for each of the five changed stamped files: `playwright.config.ts`,
  `scripts/README.md`, `scripts/doctor.sh`, `scripts/retire-delete.sh` and
  `scripts/runtime-dirs.txt`. `--resync` backs each one up to `.qa-bak` and refreshes it.
  Measured on a project stamped from the previous commit that still has both old doctor rules:
  2 warnings before; after the plugin update, 8 (the 5 drift lines plus the Check 9c warning)
  and the ℹ️; 3 after `--resync`. The Check 9c warning and the ℹ️ stay until you delete those two
  rules. A fresh stamp's doctor output is unchanged. Doctor still runs 32 numbered checks.
- `bin/qa-scaffoldtest` gains 23 cases (270 → 293).
  - For the launcher: when another project's install is the only one, it exits 2, runs nothing,
    and lists that project with its doctor command. A project record with no `projectPath` is
    listed as unnamed. The same record with this project's path is picked (the control), and so
    is one ending in `/`. A managed install beats another project's newer one. Run through a
    symlink, a record holding the real path or the symlink path is picked. Restoring the old
    fallback tier fails 7 of them.
  - For the two rules: neither is in the template, and a fresh stamp gets neither line. With both
    present, doctor prints the ℹ️ for the plain rule and the Check 9c ⚠️ for the other, naming
    `CLAUDE_CONFIG_DIR` and `bash -c`. It exits 0, counts one more warning than a fresh stamp, and
    prints no other new line. Each rule on its own gets only its own line, and the ℹ️ is not
    counted. Removing the rule from Check 9c's list fails 5 of them.

### Claude takes the guarded path: `run` becomes model-invocable, three agents stop inviting direct use

- **`/qa-warden:run` no longer sets `disable-model-invocation: true`.** The flag did not stop Claude
  running tests: `Bash(npx playwright *)` is pre-allowed, so Claude could already run a bare
  `npx playwright test` with no prompt. All the flag blocked was the guarded wrapper, with its
  zero-test and freshness checks and the report paths `/qa-warden:report` and `/qa-warden:heal` read.
  It also hid the skill's description, including "Do not hand-roll a bare `npx playwright test`",
  from Claude. Claude can now invoke it; you can still type it. It uses no model and keeps
  prod-guard. README, `DOCUMENTATION.md`, `reference/knowledge-map.md` and `reference/DESIGN.md` list
  it under "You or Claude".
- **The planner, generator and healer agents no longer say "Use proactively".** The flag on
  `/qa-warden:new-spec`, `/qa-warden:gen` and `/qa-warden:heal` blocks only the skill, so those
  descriptions invited Claude to delegate to the agent directly. That skipped `gen`'s verifier (the
  check that the test can fail) and `heal`'s sentinel loop. Each description now names its command and
  says not to delegate directly.
- **Sentinel handoffs that need a user-only command now go to you.** `reference/sentinel-actions.md`
  told the orchestrator to run `/qa-warden:gen` (`.healer-needs-migrate`) and `/qa-warden:new-spec`
  (`.healer-needs-spec-update`), which Claude cannot run. Those rows, and `/qa-warden:heal`'s loop, now
  give you the exact command and keep the sentinel until it has run.
- New projects' `CLAUDE.md` says to compile with `/qa-warden:gen`, not by naming the `generator`
  subagent, which skipped the verifier. Existing projects keep their copy; `CLAUDE.md` is yours and
  `--resync` does not touch it. No stamped file changes, so there is no drift event.

---

## 0.5.6 — nightly CI hardening, a truncated hook message, shellcheck cleanup (2026-10-09)

Each item is backed by GitHub's, Playwright's or Anthropic's official docs, or by a reproduction.

- **`playwright.config.ts` sets `globalTimeout` (50 min) in CI.** The nightly job times out at 60 min;
  before, a long run was killed mid-suite with no report and no artifact. Playwright now stops first,
  so the reporters still write the report and `last-run.json` (Playwright's CI docs).
- **CI default workers drop from 4 to 2** (Playwright's own example, `workers: process.env.CI ? 2 :
  undefined`). A private repo's `ubuntu-latest` runner has 2 vCPUs. `QA_WORKERS` still raises it.
- **Secrets reach only the two steps that read them** (prod-guard and the suite), through one YAML
  anchor, instead of every step. `npm ci` install scripts and the browser download no longer see them.
- **Prod-guard runs right after checkout**, before Node and `npm ci`, so a misconfigured nightly fails
  in seconds.
- **Checkout sets `persist-credentials: false`**; the job never pushes.
- **`concurrency: qa-nightly`** queues a manual run behind a running nightly instead of letting both hit
  the same site with the same test user.
- **The browser install uses `--only-shell`** (headless shell only; Playwright's browsers docs).
- **`blob-report/` is now in the artifact**, so the JUnit export in DOCUMENTATION §16.2 works from the
  nightly without a rerun. The HTML-report step is skipped, not failed, when no blob was written.
- Header comments now cover the schedule's limits (default branch only; public repos disable it after
  60 days with no activity) and orgs that enforce SHA-pinned actions.
- **Fixed: the healer's stub/clock denial reached the agent cut in half.** An unescaped `"` inside
  the deny message in `hooks/assertion-contract.sh` ended the string at `healer.md §Anti-drift`, so
  the healer never saw what it may patch instead or how to report a false positive. The edit was
  still denied, which is why every hooktest case passed. A new hooktest case checks the message
  arrives whole (58 cases), and shellcheck now gates CI, so this class of slip fails the build.
- The `coverage`, `impact` and `review` skill descriptions now say when to use them, and `help`'s
  is in the third person (Anthropic's skill-authoring guidance; the listing grows ~44 tokens).
- Four reference files over 100 lines (`knowledge-map`, `glossary`, `how-to-import-manual-cases`,
  `tutorial-first-test`) start with a table of contents.
- Dead code removed (shellcheck): an unused variable each in `doctor.sh` and `coverage.sh`, and a
  case pattern in `doctor.sh` that could never match. `init.sh` exits if it can't `cd` to the project.
  Doctor's output is unchanged.
- Run `/qa-warden:init --resync` to pick these up; doctor reports the template drift. Resync refreshes
  `qa-nightly.yml.example` only: if you already armed it as `qa-nightly.yml`, diff the two and carry
  the changes over (keep your own secrets in the `&qa-env` block).

## 0.5.5 — nightly visibility step hardened (2026-09-30)

- **The nightly's repo-visibility step now writes exactly `private=true` or `private=false`.**
  On an HTTP error, `gh api` prints the error JSON to stdout without applying `--jq`, so in
  0.5.4 a failed lookup wrote that JSON as the value. The upload was still skipped (only
  `'true'` passes the gate), so nothing leaked, but the value is no longer passed through.
  Tested against a public repo, a private repo and a missing repo, and linted with actionlint.
  Run `/qa-warden:init --resync` to pick it up; doctor reports the template drift.

## 0.5.4 — fixes from a whole-plugin security review (2026-09-30)

Each item was confirmed by a local reproduction and against the official docs before it was fixed.

- **Bug traces no longer get committed.** The healer copies a failure's `trace.zip` into
  `bugs/<slug>/`, which is tracked. A Playwright trace stores the browser context options
  (the `httpCredentials` password, the `extraHTTPHeaders` values), every `fill()` value and
  the Cookie/Authorization headers in plain text (checked by recording a 1.63.0 trace and
  grepping it). `templates/gitignore` now ignores `bugs/**/trace.zip`; the healer, generator
  and CLAUDE.md Bug-report schema call the copy local-only.
  - **Existing projects:** `.gitignore` is outside the resync set, so add
    `bugs/**/trace.zip` by hand. `/qa-warden:doctor` Check 11b now warns when that rule is
    missing, and when a trace is already tracked (`git rm --cached` it, and rotate any QA
    credential that was pushed).
- **The nightly example uploads traces and the HTML report on private repos only.** GitHub
  redacts secrets in logs, not in artifacts, and anyone who can read a public repo can
  download its artifacts. A new step reads the repo's visibility from the API (a `schedule`
  run has no event payload, so `github.event.repository.private` is not available) and the
  upload is skipped when the lookup fails. The workflow also sets `permissions: contents: read`.

## 0.5.3 — fixes from a whole-plugin code review (2026-09-30)

Every item below was reproduced before it was fixed, and each hook fix has `bin/qa-hooktest`
cases, both deny and allow (34 → 57).

- **The assertion-contract hook** (healer/verifier) could be walked past four ways, now closed:
  - It stripped every `{...}` options object, so `toBeVisible({ visible: false })`, a looser
    `maxDiffPixelRatio`, an added `ignoreCase`, and the verifier renaming a locator's
    `{ name }` all passed. Only the `timeout` key is ignored now.
  - It compared line by line, so a Prettier-wrapped assertion's expected value (on its own
    line) could be retyped. It now compares whole `expect(...)` statements, including a
    `.matcher` on the next line; re-wrapping alone still passes.
  - `comm` ran in the user's locale on `LC_ALL=C`-sorted input, so under `en_US.UTF-8` adding a
    barrier assert could be denied as "removed". Now `LC_ALL=C comm`.
  - The healer's no-new-stub check missed `page.context().route`, `routeFromHAR`,
    `routeWebSocket` and `context.clock`. It now keys on the method, whatever the receiver.
- **Both hooks were off in a QA project under a directory named `tests/`** (`/repo/tests/qa/`):
  the root was cut at the first `/tests/` in the path. It is now found by walking up.
- **Claude no longer runs in CI.** `qa-review.yml.example` (the PR reviewer workflow) is removed,
  and so are the nightly's commented opt-in AI-heal step, the `CLAUDE_CODE_OAUTH_TOKEN` block in
  `.env.example`, and the `/qa-warden:review` "CI wiring" section. The review found the PR gate
  could never fail anyway: `claude-code-action` does not fail a job because the model was asked
  to. The review gate is local (`/qa-warden:review` marker + doctor Check 15), and the nightly
  stays plain Playwright at $0 LLM. If an earlier `/qa-warden:init` stamped
  `.github/workflows/qa-review.yml.example` (or you renamed it to `.yml`), delete it by hand:
  `--resync` never delivered it and does not remove it.
- **Stamped settings**: `Read(.env)` is denied (it also covers `cat .env` in Bash; scripts that
  load `.env` are unaffected), and the `/etc` deny is now `Read(//etc/**)`. A single leading
  `/` anchors at the project, so `Read(/etc/**)` never covered the system `/etc`. `--resync`
  merges both in.
- **`/qa-warden:impact route=`** now matches `:id` / `{id}` / `[id]` as one parameter and a
  concrete path (`/rooms/42`) against a recorded template, as `/qa-warden:coverage` does. It
  compared exactly, so an affected spec could read as not impacted.
- **`/qa-warden:run`**: `mode=single` no longer reports a run as done when
  `check-last-run.sh` returns an unexpected code (e.g. missing script), and `mode=repeat`
  stops with exit 2 on an empty or aborted report instead of printing nothing.
- **`cli-fill-env.sh`** treats any `*PASS*` name as a secret, which covers the toolkit's own
  `QA_BASIC_AUTH_PASS` and `QA_CLIENT_CERT_PASSPHRASE`.

---

## 0.5.2 — fixes from a full run of the demo walkthrough (2026-09-30)

A headless run of the README walkthrough against Playwright's TodoMVC demo passed end to end
(explore drafted `auth_mode: none`, gen wrote no login setup, the verifier caught all 5 injected
defects, `SMOKE: PASS (1/1)`) for about $6 and 40 minutes. It surfaced these:

- **Confirming the explore draft** now says what it takes: delete `draft:` and the `> REVIEW:`
  banner, resolve `# REVIEW:` notes, set `last_verified:` to today. Deleting only `draft:` left
  `/qa-warden:review` warning that the context was unconfirmed while doctor said healthy.
- **`/qa-warden:doctor`** runs its script as one command; the `if …; fi` wrapper it used matched
  no allow rule and was denied headless.
- **Headless `--add-dir`**: `/qa-warden:gen` belongs on the list too (its verifier reads
  `verify-invariants.md` from the plugin). The nightly CI example's opt-in heal step now says the
  runner needs the plugin installed plus `--add-dir` and `--settings` (`--resync` to pick it up).
- README: the "Try it in 5 minutes" section is now "Try it on a demo app", with the measured
  time and cost; the reviewer-eval cost figure is updated.

---

## 0.5.1 — fast lane first in the stamped CLAUDE.md (2026-09-30)

The stamped `CLAUDE.md` called the rigor chain (`intake` → `ideate` → `new-spec` → `gen`) *the*
authoring chain, so agents such as `/qa-warden:doctor` recommended it to newcomers. It now
names the fast lane (`new-spec` → `gen`) first and the rigor lane as the P1 option. `--resync`
does not rewrite `CLAUDE.md`; edit that line by hand in existing projects if you want it.

---

## 0.5.0 — apps without a login, headless-safe prompts, teammate install (2026-09-30)

No change to the spec format or the oracle vocabulary. Run `/qa-warden:init --resync` to pick
up the script fixes (`doctor.sh`, `init.sh`, `post-run-checks.sh`) and the new permission
rules; `.env` and customized files are left alone.

**Added**
- **`auth_mode: none`** for a site with no login. Tests run unauthenticated: no `storageState`,
  no login setup file, no credentials needed. `/qa-warden:explore` drafts `none` (flagged for
  review) when it finds no login form and no `QA_USER_*` credentials. Before this, a public app
  got a login setup with empty credentials that failed every run. An absent `auth_mode` still
  means `form`.
- **Teammate install:** `/qa-warden:init` adds the `qa-warden` marketplace to the project's
  `.claude/settings.json` (`extraKnownMarketplaces`), so a teammate who clones and trusts the
  folder gets the plugin. Your own entries win in the merge.
- **doctor Check 21a:** warns, offline, when `BASE_URL_APP` is empty or still a placeholder, and
  the verdict reads "Setup is NOT ready yet" instead of "healthy".

**Fixed**
- **`/qa-warden:new-spec` overwrite guard never fired.** It stored the spec path in a shell
  variable and tested it in a later call, which runs in a fresh shell. A revision could be
  treated as new authoring. It now checks the resolved literal path.
- **Permission prompts and headless denials** from commands the allow list cannot match:
  agents no longer load `.env` and drive the browser in one chained command (they resolve the
  URL with `bash scripts/prod-guard.sh --list-targets` and type it literally); the reviewer's PR
  scope, `/qa-warden:report` and `/qa-warden:new-spec` use single allowlisted commands instead of
  variables and loops. New allow rule: `Bash(git ls-files *)`. In CI the reviewer now reviews
  the PR diff instead of silently widening to the whole tree.
- **`doctor.sh` run directly** compared against the wrong installed copy: it ignored
  `CLAUDE_CONFIG_DIR` and did not recognise `--scope project` installs, so it could print false
  "substrate drift" warnings that suggested a downgrading `--resync`. `/qa-warden:doctor` was
  not affected.
- `npm run init` printed only the rigor lane; it now prints the fast lane first, like
  `/qa-warden:init`.
- Open-bug lines in run output showed an empty title; they now use the H1, else the first
  Summary line, else the file slug.
- `run`, `coverage` and `impact` quote the plugin path in their pre-approved commands, so a
  plugin path containing a space no longer breaks them.
- Stamped `CLAUDE.md`: bug evidence may read "trace not retained — <reason>" when Playwright
  kept none (a parked test); `QA_ADMIN_*` is an elevated role on the same or a separate site;
  the planner's YAML check is a read-back, not a parser command. `--resync` does not rewrite
  `CLAUDE.md`; existing projects keep the old wording unless edited by hand.

**Known limit:** skills that read reference files inside the plugin (`report`, `help`, `heal`,
`batch-fix`, `doctor --verify-invariants`) ask once for the read interactively; a headless run
needs `--add-dir <plugin path>`. No skill rule can pre-approve a read outside the project.

---

## 0.4.1 — documentation fixes (2026-09-30)

No behaviour change. A full audit of the docs against the code fixed:

- **Install and first run:** the tutorial now shows the `/plugin marketplace add its-magdy/qa-warden`
  step and `--scope project`; init already creates `.env`, so the docs say to edit it rather than copy it.
- **Rigor lane:** `/qa-warden:explore mode=area site=<id> area=<area>` is now listed before
  `/qa-warden:intake`, which stops without that area context.
- **`/qa-warden:import-cases`:** the import guide said the command did not exist; it now documents it.
- **Who does what:** fault injection (step 8b) and the kept video (step 8d) are the verifier's, not the
  generator's; the generator, not the verifier, writes page objects; the healer parks an
  undocumented product bug as an expected failure and leaves only a documented one red.
- **Stale numbers and paths:** healer budget 14 turns (not 5), 19 commands, 7 agents, 8 prod-guard
  rails, selfcheck 8 checks, hooktest 34 cases; `qa/` paths left over from the directory rename.
- **README:** new Uninstall and Troubleshooting sections, and a note on the two hooks and the
  permission rules init merges.

The stamped `CLAUDE.md` changed by one line (the video is kept by the verifier at step 8d).
`--resync` does not rewrite `CLAUDE.md`, so existing projects keep the old wording unless you
edit it by hand; nothing depends on it.

---

## 0.4.0 — renamed to QA Warden (2026-09-24)

**BREAKING:** the plugin id is now `qa-warden`, so every command moves from `/qa:<cmd>` to
`/qa-warden:<cmd>` and the install string from `qa@qa-toolkit` to `qa-warden@qa-warden`.
Nothing else changes: the `QA_*` env vars, the `specs/` and `tests/` layout, the spec format,
and the `bin/qa-*` scripts all stay as they were. The marketplace is renamed too, from `qa-toolkit`
to `qa-warden`, and the plugin directory moves from `qa/` to `qa-warden/`.

**Upgrading a project:**
1. `/plugin uninstall qa@qa-toolkit` and `/plugin marketplace remove qa-toolkit`, then
   `/plugin marketplace add its-magdy/qa-warden` and `/plugin install qa-warden@qa-warden --scope project`.
   The old `qa@qa-toolkit` entry in `.claude/settings.json` `enabledPlugins` is now stale; remove it.
2. `/qa-warden:init --resync`. Until you run it, `/qa-warden:doctor` reports substrate drift,
   because the resynced scripts mention the new command names.
3. Replace `/qa:` with `/qa-warden:` in your project `CLAUDE.md`. `--resync` never rewrites that
   file, and doctor warns while any `/qa:` remains.

- `scripts/doctor.sh` finds the installed plugin under either id and prefers `qa-warden`, so the
  substrate-drift baseline resolves during the transition.
- The assertion-contract hook already stripped the plugin namespace from `agent_type`;
  `bin/qa-hooktest` now covers `qa-warden:healer` and `qa-warden:verifier` explicitly.

## 0.3.0 — the feature release after the published 0.2.0 (repository-only)

### A documented defect stays red: no `test.fail` marker (found in the demo run, 2026-09-27)

- `agents/healer.md` step 0 and its `must_fail_when` bucket now forbid `test.fail` alongside
  `test.fixme`/`test.skip`. Before, they named only the last two, so in the demo run four of five
  heals of a defect the spec already listed took the product-bug bucket's conditional `test.fail`
  and turned the nightly red into an "expected failure". That bucket is for undocumented defects.
- `skills/heal/SKILL.md` step 6 says which marker applies: a documented defect stays red (any
  marker the healer added is reverted); only an undocumented product bug is parked.

### The assertion hook also guards the oracle module (found building the demo, 2026-09-27)

- `hooks/assertion-contract.sh` now covers `tests/<area>/<feature>.oracle.ts`, where the
  generator keeps expected totals and exact strings (F-33). Before, it checked only `*.spec.ts`,
  so a healer or verifier that retyped `EXPECTED_TOTAL` turned every importing test green without
  touching an `expect(...)` line, and nothing denied it. Any removed or rewritten code line in the
  module is now denied for those two agents; adding an export and editing comments stay allowed.
  `bin/qa-hooktest` has 10 new cases.

Thirteen working sessions closing the 2026-09-06 audit (all four blocks). Four structural
changes a consumer cannot infer from a file diff, three deliberate decisions to change
nothing, and a large body of correctness work.

### Permission and fork-wording fixes found by the 2026-09-26 doc review

- `templates/settings.json` no longer ships its 30 path-scoped `Write(...)` rules (8 allow, 22 deny).
  Claude Code checks file permissions against `Edit(...)` and `Read(...)` rules only, never consults
  a `Write(<path>)` rule, and warns about each one at startup. Every one had an `Edit(...)` twin in
  the same list, so no protection changes. The scaffold's merge never removes a rule, so existing
  projects keep them: `/qa-warden:doctor` Check 9c now raises one warning listing them. Delete
  them from `.claude/settings.json` by hand.
- `approve`, `intake` and `batch-fix` said a `context: fork` skill inherits the parent's history
  (or tools). It does not: it runs as a fresh subagent without the conversation history. The
  conclusion (a fork is no way to make an interactive skill work) is unchanged.
- The `axe-a11y`, `visual-regression` and `metamorphic-relations` descriptions are about half as
  long (~630 → ~340 chars each), cutting the always-loaded skill listing from ~1,228 to ~1,010
  tokens. All three are invoked by name (generator, `/qa-warden:review`, verifier preload), so the
  cut text (detection rates, Applitools note, mutation-testing contrast) stays in each body.

### Prompt audit (2026-09-26) — stale cross-references and contradictions

An audit of every agent, skill, reference doc, hook message and the stamped `CLAUDE.md` found no
older-model pressure language worth changing; the defects were statements the repository itself
contradicts, left behind when behaviour moved between agents. 33 fixes, prose only:

- Step 8a (twins) and 8b (fault injection) are credited to the verifier everywhere; `CLAUDE.md`,
  `planner.md` and `reviewer.md` still said the generator.
- `/qa-warden:retire` and reviewer Check 12 no longer store the search command in `$RG`. On a zsh
  Bash tool an unquoted `$RG` is not word-split (`command not found: rg -l`), each Bash call is a
  fresh shell, and a `$VAR`-led command matches no allow rule, so the consumer list came back
  empty — which `retire` reads as "unused". The tool is now typed literally on each line.
- `CLAUDE.md` no longer says the hooks skip the generator (only the assertion hook filters by
  agent), and names the `Edit(...)` allow rules instead of a `Write`/`Edit` allowlist.
- The reviewer's fail-closed list matches its whole-tree fallback; Check 2c's WARN list points at
  the two FAIL sub-cases instead of contradicting them; Check 6 no longer quotes a retired gate.
- `heal`/`report` describe the run-of-record gating of the `json` reporter; `run` drops command
  names that never existed; `ideate`/`new-spec` examples carry `basis=`; `doctor` Check 0b no
  longer calls a missing `rg` blocking for `retire` (it falls back to grep).
- Hook deny messages match their code: the assertion hook names retyped strings, and the lint
  hook gives `CLAUDE.md`'s locator priority.
- Smaller fixes in `healer`, `verifier`, `planner`, `exploration`, `playwright-cli`,
  `test-data-seed`, `visual-regression`, `knowledge-map`, `sentinel-actions`, `report-template`
  and the `basis.md` template. `CLAUDE.md` belongs to the project, so existing projects keep the
  old wording until they edit it; the `basis.md` template reaches them via `--resync`.
- `CLAUDE.md`'s locator priority no longer calls itself "Playwright's own recommendation".
  Playwright's docs only put role locators first and test ids last; label/placeholder before
  text for form fields is Testing Library's documented priority. The order is unchanged.

### First observed end-to-end run of 0.4.0 (run-01, 2026-09-26) — one dead script, two platform traps, twenty prose gaps

A lab drove the whole chain (`help` → `init` → `explore` → `intake` → `ideate` → `approve` →
`new-spec` → `gen` + verifier → `review` → four fast-lane specs → `run` → `report` → `coverage`
→ a change event + `heal`) against a booking app and logged 79 observations. Every finding
below was re-verified against the source before it was fixed; the moat held throughout (the
healer changed two locator lines and zero assertions, no oracle was weakened, the reviewer
caught every hollow pass). What broke was around the moat, not in it.

**Consumer-visible (reaches existing projects through `/qa-warden:init --resync`)**
- `scripts/doctor.sh` was a syntax error under stock macOS `/bin/bash` 3.2 (a `case … *.example)`
  inside `$( … )` at the lock-shard check): seven lines, exit 2, no rollup. Homebrew bash 5 hid it
  from every maintainer machine. One arm is now `(*.example)`, and `bin/qa-selfcheck` gains check 9k: every shell script
  must parse under `/bin/bash` when that binary is bash 3.x (skipped with a note elsewhere).
- `scripts/review-marker.sh` wrote `commit: HEAD` then `unknown` in a repository with no commit;
  `git rev-parse --verify -q` fixes the shape.
- `scripts/post-run-checks.sh` counted the verifier's `*-blind-*.md` / `*-unverified.md` records
  as open app defects. They are test-contract gaps and now print and count on their own line
  (`post-run: … open-bugs=N test-gaps=M`). `/qa-warden:report` and its template split the ledger
  the same way and count both Found-by shapes (bold inline, or a `## Found-by` heading), with
  `planner` / `exploration` values for bugs the main session files on their behalf.
- `settings.json` allows `QA_WORKERS=1|2|4|50% npx playwright test …` (one literal rule per
  value — a `*` before the program would not limit the rule) — the documented capacity knob
  matched no allow rule, so a subagent's run was denied. `.env.example` now says to quote values
  containing `#` (dotenv truncates `Member#2026` to `Member`; the shell loader does not) and that
  `QA_TZ` pins the browser only and should match the app's timezone.

**Platform traps (documented, worked around)**
- `/qa-warden:report` no longer runs as a forked subagent. Claude Code refuses any subagent
  `Write` whose basename matches `report*.md` / `summary*.md` / `findings*.md` / `analysis*.md` (any case)
  (anthropics/claude-code#44657, no opt-out), so `reports/summary.md` was never written while
  `reports/coverage-all.md` was. Inline, the Write succeeds; the returned block is unchanged.
- `hooks/assertion-contract.sh` denies the verifier removing *any* `expect` line, including a
  probe it inserted itself, through `Edit` and through a `Write` of the pre-probe file — so a
  probe that carried an `expect` could go in but not come out, and the only exit was a Bash
  rewrite the hook never sees. The hook is unchanged (stateless, fail-open); the verifier now keeps
  probes injection-only and reverts with one `Edit`, `hooks/README.md` documents the limit, and
  `qa-hooktest` pins both cases (24 cases, was 22). The verifier, generator and healer are told to
  touch `tests/**` only with `Edit`/`Write`: a `cat > tests/x.spec.ts <<EOF` needs no prompt
  (redirect targets are checked against the `Edit(tests/**)` allow) and no hook sees it.

**Authoring chain**
- `/qa-warden:approve` prints `basis=<area>/<feature>` on every fanned `new-spec` line and
  `new-spec` forwards it; the planner reads the parent checklist under that name. Before, a
  fanned spec's slug found no `.cases.md` and the planner silently took the fast lane past the
  approval gate it was meant to enforce.
- `generator.md` no longer lists `// verified:` among the annotations it is "required to emit"
  (it never authors one; step 8 already forbade it); the verifier's re-run skip accepts a carried
  stamp only when `git diff` shows the line unchanged, so a stamp new in the working tree gets a
  fresh probe.
- Generator: a named `PARTIAL — budget reached …` return when the turn budget is hit (the prose
  budget ended in no behaviour); one sweep per route, no driving of flows the planner marked
  untried; UI cleanup must anchor on an auto-waiting `expect` instead of a non-waiting
  `isVisible()` that silently skips itself; app-local time computed from the app's timezone, not
  the host's. `gen` re-invokes a truncated generator in the foreground rather than letting the
  main session compile tests unguarded.
- Intake asks the human when an observed example breaks a rule it is recording in the same basis
  (a Total that is not Net + VAT was stamped as an example and travelled two steps downstream).
- Planner and exploration: live probes are read-only; a probe that would create, submit, cancel
  or pay is proposed to the human first. `playwright-cli/SKILL.md` said the planner uses MCP;
  it uses the CLI first. Exploration writes `stable_testids: []` only after a sweep actually ran
  and has a DOM-sweep recipe when app source is off-limits.
- Healer: a locator heal whose old text also appears in the paired spec now writes the
  `.healer-needs-spec-update` sentinel, so a recompile cannot regress the heal or let a
  no-results scenario pass vacuously. `batch-fix` runs its precheck in the foreground.
- Reviewer (no new check): Check 3 FAILs a `test.fail`/`fixme`/`skip` under `page-objects/**`
  and WARNs a park narrower than the bug's Actual; Check 7 keys only on `draft: true` or a
  `> REVIEW:` line, not on the word "auto-drafted" in a comment.
- `coverage.sh` normalises `:id` / `{id}` / `[id]` before diffing planned against tested routes.
- `ideation` gains the `Edit` tool, so revising a checklist is an edit rather than a full
  rewrite or a Bash `sed -i` the deny list blocks.

### MIT license (2026-09-24)

- The plugin now ships a `LICENSE` file (MIT) at its root, matching `"license": "MIT"` in
  `plugin.json`. Installs copy only the plugin directory, so the repo-root copy alone never
  reached installed users.

### Prompt audit — dated instructions removed from the agent, skill and CLAUDE.md prompts (2026-09-24)

A `/claude-api prompt-audit` pass over every prompt surface (7 agents, 24 skills, the shipped
`CLAUDE.md`, the context templates, the hook deny messages) against the Claude 5 generation the
`model:` pins resolve to. No thinking scaffolds, cadences, word caps or retired-model workarounds
were found. What changed, all behaviour-neutral by intent except the first group:

- **Nine places where two prompts disagreed** now say one thing: the generator's Process step 7
  ran a mutating spec once while §Cross-RUN idempotency required twice; the reviewer's turn-budget
  line said "stop at 15" while §Inputs designs the whole-tree fallback to exceed it, and its output
  recap said "re-emit per check" while §Inputs says "in batches"; `CLAUDE.md` told the exploration
  subagent to STOP on `site= area=` that `/qa:explore` accepts as inferred area mode, and credited
  twin authoring to the generator inside the bullet that assigns it to the verifier; the planner's
  "three hard rules … restated under §Hard rules" restated only two; `run/SKILL.md` said smoke does
  not refresh `last-run.json` two screens after saying it does; `gen/SKILL.md` handed the generator
  a "one expect per item" rule its own Hard rules 3–4 contradict; the generator called
  `POST /api/test/reset` "harness-blocked" when only reviewer Check 13 catches it.
- **Model-invocable trigger text that pushed orphan asserts** (`axe-a11y`, `visual-regression`)
  now scopes to the oracle key / audit probes the assertion contract allows.
- **Migration-relative and history phrasing** ("now enforces", "no longer", "until this split",
  "the old generator", "before them", incident retellings, a 0.2.0→0.3.0 budget history in the
  always-loaded core) rewritten as rules that always held. Incident-ID tags on live rules stay.
- **Maintainer-only notes moved out of delivered prompt text** into frontmatter `#` comments
  (reviewer check-count freeze and doctor-port notes, planner Check 9bb notes, healer
  `HEALER_TURN_BUDGET` clamp arithmetic, generator sync note). Nothing was deleted.
- **Turn-budget lines are ceilings, not countdowns** ("at ~turn 25 stop", "if past 15") — the
  `**Turn budget: N` token selfcheck 9bc parses is unchanged.
- **Hook deny messages** no longer tell the blocked agent how to switch the hook layer off; the
  escape hatch stays documented in `hooks/README.md` for the operator.

### First end-to-end run of 0.3.0 — five run-only defects fixed (2026-09-21)

Found by driving explore → new-spec → gen → review → run headless against a live app. The
pipeline worked (it caught the app's planted bug and kept the oracle); these are the frictions
only a real run shows. Existing projects pick all of it up with `/qa:init --resync`.

- **New `scripts/cli-fill-env.sh <session> <ref> <ENV_VAR_NAME>`** — the sanctioned way to type a
  credential through `playwright-cli`. Every Bash call is a fresh shell, so a loaded `.env` never
  reached the next call; agents either typed the literal password into `fill` (it landed in the
  transcript, 2 of 3 runs) or skipped the login and left auth unverified. Takes the variable
  NAME, hides the value, refuses to put a secret in a non-password field. `--check <VAR>…`
  reports set/unset without reading values. `agents/exploration.md` and `CLAUDE.md`
  §Environment now require it.
- **`scripts/prod-guard.sh --probe`** replaces the inline reachability loop in `/qa:explore`, and
  the guard now prints `prod-guard: PASS|REFUSED` as its last line. Both were permission
  failures: a compound command needs a rule per subcommand, so the loop — and the
  `; echo exit=$?` agents kept appending — never matched the allow rule.
- **`/qa:run` parses `mode=` inside `run.sh`**; the skill is now one pre-approved call instead of
  an inline binding block that was not.
- **New `scripts/review-marker.sh <spec> <test> PASS|FAIL`** writes the `.reviewed` marker
  (byte-identical to the hand-rolled form) in one allow-listed call; a single review had spent
  4 denied calls improvising it.
- **Generator: tags are string literals, never computed.** A data-driven loop emitting
  `` `@${t}` `` is selected correctly by Playwright and invisible to every static check —
  `/qa:doctor` FAILed a reviewed-green project with "no test carries @smoke".
- **Bug files state the observation, not a guessed cause** (`CLAUDE.md` §Bug-report schema) — a
  bug was filed and named after a cause that the seed data could not distinguish from the real one.

### `/qa:run mode=changed` + a reviewer fix-shape rule (2026-09-21)

- **New `/qa:run mode=changed [<git-ref>]`** — runs only what a change touches, via Playwright's
  `--only-changed` (changed test files plus every test that imports a changed page object or
  fixture). Writes `reports/changed.json`; never touches `artifacts/last-run.json`, so it is not
  the run of record. Two things it guards because Playwright answers both with "0 tests, exit 0"
  and no error (measured): a repo with no commit yet, and a ref that does not resolve. It also
  lists edited `specs/**/*.md` — no test imports Markdown, so those are never selected and their
  tests stay stale until `/qa:gen`. "Nothing selected" is reported as nothing ran, not as a pass.
- **The reviewer's proposed spec fixes must be contract-valid.** Its own examples write
  `must_fail_when: "…"` inline as shorthand, and in one observed run it proposed exactly that
  scalar shape (plus a spec-level `negative: true`) in a diff a human would paste. It is now told
  the list form and that `negative:` is a `scenarios:`-entry key.

### Ceremony audit (2026-09-21) — two dead-end round-trips removed

- **`/qa:explore` given both `site=` and `area=` but no `mode=area` now runs** as `mode=area` and
  announces the inference, instead of STOPping to make you retype it. Both keys were typed, so nothing is guessed. With
  only ONE of the two keys it still STOPs — the rule that a mistyped area run must never fall
  through to `mode=hot` (and stamp `last_verified`) is unchanged.
- **`/qa:retire` can close an abandoned authoring chain.** Doctor Check 18 has always said "or
  `/qa:retire` the chain", but retire resolved `site:` from the spec's YAML — and an abandoned
  chain has no spec. It now takes `<site>` from the `.cases.md` path and deletes just the
  `.cases.md` + `.basis.md`.
- Doctor Check 20's comment no longer claims a subagent "cannot read CLAUDE.md" (it can, unless
  its frontmatter sets `omitClaudeMd`). Comment-only; the check is unchanged.

### Functional audit (2026-09-21) — every skill traced as if executed; two false-clean paths closed

- **`/qa:coverage` and `/qa:impact` no longer go false-clean on an old substrate.** Both call
  `scripts/spec-links.sh` and neither checked it exists: without it, coverage dims 1/5/6 and
  impact's `BLIND SPOTS` printed EMPTY — which reads as "no gaps" / "complete". Both scripts now
  refuse (exit 2) and name the fix (`/qa:init --resync`).
- **`/qa:doctor` no longer prints `0/3 … missing … ✅`.** The Playwright lockstep line ended in an
  unconditional ✅; fewer than three pin sites is now a ⚠️ and is tallied as a warning.
- **`metamorphic-relations` credited the wrong agent.** Its description said the *generator*
  authors the twins; the verifier owns steps 8a/8b (and the generator is barred from the skill).
- **Verifier's last-resort probe cleanup could hang.** It told a subagent to `mv` the probe file
  ("prompts once, acceptable") — a subagent's prompt has nobody to answer it. It now uses the
  allow-listed `scripts/retire-delete.sh`.
- **`/qa:doctor --verify-invariants`** said it "writes nothing" while its mechanism needs an
  in-spec probe; it now says what it means — the probe is reverted, the tree is left unchanged.
- **Scaffold `Next:` block** now leads with the fast lane (it called the optional rigor lane
  REQUIRED, contradicting both READMEs) and points at `/qa:help` instead of a
  `reference/glossary.md` that is never stamped into a project.
- **Argument handling:** `/qa:heal` stops on an empty id instead of triaging the whole results
  dir; `/qa:ideate` actually resolves the `site=` it advertises; `/qa:import-cases` takes
  `site=`, names its output path, and keeps the `# cases:` H1 (`/qa:coverage` silently dropped a
  file without it); `/qa:run` pre-approves its own script like `/qa:coverage`/`/qa:impact` do.
- **Snippets that broke if followed literally:** `axe-a11y`'s headline snippet skipped the
  settle floor the next paragraph mandates (a real contrast failure could scan clean);
  `test-data-seed`'s `mergeTests` recipe imported a `./pom.fixtures` module nothing creates.
- **Honesty:** the README's "fast lane skips no FAIL-level gate" now adds that Check 14 is
  SKIPPED (not downgraded) without a `.cases.md`; `/qa:review` says `--resync` deliberately does
  not deliver the optional CI workflow; `/qa:explore`'s unreachable message masks `user:pass@`.
- Glossary gains **substrate**, **waiver**, **situation step**; smaller citation fixes in
  `/qa:help`, `exploration.md`, `planner.md`, `knowledge-map.md`, `gitignore`.

### Behavioural evals (2026-09-21) — maintainer-only, not shipped to projects

- New `evals/` suite for `claude plugin eval`: five reviewer cases, each planting ONE known defect
  (no `expect`, orphan oracle item, asserted value ≠ oracle value, `waitForTimeout`, plus a
  correct control) in a real scaffolded project, graded by free regex over the reviewer's own
  `Check N (…): PASS|FAIL` lines. One case verified end-to-end; see `evals/README.md`.

### Outside-in audit (2026-09-20) — one false claim, two unguarded paths, one missing step

- **Fixed a false claim.** `CLAUDE.md` §"Escalation rules" said a flaky test is *auto-moved* to
  `@quarantine` over a rolling 14 days. Nothing records run history or moves a tag — only the
  `grepInvert` *exclusion* is enforced. Reworded: `/qa:run mode=repeat` measures, a human tags.
  `/qa:report`'s flake line now says it is this-run-only, not a trend.
- **`/qa:batch-fix` no longer inherits the lookalike guard from one file.** The healer's HEAL02
  check ran on the representative failure only, then the locator patch went to N files whose
  green proved only that *something* matched. The proposal now splits the N specs: those with a
  downstream side-effect oracle are batch-eligible, the rest are listed for individual `/qa:heal`.
- **Ideation gained a level-triage step (2b).** One UI case per partition; the other members are
  noted `API-LEVEL` (rejected-input siblings only — request-level scenarios via
  `network_response_status` / `response_body_contains`, which the planner reserves for the
  negative path) or `PUSH DOWN` (no browser- or response-visible observable). Advice
  to the approver — never drops a row.
- **Declared-but-unbuildable non-functional needs are now labelled.** Only `a11y` has an oracle
  key. `basis.md` says so at the point of declaration, and ideation ends `i18n` / `concurrency` /
  `performance` rows with `NOT BUILDABLE … waive (⊘ out-of-vocab) at /qa:approve`, so they stop
  becoming approved cases that reviewer Check 14 WARNs on forever.
- **New optional `.github/workflows/qa-review.yml.example`.** The local gate (`/qa:review`'s
  hash-pinned `.reviewed` marker + doctor Check 15) stays the default. The workflow is for teams
  that need an unforgeable gate, and it now states the prerequisite the old in-skill snippet
  omitted: the runner must install the plugin (`plugins:` + a **Git-URL** `plugin_marketplaces:`)
  or the `reviewer` subagent does not exist there. Deliberately NOT in `resync-set.txt` — an
  optional example must not raise a blocking substrate-drift ❌ on existing projects; a plain
  `/qa:init` stamps it.
- **Docs:** `qa-warden/README.md` leads with the four-command fast lane and gains a section on how the
  healer differs from Playwright's official one (whose instructions list "Fixing assertions and
  expected values"). The catalog no longer claims `visual-regression` triggers during spec
  authoring — no oracle key requests a screenshot, so only `/qa:review url=` reaches it.

### Added — the generator/verifier split

`/qa:gen` is now a **two-call chain**: the `generator` compiles a spec to a `.spec.ts`, and a
new `verifier` agent checks it independently. Agent count 6 → 7.

- The split is enforced by a **prohibition, not a file boundary**: the verifier may not edit
  any `expect(...)`, locator, or asserted value. A mis-compile goes back to the generator with
  a `<file>:<line>`; a decorative oracle goes back to the planner. Without that rule the
  self-grading would just move one agent over.
- **Exactly one agent may declare `Write(artifacts/route-manifests/**)`, and it must be the
  verifier.** The route manifest is the ship signal and is gated on verification passing — if
  the generator reclaims the write, the gate detaches from the thing it gates.
- The generator keeps its name and its step numbers (`8a`–`8d`): those are shared vocabulary
  across reviewer Checks 2b/6, doctor 13/15b, the basis template and `DESIGN.md`.
- Enforced by new doctor **Check 9g**.

### Added — the `hooks/` enforcement layer

Two `PreToolUse` hooks now ship at the plugin root (auto-discovered; no `plugin.json` key).
This **reverses** a "no PreToolUse hooks" stance that had been stated as deliberate in ten
places — and the reversal is narrower than it sounds.

- `assertion-contract.sh` denies the healer or the verifier an edit that **removes or rewrites**
  an assertion. It is a **subset test, never equality**: adding assertions passes, and only the
  weakening direction is blocked. It compares matcher + asserted literal, masking the
  `expect(...)` *argument* (re-pointing a locator is the healer's actual job) and stripping
  options objects (`{ timeout: N }` is a sanctioned widen).
- `spec-lint.sh` covers the lexical bans that are decidable from the proposed text alone.
- **The bar for inclusion was "decidable from the proposed text alone."** Three reviewer checks
  deliberately did *not* clear it and remain the reviewer's job by discipline: Check 11's
  credential regex (documented as false-FAILing valid specs), Check 11's inline-URL gate (it
  false-FAILs a legitimate `toHaveAttribute('href', 'https://…')` oracle), and Check 3 (decidable
  at rest but order-dependent at write time). **The hooks are a floor, not a gate.**
- Plugin hooks fire in **every repository their owner opens**, so the layer is scoped by a
  two-file project marker (`playwright.config.ts` **and** `scripts/prod-guard.ts` — the config
  alone would lint every Playwright repo you own).
- Escape hatch: **`QA_HOOKS_OFF=1`**. It must be set in Claude Code's own environment — a hook
  never sources the project `.env`, which is why it is deliberately absent from `.env.example`.
- **Fail-open is proven, not asserted**: no `jq`, garbage stdin, empty stdin, missing
  `hook-lib.sh`, unbalanced parens in a source line — all exit 0.
- Enforced by new doctor **Check 9h**. Note its first arm exists because a dangling or
  non-executable hook command does **not** block: the harness logs an error and the write
  proceeds, so a broken gate reads as shipped while enforcing nothing.

### Added — `fault:` and `clock:` situation steps

Network interception (`page.route`) and `page.clock` are now available to the planner and
generator, unlocking Interfaces and Time cases that `/qa:ideate` had been enumerating and the
planner had been dropping for want of the APIs.

- **These are not oracle keys.** The oracle vocabulary stays at **16**. A stub sets up a
  *situation*; the oracle asserts the app's *degradation*, and existing keys already cover it.
- **Pair every `fault:` with `network_response_status: { url, status }`.** A `fault:` whose glob
  matches nothing is otherwise **silent** — the real server answers, the app behaves normally,
  and every oracle passes for the wrong reason. Asserting the injected status makes a missed
  stub go **red**, because the real response carries a different one.
- `advance:` vs `advance_idle:` is load-bearing: `runFor` fires **every** timer, `fastForward`
  fires each due timer **at most once**. `clock.install()` must precede navigation.
- **`routeFromHAR` replay is refused, not missing.** A suite served from a frozen backend stays
  green through every server-side regression, which inverts the economic thesis of the toolkit.
  It is now a lexical ban in `spec-lint.sh`. `recordHar` is also not shipped — a recorded HAR
  carries `Authorization`/`Cookie` request headers.
- `assertion-contract.sh` gains a **healer-only** arm denying an edit that *introduces* a
  `page.route`/`page.clock`: both make a red test green without touching a single assertion, so
  the subset test is blind to them. Scoped to the healer alone on purpose — the verifier's
  step-8b injection *is* a `page.route`.
- Known limit, recorded rather than filled: there is still **no request-side oracle** (you
  cannot assert the request the client sent).
- Enforced by new doctor **Check 9i**.

### Added — `test lock:` and Playwright 1.63.0

- `lock:` is adopted as a `TestDetails` field. **The generator owns both sides of it; the planner
  authors nothing**, because `lock:` is a `TestDetails` field rather than spec YAML.
- **`lock:` has no runtime observable at all**, so unlike `fault:` it has no oracle-key proof.
  The only thing that makes a lock mean anything is the second occurrence of its own symbol, so
  the proof is a **pairing** proof and it lives in doctor, not the vocabulary. New **Check 9l**,
  counted per **site, not per file** (two same-lock tests in one file genuinely do exclude each
  other under `fullyParallel`, so a file-granular count would fail a pairing that holds).
- Three properties were reproduced on a real 1.63.0 fixture rather than trusted: a lock-sharing
  pair **split across shards** runs concurrently; a locked test inside a hooked `describe.parallel`
  **stalls its unlocked neighbour**; a **singleton lock overlaps everything**.
- Playwright pinned **1.61.1 → 1.63.0** for anyone upgrading from 0.2.0 (the repo passed through
  1.62.1 in between, which was never published either). All four lockstep sites move together —
  `@playwright/test`, `overrides.playwright`, `overrides.playwright-core`, and the version-pinned
  `npx` argument in `.mcp.explore.json` — enforced by doctor **Check 8b**.
- Doctor Check 13's isolation-marker grep no longer WARNs on a spec isolated only by a lock.

### Decided — three evaluations that deliberately changed nothing

These are **verdicts, not omissions**. Each was worked as a full item and closed on the evidence.

- **Split `exploration` into hot/area agents → KEEP ONE AGENT.** A split needs a prohibition to
  carry it (the verifier's `expect()` ban is what makes the generator split work); the
  provisioning lens came back empty for the first time; and the split would not have fixed the
  footgun anyway, since every live bad instance is an under-specified *area* invocation. **What
  shipped instead**: the silent `mode=hot` default was fixed, five live bad `/qa:explore`
  invocations in the toolkit's own text were corrected, and doctor **Check 9j** was added.
- **Merge `/qa:coverage` into `/qa:impact` → KEEP TWO COMMANDS.** They have different argument
  shapes, different per-script `allowed-tools` that a merge would widen, and one is a read-only
  query that would inherit a writing contract. The shared logic was **extracted** instead
  (following the `spec-links.sh` precedent). New doctor **Check 9k**.
- **Playwright 1.63.0 → initially STAY, then reversed.** Session 10 read 1.63.0's own `.d.ts` and
  shipped runner bundle and refuted two of three claimed features, so the bump was declined. It
  was reversed once `test lock:` turned out to be the thing the bump actually enabled. Session
  10's real output was doctor **Check 8b** widened to all four lockstep sites, which is what made
  the eventual bump safe.

### Changed — correctness and safety

- **Healer could not execute its own process** — turn budget was below its own documented floor.
- **`/qa:new-spec` silently destroyed an existing spec.** Fixed.
- Generator read `mutates_server_state` from the wrong file.
- Reviewer FAILed on a form the planner never emits.
- `invariant_holds_when:` had two incompatible shapes.
- A silent **third permission tier**: eight `resync-set` members sat inside a `Write(specs/**)` /
  `Write(fixtures/**)` allow glob, so an agent could clobber `_templates/basis.md` with **no
  prompt at all**, corrupting every later `/qa:intake`.
- `approve`'s `⊘` waived rows matched neither reviewer waiver form, so a correctly-waived case
  warned forever.
- **All 7 agents now pin `model:` in frontmatter** (`opus` for planner/ideation/reviewer/
  verifier, `sonnet` for exploration/generator/healer). This reverses an earlier no-pin
  decision. Cost impact is authoring-time only — the nightly Playwright replay is unchanged.
- `report/SKILL.md` brought back under the size ceiling (21,725 → 17,695 bytes); **no skill now
  exceeds it.**
- Prod-guard `.ts` ↔ `.sh` parity audited differentially (55 cases, 54 identical verdicts; the
  one divergence is diagnostic-only and both layers still refuse).

### Removed — `DOCUMENTATION.html`

The hand-authored visual one-pager is deleted. It had no generator, sat a full release cycle out
of date (no mention of the verifier split, `lock:`/`fault:`/`clock:` or Playwright 1.63.0), and
two of the three pointers to it were already false — the repo README called it "a browser-viewable
copy of the reference" when it was a different, smaller document, and `qa-warden/README.md` shipped
*inside the plugin* pointing at a repo-root file consumers never receive. `DOCUMENTATION.md` is
now stated to be canonical.

### Changed — plugin layout

All `/qa:*` entry points now live at `skills/<name>/SKILL.md`. The old `commands/` directory is
gone (0.2.0 shipped 21 commands + 6 skills; this build ships 23 skills and no `commands/`). A
`commands/x.md` and a `skills/x/SKILL.md` both define `/qa:x`, so the two layouts coexisting is
invisible until behaviour diverges — doctor **Check 9d** now fails on a reappearance.

### Changed — `/qa:init --resync` now delivers permissions and its own ignore rule

Two upgrade-path holes, both measured on a scratch project stamped from the published 0.2.0
build. Neither was visible from the command's own output: it exited **0** in both cases.

- **Permissions travel with the substrate.** The `.claude/settings.json` merge ran only on the
  plain stamp, so a resync-only upgrade delivered **0 of 37** new rules. It is now one
  `stamp_permissions()` function called by both paths — single-sourced, because a copy of the
  `jq` in a second place is just the same gap again. See *Upgrading from 0.2.0* below.
- **`--resync` appends `*.qa-bak` to `.gitignore` before writing any backup.** That ignore rule
  shipped after 0.2.0 and `.gitignore` is outside the resync set, so the command was generating
  13 unignorable untracked files per upgrade.

**No full permission subset check was added, and that is a decision.** Doctor **Check 9f** stays
scoped to `mcp__` grants. A plain subset check was built and run against three scratch projects:
it reported 37 missing on a resync-only upgrade (right), 0 on a current project (right), and 2
on a current project whose owner had deliberately deleted two deny rules (wrong) — and gating
the required set on the shipped template, the shape that closed the `CLAUDE.md` gap, does not
separate those last two, because both rules are still shipped. The deciding fact is narrower:
`scripts/doctor.sh` is itself a resynced file, so any check added to it reaches a project only
through the same command that now performs the repair, and never before it. It could not
observe the state it would be written for.

### Changed — doctor

**27 → 36 checks** for anyone coming from 0.2.0. It reached 43, then seven moved out (next
paragraph); the additions below are sub-checks inside existing numbers.

**Seven checks left doctor for a new `bin/qa-selfcheck`** — 9b, 9bc, 9be, 9d, 9e, 9h, 9j. They read
only the plugin's own source, so a consumer could never fix one, and under version skew (a
project resynced by a teammate on a newer plugin) they printed a wall of ❌ that all meant
"update your plugin": measured against the published 0.2.0, doctor's findings drop 33 → 15.
Moved **verbatim** and proven equivalent — byte-identical doctor output on a healthy project, and
every one of the 33 findings reproduced by doctor + selfcheck together. Ids are retired, not
reused. The six checks that also read the project (9bb, 9bd, 9g, 9i, 9k, 20) stayed. The
equivalence test itself found a hole: Check 9h never noticed a hook script that exists but is
**unregistered** in `hooks.json`; it now does.

**New `bin/qa-hooktest`** — the two `PreToolUse` hooks are the only code here that can block a
write, and they had no tests. 20 real payloads now pin what each denies and allows, including
the two documented gaps (a call split across lines; `toBeTruthy()` on a literal) asserted as
`allow`, so closing one is a visible change. Mutation-checked: breaking one regex turns exactly
one case red.

Check 9f gained an **arm 3** for the one permission-delivery failure the scaffold fix
cannot close: the merge needs `jq`, and without it qa-scaffold parks the rules in
`.claude/settings.qa-suggested.json` and moves on. That file's presence is proof the merge
never ran — an intent-free signal, unlike a subset check — and doctor now names it, counts
the rules that never landed, and says what they cost. A successful merge deletes the file,
so the signal cannot go stale; if you hand-merged it and left it behind, doctor says so
separately. The presence test sits outside the `jq` gate, since the state it detects *is*
`jq` being absent.

Check 9 also gained a **CLAUDE.md vocabulary containment** sub-check, which closes the widest
hole in the upgrade path itself. `CLAUDE.md` is shared-ownership, so `--resync` skips it *and*
Check 9's byte-compare skips it — both right in isolation, but together they meant the one file
every new authoring feature is documented in was the one file an upgrade could not deliver, and
nothing said so. It now WARNs per missing toolkit-owned symbol (manifest:
`scripts/claude-md-vocab.txt`), naming the reason and the template to diff against. Symbols, not
sections, on measurement: across the 0.2.0 → this-release upgrade the `## ` heading set is
identical (19 = 19) while the 93 new lines land inside ten pre-existing sections, so a
section-level diff would have reported green on precisely this release.

---

## Upgrading from 0.2.0

Verified end-to-end on a scratch project stamped from the published 0.2.0 build, on
2026-09-20. The numbers below are measured, not estimated.

```sh
# 1. Update the plugin, then restart Claude Code.
# 2. Refresh the toolkit-owned substrate (20 of 30 files change; each is backed up to .qa-bak).
#    This now delivers the permission rules too — one call, not two:
/qa:init --resync
# 3. Chromium 1228 -> 1243 (Chrome 149 -> 153). --resync runs `npm install` but NOT this:
bash scripts/init.sh        # or: npx playwright install chromium
# 4. Check what is left:
/qa:doctor
```

### The permission step is no longer separate

Through 0.2.0, `--resync` refreshed files but did **not** run the `.claude/settings.json`
permission merge, so a 0.2.0 project that only resynced was left missing **37 rules** — 2 MCP
grants, 9 `Bash` allows and 26 `Write`/`Edit` denies — after a green, exit-0 upgrade. The
verified recipe needed a second, plain `/qa:init` that nothing in the resync banner mentioned.

`--resync` now runs the same merge, from the same single-sourced function as the plain stamp.
Measured on a scratch 0.2.0 project: 37 missing rules before, **0** after, and the resulting
`settings.json` is **byte-identical to what the old two-call recipe produced** — including on a
project whose owner had deleted rules by hand, because the merge was always an additive union
that re-adds them. So this changes how many commands you type, not what you end up with.

Re-running is a measured no-op: the merge is byte-stable, keeps your own rules, and preserves
sibling keys (`permissions.ask`, `defaultMode`, `model`, `env`).

### Four permission rules must be deleted BY HAND

The settings merge is an additive union — it can add a rule but can never remove one. Doctor
**Check 9c** names them; delete each from `.claude/settings.json`:

| Retired rule | Why it must go |
|---|---|
| `Bash(sed *e)` | Over-blocks ordinary `sed`; a deny cannot be interactively approved |
| `Bash(sed *e *)` | Same |
| `Bash(sed *e;*)` | Same |
| `Bash(printenv)` | **Security.** Auto-approves a bare `printenv` — a dump of every `.env` secret loaded in that shell (`QA_ADMIN_PASSWORD`, `QA_TOTP_SECRET`, `QA_CLIENT_CERT_PASSPHRASE`) straight into the transcript. Nothing ever consumed it; the mandated form is the scoped `printenv $base_url_env`, still covered by `Bash(printenv *)`. |

The replacements for the `sed` rules are `Bash(sed *e'*)` and `Bash(sed *e"*)`.

### Three files `--resync` will not overwrite — merge them by hand

These are shared-ownership by design (you edit them), so the resync never copies over them.
Measured drift from the 0.2.0 templates:

| File | Drift | What you lose by skipping it |
|---|---|---|
| `CLAUDE.md` | **122 lines, +13.5 KB** | **All four structural features of this release.** After a clean, green `--resync` the project's `CLAUDE.md` contains **zero** mentions of `lock:`, `fault:`, `clock:` or `verifier`. The in-project agents read this file, not the plugin. **Doctor now names this gap** — see below. |
| `.gitignore` | 9 lines | Assorted ignore rules. The one that mattered, `*.qa-bak`, is now delivered by `--resync` itself — see below. |
| `.env.example` | 8 lines | New optional seed/config vars. |

Diff each against `<plugin>/templates/` and port what you want.

`CLAUDE.md` is the one that costs you a feature rather than a convenience, so it is no longer
silent. Doctor's **CLAUDE.md vocabulary containment** sub-check (Check 9, new in this release)
greps your stamped `CLAUDE.md` for the toolkit-owned symbols in
`scripts/claude-md-vocab.txt` and WARNs per missing symbol with the reason and the template path
to diff against. On a freshly-resynced 0.2.0 project it emits exactly four warnings — `fault:`,
`clock:`, `lock:`, `verifier` — and they clear as you port the prose across.

It **warns rather than fails**: the repair is a hand-merge, not a command, and a repair the
toolkit cannot perform for you should not red your CI. It matches on symbol *presence* anywhere
in the file, so rewording and your own additions are free — only a deletion is reported.

### `--resync` no longer litters files your old `.gitignore` cannot cover

The `*.qa-bak` ignore rule shipped **after** 0.2.0, and `.gitignore` is one of the files
`--resync` will not overwrite — so the command generated its own commit-bait. Measured on the
scratch project: **13 `.qa-bak` files written, 0 of them ignored**, all offered up by the next
`git add -A`.

`--resync` now appends `*.qa-bak` to `.gitignore` before it writes any backup, so the same run
that creates them covers them (13 untracked → **0**). It appends only that one pattern — litter
this command itself creates, and a filename only this script produces, so there is no ignore
*policy* being pushed onto your project. It checks `git check-ignore` first, so a rule you
already have (including a global or `.git/info/exclude` one) is left alone, and re-running does
not append twice.

The done banner now also counts the backups and prints the sweep command.

### What a clean upgrade looks like

On the scratch project, after steps 1–3, `/qa:doctor` exits **0** with only the four
hand-delete warnings above, the four `CLAUDE.md` vocabulary warnings until you merge that file,
plus two environment notes (`ripgrep` not installed, no `artifacts/last-run.json` yet).
`playwright lockstep: 3/3 … at 1.63.0 ✅`, no substrate drift, no missing permission rules and
no unignored `.qa-bak` files.
