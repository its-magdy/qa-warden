# `fixtures/factories/` — derived test-data generators

> **GENERATED ON DEMAND** (see `fixtures/schemas/README.md`) — the scaffold ships
> no live `<entity>.ts` factory, only a `user.ts.example` illustration. The
> generator writes `fixtures/factories/<entity>.ts` (paired with its schema),
> grounded in the real app, the first time a spec uses the `factory:` form.
> **OPT-IN** — load-bearing only for specs that instantiate entities that way.
> API-seeded / credential-only projects never trigger generation here and may
> drop `zod`/`zod-fixture` from `devDependencies`.

One factory per schema in `fixtures/schemas/`. Each factory wraps `zod-fixture` to
produce realistic defaults, and accepts `overrides` so individual specs can pin
specific values they assert on.

## Usage from a spec's YAML `data:` block

```yaml
data:
  user: { factory: "user", overrides: { name: "Alice Tester" } }
```

The generator resolves this at compile time by calling `makeUser({ name: "Alice Tester" })`
and inlining the resulting object into the generated `.spec.ts`.

## Usage from a Playwright test directly (seed, helpers)

```ts
import { makeUser } from "../fixtures/factories/user";

const alice = makeUser({ name: "Alice Tester" });
await request.post("/api/v1/users", { data: alice });
```

## Rules

1. **Never inline test data in a spec.** Use `factory: <name>` in the YAML and let the generator resolve. Reviewer Check 10 enforces this.
2. **Never log a generated password.** Echo the field name (`password`) for debug, never the value.
3. **One factory per schema.** Don't proliferate `makeUserWithPhone()` vs `makeUserBasic()` — use overrides.
4. **Worker-scoped uniqueness** for anything that hits a real DB. Combine the factory with `testInfo.parallelIndex` (see `test-data-seed` skill).

## When a schema changes

1. Edit `schemas/<entity>.ts`.
2. TypeScript compile breaks every call site that no longer matches.
3. Update each call site (often: just rename a field; sometimes: add an override).
4. Run `/qa:impact field=<new-field>` to find any specs that reference the field via route-manifest only.
5. Regenerate affected `.spec.ts` files.

The 5 steps above **are** the change-cascade playbook: schema edit → `tsc` breaks call sites → fix them → `/qa:impact` finds manifest-only refs → regenerate.
