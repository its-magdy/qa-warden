---
name: visual-regression
description: Add Playwright `toHaveScreenshot()` assertions to catch layout/CSS/typography regressions that text oracles miss. Use in `/qa:review url=` live-page audits (`tests/_audit-<slug>.spec.ts` probes) and when a human is hand-hardening a visually-meaningful flow outside the managed spec contract — a designer reports "something looks off," or the closed oracle vocabulary cannot capture the regression class. Not for generated specs, where a screenshot expect has no oracle key and reviewer Check 2 flags it as an orphan. Not a replacement for Applitools visual-AI at scale — a cheap self-hosted layer that catches the obvious.
user-invocable: false
disable-model-invocation: false
---

# visual-regression

Screenshot-diff oracle. Catches the layout/CSS/typography bug class that `text_visible` + `count_equals` cannot see.

## When to use
- Each "meaningful UI state" in a spec — not every page, but every **state transition** worth a snapshot (post-login dashboard, cart with 2 items, error banner visible, checkout success).
- Whenever a bug report says "something looks wrong" but the text/DOM is fine.
- Outside a managed spec's assertion contract — a screenshot assert has no closed-vocab oracle key, so reviewer Check 2 treats it as an orphan expect. Keep it to `/qa:review url=` audits (`tests/_audit-<slug>.spec.ts`) and human hand-hardening.

**Do not use** as the sole oracle — visual diffs without a semantic assertion are the classic "green-but-empty" trap flipped upside down (red-but-meaningless). And do not use this skill for high-volume UI-heavy apps — pair with Applitools / Chromatic / Percy / Argos at that point (Applitools' 1B+ training images is a genuine moat you cannot self-host — see `reference/DESIGN.md` §"Honest limits").

## How
Playwright's built-in `toHaveScreenshot()` stores baselines under `tests/<spec>.spec.ts-snapshots/` by default — that default is fine. Optionally override the path to land them under `artifacts/visual/<testname>.png` if you want them in the artifact tree (`skills/review/SKILL.md`'s URL-audit mode treats this as an optional override, not a requirement).

Every snapshot call must be preceded by a **stable-state wait** — the #1 source of visual flakes:
1. **Wait on a web-first assertion for the state you're snapshotting** — `await expect(page.getByRole('heading', { name: 'Order confirmed' })).toBeVisible()` (or the spinner *gone*: `await expect(page.getByTestId('spinner')).toBeHidden()`). **Do NOT use `await page.waitForLoadState('networkidle')`** — it is officially discouraged (there is an `eslint-plugin-playwright/no-networkidle` rule) and the healer bans it: on any app with analytics beacons, websockets, or polling it either never resolves or hangs unpredictably. Wait on the actual application-visible readiness signal, which is what the screenshot depends on anyway.
2. `await page.evaluate(() => document.fonts.ready.then(() => {}))` — webfonts loaded. **Return `.then(() => {})`, not `document.fonts.ready` bare:** the promise resolves to a `FontFaceSet`, which is non-serializable, so returning it bare makes `page.evaluate` throw on serialization. The `.then(() => {})` resolves to `undefined` (serializable) while still awaiting fonts. (Do NOT "simplify" to `page.waitForFunction(() => document.fonts.ready)` — a promise is always truthy, so it returns immediately *without* waiting for fonts.)
3. Disable animations. The stamped `playwright.config.ts` **already ships** `reducedMotion: 'reduce'` globally — under **`contextOptions: { reducedMotion: 'reduce' }`**, NOT a top-level `use: { reducedMotion }` (that form fails Playwright's `TestOptions` typecheck; the config comments this). So it's on by default; override per-test via `page.emulateMedia({ reducedMotion: 'reduce' })` only if a specific spec needs different motion behavior.
4. If you have known-animated elements (spinners, marquees), mask them: `{ mask: [page.getByTestId('spinner')] }`.

## Examples
Minimal pattern:
```ts
import { test, expect } from '@playwright/test';  // standalone snippet — in a real spec import from '../../fixtures/test' (the project fixtures barrel)

test('checkout confirmation looks right', async ({ page }) => {
  await page.goto('/checkout/success?order=1234');
  // web-first readiness wait — NOT networkidle (discouraged / healer-banned):
  await expect(page.getByRole('heading', { name: /thank you|order confirmed/i })).toBeVisible();
  await page.evaluate(() => document.fonts.ready.then(() => {}));  // resolve to void — a bare FontFaceSet is non-serializable
  await expect(page).toHaveScreenshot('checkout-success.png', {
    maxDiffPixels: 100,
    mask: [page.getByTestId('order-timestamp')],
  });
});
```
Baseline management:
```bash
# Intentional baseline update (after an approved design change):
npx playwright test --update-snapshots checkout.spec.ts
# Review the diff, commit the new PNG alongside the spec change.
```
CI-only tolerance (font rendering differs across platforms — pin the runner OS or run visual diffs on Linux only):
```ts
await expect(page).toHaveScreenshot('hero.png', {
  maxDiffPixels: 50,
  threshold: 0.2,             // per-pixel color tolerance
});
```

## Gotchas
- **OS-dependent rendering:** a macOS-authored baseline will diff-fail on Linux CI. Run visual diffs on one platform only (Linux CI runner), or keep OS-specific baselines.
- **maxDiffPixels vs threshold:** `threshold` is per-pixel color delta (0–1); `maxDiffPixels` is the integer cap on diffed pixels. Set both, tune `maxDiffPixels` per test.
- **Dynamic content** (timestamps, random IDs, avatars, CSRF tokens) — mask with `{ mask: [...] }` or stub in a fixture. Do not "just accept" the baseline churn.
- **Baseline rot:** unreviewed `--update-snapshots` is how visual regression becomes rubber-stamp. Require diff-review in PR.
- **Not a replacement** for visual-AI (Applitools) — self-hosted Playwright diffs catch the obvious; the long tail (perceptual, cross-viewport, cross-browser) needs a specialist (`reference/DESIGN.md` §"Honest limits").

## References
- `reference/DESIGN.md` §"Honest limits" (why self-hosted diffs need a specialist for the long tail).
- Playwright docs: https://playwright.dev/docs/test-snapshots
- Specialist pairings: Applitools, Chromatic, Percy, Argos.
