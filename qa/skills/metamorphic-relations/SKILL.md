---
name: metamorphic-relations
description: Generate 2-3 metamorphic-relation "twin" specs of a passing `.spec.ts`. Twins run on the nightly schedule and flag any twin whose outcome disagrees with the parent — catching specification drift that mutation testing cannot (mutation asks "does breaking code fail the test?"; MRs ask "does an invariant-preserving transform keep the output equal?"). A metamorphic-relation oracle-defense layer. Authored by the VERIFIER (Process step 8a — it has Write, and is independent of the generator that wrote the parent) right after a new spec's first green run; the read-only reviewer only VERIFIES the twins exist and agree.
user-invocable: true
disable-model-invocation: false
argument-hint: <parent-spec-path>
---

# metamorphic-relations

A metamorphic-relation oracle layer (the *why* is in `reference/DESIGN.md` §"Why the oracle defenses exist"). Mutation testing is intra-spec ("break the code → does the test fail?"); metamorphic relations are **cross-input** ("transform the input in an invariant-preserving way → does the output stay equal?"). MRs work without ground-truth answers, which makes them unusually well-suited to LLM-authored oracles.

Published work on metamorphic testing reports that MRs surface a **meaningful, double-digit share of defects that assertion-based tests miss** — the value is catching *specification drift* an example-based oracle can't see, not a single headline number. (Cite a specific paper only if you verify the id/venue first; don't pin a precise percentage to an unverified reference.)

## When to use
- After a new `.spec.ts` first goes green — the **verifier** (Process step 8a) authors 2-3 twins directly, following these patterns, and writes `tests/<area>/<feature>.metamorphic.spec.ts`. The read-only **reviewer** (Check 6) then verifies the file exists and its twins agree with the parent. (Twin *generation* lives with the verifier because the reviewer has no Write tool — a reviewer told to "generate twins" is a contradiction the toolkit used to ship.)
- When a human is hand-hardening a critical flow ("I don't fully trust this oracle — what invariants should hold?").
- As part of `/qa:review url=<url>` for compliance-critical specs.

**Do not use** as a replacement for the other oracle defenses. MRs **narrow** the wrong-specs gap but do not close it. The honest limit (see `reference/DESIGN.md` §"Honest limits"): if the human wrote a YAML that doesn't reflect the real business rule, no amount of MRs helps.

## Canonical MR patterns (e-commerce)
Use these as the template for domain-specific variants:
1. **Reorder-invariance** — Reorder items in cart → total unchanged, line-count unchanged.
2. **Round-trip identity** — Add-then-remove same item → cart state identical to pre-add.
3. **Returning sequence** — Change quantity 2 → 4 → 2 → total returns to original.
4. **Inverse operations** — Switch currency and back → total in base currency unchanged.

Domain variants (extrapolate):
- Auth: login → logout → login → session-state identical.
- Search: query `foo` → query `foo AND true` → result set identical.
- Sort: sort asc → sort desc → sort asc → order identical.
- Pagination: page 1 → page 2 → page 1 → same rows on page 1.

See Segura's MROP taxonomy (equivalence, subset, disjoint, complete, difference): https://dl.acm.org/doi/10.1145/3708521

## How
1. **Read the parent spec** — `.spec.ts` and paired `specs/<path>.md` YAML (especially the `oracle:` block — the same closed vocabulary applies to twins).
2. **Identify invariants** — what transformation can we apply to the inputs/actions that should NOT change the asserted output? Pick 2-3 from the canonical list + domain.
3. **Emit the twin file** — `tests/<area>/<feature>.metamorphic.spec.ts`. Each twin is a `test()` that:
   - Sets up the same prerequisite state as the parent (reuse fixtures).
   - Applies the invariant-preserving transform.
   - Reuses the parent's assertions (same closed-vocab oracle), checking that the result is equal / unchanged / restored.
