#!/usr/bin/env bash
# Shared eval fixture: a real scaffolded QA project (no npm install) holding ONE correct
# spec + compiled test for a failed-login scenario. Each reviewer case sources this, then
# applies exactly ONE planted defect — so a case's red is attributable to that defect alone.
# Runs in the eval run's EMPTY workspace (cwd), outside the agent sandbox, only under --scaffold.
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$PLUGIN_ROOT/bin/qa-scaffold" "$PWD" --no-install >/dev/null 2>&1 || { echo "qa-scaffold failed" >&2; exit 1; }

mkdir -p specs/auth tests/auth
cat > specs/_context/app.context.md <<'CTX'
---
last_verified: 2099-01-01
volatility: low
sites:
  - id: app
    base_url_env: BASE_URL_APP
    auth: form
naming:
  area_dirs: [auth]
---
# App context (eval fixture — human-confirmed, not a draft)
CTX

cat > specs/auth/login.md <<'SPEC'
# Login — wrong password is rejected

A registered user who types a wrong password stays on the login page and sees the
exact rejection message. No session is created.

```yaml
name: wrong password is rejected
tags: [regression, auth]
site: app
data:
  user: { email: "alice@example.com", password_env: "QA_ALICE_PW" }
steps:
  - "Navigate to {{base_url}}/login"
  - "Fill Email with the user's email"
  - "Fill Password with a wrong password"
  - "Click the Sign in button"
oracle:
  error_shown: "Invalid email or password"
  url_matches: "/login$"
```
SPEC

cat > tests/auth/login.spec.ts <<'TEST'
import { test, expect } from '../../fixtures/test';

test.describe('auth/login', { tag: ['@regression', '@auth', '@site:app'] }, () => {
  test('wrong password is rejected', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('alice@example.com');
    await page.getByLabel('Password').fill('definitely-wrong');
    await page.getByRole('button', { name: 'Sign in' }).click();

    // oracle: error_shown
    await expect(page.getByRole('alert')).toHaveText('Invalid email or password');
    // oracle: url_matches
    await expect(page).toHaveURL(/\/login$/);
  });
});
TEST
