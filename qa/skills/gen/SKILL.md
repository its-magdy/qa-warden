---
description: Compile a Markdown+YAML spec into a Playwright .spec.ts via the generator subagent.
argument-hint: "<spec-path or area/feature> [site=<id>] [keep-video]"
disable-model-invocation: true
---

Delegate to the `generator` subagent (uses `@playwright/cli`) to compile
`$ARGUMENTS` into a matching `.spec.ts` under `tests/` using the same
kebab-case basename. The generator runs SERIALLY in the main working tree
against the real `node_modules`/`.env` — it needs no initial commit.

**No argument given?** If `$ARGUMENTS` is empty, do **NOT** proceed — print the block below
verbatim and stop, so the user has a concrete command to copy:

```
Usage:  /qa:gen <spec-path or area/feature> [site=<id>] [keep-video]
Compile ONE spec into a runnable test. For example:

  /qa:gen specs/auth/login.md      compile the spec you just drafted
  /qa:gen auth/login               the same spec, by area/feature
  /qa:gen tasks/update-task        compile the update-task spec

First time? Follow ${CLAUDE_PLUGIN_ROOT}/reference/tutorial-first-test.md.
```

**Safety rail (CLAUDE.md §Environment):** run `bash scripts/prod-guard.sh` first — STOP and ask the user to confirm in-chat if it exits non-zero. The subagent's live-snapshot steps drive `playwright-cli` against `$BASE_URL_<SITE>` — only the `npx playwright test` half is covered by the enforced `globalSetup` guard; the CLI-driving half has no backstop but this check.

**Normalize the spec argument first.** Accept the bare `<area>/<feature>` form
(what users learn from `/qa:new-spec`, `/qa:intake`, `/qa:ideate`) as well as a
full `specs/<area>/<feature>.md` path, resolved via the canonical resolver
(missing script → re-run `/qa:init` to stamp it):

```bash
SPEC=$(bash scripts/resolve-spec-path.sh spec "$ARGUMENTS")
```

So `/qa:gen checkout/coupon` maps to `specs/checkout/coupon.md`, while a full
`specs/checkout/coupon.md` path is used as-is. `/qa:gen` reads `site:` from the
spec's own YAML, so a stray inline `site=…` flag (users carry it over from
`/qa:new-spec`) is not needed here — the resolver strips any `key=val` token and
resolves on the bare path token, so `/qa:gen checkout/coupon site=app` still
maps to `specs/checkout/coupon.md` instead of a broken `…coupon site=app.md`.
Compile the resolved `$SPEC`.

Requirements the generator must honour:

- Locators: the 7 official `getBy*` factories only — `getByRole`, `getByText`, `getByLabel`, `getByPlaceholder`, `getByAltText`, `getByTitle`, `getByTestId` (no XPath, no CSS). Prefer `getByRole` with an accessible `name:`; `getByText` for assertion targets, not click actions.
- Auto-waiting assertions — **never** `page.waitForTimeout`.
- One `expect(...)` per oracle-vocab item in the YAML; Playwright 1.49+
  `page.ariaSnapshot()` is preferred for structural asserts.
- Closed oracle vocabulary only (CLAUDE.md §Assertion style).

**Process scenarios SEQUENTIALLY if the spec contains multiple** (YAML
`scenarios:` array or multiple fenced oracle blocks) — compile one at a time
in the main working tree so each pass can reuse and extend the page objects
the earlier ones created.

**The spec must be confirmed green before declaring done — and the generator's
own run satisfies this.** The generator runs the compiled test as its Process
step 7 (and re-runs twins/mutating specs in 8a/8b), so do **NOT** re-run it
yourself after the agent returns green — that doubles the verification
wall-clock for zero signal. Only verify the generator's report says green and
the route manifest exists. If you ever DO need a manual run (e.g. the generator
returned without a run log), use
`npx playwright test tests/<area>/<feature>.spec.ts --retries=0 --reporter=line`
— the **compiled test path**, not `$SPEC`, and `--reporter=line` is load-bearing
(same clobber-guard as `/qa:heal` / `/qa:batch-fix`; why: CLAUDE.md §Reporting
pipeline). If the generator reports red, do not hand it off as "done". The
generator does NOT self-commit — it leaves the green test for the caller to
commit after review.

On green, `/qa:gen` also emits (a) metamorphic twins at
`tests/<area>/<feature>.metamorphic.spec.ts` (new specs only) and (b) a **route
manifest** at `artifacts/route-manifests/<area>/<feature>.json` — the data source
`/qa:impact` intersects for requirement-change-cascade analysis. So a spec is not
fully "generated" until its manifest exists; without any manifests, `/qa:impact`
cannot run — it exits with a "NO MANIFESTS FOUND" error (there is no grep fallback),
so generate specs (which writes their manifests) before running impact analysis.

**Confirmation video (new specs).** Green means the assertions passed — not that
the test drives the flow the QA *intended* (it could click a wrong-but-equivalent
path). So for a **brand-new** spec the generator's final step (8d) re-runs the
parent spec once with `QA_KEEP_VIDEO=1`, which keeps the `.webm` even on a pass
(`playwright.config.ts` is `retain-on-failure` by default). **Surface that video
path in your handoff** — e.g. `📹 review: artifacts/test-results/<id>/video.webm`
— and tell the human to watch it to confirm intent, then delete `artifacts/` once
satisfied (the video is disposable, human-only; no agent reads it). Only the parent
spec's video is kept — never the twin or fault-injection runs, so the human never
opens a deliberately-red injected run by mistake. This is local authoring
wall-clock only; the nightly/CI never sets `QA_KEEP_VIDEO`, so the $0 replay
promise is untouched.

**Force a video on a re-run: `keep-video`.** 8d fires only on a spec's *first*
green. To get a fresh confirmation video for an **existing** spec (e.g. after an
edit), pass the `keep-video` token — `/qa:gen checkout/coupon keep-video`. Detect it
in `$ARGUMENTS` (`case "$ARGUMENTS" in *keep-video*) …`) and, after the generator
returns green, run the compiled test yourself with the flag:
`QA_KEEP_VIDEO=1 npx playwright test tests/checkout/coupon.spec.ts --retries=0 --reporter=line`,
then report the `.webm` path. The spec path still resolves cleanly: the resolver
takes the FIRST bare token as the path (`checkout/coupon`) and ignores any token
after it, so a trailing `keep-video` never corrupts the resolved path.
