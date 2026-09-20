# qa-toolkit — the `qa` Claude Code plugin

**AI authors declarative specs → Playwright replays them nightly at ~$0 LLM cost → AI triages only on failure.**

## Install

```bash
# 1. register this marketplace (private git: SSH/HTTPS both work)
/plugin marketplace add git@your-host:org/qa-toolkit.git

# 2. install the plugin at project scope (records it in .claude/settings.json,
#    so teammates who clone + trust the repo are auto-prompted to install)
/plugin install qa@qa-toolkit --scope project

# 3. stamp the runtime substrate into THIS project + install deps
/qa:init
```

## First test today (fast lane)

**New here? Follow the [step-by-step tutorial](qa/reference/tutorial-first-test.md)** — it walks
this through and shows what you'll see at each step. The quick version:

1. Edit `.env` — `BASE_URL_APP` → your staging or localhost, **never prod**; `QA_USER_*` creds (the test account must already exist).
2. `/qa:explore` — the first run writes a **DRAFT** app context; review + confirm it.
3. `/qa:new-spec auth/login` → `/qa:gen specs/auth/login.md` → `/qa:review` → `/qa:run mode=smoke`

**Rigor lane** (P1 / money / compliance): insert `/qa:intake` → `/qa:ideate` → `/qa:approve` between explore and new-spec — it pins *what correct means* before anything is generated. The fast lane skips no FAIL-level gate — but with no `.cases.md`, reviewer Check 14 (approved-case traceability) has nothing to read and is SKIPPED, not downgraded: *completeness* is unchecked on the fast lane.

> **Day-1 glossary:** site — one deployed app under test (`BASE_URL_<SITE>`) · area — a product area, the folder specs group under · spec — the human-readable Markdown contract in `specs/` · test — the compiled Playwright `.spec.ts` in `tests/` · oracle — the spec's definition of "correct" (the assertions) · smoke — the `@smoke`-tagged fast gate `/qa:run mode=smoke` runs · **[full glossary →](qa/reference/glossary.md)**

**"Isn't this just BDD again — prose specs the tests quietly ignore?"** No: Gherkin's failure was prose and automation held together by convention, drifting apart. Here the spec's oracle is a **closed 16-key vocabulary** that compiles 1:1 to `expect()` calls, and a read-only reviewer **blocks the merge** when they diverge — a step with no assertion, an assertion asserting the wrong literal, or an out-of-vocab "should look right" is a failed PR, not a style note. Declared invariants aren't trusted either: the generator **fault-injects each `must_fail_when` defect** at authoring time and refuses to ship an oracle that doesn't go red on it. And the agents can't "ignore the spec at runtime" because at runtime there are no agents — the nightly is plain `npx playwright test`, replaying exactly the code the reviewer gated.

