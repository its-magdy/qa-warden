---
name: test-data-seed
description: Build worker-scoped, API-seeded, teardown-by-tag test fixtures that are parallel-safe at 10+ workers. Use whenever a spec needs a user, order, org, or any writeable resource — UI-seeded and hardcoded-email patterns collide immediately at parallel scale. Invoked during generator authoring or when a flake post-mortem traces to data collisions across workers.
user-invocable: false
disable-model-invocation: false
---

# test-data-seed

Parallel-safe test data seeding. The canonical rule: worker-scoped fixtures keyed on `workerInfo.parallelIndex`, API-seeded never UI-seeded, teardown-by-tag never by name matching.

> **Two distinct layers — do not conflate (this skill owns the second):**
> - **`fixtures/factories/<entity>.ts`** — *pure data generators* (`makeUser()` via `zod-fixture`). Return a plain object; no browser, no API, no teardown. Referenced from a spec's `data:` block via the `factory:` form. Owned by the schema/factory layer.
> - **`fixtures/seed/<entity>.seed.ts`** — *worker-scoped Playwright seed fixtures* (what THIS skill emits). API-seed a real resource per worker slot and tear it down. Wired into `fixtures/test.ts` and consumed as a fixture (`async ({ seededUser }) => …`), NOT via the `data:` block.
> A seed fixture typically **calls** the data factory to build its payload, then POSTs it. Keep them in separate files with separate names so the `makeUser()` generator and the `seededUser` fixture never collide.

## When to use
- Any spec that writes: login as a fresh user, create an order, provision an org, upload a file.
- Anytime a spec hardcodes `alice@example.com` (the §8 example does this deliberately as a teaching anti-pattern — it will collide at 10 workers).
- When a flake post-mortem groups failures by "same user / same timeslot / resource already exists."

## The five rules
1. **Worker-scoped fixtures keyed on `workerInfo.parallelIndex`** — stable across retries. In a `{ scope: 'worker' }` fixture the third callback arg is **`workerInfo`** (`WorkerInfo`), NOT `testInfo` — a worker fixture never receives `testInfo`, so `testInfo.parallelIndex` there is an undefined-binding bug. Both carry `.parallelIndex`; bind it off `workerInfo` in a worker fixture.
2. **One tenant/user/org per worker slot**, seeded once per worker, torn down in fixture teardown.
3. **API-seeded, not UI-seeded** — UI seeding is the #1 cross-worker collision source (flaky form, flaky auth redirect, flaky DB latency all stack).
4. **Teardown-by-tag** (`tag:test-run-{runId}`), never by name matching. Tag every seeded resource; the teardown deletes every row with that tag regardless of what the test named it.
5. **Teardown lives in the FIXTURE (after `use()`), never `afterEach`** — a fixture teardown runs even when setup or the test fails; `afterEach` is skipped on a `beforeEach` crash, leaking exactly the rows a failed run creates. And keep the frame honest: unique-per-worker creation AT SETUP is the isolation guarantee; teardown is best-effort bloat control, never correctness.

## Why `parallelIndex`, not `workerIndex`
`workerIndex` is assigned when a worker process spawns and **changes on retry** — a retried test gets a different `workerIndex` and will collide with the first attempt's fixture. `parallelIndex` is the slot (0..N-1 where N = configured workers) and is **stable across retries**. Always use `parallelIndex`.

## Example — parallel-safe user seed fixture
```ts
// fixtures/seed/user.seed.ts  (a worker-scoped SEED FIXTURE — distinct from the
// pure make<Entity>() generator in fixtures/factories/<entity>.ts, which the
// generator creates on demand from the real model; this one API-seeds & tears
// down. Merge this extend into fixtures/test.ts so specs get { seededUser }.)
import { test as base } from '@playwright/test';
import { randomUUID } from 'node:crypto';

type Fixtures = { seededUser: { email: string; password: string; id: string; token: string } };

export const test = base.extend<{}, Fixtures>({
  seededUser: [async ({}, use, workerInfo) => {
    const runId = process.env.QA_RUN_ID ?? 'local';
    const slot = workerInfo.parallelIndex;
    const email = `qa+slot${slot}-${randomUUID().slice(0, 8)}@example.test`;
    const password = randomUUID();

    // API-seeded, not UI-seeded:
    const res = await fetch(`${process.env.API_URL}/admin/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.QA_ADMIN_TOKEN}` },
      body: JSON.stringify({ email, password, tags: [`test-run-${runId}`, `slot-${slot}`] }),
    });
    if (!res.ok) throw new Error(`seed failed: ${res.status}`);
    const user = await res.json();

    // Expose the session token so a UI spec can inject it before hydrate (see
    // "Bridge the API-seeded identity" below). If your create-user endpoint doesn't
    // return one, log in with { email, password } here and capture it instead.
    await use({ email, password, id: user.id, token: user.token });

    // Teardown-by-tag, not by email:
    await fetch(`${process.env.API_URL}/admin/users?tag=test-run-${runId}&slot=${slot}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${process.env.QA_ADMIN_TOKEN}` },
    });
  }, { scope: 'worker' }],
});
```

