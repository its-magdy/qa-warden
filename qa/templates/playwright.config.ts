// This is the DETERMINISTIC REPLAY layer. No LLM runs here.
// Nightly: `npx playwright test` executes AI-authored .spec.ts at $0 LLM cost.
// Triage (LLM) happens elsewhere: healer subagent reads trace.zip on failure.

import { defineConfig, devices } from '@playwright/test';
import type { ReporterDescription } from '@playwright/test';
import * as dotenv from 'dotenv';

// Load .env before defineConfig reads process.env.
// `{ quiet: true }` is LOAD-BEARING: dotenv v17+ prints an "injected env (N)"
// banner to STDOUT by default, which prepends non-JSON to every reporter that
// writes/streams JSON — corrupting `artifacts/last-run.json` and any `jq` in
// /qa-warden:report, /qa-warden:run mode=single, /qa-warden:run mode=repeat. Suppress it at the source; do NOT
// try to strip it downstream (it's on stdout, not stderr). See dotenv#876.
dotenv.config({ quiet: true });

const isCI = !!process.env.CI;

// Run-of-record gate for the json reporter (see the reporter comment below).
// CI (the nightly) and /qa-warden:run mode=smoke (which sets QA_RUN_OF_RECORD=1) write
// artifacts/last-run.json; every other run leaves the run-of-record untouched.
const isRunOfRecord = isCI || process.env.QA_RUN_OF_RECORD === '1';

// Reporting sinks (see CLAUDE.md §Reporting pipeline):
//  1. json → artifacts/last-run.json — the SINGLE machine-readable source of
//     truth /qa-warden:report reads. GATED to run-of-record runs (isRunOfRecord above):
//     agent-side verification runs (heal/gen/twin/doctor re-runs) and local
//     ad-hoc runs can therefore NEVER clobber it — previously this was guarded
//     only by "--reporter=line on every side run" prose across seven files (the
//     F15 staleness class). Keep passing --reporter=line on verification runs
//     anyway: terse output, and belt-and-suspenders if someone unsets the gate.
//  2. CI → blob (shardable; merge with `npx playwright merge-reports --reporter
//     html ./all-blob-reports`). Local → browsable html.
//  3. line — human progress.
const reporters: ReporterDescription[] = [
  isCI ? ['blob'] : ['html', { open: 'never' }],
  ['line'],
];
if (isRunOfRecord) {
  reporters.unshift(['json', { outputFile: 'artifacts/last-run.json' }]);
}

// baseURL for the customer-facing `app` site — also the top-level default. Falls back
// through BASE_URL_APP → BASE_URL (single-site forks that never define site-suffixed env
// vars) → `http://localhost` (fail-fast local, NOT a real external host: an ad-hoc
// `npx playwright test` with an unloaded .env then hits localhost and fails immediately,
// instead of silently driving a live external domain). Set BASE_URL_APP in .env for real runs.
const APP_BASE_URL = process.env.BASE_URL_APP ?? process.env.BASE_URL ?? 'http://localhost';

// Collection rules shared by EVERY site project (app, admin, and any site added later).
// Spread into each project below rather than re-typed per site: the `_`-prefix pair is the
// toolkit's most drift-prone invariant (doctor Checks 3/14/15 mirror it, and it has already
// had to be fixed in lockstep once), so a second hand-kept copy per site is exactly the
// wrong place for it — a site added without both globs silently collects scratch specs.
//
// - `**/*.setup.ts`: setup files run ONLY in the `setup` project — never in a site project
//   (F-018). Without this the app project's untagged-match grep would also run them here.
// - `**/_*.spec.ts` + `**/_*/**`: ignore `_`-prefixed SCRATCH specs (e.g. a `/qa-warden:review url=`
//   throwaway visual spec with an OS-locked baseline) — probe byproducts, not managed suite
//   members, so the nightly must not run them (P-03). BOTH globs are required: the first
//   ignores a `_`-prefixed BASENAME, the second any file under a `_`-prefixed DIRECTORY
//   (`_probe/mischosen.spec.ts`). With only the first, a `_probe/` dir was collected (0 valid
//   tests) yet nagged by doctor Check 15 while Check 14 stayed blind: un-ignored, un-caught,
//   review-nag-only (F-027). In lockstep with doctor Checks 3/14/15's `/_`-segment exclusion.
//
// Deliberately NOT here: a path ignore for '**/admin/**'. Each site's `grep` already excludes
// the other site's tagged specs, so a path ignore would only affect UNTAGGED specs under
// tests/admin/ — path-ignored from `app` and grep-excluded from `admin`, they would run in NO
// project (silent false-green). Without it such a spec runs in `app` against the app baseURL
// and fails LOUDLY, which is the correct failure mode.
const siteProjectDefaults = {
  testIgnore: ['**/*.setup.ts', '**/_*.spec.ts', '**/_*/**'],
  dependencies: ['setup'],
};

