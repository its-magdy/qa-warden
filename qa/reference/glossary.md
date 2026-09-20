# Glossary

The words this plugin uses, defined once. This is the **single source of truth** for
terminology — other docs link here rather than re-defining. If a doc uses a term a
different way, that doc is wrong; reconcile it to this page.

> New here? Read the **[first-test tutorial](tutorial-first-test.md)** first — it shows
> most of these terms in action before you need the definitions.

---

**area** — a product area, the folder your specs group under (`specs/<area>/…`). Examples:
`auth`, `tasks`, `checkout`. One `area` maps to one specialist-context file
(`specs/_context/<site>/<area>.md`).

**assertion contract** — the set of oracle assertions in a spec, owned by the planner. It is
*sacred*: the healer may patch locators but may **never** weaken or change what a test asserts.

**basis** (test basis) — the plain-language record of *what "correct" means* for one
feature, captured by `/qa:intake` into `<feature>.basis.md`. Its rules (marked with a 🔵 in
the basis) **are** the oracle — the spec's assertions trace back to them. Think "the contract
the feature must honor."

**brain / body** — the two halves of the plugin. The **brain** is the plugin-shipped config
(agents + skills) — auto-updates on `/plugin update`. The **body** is the per-project
runtime files `/qa:init` stamps (config, scripts, `CLAUDE.md`) — updated with `/qa:init --resync`.
A plugin fix reaches the brain automatically; the body doesn't move until you resync.

**case** — one candidate test scenario on the checklist `/qa:ideate` produces
(`<feature>.cases.md`). A human approves/prunes cases before any test is written. A case
becomes a scenario in the spec.

**closed vocabulary** — the fixed set of **16 oracle keys** an assertion is allowed to
use (`text_visible`, `network_response_status`, `value_between`, …). "Closed" = you cannot
invent a new one; the reviewer FAILs an out-of-vocab assertion. This is what stops
free-form "should look right" checks. *(Short form sometimes seen: "closed-vocab" — prefer
the full term.)*

**context** — a file describing what the AI found in your app, so it doesn't guess later.
Two kinds: the **hot** context `specs/_context/app.context.md` (sites, auth, naming — written
by `/qa:explore`) and per-area **specialist** context `specs/_context/<site>/<area>.md`
(routes and vocabulary for one area). A third **cold** tier is the live page snapshot taken at
generate time — where selectors actually come from; nothing selector-level is cached in the files.

**fast lane** — the quick path from `/qa:explore` straight to `/qa:new-spec`, skipping the
rigor lane. Skips no FAIL-level gate; used for lower-risk features. Contrast **rigor lane**.

**green-but-empty / green-but-wrong** — a test that passes while *not actually checking* what
it claims (empty), or checking the *wrong* value (wrong). The central failure mode the whole
toolkit defends against — see [reviewing-without-code.md](reviewing-without-code.md).

**healer** — the subagent invoked **only on a failing test**. It reads the trace, and
either patches the locator/wait or files a bug — **it never changes what the test
asserts**. Think "a teammate that fixes the plumbing, not the contract."

**locator** — the way a test step finds an element on the page ("the button named Sign in",
"the field labelled Email"). Playwright's word for a selector. When the UI shifts, the healer
repairs the locator; it never touches what the test *asserts*.

**metamorphic twin** (twin) — an extra test the verifier writes that changes the input in
a way that *shouldn't* change the outcome (reorder a cart, add-then-remove) to catch a spec
that's silently wrong. The reviewer verifies twins exist and agree with the parent.

**must_fail_when** — a list, in the spec, of the specific defects the test **must** catch.
The **verifier** — a different agent from the one that wrote the assertion — injects each
defect at authoring time and refuses to ship an oracle that doesn't go red on it, so a
declared invariant can't silently evaporate.

**oracle** — the spec's definition of "correct": the assertions, written in the closed
vocabulary. The oracle is *what* the test checks; the steps are *how* it gets there. The
whole plugin exists to keep the oracle honest (present, actually able to tell right from
wrong, and checking the right value).

