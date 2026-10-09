# QA Warden

> AI writes your Playwright E2E tests from plain-language specs. No AI can quietly loosen them afterwards.

QA Warden is a Claude Code plugin that turns a Markdown spec into a Playwright `.spec.ts`. Each spec defines "correct" (its **oracle**) with a closed 16-key YAML vocabulary. A non-coder can read the oracle, and it compiles one-to-one into `expect()` calls. The nightly run is plain `npx playwright test`, so it costs roughly $0 in LLM calls. AI comes back only to triage a failure.

The party it guards against is the AI itself, when it would weaken an assertion to turn a red test green:

- A **verifier** breaks the app on purpose and checks that each assertion goes red.
- A read-only **reviewer** blocks the PR when the spec and the test disagree.
- The **healer** repairs selectors and waits, never the assertion. A red test stays red until a human decides whether the app or the spec is wrong.

It is a test-authoring plugin, not a security or secrets tool. This repo is both the plugin and its marketplace, and both are named `qa-warden`.

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
- [Scope and limits](#scope-and-limits)
- [Documentation](#documentation)
- [For maintainers](#for-maintainers)
- [License](#license)

---

## Prerequisites

- **Claude Code** with plugin support (`/plugin` commands). Not claude.ai or Cowork: they don't install a plugin that has a top-level `bin/` directory, and this one does.
- **macOS, Linux or WSL.** The two hooks are shell scripts; native Windows can't run them.
- **Node.js `>=22`** and `npm`, for the Playwright project that `/qa-warden:init` stamps
- **`git`**
- **`jq`**: required. Without it, `/qa-warden:doctor` reports a ❌ and `.claude/settings.json` can't be auto-merged.
- **`ripgrep` (`rg`)**: recommended. Without it, `/qa-warden:retire` consumer checks fall back to `grep`.
- A **staging or local** instance of the app under test, plus a test account that already exists in it. Never production.

---

## Installation

### Install the plugin

Run these inside Claude Code, from the project that will hold the tests:

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
/plugin marketplace add its-magdy/qa-warden#qa-warden--v0.5.6
```

Updates are manual by default (see [Versioning and releasing](#versioning-and-releasing)). To get them automatically, run `/plugin`, open the **Marketplaces** tab, select `qa-warden` and choose **Enable auto-update**.

### What `/qa-warden:init` does

- Copies every file in the plugin's `templates/` into the project, skipping any file that already exists:
  - `package.json` (with `@playwright/test` pinned to `1.63.0`), `playwright.config.ts`, `tsconfig.json`
  - `CLAUDE.md`, `.mcp.json`, `.mcp.explore.json`, `.gitignore`, `.env.example`
  - `scripts/`, `fixtures/`, `page-objects/`, `specs/_context/_templates/`
  - one CI example, `.github/workflows/qa-nightly.yml.example`
- Creates `.env` from `.env.example`.
- Merges its permission rules and a `qa-warden` entry under `extraKnownMarketplaces` into `.claude/settings.json`.
- Runs `npm install` and installs the Playwright browsers.

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
- Each additional site under test gets its own `BASE_URL_<SITE>` variable.
- A site with no login is recorded as `auth_mode: none` in `specs/_context/app.context.md`. Its tests run unauthenticated and `QA_USER_*` stays empty. When `/qa-warden:explore` sees no login and no `QA_USER_*` credentials, it drafts `auth_mode: none` with a `# REVIEW:` line for you to confirm.

Check the setup. Doctor is read-only and offline; it never contacts `BASE_URL_APP`:

```bash
/qa-warden:doctor
```

A healthy project prints a summary with no ❌ blockers and the verdict "Setup looks healthy". While `BASE_URL_APP` is empty or a placeholder, doctor prints a ⚠️ and the verdict reads "Setup is NOT ready yet — fill in .env".

---

## Usage

### Try it on a demo app

This walkthrough targets Playwright's public TodoMVC demo, so you need no app of your own and no account. In a new, empty folder, [install the plugin](#install-the-plugin), then set one line in `.env` and leave `QA_USER_*` and `QA_ADMIN_*` empty:

```bash
BASE_URL_APP=https://demo.playwright.dev/todomvc/
```

Keep the trailing slash. Without it, the app's relative `goto('./')` lands on a 404.

```bash
/qa-warden:doctor                    # the .env ⚠️ should be gone
/qa-warden:explore                   # drafts app.context.md with auth_mode: none
/qa-warden:new-spec todos/add-todo   # describe: "add two todos; both are listed and the counter reads '2 items left'; tag it smoke"
/qa-warden:gen specs/todos/add-todo.md
/qa-warden:review
/qa-warden:run mode=smoke
```

After `/qa-warden:explore`, [confirm the draft context](#confirm-the-app-context). The oracle should look something like this:

```yaml
oracle:
  text_visible: "2 items left"
  count_equals: { locator: "getByTestId('todo-item')", n: 2 }
```

A test id is justified here: the demo's rows carry `data-testid="todo-item"`, and the `listitem` role also matches the filter links.

**Cost.** The authoring pass (`explore` through `review`) makes real model calls; `/qa-warden:run` has no LLM cost. A measured run of exactly these steps (0.5.1, 2026-09-30) took about 40 minutes and about $6. Half of that was `gen`, whose verifier breaks the app on purpose to prove the test can fail. The demo is public and shared, so it may change or be down.

### Fast lane: your first test

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
| `/qa-warden:run mode=single\|smoke\|repeat\|changed` | Run tests (no LLM) | You only |
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

## For maintainers

### Repository layout

```
.claude-plugin/marketplace.json   the marketplace catalog (lists the QA Warden plugin)
qa-warden/                        the plugin
├── .claude-plugin/plugin.json    manifest; pinned `version`
├── agents/     planner, generator, verifier, healer, reviewer, exploration, ideation
├── skills/     23 skills: the 19 /qa-warden:* commands + 4 model-only helpers
│               (playwright-cli, axe-a11y, visual-regression, test-data-seed)
├── hooks/      2 PreToolUse gates: lexical reviewer FAILs, and the healer/verifier
│               assertion prohibition (see qa-warden/hooks/README.md)
├── reference/  DESIGN.md, tutorial, how-to, glossary, ideation and sentinel references
├── templates/  the runtime substrate /qa-warden:init stamps into each project
├── bin/qa-scaffold    deterministic substrate installer (used by /qa-warden:init)
├── bin/qa-selfcheck   plugin consistency checks (not stamped into projects)
├── bin/qa-hooktest    hook regression tests (not stamped into projects)
└── evals/             behavioural evals for the reviewer (`claude plugin eval`)
```

Agents, skills, hooks and `reference/` update automatically with the plugin. Everything under `templates/` is copied into a project once. A template fix reaches an existing project only through `/qa-warden:init --resync`, and `/qa-warden:doctor` reports when a project needs it.

### Running the checks

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs all of these except the evals, plus shellcheck, on every pull request and push to `main`, on Ubuntu and on macOS (the macOS job is the one that parses every script with bash 3.2). It makes no model calls and needs no secrets; the Claude Code CLI is installed only for `claude plugin validate`. Run them locally before every plugin commit anyway:

```bash
qa-warden/bin/qa-selfcheck                    # 8 consistency checks over agents/ skills/ hooks/ reference/
qa-warden/bin/qa-hooktest                     # 58 real payloads through the two PreToolUse hooks
claude plugin validate --strict ./qa-warden   # mandatory after any frontmatter edit
```

Expected tail:

```
qa-selfcheck: ✅ plugin is self-consistent — all 8 checks passed
qa-hooktest: ✅ all 58 cases passed
```

When you change `qa-warden/agents/reviewer.md`, also run the behavioural evals. They make real model calls (on 2026-09-30, about $0.4 and 2 minutes per case; all five cost $1.97), so run them per change, not per commit. Details: [`qa-warden/evals/README.md`](qa-warden/evals/README.md).

```bash
cd qa-warden && claude plugin eval . --tag reviewer --runs 1 --ablation none --scaffold --trust-plugin --no-publish
```

Load the plugin locally without the marketplace (run `/reload-plugins` after edits):

```bash
claude --plugin-dir ./qa-warden
```

### Versioning and releasing

The plugin ships in **versioned mode**: `qa-warden/.claude-plugin/plugin.json` sets an explicit `version`, currently `0.5.6`. Users receive an update only when that string changes.

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