## The seed adapter — parameterize auth scheme + teardown, don't assume them
The example above hardcodes **`Authorization: Bearer ${QA_ADMIN_TOKEN}`**, a `POST /admin/users` endpoint, a `tags:[…]` body field, and **teardown-by-tag via `DELETE …?tag=`**. **Real seed APIs almost never match that exact shape** — a real app in the wild needed `x-test-seed-token: <token>` (not Bearer), `POST /api/test/users` with server-**generated** emails (the client can't choose the email), and had only a destructive **global** reset (no per-tag delete). Treating the template as a fixed contract makes the generator either mis-seed or give up. Instead, factor the *variable* parts into a small **adapter** and keep the five rules' invariant core (worker-scoped, API-seeded, tag-isolated, parallelIndex-keyed, teardown-in-fixture):

```ts
// fixtures/seed/adapter.ts — the ONLY place app-specific seed wiring lives.
export interface SeedAdapter<T> {
  auth(): Record<string, string>;                 // e.g. { Authorization: `Bearer ${T}` } OR { 'x-test-seed-token': T }
  create(payload: unknown): Promise<T>;           // POST to the app's real seed endpoint; return the created resource
  teardown(handles: T[]): Promise<void>;          // delete-by-tag if supported; else delete-by-id the handles you created; NEVER a global truncate
}
```
- **Auth scheme is a parameter, not `Bearer`.** Read the real header from `specs/_context/<site>/<area>.md` (exploration records the seed API's auth) — `x-test-seed-token`, `Bearer`, a signed cookie, basic-auth — and return it from `auth()`. Do not assume `Bearer`.
- **Endpoint + payload shape are parameters.** Some APIs generate the email/id server-side (you get it back from the response), some accept a client-chosen one. `create()` returns the *actual* created resource so teardown can target it.
- **Teardown strategy degrades gracefully.** Prefer delete-by-tag (rule 4). If the app has no tag filter, fall back to **delete-by-id the specific handles this worker created** — track them and delete exactly those. **Never** fall back to a global `POST /api/test/reset`/truncate in teardown: it is cross-worker-unsafe under `fullyParallel`, wipes rows other workers are mid-test on, and is blocked by the command harness as a mass-delete. If neither by-tag nor by-id teardown is possible, that is an **escalation to the caller**, not a reason to wire the destructive reset.
- The `env` (`API_URL`, admin token, `QA_RUN_ID`) the example reads must be **declared in `.env.example`** so a fixture authored from this skill doesn't POST to `undefined/admin/users` with `Bearer undefined`. If they're absent, add them (or the app's real equivalents) when you wire the adapter.
- **A throwaway signup password is still a credential — env-source it or annotate it (F-10).** When the seed fixture signs up an ephemeral account it needs a password; do NOT inline a bare literal like `const password = "Passw0rd!"` — it contradicts the `password_env` discipline the rest of the suite enforces and reads as a leaked secret to the reviewer's hardcoded-credential scan (Check 10). Prefer resolving it from env (`process.env.QA_SEED_PASSWORD ?? process.env.QA_USER_PASSWORD`); if a literal is genuinely unavoidable for a throwaway account, annotate it `// non-secret throwaway — ephemeral account created + deleted within this test` so the reviewer's negative-fixture carve-out recognizes it. It's non-secret by nature (the account is destroyed in teardown), but it should never *look* like an inlined real credential.
- **The seed `API_URL` host MUST be non-prod, and is now screened by prod-guard (B-3).** This path CREATES and DELETES real records; a mis-set `API_URL=https://prod…` with a real admin token would seed/delete production rows. Both prod-guard layers (`scripts/prod-guard.sh` + the enforced `scripts/prod-guard.ts` globalSetup) now word-boundary-match `prod`/`production` over `API_URL` / `*_API_URL` in addition to `BASE_URL_*` — so a prod-marked API host is refused before the suite runs. Residual limit (same as BASE_URL): a prod API with no telltale name (`api.acme.com`) can't be auto-detected — keep `API_URL` on staging/QA explicitly. The global-truncate ban (above) and this per-host guard are complementary: one stops mass-delete, the other stops any create/delete against a prod host.

## Wiring: compose with `mergeTests`, and get the seeded identity into the browser
Two steps the example above leaves implicit — both are load-bearing and both were
*invented from scratch* the first time a real mutating UI spec used this skill:

- **Compose with `mergeTests`, not a re-`extend` chain.** When `fixtures/test.ts` already
  has a POM `base.extend<PomFixtures>({...})`, do **not** re-`extend` that with the seed
  fixture inline — chaining two independent `extend`s can silently drop the worker scope of
  the seed fixture. **First MOVE that existing POM `base.extend<PomFixtures>({...})` block out
  of `fixtures/test.ts` into a new `fixtures/pom.fixtures.ts`** (exporting it as `test`) — the
  scaffold ships one flat barrel, so that module does not exist until you create it. Then
  compose the two test objects with Playwright's `mergeTests`:
  ```ts
  // fixtures/test.ts  (the barrel every spec imports — its path must not change)
  import { mergeTests } from '@playwright/test';
  import { test as pomTest } from './pom.fixtures';      // { loginPage, checkoutPage, … }
  import { test as seedTest } from './seed/customer.seed'; // { seededUser } — worker-scoped
  export const test = mergeTests(pomTest, seedTest);       // scopes preserved: seededUser stays worker-scoped
  export { expect } from '@playwright/test';
  ```
- **Bridge the API-seeded identity INTO the browser (mutating UI specs).** Seeding a user
  over the API gives you a token/session on the *Node* side — the browser knows nothing about
  it. A UI spec that must act *as* the seeded user has to inject that auth **before the SPA
  hydrates**, or the app boots logged-out and redirects. Use `addInitScript` (runs before any
  page script on every navigation) to plant the token the app reads at boot, e.g.:
  ```ts
  // in a page object / fixture, before the first goto:
  await context.addInitScript(([k, v]) => localStorage.setItem(k, v),
    ['sw_token', seededUser.token]);   // key from app.context.md sites[].token_storage
  ```
  For cookie/session auth, write a `storageState` JSON from the seed and `test.use({ storageState })`
  instead. Which mechanism the app needs (localStorage key vs cookie) comes from the hot-tier
  `sites[].auth_shape` / `token_storage` fields — declare them there, don't hardcode the key
  in every spec.

## Consumable / finite resources (stock, credits, quotas, seats)
The rules above isolate *creatable* resources (a fresh user/order per worker). A different, harder class is a **finite resource the test consumes** — product **stock**, account **credits**, rate-limit **quota**, redeemable promo codes, bookable seats. These have no per-worker "create a fresh one" escape: there is one global stock count, and a checkout that buys the last unit depletes it for everyone.
- **Symptom:** the spec is green on fresh state and **red on the 2nd run** (and flaky across workers) as the resource exhausts — the Add-to-cart/checkout control disables and every scenario times out. The generator's `--reporter=line` **run-twice** green-check (generator.md §"Cross-RUN idempotency → CONSUMABLE resources") is what surfaces this before it ships.
- **Preferred fix — restock in setup via a sanctioned hook.** If the app exposes a seed/restock endpoint that can *set* a quantity (`POST /api/test/seed { product: X, stock: 20 }`), drive it in a worker-scoped `beforeAll`/fixture through the adapter so each run starts from a known quantity. Restore, don't just consume.
- **Second choice — per-worker resource slice.** If stock can be scoped (a distinct SKU / tenant / coupon per `parallelIndex`), seed one finite pool per worker so workers don't contend for the same units.
- **Do NOT** paper over depletion by (a) wiring a destructive global truncate into teardown, (b) picking a "probably has stock" product and hoping, or (c) asserting a loose `value_between` wide enough to pass on any stock level — that defeats the oracle. If the app offers **no** set-quantity hook and **no** scopable slice, escalate: a consumable-resource flow with no restock is a test-isolation design gap for the human to resolve, not a generator improvisation.

## Tooling choices
- **Testcontainers** (https://testcontainers.com/) — ephemeral DB per worker, safest long-term OSS bet. Use for services with complex schema / stateful interactions.
- **Snaplet Seed** (https://snaplet.dev/) — synthetic-data generator for realistic-shaped data, TypeScript-native.
- **Neosync** — OSS, but maintenance status is weak post-acquisition (as of Apr 2026). Treat as "watch-list" not "adopt".
- **Home-grown API seeding** (example above) — correct for most teams starting out.

## Gotchas
- **Shared fixtures at test scope** re-seed per test and slow the suite — use `scope: 'worker'` for per-worker-once data.
- **Read-only shared data** (currency lookup, country list) can be seeded once globally; do not per-worker it.
- **Never share writeable resources across workers.** One cart, one order, one session per worker slot.
- **Tag-delete blind spots:** cascade children the *app* created don't carry your tag; soft-delete hides rows from the cleanup query while they still hold unique keys; eventual consistency can miss just-written rows; a rate-limited API can 429 the teardown itself. Treat tag-delete as best-effort, not proof of a clean DB.
- **Tier the accounts:** reusable per-worker IDENTITY (the account + `storageState`, seeded once and kept) vs throwaway per-test TRANSACTIONAL data (orders/uploads, created and deleted per test). Reuse identity; never reuse transactional rows.
- **Leaks:** if teardown fails silently, tagged rows accumulate. Have the APP TEAM run a nightly `DELETE ... WHERE tag LIKE 'test-run-%' AND created_at < now()-interval '24 hours'` backstop (it needs direct DB access this toolkit deliberately disclaims), and heartbeat-monitor it — it is a backstop, not the safety net.
- **Env variables, not hardcoded API tokens** — `QA_ADMIN_TOKEN` lives in **`.env`** (gitignored; declared in `.env.example`). `.env` is the ONLY env file anything loads: `playwright.config.ts` calls bare `dotenv.config()` and the CLAUDE.md shell loader sources `.env` alone — a token parked in `.env.test` is never loaded and every seed request goes out as `Bearer undefined`.

## References
- Playwright fixtures: https://playwright.dev/docs/test-fixtures
- Testcontainers: https://testcontainers.com/
- Snaplet Seed: https://snaplet.dev/
