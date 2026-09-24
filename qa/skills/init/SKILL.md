---
description: Bootstrap the QA runtime substrate into the current project (configs, scripts, fixtures, CLAUDE.md, permissions) and install dependencies. Run once per project after installing the QA Warden plugin.
argument-hint: "[--no-install] (skip npm/playwright install) | [--resync] (force-refresh toolkit-owned substrate in an already-scaffolded project)"
disable-model-invocation: true
---

You are bootstrapping this project to use the **QA Warden** plugin. The plugin ships
the *brain* (agents, skills); this command stamps the *body* (runtime
substrate) that a plugin cannot carry on its own.

## What to do

1. Run the deterministic scaffold script bundled with the plugin, targeting the
   current project root:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/qa-scaffold" "${CLAUDE_PROJECT_DIR}" $ARGUMENTS
   ```

   The script is idempotent and **never clobbers** an existing file — re-running
   it only fills in what's missing.

   **`--resync` (repairing an already-scaffolded project):** because the default
   run is skip-if-exists, a plugin fix to a substrate file (`package.json`,
   `playwright.config.ts`, `scripts/prod-guard.*`, a pinned dependency, …) does
   **not** reach a project that was scaffolded before the fix — and the project
   deny-list blocks any agent from repairing it in place (F-015/F-016). Run
   `/qa-warden:init --resync` to force-overwrite **only the toolkit-owned substrate**
   from the current templates, backing up each changed file to `<file>.qa-bak`
   first, then reinstalling deps if `package.json`/lockfile changed. It never
   touches user-authored files (`.env`, a customized `CLAUDE.md`,
   `fixtures/test.ts`, or anything under
   `specs/`/`tests/`/`page-objects/`/`steps/`/`bugs/`). `/qa-warden:doctor`'s
   substrate-drift check tells you when a project needs this.

   **`--resync` is the whole upgrade — do not tell the user to follow it with a
   plain `/qa-warden:init`.** Both paths run the same permission merge. Two files are therefore touched that the
   list above does not cover, both additively and neither overwritten:
   `.claude/settings.json` (union of the permission arrays — it can add a rule
   but never remove one) and `.gitignore` (one appended `*.qa-bak` pattern, so
   the backups the resync itself writes are not offered up as new files).

2. Read the script's stdout. It reports, per file, whether it was `created` or
   `exists (skipped)`, and whether `git init` / `npm install` / browser install
   ran.

3. Summarize for the user what was stamped, then relay the script's `Next:`
   block **verbatim** — the scaffold already emits its commands in the namespaced
   `/qa-warden:` form (e.g. `/qa-warden:explore`, `/qa-warden:intake`), so relay them as-is; do not
   re-prefix or strip the namespace. The scaffold's heredoc is the single source
   of the next-steps list; do not maintain a separate copy here.

## Guardrails

- Do NOT overwrite `.env` if it already exists (it holds secrets).
- Do NOT overwrite a customized `CLAUDE.md`; the script skips it when present.
- If the project already has a `.claude/settings.json`, the script MERGES the
  permission allowlist/deny rules rather than replacing the file. The deny list
  is **safety-only** — it blocks destructive/dangerous operations (**every `rm`
  command** — the rule is `Bash(rm *)`, not just `rm -rf`, and deny rules cannot
  be interactively approved; `find … -delete` and `truncate` are denied too, so
  commands that must clean up do it WITHOUT those primitives: `/qa-warden:run mode=repeat`
  overwrites its own report files in place (`>`/`2>` truncate-and-rewrite), and
  `/qa-warden:retire` deletes through the allow-listed `scripts/retire-delete.sh` wrapper
  (the deny can't be bypassed inline — see F-031) — force-push, `git reset --hard`,
  `curl … | sh`, writes to
  `package.json` / `playwright.config.ts` / `package-lock.json` / `prod-guard.*`,
  reading `/etc`). `.env` is not hard-denied — it is simply outside the
  write-allowlist, so an agent write to it needs explicit per-prompt human
  approval (gitignored + human-owned, not blocked). Reading product source
  outside the QA repo is allowed (grey-box locator disambiguation); writes are
  scoped to the QA repo dirs.
- This command writes project files. The first time, the user may need to
  approve the writes / the trust dialog for the folder.