// QA_WORKERS: staging-capacity slot (a shared staging DB that can't take 4 parallel
// writers is an environment fact, not policy). Accepts a positive integer or a Playwright
// percent string ('50%'). VALIDATED, not trusted: the old inline `Number(...)` turned a
// typo (`QA_WORKERS=four`) into `NaN` and `QA_WORKERS=0` into `0`, and handed either to
// Playwright with no diagnostic — concurrency silently changed on a malformed value. Fall
// back to the default and warn on STDERR (never stdout — that is what corrupts the JSON
// reporter; see the dotenv note above).
function resolveWorkers(): number | string | undefined {
  const raw = process.env.QA_WORKERS;
  const fallback = isCI ? 4 : undefined;
  if (!raw) return fallback;
  // `[1-9]\d*%`, not `\d+%`: this function exists to stop a degenerate value reaching
  // Playwright, and a bare `\d+%` rejected the integer `0` while waving through `0%` — the
  // same zero-worker request spelled the other way.
  if (/^[1-9]\d*%$/.test(raw)) return raw;
  const n = Number(raw);
  if (Number.isInteger(n) && n > 0) return n;
  // eslint-disable-next-line no-console
  console.warn(
    `[qa] ignoring malformed QA_WORKERS=${JSON.stringify(raw)} — expected a positive ` +
      `integer or a percent string like '50%'. Falling back to ${fallback ?? 'the Playwright default'}.`,
  );
  return fallback;
}

