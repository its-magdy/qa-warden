---
name: test-case-contract
description: "Spec format contract for specs/**/*.md: the YAML schema, the closed 16-key oracle vocabulary and argument shapes, fault:/clock: situation steps. Load before writing, compiling or reviewing a spec."
user-invocable: false
disable-model-invocation: false
---

# Test case format contract

The canonical format of a QA spec (`specs/<area>/<feature>.md`). Preloaded into the planner,
generator, verifier, reviewer and ideation agents; `/qa-warden:import-cases` invokes it. It used
to be a section of the project's `CLAUDE.md`. If that file still carries a
`## Test case format contract` section, it is a stale copy: this skill wins where they differ.

Specs are Markdown prose plus one or more fenced YAML blocks. The YAML block schema:

```yaml
name: <short scenario name>
tags: [smoke, <area>]               # viewport is a TAG, never an oracle key — `mobile` in `tags:` emits `@mobile`; the opt-in `mobile` config project routes on it (desktop-only until a human uncomments it)
site: app                           # MUST match a sites[].id in specs/_context/app.context.md. Cross-site: `sites: [admin, app]`.
basis: checkout/coupon              # OPTIONAL — set on fanned-out specs; pairs the spec back to <feature>.cases.md/.basis.md
compliance_relevant: false          # OPTIONAL — true for PCI/HIPAA/SOX-flagged flows (enables the reviewer's cross-vendor note)
data:
  user:    { email: "...", password_env: "QA_USER_PASSWORD" }   # CREDENTIAL form: a pre-seeded login account. Exactly {email|username, password_env} — carved out of reviewer Check 10, no factory needed.
  order:   { factory: "order", overrides: { units: 1 } }        # FACTORY form: REQUIRED for any entity you INSTANTIATE with non-credential fields. Inline literals (`order: { units: 1, currency: "USD" }`) where fixtures/factories/order.ts exists = reviewer Check 10 FAIL. `overrides:` pins only what the oracle asserts; the factory generates the rest, and the generator creates the schema+factory on demand.
  expected_total_range: [49.00, 50.50]
steps:                       # prose lines, plus THREE structured forms: `include:`, `fault:`, `clock:`
  - include: login
  - "Navigate to {{base_url}}/cart"
  - "Apply coupon QA20"
  # `fault:` (stub a network dependency) and `clock:` (control time) are SITUATION steps —
  # the Interfaces/Operations and Time lens forms. Shapes + the fired-proof rule that keeps a
  # silently-non-firing stub from passing green are in §"Situation steps" below.
oracle:                      # closed vocabulary only
  text_visible: "Coupon applied"
  # locator is SEMANTIC only (getByTestId/getByRole/getByLabel) — never raw CSS
  value_between: { locator: "getByTestId('order-total')", range: [39.00, 40.50] }
  no_order_created: false
must_fail_when:                # OPTIONAL to declare — but once declared it IS enforced:
  - confirmation text removed   # reviewer Check 2b (reified as oracle) + verifier step 8b fault injection (proves the oracle goes RED on the defect)
  - order total mutated outside range
fail_if:                       # OPTIONAL — negative/error-path extra red-flags (scenario-level)
  - "the order confirmation page appears"
prompt_guardrail: |            # OPTIONAL — stops an agent "healing" an expected failure away
  This test expects an ERROR. Do not declare passed=true unless the error surface was observed.
invariant_holds_when:          # OPTIONAL — precondition domain of an equality oracle (reviewer Check 2e).
                               # LIST of {invariant, holds_when} pairs, mirroring the basis
                               # integrity_invariants[]. Never a bare scalar: a spec may assert
                               # more than one equality, and a scalar cannot say which one it scopes.
  - invariant: "order-total == cart-total"
    holds_when: "single-unit order — data.order.units == 1"
output_schema:
  required: [passed, evidence, failed_step]
  evidence: { order_id: string, observed_total: number, screenshot_path: string }
scenarios: [{ name: "...", data: {...}, tags: [smoke] }]   # OPTIONAL — N data-driven variants; each entry MAY carry its own `oracle:` (same vocab + shapes), `negative: true` for error-path scenarios, and its own `tags:` (per-scenario tags — emitted by the generator as `@<tag>` on THAT scenario's test only; this is how a multi-scenario spec tags exactly one governed happy-path `@smoke` while siblings stay `@regression`)
mr: ["<invariant, e.g. 'reordering cart items does not change the total'>"]   # OPTIONAL opt-out — self-declared metamorphic relations; PRESENCE makes the verifier skip auto-twins (step 8a) and reviewer Check 6 trust these instead
```

