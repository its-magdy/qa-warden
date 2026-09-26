# Changelog

All notable consumer-facing changes to QA Warden (plugin id `qa-warden`; `qa` before 0.4.0).

The **last published build was `0.2.0` (2026-07-24)**. The `[Unreleased]` section below landed in
the repository since then as **`0.3.0`**: a feature release on the published `0.1.0 → 0.2.0`
line, with no breaking change to the spec format or the `/qa:*` surface. **`0.4.0`** adds only
the rename on top of it, and that one IS breaking (see its section).
`.claude-plugin/plugin.json` reads `0.4.0`; tag the build with `claude plugin tag ./qa`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/). Versions are the
number in `plugin.json`, which is also the key the installer caches under
(`~/.claude/plugins/cache/<marketplace>/qa/<version>/`) — so **two different builds must
never carry the same number**, or the second one has no way to announce itself.

---

## 0.4.0 — renamed to QA Warden (2026-09-24)

**BREAKING:** the plugin id is now `qa-warden`, so every command moves from `/qa:<cmd>` to
`/qa-warden:<cmd>` and the install string from `qa@qa-toolkit` to `qa-warden@qa-toolkit`.
Nothing else changes: the `QA_*` env vars, the `specs/` and `tests/` layout, the spec format,
the `bin/qa-*` scripts and the `qa-toolkit` marketplace name all stay as they were.

**Upgrading a project:**
1. `/plugin uninstall qa@qa-toolkit`, then `/plugin install qa-warden@qa-toolkit --scope project`.
   The old `qa@qa-toolkit` entry in `.claude/settings.json` `enabledPlugins` is now stale; remove it.
2. `/qa-warden:init --resync`. Until you run it, `/qa-warden:doctor` reports substrate drift,
   because the resynced scripts mention the new command names.
3. Replace `/qa:` with `/qa-warden:` in your project `CLAUDE.md`. `--resync` never rewrites that
   file, and doctor warns while any `/qa:` remains.

- `scripts/doctor.sh` finds the installed plugin under either id and prefers `qa-warden`, so the
  substrate-drift baseline resolves during the transition.
- The assertion-contract hook already stripped the plugin namespace from `agent_type`;
  `bin/qa-hooktest` now covers `qa-warden:healer` and `qa-warden:verifier` explicitly.

## [Unreleased]

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
- **Docs:** `qa/README.md` leads with the four-command fast lane and gains a section on how the
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
copy of the reference" when it was a different, smaller document, and `qa/README.md` shipped
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