**page object (POM)** — a reusable file (`page-objects/<area>/<page>.page.ts`) holding a
shared UI flow (login, checkout) so a change to that flow is a one-file fix, not an
N-test grind. The verifier writes them; the healer maintains them.

**Playwright** — the open-source browser-automation framework the compiled tests run on and
replay nightly. You never write it — the AI does; it's named in these docs only because that's
what runs under the hood.

**reviewer** — the read-only gatekeeper subagent that blocks a merge when the assertion
contract is violated (a step with no assertion, an assertion checking the wrong value, an
out-of-vocab key…). No hooks ship, so the reviewer *is* the enforcement — run it on every PR.

**rigor lane** — the fuller path that inserts `/qa:intake` → `/qa:ideate` → `/qa:approve`
before `/qa:new-spec`, pinning *what correct means* before anything is generated. Use it
for P1 / money / compliance features. Contrast **fast lane**.

**route manifest** — a per-spec record of the routes/fields/factories a test touches
(`artifacts/route-manifests/`), emitted by the verifier once a spec passes verification — so a
spec with no manifest is one that did not ship. It powers `/qa:impact` (which specs a
change would affect).

**run-of-record** — the one authoritative test run whose results (`artifacts/last-run.json`)
`/qa:report` reads. Verification/heal re-runs deliberately do **not** overwrite it, so a
side run can't masquerade as the real result.

**sentinel** — a small marker file (`artifacts/.healer-needs-*`) the healer drops when it
needs the orchestrator to do something (re-explore a stale area, re-seed auth) before it can
continue. The loop closes when the orchestrator acts on it.

**SFDIPOT** ("San Francisco Depot") — the seven test-design lenses from James Bach's
Heuristic Test Strategy Model. `/qa:ideate` rotates through these seven **plus
error-guessing** (an eighth heuristic the toolkit adds) — **8 lenses in total**, which is
the count `/qa:coverage` (`<k>/8`), the `cases.md` template, and `ideation.md` all use:

| Lens | Asks | Example (editing a task) |
|---|---|---|
| **S**tructure | what is it *made of*? | the modal, its fields, the Save button |
| **F**unction | what does it *do*? | it updates the task's title/status |
| **D**ata | what does it *handle*? | title at 120 vs 121 chars; empty; unicode |
| **I**nterfaces | what does it *connect to*? | the `PATCH /api/tasks/:id` call |
| **P**latform | what does it *depend on*? | browser, viewport, the logged-in role |
| **O**perations | how is it *used*? | a member editing their own vs another's task |
| **T**ime | what about *timing/sequence*? | two edits racing; edit after delete |
| *Error-guessing* (8th) | where would a *bug likely hide*? | off-by-one on the 120-char limit; double-submit; stale token |

Spelling it out matters: a lens left empty is a coverage gap the checklist surfaces.
(SFDIPOT proper is the first seven; error-guessing is the eighth lens the toolkit rotates —
so the toolkit's count is **8**, not 7.)

**site** — one deployed app under test, addressed by `BASE_URL_<SITE>` (e.g. `BASE_URL_APP`,
`BASE_URL_ADMIN`). A project can test several sites; each gets its own Playwright project.

**smoke** — the fast nightly gate. Tests tagged `@smoke` are what `/qa:run mode=smoke` runs; the
primary happy-path of a critical feature must be `@smoke`.

**spec** — the human-readable Markdown contract in `specs/<area>/<feature>.md` (prose +
a fenced YAML oracle block). AI writes it; a human can read it. Not the compiled test — see
**test**.

**test** — the compiled Playwright file in `tests/<area>/<feature>.spec.ts` that Playwright
actually replays nightly. Generated from the **spec**. (Rule of thumb: *spec* = Markdown you
read, *test* = TypeScript Playwright runs.)

**trace** — a recorded, step-by-step replay of a test run — DOM snapshots, network, console,
a screenshot at each step — that you open in a browser at
[trace.playwright.dev](https://trace.playwright.dev) with no install. It's how a non-coder
*sees* what a failing test did, without reading the test code.