Privacy: see [DOCUMENTATION §Privacy & data flow](DOCUMENTATION.md#151-privacy--data-flow) — TL;DR: pages the agents visit transit the API during authoring/triage only; the nightly sends nothing; creds stay local.

## Documentation

Four kinds of doc, pick by what you need right now:

| | |
|---|---|
| 🎓 **Learn** (first time) | [Tutorial — author your first test](qa/reference/tutorial-first-test.md) · [Reviewing AI-written tests without reading code](qa/reference/reviewing-without-code.md) |
| 🔧 **Do** (a specific goal) | [How-to recipes](qa/reference/how-to.md) — import manual cases · fix a failing test · brownfield adoption · nightly CI · or ask `/qa:help "how do I …"` |
| 📖 **Look up** (a fact) | [Full reference — `DOCUMENTATION.md`](DOCUMENTATION.md) · [Glossary](qa/reference/glossary.md) |
| 💡 **Understand** (the why) | [Design rationale — `DESIGN.md`](qa/reference/DESIGN.md) · [How we differ from official Playwright Test Agents](qa/reference/DESIGN.md#how-we-differ-from--and-complement--official-playwright-test-agents) |

> **Evaluating this against Microsoft's official Playwright Agents (1.56+)?** Read
> [How we differ from — and complement — official Playwright Test Agents](qa/reference/DESIGN.md#how-we-differ-from--and-complement--official-playwright-test-agents):
> the author/replay/heal mechanics are now commodity; this toolkit's value is the
> oracle-defense + governance layer (closed vocabulary, blocking reviewer, intake→approve
> rigor, fault-injection) that the official agents deliberately don't provide.

From inside a project, **`/qa:help`** gives a live, project-aware "what do I do next" answer —
or **`/qa:help <area/feature>`** to scope it to one feature.

---

## For maintainers

### Layout

```
.claude-plugin/marketplace.json   ← the catalog (lists the qa plugin)
qa/                               ← the plugin
├── .claude-plugin/plugin.json    ← manifest (pinned `version` → bump it to ship)
├── agents/    planner, generator, verifier, healer, reviewer, exploration, ideation
├── skills/    23 SKILL.md — the 19 /qa:* commands (/qa:init /qa:gen /qa:heal …)
│              + 4 capability helpers (playwright-cli, axe-a11y, …)
├── hooks/     2 PreToolUse gates — the lexical reviewer FAILs, and the
│              healer/verifier assertion prohibition (see hooks/README.md)
├── reference/ DESIGN.md (design rationale) + test-case-ideation.md + sentinel-actions.md
├── templates/ the runtime substrate stamped into each project by /qa:init
│              (incl. page-objects/ reuse layer + fixtures/test.ts barrel)
└── bin/qa-scaffold  deterministic substrate installer
    bin/qa-selfcheck the plugin's own consistency checks — NOT shipped to consumers
    bin/qa-hooktest  regression tests for the two hooks  — NOT shipped to consumers
```

### Before you commit a plugin change

```bash
qa/bin/qa-selfcheck              # 7 checks over agents/ skills/ hooks/ reference/ — must end ✅
qa/bin/qa-hooktest               # 20 real payloads through the two PreToolUse hooks — must end ✅
claude plugin validate ./qa      # mandatory after ANY frontmatter edit
```

`qa-selfcheck` holds the checks that read only plugin source (oracle-key mirrors, `maxTurns`
ordering, the `/qa:help` catalog, hook registration, `/qa:explore` invocation shapes). They used
to run inside every consumer's `/qa:doctor`, where nobody could act on them. Everything that
*compares a project with the plugin* is still in `templates/scripts/doctor.sh`.

### What the plugin carries vs. what `/qa:init` stamps

| Shipped *by the plugin* (live, auto-updates)         | Stamped *by `/qa:init`* (per-project, one-time) |
| ---------------------------------------------------- | ----------------------------------------------- |
| agents, skills, `/qa:*` commands, `reference/DESIGN.md` | `package.json`, `playwright.config.ts`, `tsconfig.json` |
|                                                      | `CLAUDE.md` (the policy / source-of-truth file) |
|                                                      | `.claude/settings.json` permission rules (incl. black-box deny) |
|                                                      | `.mcp.json` + `.mcp.explore.json` (two-config MCP pattern) |
|                                                      | `scripts/`, `fixtures/`, `.env.example`, `.gitignore` |

Why the split exists (and what each side carries in full): see
[DOCUMENTATION §4.2](DOCUMENTATION.md#42-the-brain-vs-body-split-important) and
[§16](DOCUMENTATION.md#16-the-runtime-substrate).

**Updating a stamped file after a plugin fix.** `/qa:init` is skip-if-exists, so a
template fix never reaches an already-stamped project on its own. Run **`/qa:init --resync`**
to force-refresh the toolkit-owned substrate (backs each changed file up to `<file>.qa-bak`,
reinstalls deps if `package.json`/lockfile changed, leaves `.env` and customized files
untouched); **`/qa:doctor`** flags when a project needs it.

### Versioning

This plugin ships in **versioned mode** — `qa/.claude-plugin/plugin.json` carries an explicit
`version`. Per the [plugins reference](https://code.claude.com/docs/en/plugins-reference),
setting it *"pins the plugin to that version string, so users only receive updates when you
bump it."*

> ⚠️ **Bump `version` in the same commit as every user-visible change.** Pushing without
> bumping ships **nothing** — consumers stay on the old copy and `/plugin update` reports
> they are already current, with no error to tell you otherwise. This is the one release
> mistake that fails silently.

The alternative is **commit-SHA mode**: delete the `version` key entirely and Claude Code
falls back to the git commit SHA, so every push counts as a new version automatically. That
trades per-release control for never having to remember the bump. Pick one and keep this
section in sync with `plugin.json` — a doc that describes the mode you are *not* in is how a
release silently goes nowhere.

Consumers pick up a bumped release with:

```bash
/plugin marketplace update qa-toolkit
/plugin update qa
/reload-plugins
```

Validate before pushing:

```bash
claude plugin validate --strict ./qa
```

(`--strict` passes clean in versioned mode — verified. The old note here said to drop
`--strict` because the omitted `version` produced a warning; with `version` pinned there is
no warning, so use the stricter form.)

**Local dev** (no marketplace): `claude --plugin-dir ./qa` loads the plugin for that
session only; run `/reload-plugins` after edits.

> Design lineage (the Test-Browser oracle-defense plugin × POM reuse merge, and the
> no-hooks decision): see [`MERGE-NOTES.md`](MERGE-NOTES.md).