4. **Tag** — every twin carries `@metamorphic` + the parent's **area/site** tags (e.g. `@checkout`, `@site:app`) **and `@regression`**, but **NOT `@smoke`**. Twins are heavier cross-input checks (multiple orderings, round-trips, returning sequences) that belong in the nightly regression lane — the same lane the disagreement rule below runs in. Tagging them `@smoke` inflates the fast smoke gate with slow tests and makes a "5/5 @smoke passed" count misleading (3 of them being twins). `--grep @metamorphic` remains their own lane regardless.
5. **Disagreement rule** — nightly reporting flags any twin whose pass/fail disagrees with the parent. Disagreement = a candidate spec bug (parent is under-specified) or a real defect (the invariant actually doesn't hold).

## Example — reorder-invariance twin
Parent asserts the checkout total for a two-item cart. Twin reorders the items and asserts the same total:
```ts
// tests/checkout/new-address.metamorphic.spec.ts
// Import from the PROJECT fixtures barrel (NOT '@playwright/test') so the twin reuses the
// parent's page-object fixtures + seeded state — "Fixture reuse is mandatory" (Gotchas).
// This STANDALONE snippet drives raw `{ page }` for illustration only — in a real suite the twin
// takes the parent's POM fixtures from the barrel (e.g. `async ({ cartPage })`) so it reuses the
// parent's flows and barriers.
import { test, expect } from '../../fixtures/test';

// Tags per step 4: @metamorphic + the parent's area/site tags + @regression (NOT @smoke).
// Structured `tag:` form — tags-in-title is the deprecated legacy form the reviewer flags.
test.describe('new-address', { tag: ['@metamorphic', '@checkout', '@site:app', '@regression'] }, () => {
  test('MR:reorder — total unchanged when items added in reverse order', async ({ page }) => {
    await page.goto('/products');
    // reversed order vs parent spec:
    await page.getByRole('button', { name: 'Add blue mug' }).click();
    await page.getByRole('button', { name: 'Add red t-shirt' }).click();
    await page.getByRole('link', { name: /^Cart/ }).click();
    // SAME assertion vocabulary as parent — value_between. In-policy getBy* locator
    // (testid here because the total is a bare value node with no role/label) — NEVER
    // raw CSS like page.locator('.order-total'): that fails the suite's own reviewer
    // Check 9 exactly as it would in the parent.
    const orderTotal = page.getByTestId('order-total');
    // WEB-FIRST CONTENT BARRIER before the read (see Gotchas). `toHaveText` RETRIES on
    // content, so it waits for the cart to settle on the deterministic total. `toBeVisible()`
    // only waits for *attach* — `order-total` is a persistent node whose text merely updates,
    // so reading `.textContent()` right after `toBeVisible()` captures the stale pre-re-render
    // value: the exact self-inflicted flake this skill's gotcha forbids. Settle, THEN read.
    await expect(orderTotal).toHaveText(/49\.98/);
    const total = Number((await orderTotal.textContent())!.replace(/[^0-9.]/g, ''));
    // INVARIANCE twin: a reordered cart must total the SAME known value as the parent.
    // Use a TIGHT band around that deterministic total (here the two-item cart is $49.98),
    // NOT a wide [49.00, 50.50] range — a loose band passes even if the reorder perturbed
    // the total, defeating the exact invariance this MR exists to prove.
    expect(total).toBeGreaterThanOrEqual(49.98);
    expect(total).toBeLessThanOrEqual(49.98);
  });

  // Second twin — the example must ship ≥2 (step 4 / reviewer Check 6 FAIL a
  // metamorphic file with fewer than two `@metamorphic` twins).
  test('MR:add-then-remove — total returns to the single-item value after a round-trip', async ({ page }) => {
    await page.goto('/products');
    await page.getByRole('button', { name: 'Add red t-shirt' }).click();
    await page.getByRole('button', { name: 'Add blue mug' }).click();
    await page.getByRole('link', { name: /^Cart/ }).click();
    // Remove the mug — a round-trip that must land back on the one-item total.
    await page.getByRole('button', { name: /Remove blue mug/ }).click();
    const orderTotal = page.getByTestId('order-total');
    // Web-first CONTENT barrier (Gotchas) — settle on the deterministic single-item total
    // before reading; `toBeVisible()` would let the stale pre-remove total through.
    await expect(orderTotal).toHaveText(/19\.99/);
    const total = Number((await orderTotal.textContent())!.replace(/[^0-9.]/g, ''));
    // TIGHT band around the deterministic single-item total ($19.99), NOT a loose range.
    expect(total).toBeGreaterThanOrEqual(19.99);
    expect(total).toBeLessThanOrEqual(19.99);
  });
});
```
The twin MUST use the same oracle vocabulary as the parent (`text_visible`, `value_between`, `count_equals`, ...). Out-of-vocab here fails the reviewer Check 4 just like in the parent.

## Scope boundary
- **Orthogonal to mutation testing** — mutation is intra-spec, MRs are cross-input; they answer different questions and do not replace each other. **But there is NO shipped mutation gate for browser `.spec.ts`** (see `reference/DESIGN.md` §"Honest limits"): Stryker covers **pure-TS units only** (helpers/reducers/factories that run in Node), and the agent-driven browser-mutation skill was removed to stay lean. So for a browser spec, **MRs are the only shipped cross-input oracle layer** — do not go hunting for a browser mutation runner; `must_fail_when:` (advisory, verified at authoring by the verifier's step 8b) is the closest thing.
- **Narrow but not closing** — MRs catch specification *incompleteness* (the spec missed an invariant), not specification *wrongness* (the spec encodes the wrong rule). No oracle layer fixes wrong specs.
- **Cheap to pilot** — 2-3 twins per critical flow, nightly-scheduled, low maintenance.

## Gotchas
- **Twin-parent disagreement ≠ always-a-bug** — sometimes the MR is wrong (the invariant you thought held, doesn't). Treat a disagreement as a ticket, not an auto-fail.
- **Do not invent invariants with no basis** — if you can't name the business reason the transform is invariant-preserving, do not emit the twin.
- **Fixture reuse is mandatory** — a twin that re-seeds independently will drift from the parent and give false signals.
- **A separate-file twin RACES a global-mutating parent** — `mode: 'serial'` serializes tests *within one file*, NOT across files, so under `fullyParallel: true` a `.metamorphic.spec.ts` twin runs on a different worker than its parent; if both mutate the same global, non-per-worker-isolable resource (same cart/session, same product stock, same reset endpoint) they clobber each other — green alone, flaky together. For such a spec do NOT emit a separate twin file: encode the relation as an **`mr:` block on the parent spec** instead (verifier §8a skips separate-file twins for `mr:` specs; reviewer Check 13 flags the cross-file race). Separate twin files are only safe when the flow is per-worker isolated (worker-scoped seed/account) or read-only. **Playwright 1.63+ does ship a cross-file primitive — `test lock:` — and it is still not the answer for a twin:** folding removes the contention where a lock only schedules around it, and a lock is shard-blind (the shard filter never consults it) where the fold holds under any shard layout. `lock:` belongs to the cross-FEATURE mutator/consumer case in reviewer Check 13.
- **Barrier before every read and navigation** — after a state-changing action (add/remove item, change quantity), assert the new state with a **web-first** expectation (`await expect(cart.total).toHaveText('$79.99')`) BEFORE reading a value with `.textContent()` or calling `goto()`. `.textContent()` resolves as soon as the element is *attached* and does **not** retry on content, so reading it right after an async re-render captures the *stale* value; and a full-page `goto()` can race a `localStorage`/state flush. The twin reuses the parent's flow, so reuse the parent's barriers too — a twin is the one place a dropped `await expect(...)` turns into an intermittent, self-inflicted flake.

## References
- `reference/DESIGN.md` §"Why the oracle defenses exist" (MRs as an oracle layer) + §"Honest limits".
- LLMorph / ACM TOSEM survey: https://arxiv.org/abs/2511.02108
- MROP taxonomy (Segura): https://dl.acm.org/doi/10.1145/3708521
