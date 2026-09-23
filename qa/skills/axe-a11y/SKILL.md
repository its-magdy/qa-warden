---
name: axe-a11y
description: Compile an `a11y_violations_below` oracle into a settled, full-page @axe-core/playwright WCAG scan, or run the a11y half of a `/qa:review url=` live-page audit. Use when a spec's oracle declares that key (the planner declares it per meaningful UI state — post-login, cart-with-items, error dialog open — not per page), when auditing a live page, or when adding an adversarial-pair spec to prove the detector is live. Not for specs whose oracle does not declare it — an axe scan with no oracle item is an orphan assert. Catches ~30-40% of WCAG violations by success-criterion count, ~57% by issue volume; the rest needs a human.
user-invocable: false
disable-model-invocation: false
---

# axe-a11y

Drop-in accessibility scanner using `@axe-core/playwright`. `getByRole`/`getByLabel` make tests resilient to markup churn but give you **zero** WCAG coverage on their own — this skill fills that gap automatically and cheaply. (A green scan is **not** "accessible": automated scanners catch only ~30–40% of WCAG issues by success-criterion (~57% by issue volume) — see `reference/DESIGN.md` §"Honest limits".)

## When to use
- On **every meaningful UI state**, not every page. "Every state transition of a page" is the rule — e.g. cart empty, cart with items, cart at error. A single scan per page misses state-specific violations.
- When a spec's oracle declares `a11y_violations_below` — the generator compiles that key through this skill. An axe scan with no backing oracle item is an orphan assert (reviewer Check 2).
- When auditing an existing app (the `/qa:review url=<url>` command delegates here).

## How
No install needed — `@axe-core/playwright` already ships in the scaffolded `templates/package.json` (`/qa:init` installs it). Just import and use it.
Authoritative package: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright

Drop-in snippet (the whole skill in one test):
```ts
import { test, expect } from '../../fixtures/test';  // project fixtures barrel — standalone snippet, adjust the relative path
import AxeBuilder from '@axe-core/playwright';

test('cart with items has no critical a11y violations', async ({ page }) => {
  await page.goto('/cart');
  await page.getByRole('button', { name: 'Add to cart' }).click();
  await page.getByText('1 item in cart').waitFor();
  await page.waitForLoadState('load');                               // settle floor — see below; without it a
  await page.evaluate(() => document.fonts.ready.then(() => {}));    // real contrast failure can scan as 0 violations
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations.filter(v => v.impact === 'critical' || v.impact === 'serious')).toHaveLength(0);
});
```
**Settle the page BEFORE `analyze()` — every scan, including the DEFAULT post-navigation one.** axe measures the DOM/CSS exactly as it is the instant it runs; a scan fired before the page reaches a stable state silently **false-cleans** real *static* defects. The sharpest case is **color-contrast**: it depends on the finally-rendered font, and a web font that swaps in ~500 ms after navigation changes the computed text size/weight — and therefore the contrast ratio — so an immediate post-`goto` scan can report **0 violations** on a genuine contrast failure that only appears once the font loads (observed live, F-40). This is **not** limited to error/transition states — the default-state scan needs the settle too. Floor before every `analyze()`:
```ts
await page.waitForLoadState('load');
await page.evaluate(() => document.fonts.ready.then(() => {}));   // fonts resolved → contrast reflects real rendering. Return `.then(() => {})`, NOT `document.fonts.ready` bare: the promise resolves to a non-serializable `FontFaceSet`, so returning it bare makes `page.evaluate` throw on serialization (mirrors visual-regression/SKILL.md).
await expect(page.getByRole('heading', { name: /…/ })).toBeVisible();  // a real, stable anchor for THIS state
const results = await new AxeBuilder({ page }).analyze();
```
Prefer asserting the specific post-condition of the state you're scanning (`getByText('1 item in cart')`, the error alert visible) as the anchor — but `load` + `document.fonts.ready` is the minimum even for a plain default-state scan. **Never** settle with `waitForLoadState('networkidle')` (banned — top flake source; reviewer Check 5 FAILs it).

