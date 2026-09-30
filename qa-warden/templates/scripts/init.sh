#!/usr/bin/env bash
# init.sh — one-shot bootstrap for a fresh clone of this QA template.
#
# Idempotent: safe to re-run. Each step skips if its work is already done.
#
# Steps:
#   1. Verify prerequisites (Node >=22, Claude Code installed)
#   2. Create runtime directories — read from scripts/runtime-dirs.txt, the same manifest
#      bin/qa-scaffold reads, so `npm run init` and /qa-warden:init produce the same tree.
#   3. Copy .env.example -> .env if missing, prompt to edit
#   4. npm install
#   5. npx playwright install chromium (always — idempotent)
#   6. Print next steps

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()    { printf "${GREEN}[init] ✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[init] !${NC} %s\n" "$*"; }
fail()  { printf "${RED}[init] ✗${NC} %s\n" "$*" >&2; exit 1; }
info()  { printf "[init]   %s\n" "$*"; }

# --- 1. Prerequisites ---------------------------------------------------------
info "Checking prerequisites..."

command -v node >/dev/null 2>&1 || fail "Node.js not found. Install Node >=22: https://nodejs.org"
node_v=$(node --version)                                  # asked ONCE — this ran node three times
node_major=$(printf '%s' "$node_v" | sed -E 's/^v([0-9]+).*/\1/')
[ "$node_major" -ge 22 ] || fail "Node $node_v is too old. Need >=22."
ok "Node $node_v"

if command -v claude >/dev/null 2>&1; then                # one lookup, not two
  ok "Claude Code $(claude --version 2>/dev/null | head -1)"
else
  warn "Claude Code CLI not found. Install: https://docs.claude.com/en/docs/claude-code"
fi

command -v jq >/dev/null 2>&1 || warn "jq not found — recommended for parsing Playwright JSON reports. Install: brew install jq (mac) or apt-get install jq (linux)"

# --- 2. Directories -----------------------------------------------------------
info "Creating directories..."
# SINGLE-SOURCED in scripts/runtime-dirs.txt, which bin/qa-scaffold reads too (the /qa-warden:init
# path) — so the two entry points provably produce the same tree instead of relying on a pair
# of "keep this list IDENTICAL" comments no code enforced. A missing dir here means the first
# write into it after `npm run init` hits an approval wall.
if [ -f scripts/runtime-dirs.txt ]; then
  mkdir -p $(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' scripts/runtime-dirs.txt | grep -v '^$')
  ok "dirs ready"
else
  # No hand-copied fallback list on purpose — that is the duplication this manifest removed.
  fail "scripts/runtime-dirs.txt missing — this clone predates the runtime-dir manifest; re-run /qa-warden:init --resync to stamp it, then re-run npm run init"
fi

# --- 3. .env ------------------------------------------------------------------
if [ -f .env ]; then
  ok ".env exists (not overwriting)"
else
  # Guard the copy — an unguarded cp on a clone missing .env.example would still
  # print ✓ ".env created" while creating nothing (false-green bootstrap).
  if cp .env.example .env 2>/dev/null; then
    ok ".env created from template"
    warn "Edit .env: set BASE_URL_APP (or BASE_URL) + QA_USER_EMAIL/QA_USER_PASSWORD before running tests"
  else
    warn ".env.example missing — no .env created. Restore it (re-run /qa-warden:init) or write .env by hand before running tests"
  fi
fi

# --- 4. npm install -----------------------------------------------------------
if [ -d node_modules ] && [ -f node_modules/.package-lock.json ]; then
  ok "node_modules present (skipping npm install — re-run npm install manually if package.json changed)"
else
  info "Running npm install..."
  npm install || fail "npm install failed"
  ok "dependencies installed"
fi

# --- 5. Playwright browsers ---------------------------------------------------
# Always run — the old "skip if an ms-playwright cache dir exists" heuristic false-skipped
# when the cache held ANOTHER Playwright version's browsers, and the first real run then
# died with "Executable doesn't exist". `install chromium` is idempotent: a fast no-op
# when the right revision is already present, a download only when it isn't.
info "Ensuring the Chromium revision this Playwright version needs is installed..."
# Match the `install-browsers` npm script and bin/qa-scaffold: `--with-deps` also
# installs the OS libraries Chromium needs, so a fresh Linux CI runner doesn't die
# on the first real run with a missing-shared-library error. On macOS it is a
# no-op (no system deps to fetch); on Linux it may need sudo — if it fails for
# lack of privileges, fall back to the browser-only install so bootstrap still
# completes (CI images that pre-install the libs are unaffected).
npx playwright install --with-deps chromium \
  || npx playwright install chromium \
  || fail "playwright install failed"
ok "browsers ready"

# --- 6. Next steps ------------------------------------------------------------
cat <<'NEXT'

[init] ✓ Project initialized.

Next steps:
  1. Edit .env — set BASE_URL_APP (must NOT be a production host; the guard matches
     a `prod`/`production` marker at a word boundary) and QA_USER_* creds.
  2. Run `claude` to start an interactive session.
  3. Inside Claude Code (same chain bin/qa-scaffold prints — keep the two in step):
       /qa-warden:explore                          # build app context (site/auth map)
       /qa-warden:explore mode=area site=app area=auth
                                            # area context — REQUIRED before intake
       /qa-warden:intake auth/login                # interview -> basis.md (pins the oracle)
       /qa-warden:ideate auth/login                # SFDIPOT checklist -> cases.md
       /qa-warden:approve auth/login               # record approve/prune — REQUIRED before new-spec
       /qa-warden:new-spec auth/login              # draft your first spec
       /qa-warden:gen specs/auth/login.md          # compile spec -> .spec.ts
       /qa-warden:review                           # reviewer gates the assertion contract
       /qa-warden:run mode=smoke                        # run the @smoke suite
     New to these terms (oracle, basis, SFDIPOT, assertion contract)? Run /qa-warden:help.
  4. Run the suite: `npx playwright test` (plain Playwright, no LLM cost).

Read CLAUDE.md for policy.
NEXT
