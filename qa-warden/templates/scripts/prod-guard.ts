// ENFORCED prod-guard — runs as Playwright `globalSetup`, BEFORE any test.
//
// The command-layer prod-guard (scripts/prod-guard.sh — CLAUDE.md §Environment) is
// an advisory shell check an agent must remember to run. A bare `npx playwright test`
// with a prod BASE_URL_* bypasses it and runs the data-mutating suite against
// production (F-012). This module closes that hole: Playwright imports it once at
// startup, and a throw here aborts the ENTIRE run before a single browser opens —
// so even a plain `playwright test` (nightly, CI, ad-hoc) is guarded.
//
// It decides NOTHING itself. The verdict — the screened var-name set (every BASE_URL_*,
// API_URL, *_API_URL), WHATWG host extraction with the scheme-less `host:port` fallback,
// placeholder sentinels, the word-boundary prod marker and the QA_ALLOW_PROD=1 override —
// lives in scripts/prod-guard-core.mjs, which scripts/prod-guard.sh runs too. One file, so
// the two layers cannot disagree on what "prod" means; see that file for each rule's why.
// This module only turns the core's result into the throw Playwright needs.
//
// QA_ALLOW_PROD=1 disables the prod-MARKER check ONLY; placeholder / unconfigured-target
// refusals are config errors with no env escape (the fix is editing .env).
//
// Residual limit (same as the shell guard): a prod host with no telltale name
// (e.g. `www.acme.com`, an IP literal, or an alpha-suffixed `prodapi`) cannot be
// auto-detected — keep every BASE_URL_* on staging/QA explicitly.

import * as dotenv from 'dotenv';
import { maskUrl, screenTargets } from './prod-guard-core.mjs';

// playwright.config.ts already loads .env, but globalSetup is a separate module and
// may be imported before that side effect is visible — load again (idempotent, quiet
// so the banner never corrupts a JSON reporter). See CLAUDE.md §Reporting pipeline.
dotenv.config({ quiet: true });

export default function globalProdGuard(): void {
  const result = screenTargets(process.env);
  if (result.allowProd) {
    // eslint-disable-next-line no-console
    console.warn(
      '[prod-guard] QA_ALLOW_PROD=1 — prod-MARKER check disabled for this run ' +
        '(placeholder / unconfigured-target checks still apply).',
    );
  }

  // Fail-CLOSED on an unconfigured primary target (F-08). An empty primary means .env was
  // copied but never set, so REFUSE rather than run the mutating suite against a host the
  // user never chose. Deliberately NOT exempted by QA_ALLOW_PROD.
  if (result.primaryEmpty) {
    throw new Error(
      '[prod-guard] REFUSING to run: BASE_URL_APP is empty.\n' +
        'Edit .env and set BASE_URL_APP to your staging/QA target before running the suite.',
    );
  }

  const placeholders = result.results
    .filter((r) => r.verdict === 'placeholder')
    .map((r) => `${r.name}=${maskUrl(r.value)}`);
  if (placeholders.length > 0) {
    throw new Error(
      '[prod-guard] REFUSING to run: a screened URL var (BASE_URL_*/API_URL) is still a placeholder:\n' +
        placeholders.map((o) => `  • ${o}`).join('\n') +
        '\n\nEdit .env and set each to a real staging/QA target.',
    );
  }

  const offenders = result.results
    .filter((r) => r.verdict === 'prod')
    .map((r) => `${r.name}=${maskUrl(r.value)} (host: ${r.host})`);
  if (offenders.length > 0) {
    throw new Error(
      '[prod-guard] REFUSING to run: a screened URL var (BASE_URL_*/API_URL) looks like PRODUCTION:\n' +
        offenders.map((o) => `  • ${o}`).join('\n') +
        '\n\nThis suite mutates data. Point BASE_URL_* at staging/QA, or set ' +
        'QA_ALLOW_PROD=1 ONLY if you are certain this target is safe to run against.',
    );
  }

  // The core's own verdict must agree; a refusal it reports for a reason not handled above
  // still refuses (fail closed).
  if (result.verdict !== 'PASS') {
    throw new Error('[prod-guard] REFUSING to run: scripts/prod-guard-core.mjs returned ' + result.verdict + '.');
  }
}
