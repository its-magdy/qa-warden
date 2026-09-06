import { test as base, expect } from "@playwright/test";

// Re-export Playwright's core types from the barrel so specs and helpers can
// `import { test, expect, type Page } from "../fixtures/test"` in one line.
export type { Page, Locator, TestInfo } from "@playwright/test";

/**
 * The fixtures barrel. Specs import { test, expect } from HERE, never from
 * "@playwright/test" directly — that's what lets every spec get isolated state and
 * ready-to-use page objects without calling `new`.
 *
 * This is the BASE barrel a fresh project starts with (only Playwright's built-ins).
 * As the generator promotes a repeated flow into a page object under
 * `page-objects/<area>/<page>.page.ts`, it adds a fixture here, one per object:
 *
 *   import { LoginPage } from "../page-objects/auth/login.page";
 *   type Fixtures = { loginPage: LoginPage };
 *   export const test = base.extend<Fixtures>({
 *     loginPage: async ({ page }, use) => { await use(new LoginPage(page)); },
 *   });
 *
 * Then a spec reads:  test("...", async ({ loginPage }) => { await loginPage.login(...) })
 *
 * Page objects hold SEMANTIC locators (getByRole/getByLabel/getByTestId) validated live
 * at generate time — see CLAUDE.md §"Page-object reuse layer (POM)". A shared flow that
 * changes is then fixed in ONE page object (the healer's highest-leverage move), not in
 * every spec that uses it.
 *
 * Data fixtures (worker-scoped, API-seeded) come from the test-data-seed skill + the Zod
 * factories under fixtures/factories — keep those separate from page-object fixtures.
 */
export const test = base;

export { expect };