**Smoke-lane rule.** `@smoke` is the fast nightly gate (`/qa-warden:run mode=smoke` runs ONLY `--grep @smoke`). The **primary / governed happy-path of a P1 / critical area MUST be tagged `smoke`** — a P1 flow (checkout/payment/login) tagged `regression`-only leaves the smoke gate blind to a fully-broken feature. Edge/negative cases and metamorphic twins stay `regression`. **In a multi-scenario spec, put that `smoke` tag on the ONE governed happy-path via its per-scenario `tags: [smoke]` (see the `scenarios:` field above) — NOT on the spec-level `tags:`, which would tag every scenario's test and make `--grep @smoke` select the whole file instead of just the happy path.**

Closed **oracle vocabulary** (THE canonical list — the single source of truth every agent/command mirrors; planner, generator, reviewer Check 4, and `scripts/oracle-keys.txt` must all match this exact set; `/qa-warden:coverage` builds its `KEYS_RE` from that manifest at runtime, so it is not a mirror) — assertions must be one of these **16**: `text_visible`, `url_matches`, `count_equals`, `value_between`, `error_shown`, `no_order_created`, `attribute_equals`, `element_state`, `network_response_status`, `response_body_contains`, `download_received`, `clipboard_contains`, `storage_state`, `upload_accepted`, `dialog_dismissed`, `a11y_violations_below`. No free-form `"should look right"`. No free-form assertions. Negative/error-path specs add `fail_if:` and a `prompt_guardrail:` stanza so the agent does not "heal" the failure away. **Adding/removing a key means editing all sites above in the same change — a divergent list means the reviewer FAILs specs its own planner authors.**

