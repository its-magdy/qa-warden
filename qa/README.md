# qa — AI-authored, Playwright-replayed E2E QA

A Claude Code plugin that turns plain-language specs into a deterministic Playwright
end-to-end suite. **AI authors the specs and tests; Playwright replays them nightly at
$0 LLM cost; AI is invoked again only to triage a failure.** Shared UI flows live in an
AI-maintained page-object layer, so a flow change is a one-file fix.

**New here?** Start with the **[first-test tutorial](reference/tutorial-first-test.md)** (author one
test end to end), and keep the **[glossary](reference/glossary.md)** open for any unfamiliar term.

## The authoring workflow

```
/qa:init                     once per project — stamp the runtime substrate, then edit .env
   ↓
/qa:explore                  build specs/_context/app.context.md (sites, auth, env, naming)
   ↓   ── decide WHAT to test ──
/qa:intake  <area/feature>   interview → the test basis (what "correct" means — the oracle)
/qa:ideate  <area/feature>   SFDIPOT checklist of candidate cases  ← a HUMAN approves/prunes
/qa:approve <area/feature>   record the human verdict (approve/prune/defer; mints row ids)
   ↓   ── build the tests ──
/qa:new-spec <area/feature>  draft one Markdown spec + closed-vocab YAML oracle
/qa:gen      specs/<f>.md    compile the spec → tests/<f>.spec.ts, run it green
   ↓
/qa:review   [spec-or-diff]  reviewer gates the assertion contract (run on every PR)
   ↓
/qa:run mode=smoke           run the @smoke suite (no LLM)
   ↓   on failure
/qa:heal <test-id>           triage from the trace; patch selectors/waits, never assertions
```

The intake → ideate → approve stretch is the **rigor lane** (P1/money/compliance — it pins
what correct means before anything is generated); the **fast lane** goes straight from
explore to new-spec and skips no FAIL-level gate.

`/qa:report` aggregates a run into a PR/Slack-ready summary. The full command catalog and a
"where am I / what's next" read of your project are always available from **`/qa:help`**.

## The cost model

Running an LLM is the expensive part of an AI-driven test, so we only do it where it is
irreplaceable — **authoring** a spec and **triaging** a failure. The nightly regression run
is plain `npx playwright test`: deterministic, no agent in the loop, **~$0 LLM cost**.
Generate once, replay forever; the healer runs *only* on a red test, never on a green build.
That takes a 100-test nightly suite from thousands of dollars a month (pure-agentic) to
roughly $5–50. The same split bounds what leaves your machine: pages the agents visit
transit the API during authoring/triage only, and the nightly sends nothing — see
`DOCUMENTATION.md` §15.1 "Privacy & data flow" in the marketplace repo (the repo this
plugin installs from; the file is not shipped inside the installed plugin).

## What it can't do

This stack is **E2E / integration tests against a real browser, only.** It is not for:

- unit / component / contract tests (keep those in the product repo — Vitest/Pact),
- performance or load testing (k6/Locust),
- security DAST (ZAP/Burp),
- native mobile — Playwright does not drive iOS/Android.

Automated a11y and visual checks are included but are **partial** oracles: a green a11y scan
is not "accessible," and self-hosted visual diffs need a specialist for the long tail. See
`reference/DESIGN.md` §"Honest limits" for the full set of concessions.

## Learn more

- **[`reference/tutorial-first-test.md`](reference/tutorial-first-test.md)** — author your first test, step by step (start here).
- **[`reference/glossary.md`](reference/glossary.md)** — every term this plugin uses, defined once.
- **[`reference/reviewing-without-code.md`](reference/reviewing-without-code.md)** — for the non-coder who signs off: judge AI-written tests by their oracle + video, and the gates that stop for a human.
- **[`reference/how-to.md`](reference/how-to.md)** — goal-titled recipes: import manual cases, fix a failing test, brownfield adoption, nightly CI, add rigor to a P1 flow.
- **`/qa:help`** — everything else: what each command/agent/skill does, and what to run next.
- **`DOCUMENTATION.md` (marketplace repo root)** — the full written reference for humans and
  agents (visual companion: `DOCUMENTATION.html`). Lives beside the plugin in the repo it
  installs from — installed plugins can't reference files outside their own directory, so
  read it on the repo, not via a `../` path.
- **`reference/DESIGN.md`** — the design rationale (the *why* behind the cost model, the
  oracle defenses, and the CLI-vs-MCP split).
- **repo root `README.md`** — how the plugin is packaged and installed from the marketplace.
