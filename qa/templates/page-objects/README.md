# page-objects/ — the reuse + maintainability layer (POM)

Shared UI interactions live here, **not** inlined into every spec. This is what makes a
shared-flow change a **one-file fix** instead of an N-test grind.

```
page-objects/<area>/<page>.page.ts          one class per page: semantic locators + actions
page-objects/<area>/components/<widget>.ts   reusable widget (modal, nav, table)
```

## The rules (enforced by the generator, healer, and reviewer)

1. **Semantic locators only** — the 7 `getBy*` factories (`getByRole`, `getByLabel`,
   `getByTestId`, …). **No CSS, no XPath, ever.** The reviewer's Check 9 fails a page object
   that holds a raw selector — that's the exact thing that makes a POM layer rot.
2. **Live-validate, then centralize.** The generator pulls the live AX tree
   (`playwright-cli snapshot`) to validate a locator at compile time, then writes it into the
   page-object method. A semantic locator in one file is *not* a stale cached snapshot — it's
   the same locator you'd write inline, just in one place. (Resolves the "never cache locators"
   tension — see CLAUDE.md.)
3. **Actions in the user's language.** `login(email, pw)`, `addToCart(sku)` — not selector
   plumbing. Page state checks are `expect*` helper methods.
4. **No oracle drift.** A page object's `expect*` helpers assert exactly what a spec's
   `oracle:` dictates. Never add or weaken an assertion in a page object to make a flow pass —
   assertion drift is drift wherever it lives (the reviewer catches it).
5. **Earn the abstraction.** Promote a flow when it is **inherently reusable** (login, checkout,
   a shared widget — promote on first write) OR when it has **appeared 2–3 times**. A one-off,
   single-use flow is premature abstraction — the reviewer WARNs on it.

## Who writes here

- **generator** — runs **serially in the main tree**, so during authoring it both CREATEs new
  page objects AND updates existing ones. When it finds a flow already inlined in another spec,
  it extracts it and updates both call sites (serial → no cross-generator conflict).
- **healer** — OWNs page-object edits during *maintenance* (when a nightly run goes red). When a
  shared locator breaks, it fixes the one method and re-runs every consumer. This is the reuse
  payoff for maintenance.

Wire every page object into `fixtures/test.ts` so specs never call `new`.
