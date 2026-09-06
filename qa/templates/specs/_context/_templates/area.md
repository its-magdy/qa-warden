<!--
SPECIALIST-TIER area-context template — written by the `exploration` agent in
`mode=area site=<id> area=<name>`. Captures what the agents need to KNOW about one
product area on one site to author/heal specs: routes in scope, the domain
vocabulary actually visible on the page, observed (not predicted) flakes, and any
cross-site contracts. NOT selectors — the generator pulls those LIVE at compile time.
NOT business intent — that lives in the feature's `.basis.md`.
Target ~150 lines (a tunable default, not a hard cap — split oversized areas into
sub-areas, e.g. checkout-payment.md / checkout-shipping.md). Delete this comment.
-->

# context: <site>/<area>

```yaml
site: <id>                    # MUST match a sites[].id in app.context.md
area: <name>
volatility: reference         # critical | reference | stable — picks the Check 7 staleness
                              # threshold from staleness_tiers in app.context.md.
                              # critical ≈ auth/payments/compliance · reference = default · stable = rarely changes
last_verified: <YYYY-MM-DD>   # set to today on every refresh; drives reviewer Check 7 (context freshness)

# routes that belong to THIS area on THIS site (depth-2, breadth-first; not the whole app)
routes:
  - path: "/<route>"
    purpose: "<what this screen is for>"
    auth: <required|public>

# domain vocabulary OBSERVED on the page — entities, statuses, exact error wording.
# The generator/planner reuse these exact strings in oracle assertions.
vocabulary:
  entities: [<entity>, <entity>]
  statuses: [<status>, <status>]
  exact_errors:                # copy the wording verbatim — oracles assert against it
    - "<exact on-screen error text>"
  exact_success:               # load-bearing SUCCESS/status copy `text_visible` oracles assert against
    - "<exact on-screen success/confirmation text>"   # e.g. "Order confirmed", "Coupon applied", "Your cart is empty"
    # NOT ALL SUCCESS IS TEXT. Many flows (login, some checkouts) succeed via a REDIRECT + a state
    # change (a token written, a URL change) with NO success banner. Do NOT invent a string — record
    # the sentinel `- "(none — success is a redirect/state change)"` and note the real signal
    # (target URL, token key). The generator then steers the oracle to `url_matches` / `storage_state`
    # / `element_state`, never a fabricated `text_visible`.
  # Stable data-testid HINTS observed via grey-box (source grep / shipped TESTIDS.md / `npx
  # playwright-cli eval "el => el.getAttribute('data-testid')"` on the settled DOM — the live
  # ground-truth when source is off-limits and no manifest exists) — the AX
  # snapshot cannot see data-testid, so record the stable ones here so the generator prefers
  # getByTestId over a brittle text/regex locator. A HINT, not a cached selector: the generator
  # re-validates each against the live DOM at compile time. Omit if the app ships no testids.
  # RECORD THE ENTITY ID-SPACE for scoped testids. Apps commonly reuse a `<id>` suffix across
  # DIFFERENT entities — add-to-cart-<PRODUCT id>, cart-item-<CART-ITEM id>, order-row-<ORDER id>.
  # A scoped oracle that wires a product id where a cart-item id is required mis-targets silently
  # (green-but-wrong). So name the id-space per scoped testid, e.g.
  # "order-row-<ORDER id>: one row per placed order". This also warns count_equals authors NOT to
  # count an instance-scoped id (order-row-1 reads n:1 even with a duplicate) — count the SET.
  stable_testids:              # optional — `<testid>: <what it targets [+ id-space if scoped]>`
    - "<testid>: <element it targets, e.g. dashboard-open-count: open-tasks tile value>"

# flakes you SAW in this run only — never predicted. Empty is the correct default.
# `cause:` separates a genuine PRODUCT flake from a tooling/env artifact (e.g. a playwright-cli
# shared-session drop) so the healer/planner don't chase harness noise as if it were a defect.
known_flaky_surfaces:
  - route: "/<route>"
    symptom: "<what you observed>"
    cause: <app|tooling|env>   # app = real product flake · tooling = CLI/MCP/session artifact · env = infra/timing

# couples_with — OTHER areas whose state/rules can INVALIDATE an oracle written for THIS area
# (inbound coupling — the interdependency view). This is the machine-readable slot /qa:intake
# reads to seed a feature's own `couples_with:` and /qa:ideate reads to enumerate a case per
# coupling. DISTINCT from "Cross-feature contracts" below, which records THIS area's OUTWARD
# effects on others; couples_with is what FLOWS IN. Record a coupling when discovery shows this
# area's displayed/computed values depend on a rule owned elsewhere (multi-unit summing, a
# publish-state gate, a roster the counts derive from). A HINT for authors, not a contract —
# omit if none observed.
couples_with:
  - area: "<other-area>"
    channel: "<shared-data | cross-surface-aggregate | state-gate | cross-actor | config-flag>"   # the coupling angle (see basis.md couples_with note)
    coupling: "<the rule/state there that an oracle in THIS area must account for>"

# provenance — how each recorded fact was verified. Optional but recommended when a fact was
# confirmed via API/source but NOT re-observed in the UI (so downstream trust/freshness is machine-readable
# instead of buried in prose). Attach `[via: ui|api|source]` inline to any fact that isn't UI-verified;
# a claim INFERRED rather than directly observed is tagged `[via: unverified]`.
```

## Cross-feature contracts & invariants
<!-- Two kinds of verified relationship live here:
  (1) CROSS-SITE — an action here changes user-facing state on ANOTHER site (admin refund →
      user-facing order status). Add a reciprocal pointer in the partner area file.
  (2) INTRA-SITE invariants / side effects — the verified facts that power must_fail_when and
      metamorphic relations: stock decrement on purchase, cart clears after checkout, order
      total == cart subtotal. These are first-class here even when no second site is involved. -->

- <site:area action> → <other-site:area observable result>   <!-- cross-site; or: none -->
- invariant: "<verified intra-site side effect / equality>"   <!-- e.g. "placing an order decrements product stock by qty"; or: none -->

## Notes
<!-- Auth quirks (MFA, IP block) seen during discovery; anything a future author needs.
Keep terse. If discovery was incomplete, say so at the top with a one-line banner. -->