export default defineConfig({
  testDir: './tests',
  // ENFORCED prod-guard: throws before any browser opens if a BASE_URL_* looks like
  // production (word-boundary match; QA_ALLOW_PROD=1 overrides the marker check ONLY —
  // placeholder/empty-target refusals have no env escape). Makes even a bare
  // `npx playwright test` safe — the command-layer shell guards are advisory only (F-012).
  globalSetup: './scripts/prod-guard.ts',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  // Retries run at the END of the suite, one at a time in a single worker, instead of being
  // interleaved with the rest of the run (Playwright's default, 'immediate'). Requires >= 1.62
  // — verified against the v1.63.0 type declarations, not a blog; we pin 1.63.0.
  // Why it matters here: an interleaved retry re-runs the failed test WHILE the rest of the
  // suite is still mutating shared server state, so a retry can go green for a reason that has
  // nothing to do with the fix (or stay red because a *different* test raced it). That turns a
  // real defect into "flaky" and a race into "passed on retry" — both are the green-but-wrong
  // outcome this toolkit exists to block. Isolating retries costs wall-clock, not correctness.
  retryStrategy: 'isolated',
  // Validated above in resolveWorkers() — a malformed QA_WORKERS warns and falls back
  // rather than reaching Playwright as NaN/0.
  workers: resolveWorkers(),
  // Reporters are assembled above (run-of-record gate on the json sink).
  reporter: reporters,
  outputDir: './artifacts/test-results',
  // Quarantine lane (CLAUDE.md §Escalation rules): tests tagged @quarantine are
  // excluded from EVERY default run — the bare nightly, /qa-warden:run mode=smoke, and the
  // package.json grep scripts — so a flaky test can't keep failing the gate while
  // it waits for a fix. Gated on an env var because CLI `--grep-invert` does NOT
  // override a config-level grepInvert (verified: with a static grepInvert here,
  // `--grep @quarantine --grep-invert '$^'` still lists 0 tests — quarantined
  // tests would be unrunnable). Run the quarantine lane explicitly with:
  //   QA_RUN_QUARANTINE=1 npx playwright test --grep @quarantine
  grepInvert: process.env.QA_RUN_QUARANTINE === '1' ? undefined : /@quarantine/,
  use: {
    // Default baseURL is the customer-facing site (APP_BASE_URL, defined above).
    // Per-project baseURL below overrides per site.
    baseURL: APP_BASE_URL,
    // Trace kept only for FAILURES — trace.zip is the healer's primary triage input
    // (`npx playwright trace …`); passing runs record then discard it, mirroring the
    // video policy below.
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // DELIBERATE tradeoff: keep a real .webm for every FAILURE so a human can
    // watch exactly what happened end-to-end (the trace film strip is stills, not
    // continuous playback). Cost: 'retain-on-failure' records every test at
    // runtime and deletes on pass (~10-30% wall-clock overhead) — no agent
    // consumes video (the healer uses trace.zip + error-context.md +
    // screenshots); this exists for the human. Set to 'off' if runs get slow.
    //
    // FIRST-RUN REVIEW MODE: QA_KEEP_VIDEO=1 flips this to 'on', keeping the .webm
    // even when a test PASSES — so after authoring a spec a QA can watch the video
    // to confirm the test actually drives the flow the way they intended (not just
    // "green"), then delete artifacts/ once satisfied. Kept OFF by default so the
    // nightly/CI gate stays cheap and doesn't accumulate green-run videos:
    //   QA_KEEP_VIDEO=1 npx playwright test tests/checkout/coupon.spec.ts
    video: process.env.QA_KEEP_VIDEO === '1' ? 'on' : 'retain-on-failure',
    // Freeze CSS animations/transitions so time-based motion can't flake a visual
    // diff or an auto-waiting assertion (F-013). Harmless for non-visual specs; the
    // visual-regression skill assumes this is set globally. NOTE: `reducedMotion` is a
    // BrowserContext option, so it lives under `contextOptions` — it is NOT a direct
    // `use:` key in Playwright's TestOptions (a top-level `use: { reducedMotion }` fails
    // typecheck).
    contextOptions: { reducedMotion: 'reduce' },
    // Pin the locale so aria snapshots / toMatchAriaSnapshot baselines are
    // deterministic across machines — an unpinned locale inherits the host OS
    // language and breaks text-bearing baselines the moment a differently-configured
    // machine (or CI image) runs the suite.
    // QA_LOCALE: env slot — set when the app renders a non-English locale so
    // text_visible/error_shown literals match the app's copy. `||` not `??`: an empty
    // QA_LOCALE= in .env must fall back to the pin, not pin ''.
    locale: process.env.QA_LOCALE || 'en-US',
    // Same determinism rationale as locale: unpinned, rendered dates/times inherit the
    // host TZ and differ across machines/CI. QA_TZ overrides (ICU id).
    timezoneId: process.env.QA_TZ || 'UTC',
    // ── Walled-staging knobs — ALL no-ops until their env is set (see .env.example) ──
    // Basic-auth wall in front of staging. send:'unauthorized' = credentials only after a 401 challenge.
    httpCredentials: process.env.QA_BASIC_AUTH_USER
      ? { username: process.env.QA_BASIC_AUTH_USER, password: process.env.QA_BASIC_AUTH_PASS ?? '', send: 'unauthorized' as const }
      : undefined,
    // One extra header on every request (WAF/staging-gate bypass). TWO envs — name and value — no "name:value" parsing to get wrong.
    extraHTTPHeaders: process.env.QA_EXTRA_HEADER_NAME
      ? { [process.env.QA_EXTRA_HEADER_NAME]: process.env.QA_EXTRA_HEADER_VALUE ?? '' }
      : undefined,
    // Corporate egress proxy to reach the walled staging.
    proxy: process.env.QA_PROXY_SERVER ? { server: process.env.QA_PROXY_SERVER } : undefined,
    // mTLS client certificate (TestOptions.clientCertificates, Playwright 1.46+).
    clientCertificates: process.env.QA_CLIENT_CERT_ORIGIN
      ? [{
          origin: process.env.QA_CLIENT_CERT_ORIGIN,
          certPath: process.env.QA_CLIENT_CERT_PATH,
          keyPath: process.env.QA_CLIENT_KEY_PATH,
          ...(process.env.QA_CLIENT_CERT_PASSPHRASE ? { passphrase: process.env.QA_CLIENT_CERT_PASSPHRASE } : {}),
        }]
      : undefined,
  },
  // ── Local-target convenience (OPT-IN — leave commented for remote staging) ──
  // Uncomment ONLY when BASE_URL_APP points at localhost and you want Playwright to
  // own the dev server lifecycle. Against a REMOTE staging target this must stay
  // commented: webServer would spawn a local process and gate the whole run on a
  // localhost health-check unrelated to the real target.
  // Fields per playwright.dev/docs/test-webserver — use `url` (`port` is deprecated).
  // webServer: {
  //   command: 'npm run dev --prefix ../your-app',
  //   url: 'http://localhost:3000',
  //   reuseExistingServer: !isCI,
  //   timeout: 120_000,
  // },
  projects: [
    // setup — produces authenticated storageState ONCE before the suite, the
    // Playwright-recommended auth pattern (playwright.dev/docs/auth). The
    // generator/exploration emit `tests/<...>.setup.ts` files that log in and
    // `page.context().storageState({ path: 'fixtures/auth.<site>.json' })`; the
    // site projects then start pre-authenticated via `test.use({ storageState })`
    // instead of re-driving a full UI login in every spec (slower + less isolated).
    // With no `*.setup.ts` files this project is an empty no-op and the dependency
    // just passes; once the generator emits `tests/<site>.setup.ts` (which it does
    // for every site whose storageState is reused — see generator.md §"Storage
    // state"), they run here first and the state is REGENERATED fresh each run
    // rather than read from a committed, expiring snapshot.
    // SITE RESOLUTION IS ON THE SETUP FILE, not this project: there is ONE setup
    // project with no per-site `use`, so every *.setup.ts inherits the APP baseURL.
    // A relative `page.goto('/login')` in tests/admin.setup.ts would therefore log in
    // against the APP site and save wrong cookies to fixtures/auth.admin.json (a
    // silently-poisoned auth state every admin spec then trusts). Each *.setup.ts
    // MUST (a) read its OWN site's BASE_URL_<SITE> env var and navigate by ABSOLUTE
    // URL — never a relative goto — and (b) self-skip (test.skip) when that env var
    // is unset, since setup files still run here even when the site's project
    // (e.g. admin, gated on BASE_URL_ADMIN) is not registered.
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    // site=app — customer-facing storefront. Default project.
    // Runs specs tagged @site:app and any untagged specs (default site).
    {
      name: 'app',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: APP_BASE_URL,
      },
      // `(?:\s|$)` boundary after the tag: Playwright greps a SPACE-JOINED string of
      // titles + tags, so a tag token always ends at a space or end-of-string. An
      // unanchored /@site:app/ also matched @site:appstore / @site:app-eu and ran those
      // specs here against the wrong baseURL. (NOT \b — hyphen is a non-word char, so
      // \b still matches @site:app-eu; hyphenated site ids are legal per doctor Check 10.)
      // The untagged-default branch ^(?!.*@site:) stays PREFIX-matched on purpose — it
      // must reject ANY @site: tag. Keep in lockstep with the admin grep below.
      grep: /@site:app(?:\s|$)|^(?!.*@site:)/,
      ...siteProjectDefaults,
    },
    // site=admin — back-office. Skip block when BASE_URL_ADMIN is unset
    // (single-site forks). Routed by the @site:admin TAG the generator ALWAYS emits
    // (agents/generator.md §"Spec tagging"), NOT by file path. Playwright ANDs a
    // project's `testMatch` (file filter) with its `grep` (title/tag filter), so the old
    // `testMatch: ['**/admin/**', ...]` here silently DROPPED any @site:admin spec the
    // generator wrote under tests/<area>/ where <area> != 'admin' (and not *.cross-site):
    // it matched neither the admin project (fails testMatch) nor the app project (its grep
    // excludes @site:) and ran in NO project — a silent false-green. Tag-only routing
    // matches how the generator resolves baseURL and can't strand a correctly-tagged spec.
    ...(process.env.BASE_URL_ADMIN
      ? [
          {
            name: 'admin',
            use: {
              ...devices['Desktop Chrome'],
              baseURL: process.env.BASE_URL_ADMIN,
            },
            // Select every @site:admin-tagged test, wherever it lives. The app project's
            // grep (/@site:app(?:\s|$)|^(?!.*@site:)/) already excludes @site:admin, so a
            // spec routes to exactly one baseURL; a cross-site spec tagged BOTH runs in
            // both. Same (?:\s|$) boundary as the app grep — an unanchored /@site:admin/
            // also matched e.g. @site:admin-portal and ran it against the wrong baseURL.
            grep: /@site:admin(?:\s|$)/,
            ...siteProjectDefaults,
          },
        ]
      : []),
    // ── Mobile-viewport lane (OPT-IN — uncomment to enable) ──
    // Runs every @mobile-tagged test in an emulated phone (Pixel 7: 412x915, touch,
    // chromium — the engine the agents author against). Tag semantics are ADDITIVE,
    // mirroring @site: (a spec tagged for two lanes runs in both): ['@mobile','@site:app']
    // runs in the desktop app project AND here — intended (viewport parity, same oracle).
    // Mobile-ONLY tests: do NOT add `grepInvert: /@mobile/` to app/admin — a project-level
    // grepInvert REPLACES the top-level quarantine grepInvert for that project (quarantined
    // tests would silently run again). Fold both instead:
    //   grepInvert: process.env.QA_RUN_QUARANTINE === '1' ? /@mobile/ : /@quarantine|@mobile/
    // This project sets NO grepInvert of its own, so the top-level quarantine exclusion applies.
    // Spread `siteProjectDefaults` — do NOT hand-type `testIgnore`/`dependencies` here. That is
    // the drift this const exists to prevent, and a hand-typed `testIgnore: ['**/*.setup.ts']`
    // drops the two `_`-scratch globs, so this lane collects probe byproducts the other lanes
    // ignore. Same `(?:\s|$)` tag boundary as the app/admin greps above: a bare /@mobile/ also
    // matches @mobile-only / @mobile-safari and pulls those into the Pixel-7 viewport.
    // {
    //   name: 'mobile',
    //   use: { ...devices['Pixel 7'], baseURL: APP_BASE_URL },
    //   grep: /@mobile(?:\s|$)/,
    //   ...siteProjectDefaults,
    // },
    // Uncomment to expand browser coverage. Keep chromium as the default
    // smoke target — it's what the agents author against.
    // A cross-browser project is still a SITE project: it needs the same `grep` +
    // `siteProjectDefaults` as `app`, not a bare `use:`. Without `grep` it collects the
    // @site:admin specs too and runs them against APP_BASE_URL; without the defaults it has no
    // `dependencies: ['setup']` (every storageState spec runs unauthenticated) and re-runs the
    // `*.setup.ts` files as ordinary tests (F-018). Mirror the `app` project and change only
    // the device. For a second SITE on this browser, copy the `admin` block instead.
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'], baseURL: APP_BASE_URL },
    //   grep: /@site:app(?:\s|$)|^(?!.*@site:)/,
    //   ...siteProjectDefaults,
    // },
    // WebKit != Safari iOS. Playwright's
    // WebKit build approximates Safari on desktop; mobile Safari quirks
    // (viewport, touch, WKWebView, ITP) are NOT covered by this project.
    // For real iOS Safari coverage, use BrowserStack / Sauce Labs real devices.
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'], baseURL: APP_BASE_URL },
    //   grep: /@site:app(?:\s|$)|^(?!.*@site:)/,
    //   ...siteProjectDefaults,
    // },
  ],
});
