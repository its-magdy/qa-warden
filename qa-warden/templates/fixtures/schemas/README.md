# `fixtures/schemas/` — single source of field vocab

> **GENERATED ON DEMAND, GROUNDED IN YOUR REAL APP — not a shipped stub.** The
> scaffold ships **no live `<entity>.ts` schema** (only a `user.ts.example`
> pattern illustration with deliberately fictional fields). The generator creates
> `fixtures/schemas/<entity>.ts` — and its paired `fixtures/factories/<entity>.ts`
> — the first time a spec uses the `factory:` form, deriving the fields from the
> real app model (the intake `.basis.md` / live app), the same way it grounds
> POMs and locators. To hand-author instead, copy the `.ts.example` (drop
> `.example`) and replace its fields with your real model. The reviewer's Check 10
> ungrounded-schema guard FAILs a schema that still carries the example's
> placeholder fields.
>
> **OPT-IN — load-bearing ONLY for specs that use the `factory:` form.** This Zod
> schema + `zod-fixture` factory layer matters only for specs whose `data:` block
> *instantiates entities* via `user: { factory: "user", … }`.
> A project that seeds test data through an **API** (the `test-data-seed` skill's
> default and the common case) or only uses **credential-only** `data.user`
> blocks (`{ email, password_env }`, carved out of reviewer Check 10) has **zero
> consumers** of this layer — you can safely delete `fixtures/schemas/`,
> `fixtures/factories/`, and drop `zod` + `zod-fixture` from `devDependencies`.
> Doing so also sheds the `zod-fixture@2.5.2` pin liability (it's unmaintained and
> Zod-4-incompatible, forcing the `zod ~3.25.x` pin). Keep the layer when you have
> real entity instantiation across specs; drop it when you don't. `/qa-warden:doctor`
> won't flag its absence.

Zod schemas that define the shape of every entity your tests touch (User, Order, Org, ...).
**Change a schema → TypeScript breaks every consumer at compile time.** No grep, no hunt.

## Setup (one-time)

No install needed — both `zod@~3.25.0` and `zod-fixture@^2.5.2` already ship in the
scaffolded `package.json` at those exact pins (`/qa-warden:init` installs them). The Zod 3.25
line is pinned on purpose: a bare `zod` pulls Zod 4, which BREAKS zod-fixture@2.5.2
(its newest release; introspects Zod-3 internals). See package.json "zod_comment".

## Pattern

1. Define the entity here as a Zod schema.
2. A matching factory under `fixtures/factories/<entity>.ts` wraps `zod-fixture` to give you `makeUser({ ... })`.
3. Specs reference the entity via the **`factory:` form** in their `data:` block —
   `user: { factory: "user", overrides: { name: "Alice" } }` — the ONE canonical
   reference syntax (matches `fixtures/factories/README.md` and generator/reviewer
   Check 10). Do NOT use `{{factories.user.name}}` template interpolation; the
   generator resolves the `factory:` form, not that.
4. The worker-scoped seed fixtures under `fixtures/seed/<entity>.seed.ts` call the same `makeUser()` factory — one source of truth for spec data, seed data, and API mocks.

## When the requirements change

Example: signup goes from `first_name + last_name + email` → `full_name + phone`.

1. Edit `schemas/user.ts` (one line set of fields).
2. Run `npx tsc --noEmit` — TypeScript prints every file that still references `first_name`, `last_name`, or `email` on a User. That is your impact set.
3. Run `/qa-warden:impact field=full_name` to also catch specs that reference fields via the route manifest (covers tests/specs that don't go through TS).
4. Edit the affected specs by hand, then regenerate with `/qa-warden:gen`. (There is no `/qa-warden:migrate` command in this toolkit — the migration is manual: schema edit → `tsc --noEmit` impact set → `/qa-warden:impact` → edit specs → `/qa-warden:gen`.)

## What lives here vs `fixtures/factories/`

- **`schemas/`** = the contract. Types, validation rules, optionality. No data generation.
- **`factories/`** = the data generators. Use `zod-fixture` to produce realistic defaults; allow `overrides` for per-test specifics.

## Why this matters

Centralized field vocab is the single biggest lever against cascading-change pain in E2E suites. The 2025-26 community consensus (Snaplet Seed, zod-fixture, Microsoft engineering playbook) is: derive fixtures from a schema, never hand-maintain them.
