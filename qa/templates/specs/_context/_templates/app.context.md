<!--
HOT-TIER app-context template — the small, always-loaded, HAND-EDITED core that grounds
every agent in the app under test. Holds only the most stable facts: the sites[] table,
auth shape, env-var names, naming conventions, and a pointer to the oracle vocabulary.
NO selectors, NO sitemap, NO per-area vocab, NO "known flaky pages" — those are volatile
and live in the specialist tier (`_templates/area.md`) or are pulled live at compile time.
Human-owned ON PURPOSE: a human-anchored source of truth breaks the closed-loop in which
agent-written context would feed agent-authored tests. The `exploration` agent only
VERIFIES this file (bumps last_verified); it does not author the sites[] values.
Target ~80 lines (a tunable default, not a hard cap). Delete this comment.
-->

```yaml
# Hot-tier app context. Hand-edit sites[] then re-run /qa-warden:explore mode=hot.
sites:
  - id: app
    description: "<one line: what this site is, e.g. 'customer storefront'>"   # optional — orients the agent
    base_url_env: BASE_URL_APP        # must match a var in .env
    login_route: "<login route, e.g. /login>"
    storage_state_path: fixtures/auth.app.json
    auth_shape: "<jwt | cookie | session>"   # the single most useful stable auth fact
    auth_mode: "form"   # form | totp | magic-link | sso-redirect | manual
      # HOW login happens (orthogonal to auth_shape = where the token lives):
      #   form         — email/password form (default). Setup project REGENERATES storageState per run.
      #   totp         — form + TOTP second factor. STILL regenerated per run: the setup file
      #                  computes the 6-digit code from QA_TOTP_SECRET (otpauth lib).
      #   magic-link   — passwordless email link. Regenerable ONLY with a mail-capture harness
      #                  (Mailpit on staging; hosted e.g. Mailosaur) — note its API URL here;
      #                  no harness → treat as manual.
      #   sso-redirect — third-party IdP redirect (Okta/Auth0/Entra). Scriptable when the staging
      #                  IdP accepts the QA creds via its own login form; otherwise manual.
      #   manual       — login CANNOT be scripted (hardware WebAuthn, corporate SSO, CAPTCHA).
      #                  A human PRE-MINTS fixtures/auth.<site>.json (CLAUDE.md §"Auth beyond
      #                  form login"); the setup project VALIDATES it instead of regenerating.
    token_storage: "<localStorage key or cookie name, e.g. localStorage.app_token>"
                                             # WHERE the auth token lives (localStorage key / cookie name).
                                             # This is what token-presence/absence oracles (storage_state:<null>/<non-null>)
                                             # key off — declaring it here beats hardcoding the key in every negative spec.
                                             # Placeholder ON PURPOSE: it must be OBSERVED in your app (devtools →
                                             # Application → storage after a login), never assumed — a wrong key here
                                             # makes every storage_state presence oracle assert the wrong slot.
    creds:
      email_env: QA_USER_EMAIL
      password_env: QA_USER_PASSWORD
  # - id: admin
  #   base_url_env: BASE_URL_ADMIN
  #   login_route: /login             # VERIFY against the live admin app — do not assume /admin/login
  #   storage_state_path: fixtures/auth.admin.json
  #   auth_shape: "<jwt | cookie | session>"
  #   auth_mode: "form"
  #   token_storage: "<localStorage key or cookie name, e.g. localStorage.admin_token>"
  #   creds: { email_env: QA_ADMIN_EMAIL, password_env: QA_ADMIN_PASSWORD }

naming:
  spec_basename: kebab-case
  area_dirs: [auth, checkout, account]   # PRODUCT AREAS (specs/<area>/<feature>.md), NOT tags — smoke/regression are @tags on tests
  # on-screen vocab the generator reuses verbatim in oracles: brand name, persona display
  # names ("Hi, Demo Shopper"), category labels. Stable hot-tier facts; area-specific
  # error/success strings live in the specialist tier (`area.md` vocabulary).
  vocab:
    brand: "<Product/brand name as shown in the UI>"
    personas: ["<display name a logged-in greeting shows>"]

# test-support / seeding API — the deterministic reset/seed hook that transactional specs depend on.
# CONCEPTUALLY DISTINCT from sites[] (it is not a browser target) but load-bearing for authoring:
# the generator translates a "reset the seed" setup step to request.post("{api_url}/<reset route>")
# and the test-data-seed skill keys off it. Declaring api_url_env + secret_env here (never a literal
# secret — that lives in .env) stops every spec from re-discovering the seeding contract. Omit if the
# app ships no test-support API (then transactional oracles cannot rely on a deterministic seed — see
# CLAUDE.md relational-gap note). Add every var you name below to .env.example so /qa-warden:doctor Check 6 sees it.
test_support:                          # optional — omit if no seeding/reset hook exists
  api_url_env: "<e.g. API_URL>"        # base URL of the test-support API (env var name)
  secret_env: "<e.g. QA_TEST_SECRET>"  # env var holding the shared secret header, if the routes are guarded
  reset_route: "<e.g. /api/test/reset>"   # POST — restores the canonical seed
  seed_route: "<e.g. /api/test/seed>"     # POST — optional targeted seed; omit if only reset exists

# business_sources — OPTIONAL, source-agnostic "where the business rules live": the authority for what
# "correct" MEANS, beyond what the live app happens to show. /qa-warden:intake CONSULTS these to ground each 🔵
# oracle rule and stamp its provenance; when a source is unreachable/gated/silent, or CONTRADICTS the
# live app, intake ASKS the operator — it never guesses. Grounded in the RE "authoritative baseline"
# (single-source-of-truth) + the oracle "source of authority" concept, and RAG-style grounding is the
# best-supported defense against unfounded/"hallucinated" rules. NOT wiki-locked — `type` says what it is:
#   doc      — a local file/folder the agent can READ (a /docs dir, a markdown PRD)
#   url      — a single FETCHABLE page (public, or the exact link you paste)
#   api-spec — an OpenAPI/GraphQL schema file (the API contract)
#   tracker  — a ticket/issue (usually you PASTE the relevant text — the agent can't crawl a gated tracker)
#   human    — "ask the operator" (the always-available fallback authority)
# HONEST LIMIT: the agent reads local files, fetches a reachable URL, or ASKS you — it CANNOT crawl an
# authenticated wiki/Notion/Confluence. Point it at specific pages, paste the section, or answer directly.
# Grounding is an AID, not a completeness guarantee; all of it is advisory. Omit the whole block → intake
# grounds on the interview + live app only (today's behavior).
business_sources:                       # optional — omit if you have no external rules source
  - name: "<e.g. Product rules wiki>"
    type: doc | url | api-spec | tracker | human
    location: "<local path / URL / 'ask' for type: human>"
    covers: "<areas or topics this source is authoritative for>"
    # freshness: "<optional note — a stale source can mislead; intake flags on source-vs-app contradiction>"

oracle_vocab_ref: CLAUDE.md#test-case-format-contract   # single source of truth for the closed vocab (§"Test case format contract")

# single source of truth for reviewer Check 7 (context freshness) staleness thresholds (days). Tune per project.
# An area file's `volatility:` field selects its tier; missing/unknown → reference.
staleness_tiers:
  critical: 7                        # auth, payments, compliance — warn fast
  reference: 30                      # default
  stable: 90                         # rarely-changing surfaces

last_verified: 1970-01-01            # /qa-warden:explore mode=hot bumps this to today
```
