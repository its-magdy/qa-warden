---
name: playwright-cli
description: Drive a real Chromium/Firefox/WebKit page deterministically from an agent. Use when authoring or healing Playwright tests, running a single navigate-snapshot-assert loop, or any healer/nightly flow that must stay token-predictable. Prefer this CLI over Playwright MCP for healer, generator, and nightly; reach for MCP only for first-contact exploration.
user-invocable: false
disable-model-invocation: false
---

# playwright-cli

**This file is NOT the official Playwright skill — it is a thin project companion.** Microsoft ships an official `@playwright/cli` agent skill *inside the npm package*; `/qa-warden:init` installs it via `npx playwright-cli install --skills`, and it is the **authoritative, auto-updating** reference for the CLI's command surface (tracing, storage-state, request-mocking, test-generation, …). This companion exists ONLY to pin the toolkit-specific decision rules (CLI vs MCP), the healer/generator recipe shape, and session hygiene — the parts Microsoft's generic skill does not cover.

**Do NOT treat the command list below as the source of truth, and do not re-copy Microsoft's tool list into this file** — that is what goes stale between `@playwright/cli` releases. For the current command surface always defer to `npx playwright-cli --help` and the installed official skill (its path is printed by `--help` as "Agent skill: …"). When this companion and the installed binary/skill disagree, **the binary + its bundled skill win.**

## When to use
- **Healer** reading `trace.zip` + failing DOM from disk (the cheapest repeat loop).
- **Generator** running a freshly-written `.spec.ts` one round-trip to confirm green before commit.
- **Nightly smoke/regression** where you want predictable token cost — CLI's ~68-token schema overhead vs MCP's ~3,600-4,200.
- Any filesystem-native loop (read file, interact, write file) where MCP's live AX tree is wasted.