**Oracle argument shapes (the SoT for reviewer Check 4's arg-shape sub-check).** The reviewer cannot read the plugin's `agents/generator.md`, so the canonical per-key argument shapes are pinned here, in the skill it preloads. A right key with a wrong-named arg silently mis-compiles — the reviewer FAILs a divergent shape:

| key | argument shape |
|---|---|
| `text_visible` | `"<string>"` |
| `url_matches` | `"<regex-or-literal>"` |
| `count_equals` | `{ locator, n }`  (NOT `{ count }`) |
| `value_between` | `{ locator, range: [min, max] }` |
| `error_shown` | `"<string>"` (exact) |
| `no_order_created` | `<bool>` — generic "no record persisted" guard: the `order` in the name is historical; use it for ANY entity a failed flow must not create (order / ticket / signup / booking / task). `false` = the record MUST exist; `true` = MUST NOT. |
| `attribute_equals` | `{ locator, attr, value }` |
| `element_state` | `{ locator, state }` |
| `network_response_status` | `{ url, status }` |
| `response_body_contains` | `{ url, text }` — asserts the response BODY of the matched request contains the exact `text` (JSON error body, API message). Complements `network_response_status` (which asserts only the STATUS code): for API-level authz/error specs where the exact `{"error":"Not authorized"}` string is the oracle, not just the 403. Generator compiles it against an `APIRequestContext`/`waitForResponse` body read + `expect(body).toContain(text)`. |
| `download_received` | `{ filename?, min_bytes? }` — a file download fired (`page.waitForEvent('download')`); optional `filename` regex + `min_bytes` size floor. Both predicates are optional, but each is one paired-expect that together cover the single oracle item (Check 1). Must match `planner.md` + `generator.md` (`min_bytes`, NOT `size`). |
| `clipboard_contains` | `"<string>"` |
| `storage_state` | `{ cookies?: [...], localStorage?: { key: value } }`  (camelCase `localStorage`, per Playwright `storageState()`). **Presence sentinel:** for a server-generated value you cannot predict (a JWT, a session id), assert the value literal `"<non-null>"` — e.g. `localStorage: { tm_token: "<non-null>" }`. The generator compiles `"<non-null>"` to `.toBeTruthy()` (and its negation `"<null>"` to `.toBeFalsy()` — not `.toBeNull()`, so an absent key resolving to `undefined` via `storageState()` still passes the "token absent" assertion instead of false-redding); the reviewer treats it as a canonical shape, not a divergence. This is the ONLY way the closed vocab expresses "key present, any value." |
| `upload_accepted` | `{ selector_role, name }` |
| `dialog_dismissed` | `{ type: 'confirm'\|'alert'\|'prompt', accept? }` |
| `a11y_violations_below` | `{ max_critical, max_serious }` |

**Two assertions with the same key → write `oracle:` as a LIST of single-key maps, never a bare mapping.** A YAML mapping silently collapses duplicate keys, so `oracle: { element_state: {…aria-pressed=true}, element_state: {…aria-pressed=false} }` keeps only the last — a real assertion is dropped and the spec reads as covered (a false-pass, the exact failure this vocab guards against). When a scenario needs the same key twice (two `element_state`, two `text_visible`, …), emit `oracle:` as a sequence of one-key maps: `oracle:\n  - element_state: {…=true}\n  - element_state: {…=false}`. The reviewer FAILs a bare-mapping `oracle:` that carries a duplicate key.

## Situation steps — `fault:` (network) and `clock:` (time)

Two `steps:` entries are STRUCTURED maps rather than prose, alongside `include:`. They set up the
*situation* the oracle is then asserted against — they are **never** assertions, and neither adds an
oracle key (the fired-proof rule below is why none is needed). They exist so the SFDIPOT
**Interfaces/Operations** and **Time** lenses are generatable at all: without them the planner has no
way to author *"the payments API returns 503"* or *"the session expires after 30 minutes"* — cases
`/qa-warden:ideate` routinely enumerates.

Argument shapes (verified against the pinned Playwright 1.63.0 type declarations). **The key column
deliberately carries the trailing colon** (`` `fault:` ``, not `` `clock` ``) — these are `steps:`
keys, not oracle keys, and the colon is also what keeps them out of the plugin's `bin/qa-selfcheck` Check 9bb
oracle-arg-shape extractor, which matches a bare `` `key` `` in column 1 and would otherwise count
them as a 17th and 18th member of the closed vocabulary.

| step key | argument shape |
|---|---|
| `fault:` | `{ url, status?, body?, json?, abort?, times? }` — `url` is a glob (`**/api/pay/**`) or `/regex/` matched against the request URL. Supply EITHER a fabricated response (`status` and/or `body`/`json`) OR `abort: "<errorCode>"` (a transport failure: `connectionfailed`, `connectionreset`, `internetdisconnected`, `namenotresolved`, `timedout`, `failed`, …) — never both. `times: n` retires the stub after `n` matching requests, which is how a *retry* case is expressed (fail once, let the real server answer the retry). |
| `clock:` | `{ install_at?, advance?, advance_idle?, pause_at?, fixed_time?, system_time? }` — **exactly one per step**, so a scenario that installs then advances writes two `clock:` steps. `install_at:` starts fake time at an ISO instant and **MUST precede the first navigation** (Playwright's own guidance: install before `goto`, at a time slightly before the intended test time, or the page can hang during load). `advance:` fires every timer it passes through; `advance_idle:` jumps and fires each due timer *at most once* (the "closed the laptop lid" case). Durations are milliseconds or `"SS"` / `"MM:SS"` / `"HH:MM:SS"`. |

**The fired-proof rule — a stub that does not fire is the false-green this feature risks.** A
`fault:` whose `url` matches nothing is *silent*: the real server answers, the app behaves normally,
and every oracle in the scenario passes for the wrong reason. So a `fault:` that fabricates a
**response** MUST be paired with a `network_response_status: { url, status }` oracle item naming the
same URL and the injected status. That key is already one of the 16 — **no new vocabulary** — and it
is discriminating by construction: if the stub misses, the real response arrives with a different
status and the test goes **RED**, not green. An `abort:` fault produces no response at all and cannot
be proven that way, so the generator compiles a handler hit-count plus a barrier `expect(...)`
(the R-26 carve-out) instead. Reviewer **Check 2** treats a `fault:` step carrying neither
fired-proof as an **orphan step** and FAILs it.

**A scenario with a `fault:` step may not be tagged `smoke`.** The smoke lane is the nightly
"does this feature actually work" gate; a scenario whose dependency is fabricated cannot answer that,
and a green smoke run standing on a stub is reassurance without evidence. Author fault scenarios as
`regression`. `clock:` carries no such restriction: the requests still reach the real server.

**`clock:` moves the browser's clock, never the server's.** Playwright's `page.clock` replaces `Date`,
the timers and `performance` inside the page only. A rule the SERVER enforces on time (a hold or
session that expires, a token TTL, "checkout is refused after expiry") cannot be aged by a `clock:`
step: author it as a real wait, or through a test-support hook the app context declares, and when
neither is possible record it as an uncovered gap, not as covered. **A red under `clock:` is evidence,
not a tool artifact.** When the red shows what the SERVER says (its remaining time, its expiry, its
response) contradicting the documented rule, that is a defect signal: file the bug and keep the
documented value. Never close it, or recommend waiving the scenario, on the grounds that fake time
cannot reach the server. That reasoning explains why the clock did not move the server; it does not
explain why the server disagrees with the rule.

**HAR replay is BANNED.** `page.routeFromHAR(...)` / `browserContext.routeFromHAR(...)` anywhere under
`tests/**` or `page-objects/**` is a reviewer **Check 11** FAIL and a write-time hook deny. Recording
is not the problem, replay is: a suite served from a recorded HAR asserts the frontend against a
frozen backend, so it stays green through every server-side regression — the exact inversion of what
the nightly replay promises. (A recorded HAR is also a credential-bearing artifact: `recordHar`
captures `Authorization` and `Cookie` request headers, and `mode: 'minimal'` omits the HAR's own
cookie fields but is not a redaction guarantee. Nothing in this toolkit writes one.)

## Authoring notes and honest limits

Explanatory material behind the rules above. It comes last on purpose: after a context
compaction only the first ~5,000 tokens of a skill are re-attached, so the rules lead.

**Natively-validated inputs — author the native-block oracle, not a server-error-string that can't fire (F-17).** For an invalid-input partition on a field with HTML5 native constraints (`<input type="email">`, `required`, `pattern`, `min`/`max`/`maxlength`), a non-conforming payload (`not-an-email`, an empty required field, an over-max value) is blocked by the browser **before submit** — no request fires, no app error alert renders, the page does not navigate. A provisional `error_shown: "Invalid …"` oracle for that partition is therefore **structurally unsatisfiable** (the app never emits that string → it ships as a mystery red). Author EITHER **(a)** the *native-block* oracle — `url_matches` still on the form route + `storage_state` token `"<null>"` + no error surface, and name the scenario for what it proves (`…-native-block`, not `…-server-reject`) — OR **(b)** a payload that actually **reaches the server** (a syntactically-valid-but-unknown email) so a server `error_shown` oracle can fire. The real observable for such a field is the browser's `ValidityState`/no-navigation, not an app message. (Planner authors this; the verifier's step-8b catches a mis-authored one live and leaves it honestly red.)

**Honest limit — the relational / exact-equality gap (no `value_equals`, no cross-value oracle).** The closed vocab has **no** key for "value A is byte-identical to value B" or "this value **equals** a computed/known value exactly." `value_between` bounds a single number against author-supplied constants; it cannot express "the created order total equals the cart's computed total" (an *integrity* invariant) or "the refusal message on branch A is identical to branch B" (an *anti-enumeration relational* invariant). This is a **known, deliberate** limit (keeping the vocab closed and mechanically checkable is worth more than a relational key the reviewer couldn't validate structurally). Sanctioned ways to express it **today**, in order of preference:
- **Exact-value-against-a-known-value:** when the expected value is seeded/known, use a `value_between` with a **tight** range around it (e.g. `[80.99, 81.01]` for an $81.00 total) that **excludes the wrong value** (e.g. the undiscounted $89.99). A wide band that also admits the wrong value is a false-pass — reviewer Check 2c WARNs on it.
- **Relational (A == B):** assert the **same literal** on both branches (e.g. one shared `REFUSAL_MESSAGE` constant asserted via `toHaveText`, not `toContainText`, in both scenarios) **and** declare a `must_fail_when:` ("branch A and B messages diverge" / "the total is not carried") so the verifier's step-8b injection and reviewer Check 2b/2c force it to be discriminating. Note the residual hole: same-literal-both-branches cannot catch the case where *both* branches drift to the same *new* leaky string — record that under the spec's `# Open questions` / `# waived:`.
- **Scope the invariant to its precondition domain (`invariant_holds_when:`).** An equality/relational invariant almost never holds *universally* — "order-total == cart-total" is true only for a **single-unit** order; across multiple units the surfaces legitimately differ. Declare the domain the equality holds over in the spec's optional `invariant_holds_when:` block (mirrored from the basis `integrity_invariants[].holds_when`), and pin the `data:` **inside** that domain. An **unscoped** equality is the over-broad `require true` default that Design-by-Contract (Meyer) and metamorphic-relation input-domains warn against: green on the pinned row, **false as a stated invariant**, and no other check catches it (Check 2c only sees a wide band, 2d only the literal). Reviewer **Check 2e (WARN)** flags a tight-band (`value_between range:[x,x]`) or same-literal-both-branches equality oracle that declares **no** `invariant_holds_when:` domain, or whose pinned `data:` visibly contradicts the declared one. WARN, not FAIL — the domain predicate is free-text and not always mechanically evaluable; it is a completeness reminder, not a gate.
- **Never** invent an out-of-vocab key for this — reviewer Check 4 FAILs it. If a project hits this often enough to justify a dedicated relational key (`value_equals: { locator, expected }` / `value_matches_api: { locator, source }`) — this would be a *new* key beyond the current 16 — that is a real vocab change: add it to **every enumerating** mirror in the same commit — this skill's list + arg-shape table, `planner.md`, `generator.md`, reviewer Check 4, `scripts/oracle-keys.txt`, and `/qa-warden:coverage`'s `KEYS_RE` grep — so the byte-for-byte consistency the reviewer depends on is preserved. (The `response_body_contains` key above was added by exactly this process to close the API-body-assertion gap; the relational `value_equals` gap remains deliberately unfilled.) (`/qa-warden:new-spec` and `/qa-warden:review url=<url>` **defer** to this skill and hold no key list — nothing to edit there.)

**Honest limit — no request-side oracle.** The closed vocab can assert what the server *answered*
(`network_response_status`, `response_body_contains`) but not what the client *sent*: there is no key
for "the checkout POST carried `coupon=QA20`" or "the request set an `Idempotency-Key` header".
`network_response_status` covers the *did it call that endpoint at all* half — a status assertion on
`**/api/orders` cannot pass unless a request to it actually fired — but the payload is out of reach.
This is the same deliberate gap as the relational `value_equals` one above, and the same rule
applies: **do not invent a key for it**; record it under `# Open questions` / `# waived:`.
