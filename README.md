<p align="center"><img src="docs/assets/qa-warden-icon.svg" width="112" alt="QA Warden logo: a cream check overlapped by a larger green check, forming a W"></p>

# QA Warden

> AI writes your Playwright E2E tests from plain-language specs. No AI can quietly loosen them afterwards.

**Who it's for:** anyone who wants AI to write the end-to-end browser tests for their web app, without having to trust the AI not to cheat.

**The problem.** When an AI-written test fails, the quickest "fix" for an AI is to weaken the check: change the expected value or delete the assertion. The test turns green and the bug ships.

**What QA Warden does.** It is a [Claude Code](https://code.claude.com/docs/en/overview) plugin. You describe a feature in plain language, and it writes a [Playwright](https://playwright.dev) test for it. Three guards then keep that test honest:

- A **verifier** breaks the app on purpose, in the ways the spec says must fail, and checks that the test goes red.
- A read-only **reviewer** blocks the PR when the spec and the test disagree.
- The **healer** repairs selectors and waits, never the assertion. A red test stays red until a human decides whether the app or the spec is wrong.

You review a short Markdown spec, not TypeScript. Its "what counts as correct" part (the **oracle**) uses a fixed list of 16 YAML keys that a non-coder can read, and each key becomes one `expect()` check. Nightly runs are plain `npx playwright test`, so they cost about $0 in AI calls. AI comes back only to triage a failure.

It is a test-authoring plugin, not a security or secrets tool. This repo is both the plugin and its marketplace, and both are named `qa-warden`.

**Status:** early and pre-1.0, with one maintainer. Its full end-to-end runs so far were on small apps. Read [Known issues](#known-issues) before you rely on it.

> **AI agents:** if a user gave you this repo's URL, read [For AI agents](#for-ai-agents-installing-for-a-user) first.

[![Release](https://img.shields.io/github/v/release/its-magdy/qa-warden)](https://github.com/its-magdy/qa-warden/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Commands reference](#commands-reference)
- [How it differs from Playwright's test agents](#how-it-differs-from-playwrights-test-agents)
- [Troubleshooting](#troubleshooting)
- [Known issues](#known-issues)
- [Scope and limits](#scope-and-limits)
- [Documentation](#documentation)
- [Getting help](#getting-help)
- [For maintainers](#for-maintainers)
- [License](#license)

---

## Prerequisites

- **Claude Code** with [plugin support](https://code.claude.com/docs/en/discover-plugins) (`/plugin` commands). Not claude.ai or Cowork: they don't install a plugin that has a top-level `bin/` directory, and this one does.
- **A Claude account that can use Claude Code**: a paid plan or API billing. Writing, reviewing and triaging tests makes model calls on that account; running the tests does not.
- **macOS, Linux or WSL.** The plugin's two hooks (checks that Claude Code runs before each file edit) are shell scripts; native Windows can't run them.
- **Node.js `>=22`** and `npm`, for the Playwright project that `/qa-warden:init` creates
- **`git`**
- **`jq`**: required. Without it, `/qa-warden:doctor` reports a ❌ and `.claude/settings.json` can't be auto-merged.
- **`ripgrep` (`rg`)**: recommended. Without it, `/qa-warden:retire` consumer checks fall back to `grep`.
- A **staging or local** instance of the app under test, plus a test account that already exists in it. Never production. There is no bundled demo app yet, so you bring the app.

---

## Installation

### Install the plugin

Use a dedicated folder or repo for the tests, not your app's own repo. `/qa-warden:init` skips files that already exist, so an existing `package.json` would not get the pinned Playwright dependency. The permission rules it adds also apply to every Claude Code session in that folder (see [What the plugin changes in your session](#what-the-plugin-changes-in-your-session)).

Run these inside Claude Code, from that folder:

```bash
# 1. Register the marketplace (this GitHub repo)
/plugin marketplace add its-magdy/qa-warden

# 2. Install at project scope (records the plugin under enabledPlugins in .claude/settings.json)
/plugin install qa-warden@qa-warden --scope project

# 3. Stamp the runtime substrate into this project and install dependencies
/qa-warden:init
```

To stay on one release, pin the marketplace to its tag with `#<tag>` (tags are `qa-warden--v<version>`):

```bash
/plugin marketplace add its-magdy/qa-warden#qa-warden--v0.6.1
```

Updates are manual by default (see [Versioning and releasing](#versioning-and-releasing)). To get them automatically, run `/plugin`, open the **Marketplaces** tab, select `qa-warden` and choose **Enable auto-update**.

### For AI agents: installing for a user

If a user pasted this repo's URL and asked you to set it up or walk them through it:

1. **Check the machine.** QA Warden runs only inside Claude Code, on macOS, Linux or WSL. You can do the install steps below from any agent with a shell, as long as the `claude` CLI is installed (`claude --version`). If it is not, point the user to the [Claude Code install guide](https://code.claude.com/docs/en/overview) first. After the install, the user works in Claude Code.
2. **Check the [prerequisites](#prerequisites)** from a shell: `node --version` (needs 22 or newer), `git --version`, `jq --version`, and optionally `rg --version`. Help the user install anything missing.
3. **Install the plugin from a shell, in a dedicated folder for the tests.** Ask the user where it should live; do not use their app's repo. These are the shell forms of the two `/plugin` commands above, and they need no interactive input:

   ```bash
   claude plugin marketplace add its-magdy/qa-warden
   claude plugin install qa-warden@qa-warden --scope project
   ```

4. **Hand the next step to the user.** `/qa-warden:init` is a slash command that only a person can start; Claude never runs it on its own. The user starts Claude Code in that folder (or runs `/reload-plugins` in an open session), trusts the folder if asked, and types `/qa-warden:init`. Do not start it for them with `claude -p` or by calling the plugin's scripts.
5. **Ask the user for the target app.** That means a staging or local URL, plus a test account if the app has a login. It goes in `.env` as described in [Configuration](#configuration). Never point `BASE_URL_APP` at production, never set `QA_ALLOW_PROD=1` on your own, and never write a password anywhere except `.env`. Have the user type the password into `.env` themselves; do not ask for it in chat.
6. **Walk them through a first test.** Use [Fast lane: your first test](#fast-lane-your-first-test) against the user's own staging or local app. Tell them first what it costs (about 40 minutes and $6 for one small test) and that it raises many permission prompts. There is no bundled demo app: if the user has no app to test, say so and stop there. Never pick a public site for them, because the suite changes data in the app it tests.

### What `/qa-warden:init` does

- Copies every file in the plugin's `templates/` into the project, skipping any file that already exists:
  - `package.json` (with `@playwright/test` pinned to `1.63.0`), `playwright.config.ts`, `tsconfig.json`
  - `CLAUDE.md`, `.mcp.json`, `.mcp.explore.json`, `.gitignore`, `.env.example`
  - `scripts/`, `fixtures/`, `page-objects/`, `specs/_context/_templates/`
  - one CI example, `.github/workflows/qa-nightly.yml.example`
- Creates `.env` from `.env.example`.
- Merges its permission rules and a `qa-warden` entry under `extraKnownMarketplaces` into `.claude/settings.json`.
- Runs `git init` if the folder is not a git repository yet.
- Runs `npm install`, then `npx playwright install --with-deps chromium`. The browser is a sizeable one-time download into Playwright's own cache, outside the project. On Linux, `--with-deps` also installs the system libraries the browser needs and may ask for `sudo`.

| Flag | Effect |
|---|---|
| `--no-install` | Stamp files only; skip `npm install` / `npx playwright install` |
| `--resync` | Force-refresh toolkit-owned files in an existing project. Changed files are backed up to `<file>.qa-bak`. `.env` and customized files are left alone. |

### What the plugin changes in your session

- **Two `PreToolUse` hooks run on every `Edit` and `Write`:**
  - `assertion-contract.sh` stops the healer and the verifier from removing or rewriting an assertion in `tests/**/*.spec.ts` or an expected value in `tests/**/*.oracle.ts`.
  - `spec-lint.sh` blocks lexical reviewer FAILs (such as `waitForTimeout`, raw CSS/XPath or `.only`) in writes to `tests/**/*.ts` and `page-objects/**/*.ts`.
  - Details: [`qa-warden/hooks/README.md`](qa-warden/hooks/README.md).
- **Permission rules are merged into `.claude/settings.json`, not overwritten.** Your own rules and other keys stay. Where your file already sets a key the template also sets (such as your own `extraKnownMarketplaces` entries), your value wins. Without `jq`, init writes the rules to `.claude/settings.qa-suggested.json` for you to merge by hand.
- **The merged rules apply to every Claude Code session in this folder.** They pre-approve the test and lookup commands the agents use, and edits inside the test folders only. They also deny some things outright, such as `rm`, `sed -i`, `git reset --hard`, reading `.env`, and edits to `package.json` and `playwright.config.ts`. The full list is in [`qa-warden/templates/settings.json`](qa-warden/templates/settings.json).

### Teammates

Commit `.claude/settings.json`. It holds `enabledPlugins` (from the install) and the marketplace entry (from `/qa-warden:init`). A teammate who clones the repo and trusts the folder gets the plugin from that marketplace. Claude Code applies `extraKnownMarketplaces` only after the folder is trusted. A teammate who doesn't get it runs the two `/plugin` commands above.

### Uninstall

```bash
/plugin uninstall qa-warden@qa-warden --scope project
/plugin marketplace remove qa-warden   # optional: also drop the marketplace
```

- Removes the plugin, its commands and its hooks, and drops its `enabledPlugins` entry from `.claude/settings.json`.
- The hooks stay active in the current session until you run `/reload-plugins` or restart Claude Code.
- Everything `/qa-warden:init` stamped stays: the files listed above, `.env`, the merged permission rules and the `extraKnownMarketplaces` entry. Remove them by hand if you no longer want them.

---

## Configuration

Open the `.env` that `/qa-warden:init` created. Set the target app and, if the app has a login, the test account:

```bash
BASE_URL_APP=http://localhost:3000     # staging or localhost, never prod
QA_USER_EMAIL=member@example.test      # an account that already exists (leave blank if the app has no login)
QA_USER_PASSWORD=your-test-password
QA_ADMIN_EMAIL=                        # optional: admin-role tests
QA_ADMIN_PASSWORD=
```

- `BASE_URL_APP` ships as `CHANGEME`. The prod-guard **fails closed** until you replace it.
- Specs never contain passwords. They reference the variable name (`password_env: "QA_USER_PASSWORD"`).
- Each additional site under test gets its own `BASE_URL_<SITE>` variable. Setting it adds the site's Playwright project; you never edit `playwright.config.ts`.
- A site with no login is recorded as `auth_mode: none` in `specs/_context/app.context.md`. Its tests run unauthenticated and `QA_USER_*` stays empty. When `/qa-warden:explore` sees no login and no `QA_USER_*` credentials, it drafts `auth_mode: none` with a `# REVIEW:` line for you to confirm.

Check the setup. Doctor is read-only and offline; it never contacts `BASE_URL_APP`:

```bash
/qa-warden:doctor
```

A healthy project prints a summary with no ❌ blockers and the verdict "Setup looks healthy". While `BASE_URL_APP` is empty or a placeholder, doctor prints a ⚠️ and the verdict reads "Setup is NOT ready yet — fill in .env".

---

## Usage

### Fast lane: your first test

Set `BASE_URL_APP` in `.env` to your own staging or local app first (see [Configuration](#configuration)). There is no bundled demo app yet, so you bring the app.

```bash
/qa-warden:explore                   # learn the app → specs/_context/app.context.md
/qa-warden:new-spec auth/login       # draft specs/auth/login.md (plain language + YAML oracle)
/qa-warden:gen specs/auth/login.md   # compile → tests/auth/login.spec.ts, run it green, verify it can fail
/qa-warden:review                    # reviewer gates the assertion contract; any FAIL blocks the PR
/qa-warden:run mode=smoke            # run the @smoke suite (no LLM)
```

The spec is the only file you review. Here is the oracle `/qa-warden:new-spec` produces:

```yaml
oracle:
  url_matches: "/tasks"      # we land on the task list
  text_visible: "My tasks"   # and the page actually rendered
```

`/qa-warden:gen` also keeps a `.webm` video of the run. It shows the real flow the test drove, so you don't need to read the TypeScript. The step-by-step version, with what you should see at each step, is in the [first-test tutorial](qa-warden/reference/tutorial-first-test.md).

**Cost.** The authoring pass (`explore` through `review`) makes real model calls; `/qa-warden:run` has no LLM cost. As a guide, one measured run of these five steps for a single small test (2026-09-30) took about 40 minutes and about $6. Half of that was `gen`, whose verifier breaks the app on purpose to prove the test can fail. Your app and spec will differ.

**Expect many permission prompts.** In Claude Code's default permission mode, a first run asks you to allow a lot of shell commands one at a time; a full run once raised about 300. Most are the agents' own test and lookup commands; read each one and answer "Yes" when it is. To get fewer, press Shift+Tab to switch to a more permissive mode for the long `gen` and `review` steps. Details are in [Known issues](#known-issues).

#### Confirm the app context

The first `/qa-warden:explore` writes `specs/_context/app.context.md` as a **draft**. Open it and correct it, then:

1. Delete the `draft:` line and the `> REVIEW:` banner.
2. Resolve any `# REVIEW:` notes.
3. Set `last_verified:` to today's date.

Until then, `/qa-warden:review` warns that the context is unconfirmed. `/qa-warden:new-spec` runs the area explore itself if it needs one.

### Rigor lane: P1, money and compliance features

Add four steps between `explore` and `new-spec`. They pin down what "correct" means before any test is generated:

```bash
/qa-warden:explore mode=area site=app area=checkout   # area context → specs/_context/app/checkout.md
/qa-warden:intake  checkout/coupon   # interview → .basis.md (the intended behaviour)
/qa-warden:ideate  checkout/coupon   # SFDIPOT checklist of candidate cases → .cases.md
/qa-warden:approve checkout/coupon   # a human approves/prunes/defers each row; mints stable row ids
/qa-warden:new-spec checkout/coupon
```

The fast lane skips no FAIL-level gate. It does skip reviewer Check 14 (approved-case traceability), which needs a `.cases.md`, so on the fast lane **completeness** is not checked.

Existing manual test cases (TestRail, Zephyr or Xray CSV, Markdown, or a pasted table) can replace `/qa-warden:ideate`:

```bash
/qa-warden:import-cases checkout/coupon source=testrail exports/coupon.csv
```

### Run tests

```bash
/qa-warden:run mode=smoke                               # @smoke suite; refreshes artifacts/last-run.json
/qa-warden:run mode=single tests/auth/login.spec.ts     # one spec, CI-shaped → reports/headless-login.json
/qa-warden:run mode=repeat tests/auth/login.spec.ts 20  # flakiness probe (default N=10)
/qa-warden:run mode=changed origin/main                 # only tests touched since a git ref
npx playwright test                                     # the full suite: plain Playwright, no Claude
```

### Triage a failure

```bash
ls artifacts/test-results/                  # a failing test's id is its results directory name
/qa-warden:heal <test-results-dir-name>     # triage from the trace; patch selectors/waits or file bugs/*.md
/qa-warden:batch-fix tests/checkout         # apply one healer fix to every matching failure (asks first)
```

If product copy changed, the healer does not absorb it. It routes the question ("intentional, or a bug?") back to the planner.

### Report and analyze

```bash
/qa-warden:report                      # PR/Slack summary → reports/summary.md
/qa-warden:coverage area=checkout      # requirement/assertion/lens/flow coverage gaps (not line coverage)
/qa-warden:impact route=/api/orders    # every spec affected by a change to that route
/qa-warden:review url=https://staging.example.com/cart   # a11y + visual + closed-vocab audit of a live page
```

### Ask what to run next

```bash
/qa-warden:help                          # reads project state, names the next command
/qa-warden:help checkout/coupon          # scoped to one feature
/qa-warden:help "how do I add a test"
```

---

## Commands reference

**You only** means Claude never runs the command on its own, because it has side effects. `/qa-warden:approve` is the key case: a model able to invoke it could approve its own test plan.

| Command | Description | Invoked by |
|---|---|---|
| `/qa-warden:init [--no-install \| --resync]` | Stamp the runtime substrate and install deps | You only |
| `/qa-warden:explore [mode=hot \| mode=area site=<id> area=<name>]` | Build or refresh the app/area context files | You or Claude |
| `/qa-warden:intake <area/feature>` | Interview for the test basis → `.basis.md` | You only |
| `/qa-warden:ideate <area/feature>` | Enumerate candidate cases → `.cases.md` | You only |
| `/qa-warden:approve <area/feature>` | Record the human verdict on a `.cases.md` | You only |
| `/qa-warden:import-cases <area/feature> [source=] [<file>]` | Import manual cases as `.cases.md` rows | You only |
| `/qa-warden:new-spec <area/feature>` | Draft a Markdown spec with a YAML oracle | You only |
| `/qa-warden:gen <spec-path>` | Compile a spec to a `.spec.ts`, run it green, verify it can fail | You only |
| `/qa-warden:review [path \| url=<url>]` | Reviewer gate over the diff, or a live-URL audit | You or Claude |
| `/qa-warden:run mode=single\|smoke\|repeat\|changed` | Run tests (no LLM) | You or Claude |
| `/qa-warden:heal <failing-test-id>` | Triage one failure; fix selectors/waits or file a bug | You only |
| `/qa-warden:batch-fix <path-or-filter>` | Apply one healer fix across matching failures | You only |
| `/qa-warden:retire <area/feature>` | Retire a feature and every linked artifact (dry-run first) | You only |
| `/qa-warden:metamorphic-relations <spec>` | Generate 2–3 metamorphic "twin" specs of a passing test | You or Claude |
| `/qa-warden:report` | Aggregate the last run into a PR/Slack summary | You or Claude |
| `/qa-warden:coverage [area=] [site=]` | Static coverage report across 9 dimensions | You or Claude |
| `/qa-warden:impact route=\|field=\|factory=\|area=\|operation=\|source=` | List specs affected by a change | You or Claude |
| `/qa-warden:doctor [--verify-invariants <spec>]` | Read-only health check of the project | You or Claude |
| `/qa-warden:help [question \| area/feature]` | Situated help and "what's next" | You or Claude |

Most commands also take `site=<id>` to target a site other than the default `app`.

### Oracle vocabulary

An oracle may use only these 16 keys. The reviewer fails anything else:

`text_visible` · `url_matches` · `count_equals` · `value_between` · `error_shown` · `no_order_created` · `attribute_equals` · `element_state` · `network_response_status` · `response_body_contains` · `download_received` · `clipboard_contains` · `storage_state` · `upload_accepted` · `dialog_dismissed` · `a11y_violations_below`

---

## How it differs from Playwright's test agents

Playwright 1.56+ ships its own planner, generator and healer agents (`npx playwright init-agents`), so authoring, replay and healing are now standard. QA Warden adds the oracle-defense and governance layer on top:

| | Official Playwright agents | QA Warden |
|---|---|---|
| Healer may change assertions / expected values | Yes (listed in its instructions, 1.63.0) | No. A `PreToolUse` hook denies the edit |
| Oracle format | Free-form TypeScript | Closed 16-key YAML a non-coder can review |
| Human approval before code exists | No | `/qa-warden:intake` → `/qa-warden:ideate` → `/qa-warden:approve` |
| Proof each assertion can fail | No | The verifier fault-injects each `must_fail_when` defect |
| PR gate on spec↔test drift | No | The reviewer blocks the merge |
| Nightly LLM cost | None | None |

Why it matters: a 2026 study of autonomous test repair documented "assertion weakening and test-case deletion used as workaround mechanisms" ([arXiv:2605.01471](https://arxiv.org/abs/2605.01471)). The full comparison is in [`DESIGN.md`](qa-warden/reference/DESIGN.md#how-we-differ-from--and-complement--official-playwright-test-agents).

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The prod-guard refuses to run: `BASE_URL_APP` is a placeholder | It still holds `CHANGEME` or an `example.com` host. Set it in `.env` to your staging or local URL. |
| The prod-guard says a host `looks like production` | The host contains a `prod` or `production` label. Point `BASE_URL_*` at staging or QA. Set `QA_ALLOW_PROD=1` only if you are certain the target is safe: the suite mutates data. |
| `/qa-warden:doctor` reports `❌ jq not installed` | Install `jq` and re-run `/qa-warden:init`. The re-run merges the rules left in `.claude/settings.qa-suggested.json` and deletes that file. |
| `/qa-warden:intake` asks you to run `explore` first | Intake needs `specs/_context/<site>/<area>.md`, and a bare `/qa-warden:explore` writes only `app.context.md`. Run `/qa-warden:explore mode=area site=<id> area=<area>`, then intake again. |
| `/qa-warden:doctor` reports `substrate drift` after a plugin update | A template changed and the project's stamped copy is older. Run `/qa-warden:init --resync`; changed files are backed up to `<file>.qa-bak`. |
| `/qa-warden:doctor` says "Setup is NOT ready yet — fill in .env" | `BASE_URL_APP` is empty, or a `BASE_URL_*` still holds a placeholder. Empty `QA_USER_*` is not flagged, because a site without a login has none. |

### Running headless

- **`claude -p` ignores the project's permission rules in a folder that was never opened interactively.** It logs "Ignoring N permissions.allow entries" because the folder isn't trusted. Pass `--settings .claude/settings.json`: the warning still prints (it's about the project's own copy), but the rules passed with `--settings` apply. Or open the folder once in interactive Claude Code and trust it.
- **Some skills read reference files inside the plugin:** `/qa-warden:report` (its template), `/qa-warden:help` (its knowledge map), `/qa-warden:heal` and `/qa-warden:batch-fix` (the sentinel actions), `/qa-warden:doctor --verify-invariants`, and `/qa-warden:gen` (its verifier reads `verify-invariants.md`). Interactively, Claude Code asks once to allow the read. Headless, pass the plugin directory with `--add-dir`. The installed copy is under `~/.claude/plugins/cache/qa-warden/qa-warden/<version>/`; the `installPath` in `~/.claude/plugins/installed_plugins.json` names the exact directory. A skill cannot pre-approve that read.
- The agents resolve target URLs with `bash scripts/prod-guard.sh --list-targets` and pass them literally. They need no chained `.env`-loading command, which a headless run would deny.

---

## Known issues

Found by a full end-to-end run of the plugin against a small app with planted bugs (it caught all of them). 0.6.0 fixes what that run found, except these:

- **Many permission prompts.** A full run (explore, both lanes, gen, review) in the default permission mode raised about 300 allow-once prompts, mostly for compound shell commands the agents write themselves (`VAR=…; … $VAR`, `cd … &&`, heredoc scripts). 0.6.0 tells them to use one plain command per call, which cuts some of them, not all. Answer "Yes" once per prompt, or switch modes for long `gen` and `review` steps.
- **`/qa-warden:review` and `/qa-warden:batch-fix` still ask for one extra "Yes".** The 0.6.0 CHANGELOG says this is fixed, but it is not. Interactive Claude Code runs the reviewer and healer in the background, and by the time they write their marker or recheck, the skill's pre-approval has expired. Answer "Yes" to that prompt.
- **Parallel tests that share one account.** With `fullyParallel: true` and a single test account, specs that change shared state (a cart, say) collide, and `/qa-warden:review` Check 13 FAILs them. The plugin has no built-in answer yet: give each worker its own account, or run that area serially. `playwright.config.ts` is toolkit-owned, so that change is yours to make and `/qa-warden:doctor` will report it as drift.
- **Coverage only knows the features you specced.** `/qa-warden:coverage` measures specs, cases and routes you already have. A feature your requirements describe but nobody has specced yet is not listed as a gap. List your features yourself and spec the risky ones, access rules especially.
- **Agents may read your product's source.** QA Warden is grey-box by design: when the live app is ambiguous, agents may read the product source to settle a route, field name or API shape, though locators and expected values must still come from the live app and your requirements. If your app's repo sits next to the QA repo and you want black-box only, answer "No" to those reads, or add a deny rule such as `Read(//absolute/path/to/app/**)` to `.claude/settings.json`.
- **Fake time doesn't reach the server.** A `clock:` step moves the browser's clock only. Rules the server enforces on time (holds, sessions, token expiry) need real-wait tests, which are slow, or a test hook in your app.

---

## Scope and limits

- **Covers:** E2E and integration tests against a real browser.
- **Does not cover:** unit, component or contract tests, load testing, security DAST, or native mobile.
- **Partial oracles:** a green a11y scan does not mean the page is accessible, and visual diffs need a specialist for the long tail.
- **Privacy:** pages the agents visit pass through the Anthropic API during authoring and triage only. The nightly run sends nothing, and credentials stay local. See [§15.1 Privacy & data flow](DOCUMENTATION.md#151-privacy--data-flow).

---

## Documentation

| Need | Read |
|---|---|
| Learn (first time) | [Tutorial: your first test](qa-warden/reference/tutorial-first-test.md) · [Reviewing AI-written tests without reading code](qa-warden/reference/reviewing-without-code.md) |
| Do a specific task | [How-to recipes](qa-warden/reference/how-to.md): import manual cases, fix a failing test, brownfield adoption, nightly CI |
| Look up a fact | [`DOCUMENTATION.md`](DOCUMENTATION.md) (full reference) · [Glossary](qa-warden/reference/glossary.md) |
| Understand the why | [`DESIGN.md`](qa-warden/reference/DESIGN.md) · [`docs/MERGE-NOTES.md`](docs/MERGE-NOTES.md) (design lineage) |
| What changed | [`qa-warden/CHANGELOG.md`](qa-warden/CHANGELOG.md) |

---

## Getting help

- **Something doesn't work:** open a [bug report](https://github.com/its-magdy/qa-warden/issues/new/choose). The output of `/qa-warden:doctor` often shows the cause.
- **Security problem:** report it privately, as [SECURITY.md](SECURITY.md) describes.
- **Want to contribute:** see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## For maintainers

### Repository layout

```
.claude-plugin/marketplace.json   the marketplace catalog (lists the QA Warden plugin)
qa-warden/                        the plugin
├── .claude-plugin/plugin.json    manifest; pinned `version`
├── agents/     planner, generator, verifier, healer, reviewer, exploration, ideation
├── skills/     24 skills: the 19 /qa-warden:* commands + 5 model-only helpers
│               (playwright-cli, test-case-contract, axe-a11y, visual-regression,
│               test-data-seed)
├── hooks/      2 PreToolUse gates: lexical reviewer FAILs, and the healer/verifier
│               assertion prohibition (see qa-warden/hooks/README.md)
├── reference/  DESIGN.md, tutorial, how-to, glossary, ideation and sentinel references
├── templates/  the runtime substrate /qa-warden:init stamps into each project
├── manifests/  plugin-only data lists (resync set, CLAUDE.md symbols, prod-guard rails); never stamped
├── lib/        plugin-only shell code the scripts source (manifest.sh: the one reader of the
│               manifests; stamped-helper.sh); never stamped
├── bin/qa-scaffold      deterministic substrate installer (used by /qa-warden:init)
├── bin/qa-selfcheck     plugin consistency checks (not stamped into projects)
├── bin/qa-hooktest      hook regression tests (not stamped into projects)
├── bin/qa-scaffoldtest  scaffold, --resync, doctor and prod-guard tests (not stamped into projects)
└── evals/             behavioural evals for the reviewer (`claude plugin eval`)
```

Agents, skills, hooks and `reference/` update automatically with the plugin. Everything under `templates/` is copied into a project once. A template fix reaches an existing project only through `/qa-warden:init --resync`, and `/qa-warden:doctor` reports when a project needs it.

### Running the checks

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs all of these except the evals, plus shellcheck, on every pull request and push to `main`, on Ubuntu and on macOS (the macOS job is the one that parses every script with bash 3.2). It makes no model calls and needs no secrets; the Claude Code CLI is installed only for `claude plugin validate`. Run them locally before every plugin commit anyway:

```bash
qa-warden/bin/qa-selfcheck                    # 15 consistency checks over the plugin's own source
qa-warden/bin/qa-hooktest                     # 62 real payloads through the two PreToolUse hooks
qa-warden/bin/qa-scaffoldtest                 # qa-scaffold stamp, settings merge, --resync and doctor in temp dirs, one prod-guard URL table through both guards (needs node), run.sh's run verdicts, the symlink-containment table, and doctor vs qa-selfcheck on a scratch copy of the plugin
claude plugin validate --strict ./qa-warden   # mandatory after any frontmatter edit
```

Expected tail:

```
qa-selfcheck: ✅ plugin is self-consistent — all 15 checks passed
qa-hooktest: ✅ all 62 cases passed
qa-scaffoldtest: ✅ all 933 cases passed
```

CI runs `qa-scaffoldtest` and `qa-hooktest` a second time on Linux with `mawk` first on `PATH`, the
third awk dialect (BSD awk on macOS and gawk on the Linux runner cover the other two). That run sets
`QA_EXPECT_AWK=mawk`, which adds one case, so its tail reads 934 rather than 933.

When you change `qa-warden/agents/reviewer.md`, also run the behavioural evals. They make real model calls (on 2026-09-30, about $0.4 and 2 minutes per case; all five cost $1.97), so run them per change, not per commit. Details: [`qa-warden/evals/README.md`](qa-warden/evals/README.md).

```bash
cd qa-warden && claude plugin eval . --tag reviewer --runs 1 --ablation none --scaffold --trust-plugin --no-publish
```

Load the plugin locally without the marketplace (run `/reload-plugins` after edits):

```bash
claude --plugin-dir ./qa-warden
```

### Versioning and releasing

The plugin ships in **versioned mode**: `qa-warden/.claude-plugin/plugin.json` sets an explicit `version`, currently `0.6.1`. Users receive an update only when that string changes.

> **Bump `version` in the same commit as every user-visible change.** If you push without a bump, nothing ships, and `/plugin update` tells users they are already current. No error warns you.

To release:

1. Bump `version` in `qa-warden/.claude-plugin/plugin.json` and add an entry to `qa-warden/CHANGELOG.md`.
2. Run `claude plugin validate --strict ./qa-warden`.
3. Push, then tag with `claude plugin tag ./qa-warden`.

Consumers pick up the release with:

```bash
/plugin marketplace update qa-warden
/plugin update qa-warden
/reload-plugins
```

The alternative is **commit-SHA mode**: delete the `version` key, and every push becomes a new version automatically. If you switch, update this section too.

---

## License

[MIT](LICENSE) © 2026 Mohamed Magdy Omar