**Skip this skill and use Playwright MCP (`npx playwright mcp`, bundled since Playwright 1.62; the standalone `@playwright/mcp` package is legacy) when:** first-contact exploration of an unknown app (the planner's step-7 fallback when the CLI cannot disambiguate), or fuzz-style adversarial runs where the live DOM is the point.

## Install & invocation
`/qa-warden:init` installs `@playwright/cli` as a **local devDependency** (see `templates/package.json`) — it does NOT install globally. So the binary lives at `node_modules/.bin/playwright-cli`, which is **not on an agent Bash shell's PATH**.

**Invoke the CLI as `npx playwright-cli …` everywhere — never bare `playwright-cli`.** `npx` resolves the local `node_modules/.bin` copy from the project root; bare `playwright-cli` fails with `command not found (exit 127)` unless the operator separately ran a global install. Every recipe, agent, and command in this toolkit uses the `npx` form for this reason.

```bash
npx playwright-cli --version        # sanity check — should print the installed CLI version
npx playwright-cli install --skills # registers the upstream skill bundle
# Optional (NOT required): a machine-wide global install also puts `playwright-cli` on PATH:
#   npm install -g @playwright/cli@latest
```
Upstream skill (authoritative tool reference): https://github.com/microsoft/playwright-cli — keep commands aligned with what `npx playwright-cli --help` prints on the current install.

## Command surface — defer to the official skill
The authoritative, always-current command list is `npx playwright-cli --help` + the installed official skill (see the intro). **Do not maintain a mirror of it here.** As orientation only, the categories you compose are session management (`open`/`close`/`-s=<name>`), navigation (`goto`/`reload`), interaction (`click`/`fill`/`select`/`upload`/…), observation (`snapshot` — the a11y tree, prefer over `eval` — plus `screenshot`/`eval`/`console`), tabs, and recording (`tracing-*`/`video-*`). Exact subcommand names, flags, and availability come from the binary — check `--help`, not this paragraph. (Note: some subcommands like `network` vary by CLI version — confirm with `--help` rather than assuming.)

## Recipe — navigate + snapshot + assert
The canonical single-step loop for healer/generator work. This recipe encodes the *shape* of the loop (open → goto → snapshot → act on the ref); the exact subcommands/flags come from `npx playwright-cli --help` on the installed version.

**Bind the CLI as a shell function, not a string variable.** A `PW="npx playwright-cli"; $PW …` binding is **not shell-portable**: under **zsh** (macOS's default shell) unquoted `$PW` is NOT word-split (zsh has `SH_WORD_SPLIT` *off* by default, unlike bash), so `$PW open` tries to exec one command literally named `npx playwright-cli` → `command not found`. A function word-splits correctly in both bash and zsh:
```bash
pw() { npx playwright-cli "$@"; }                     # resolves node_modules/.bin — never bare `playwright-cli`; portable across bash+zsh
SESSION=heal-$(uuidgen | cut -c1-8)
pw -s=$SESSION open --browser=chromium   # `open` FIRST — snapshot needs a live page
pw -s=$SESSION goto "$BASE_URL/checkout"  # snapshot takes NO url; you must goto first
pw -s=$SESSION snapshot > /tmp/$SESSION.snap.yaml
# The snapshot yields elements tagged with a volatile ref, e.g.:
#   - button "Pay" [ref=e13] [cursor=pointer]
# `click <target>` wants that EXACT ref (or a unique CSS selector) — NOT a
# role-descriptor. `click 'role=button[name="Pay"]'` is REJECTED by the CLI.
REF=$(grep -oE 'button "Pay" \[ref=(e[0-9]+)\]' /tmp/$SESSION.snap.yaml | grep -oE 'e[0-9]+' | head -1)
pw -s=$SESSION click "$REF"
pw -s=$SESSION screenshot --path=artifacts/$SESSION.png
pw -s=$SESSION close
```
(If you prefer a variable, quote-expand it zsh-safely — `${=PW}` forces word-splitting — but the function above is the least error-prone form.)
**Refs (`eNN`) are volatile** — they are re-numbered on every navigation/DOM change. **Re-`snapshot` after every `goto`/`click` that changes the page** and re-read the ref; a ref cached across a nav points at nothing. To fill a field use `fill <ref> <text>` (targeted); `type <text>` types into the already-focused editable element (no target).

Always pass `-s=<name>` so parallel Playwright workers do not collide on the default session. Every plugin agent drives a NAMED session (`-s=plan-<feature>`, `-s=gen-<feature>`, `-s=intake-<feature>`, `-s=audit-<ts>`, `-s=explore-<area>-<n>`) — the shared `default` session is reserved for the human. When running many sessions concurrently, also pass a distinct `--user-data-dir` per invocation (e.g. `/tmp/pw-$PW_WORKER`) to dodge [playwright-mcp #893](https://github.com/microsoft/playwright-mcp/issues/893) and orphan-process accumulation.

> **The CLI ships its own authoritative tool reference** — the installed official
> skill named in the intro above. Don't hardcode its path (it moves between
> `@playwright/cli` releases): `npx playwright-cli --help` prints the exact location
> as "Agent skill: …". When this companion file and the installed binary disagree,
> the binary + its bundled skill win — re-check with `npx playwright-cli <command> --help`.

## Decision rule summary
| Phase | Tool | Why |
|---|---|---|
| Planner / explorer | **CLI first** (MCP only as the planner's step-7 STOP-and-restart fallback) | needs live AX tree — `goto && snapshot` gives it |
| Generator | either (default to scaffold) | — |
| **Healer** | **CLI** | reads trace + DOM from disk |
| Reviewer | read-only, no browser | — |
| Exploratory fuzz | MCP | live reaction |
| **Nightly** | **`npx playwright test`** | zero LLM, deterministic |

## Gotchas
- **Always `npx playwright-cli` — never bare `playwright-cli`.** The binary is a local devDependency, not on the agent shell PATH; bare invocation is `command not found (exit 127)`. This is the single most common first-run failure (see §Install & invocation).
- `playwright-cli` sessions persist until `close-all` or process exit — orphan sessions leak memory; always `close` or `kill-all` at script end.
- `snapshot` returns an a11y/ARIA tree, not full DOM. If you need DOM specifics use `eval 'document.querySelector(...).outerHTML'` sparingly.
- **Geometry-aware AX for AI consumption (Playwright 1.60+):** when *code* (a generated test, or a healer `eval`/MCP snapshot) needs to know not just *what* an element is but *where* it sits — overlap, off-screen, covered-by — call `page.ariaSnapshot({ boxes: true })` / `locator.ariaSnapshot({ boxes: true })`. It appends each element's `[box=x,y,width,height]`, giving an agent layout without a screenshot + vision pass (which the cost rules forbid by default). Prefer this over `--caps=vision` for "is the button actually visible/clickable" questions.
- Parallel runs without `-s=<name>` + `--user-data-dir` collide.
- CLI is **not** faster wall-clock than MCP on 10-step tests (MCP ~2-3× faster per test). CLI wins on token predictability and memory hygiene, not speed — see `reference/DESIGN.md` §"CLI vs MCP: why the split".

## References
- `reference/DESIGN.md` §"CLI vs MCP: why the split" (the decision rationale) and §"The economic thesis" (why nightly is zero-LLM).
- Microsoft upstream: https://github.com/microsoft/playwright-cli
- Outpost/Ranger cost benchmark: https://outpost.ranger.net/post/the-hidden-cost-of-fewer-tokens/