**Scope carefully — `.include()` NARROWS coverage, it is not a free "speed" knob.**
Default to a **full-page** scan. The header, nav, and footer are the most-reused
components in the app, so a violation there (an icon-only cart button with no
accessible name, an unlabeled hamburger) is the highest-impact one to catch — and
`.include('#main')` silently excludes exactly that chrome, so the scan passes green
over a real critical violation. Use `.exclude()` to drop only the widgets you
genuinely cannot fix (Stripe Elements, embedded maps); reach for `.include(region)`
**only** when the spec's oracle is explicitly scoped to that region.
```ts
// default: whole page, minus only the unfixable third-party widgets
const results = await new AxeBuilder({ page }).exclude('[data-third-party]').analyze();
```
Pick rulesets (default is WCAG 2.1 AA):
```ts
new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
```

## Adversarial-pair pattern
A scanner that never fails tells you nothing. For every axe-check spec, write a **sibling spec that deliberately breaks a label** (via `page.evaluate`, on a fixture page only) and asserts the violation IS detected. If the sibling ever passes, the detector is dead:
```ts
test('axe adversarial: broken label is detected', async ({ page }) => {
  await page.goto('/fixtures/a11y-broken');        // ship a deliberately-broken fixture
  await page.evaluate(() => {
    document.querySelector('button')!.removeAttribute('aria-label');
    document.querySelector('button')!.textContent = '';
  });
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations.some(v => v.id === 'button-name')).toBe(true);
});
```

## CRITICAL — human review required
> **AI-generated a11y fixes often satisfy the scanner without fixing the intent.** Claude will happily add `aria-label="button"` to a button that already had visible text, or `alt="image"` to a decorative image that should have `alt=""` — the scanner goes green, the screen-reader experience gets worse. A HUMAN with a screen-reader must review a11y fixes. Do not auto-merge scanner-pass diffs. (See `reference/DESIGN.md` §"Honest limits".)

## Gotchas
- Axe catches ~30-40% of WCAG success-criterion-count, ~57% by issue volume — not 100%. The rest (focus order, meaningful link text, screen-reader flow) is manual.
- Scanning every page without the state-transition rule inflates CI time without catching more bugs.
- Third-party widgets (Stripe Elements, embedded maps) generate violations you cannot fix; `.exclude()` them, don't suppress the rule globally.
- **Region-scoping (`.include('#main')`) is a coverage trap, not a speed setting.** It drops global chrome (header/nav/footer) from the scan, so a genuine critical violation there passes green. Scan the full page by default; scope only when the oracle is region-specific.
- `disableRules(['color-contrast'])` is a smell — if you are disabling critical rules to go green, you are gaming the scanner.
- **A green `violations` gate ≠ accessible — and it silently misses two common defects.** axe accepts a **placeholder as an accessible name** (an input with only `placeholder="Postal code"` passes the `label` rule) and accepts a **glyph as a button name** (an icon-only `✕` remove button passes `button-name`). Both are 0 violations while a screen-reader user is stuck. The one near-signal (color-contrast on a glyph-only control) lands in `results.incomplete` (needs-review), which a violations-only gate ignores. So: (1) when you need a signal, **surface `results.incomplete.length` / serious incomplete items** in the report, don't drop them; (2) when the intent is a **specific structural requirement** ("this input has an associated `<label>`", "this control has an accessible name"), do NOT rely on `a11y_violations_below` — assert it directly with a targeted `getByLabel('Postal code')` / `getByRole('button', { name: /remove/i })` `element_state` oracle, which resolves to nothing (RED) exactly when the label/name is missing.

## References
- `reference/DESIGN.md` §"Honest limits" (why a green a11y gate ≠ accessible).
- Package: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright
- Playwright a11y guide: https://playwright.dev/docs/accessibility-testing
