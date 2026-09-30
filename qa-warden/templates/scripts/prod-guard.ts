// ENFORCED prod-guard — runs as Playwright `globalSetup`, BEFORE any test.
//
// The command-layer prod-guard (scripts/prod-guard.sh — CLAUDE.md §Environment) is
// an advisory shell check an agent must remember to run. A bare `npx playwright test`
// with a prod BASE_URL_* bypasses it and runs the data-mutating suite against
// production (F-012). This module closes that hole: Playwright imports it once at
// startup, and a throw here aborts the ENTIRE run before a single browser opens —
// so even a plain `playwright test` (nightly, CI, ad-hoc) is guarded.
//
// It mirrors scripts/prod-guard.sh exactly (F-025-correct):
//   • screens EVERY exported BASE_URL_* (a multi-site @smoke run can touch
//     BASE_URL_ADMIN too), not just the primary target — PLUS API_URL / *_API_URL,
//     because the test-data-seed create/delete-users path drives API_URL directly and
//     a prod API_URL with a real admin token would mutate PRODUCTION rows outside a
//     BASE_URL-only guard (B-3). Keep this var-name set in lockstep with prod-guard.sh;
//   • WHATWG URL parse (`new URL().hostname`) so a scheme is stripped case-INsensitively
//     (`HTTPS://prod…`→host) AND userinfo can't masquerade as the host — a hand-rolled
//     first-`:`-cut returns the USERNAME for `https://user:pass@prod.acme.com`, silently
//     letting prod through (the F-012 hole this closes). Bare `host[:port]` values with no
//     scheme fall back to a scheme/userinfo strip + `:`/`/` cut — including `host:port`,
//     which new URL() mis-parses as scheme:path with an EMPTY hostname (see hostOf);
//   • word-boundary match `(^|[.-])(prod|production)\d*($|[.-])` so `product` /
//     `reproduction` do NOT trip but `admin-prod` / `shop.production.acme` / numbered
//     envs (`prod1`, `prod01`) DO;
//   • explicit `QA_ALLOW_PROD=1` escape hatch for the rare deliberate prod run —
//     it disables the prod-MARKER check ONLY; placeholder / unconfigured-target
//     refusals are config errors with no env escape (the fix is editing .env).
//
// Residual limit (same as the shell guard): a prod host with no telltale name
// (e.g. `www.acme.com`, an IP literal, or an alpha-suffixed `prodapi`) cannot be
// auto-detected — keep every BASE_URL_* on staging/QA explicitly.

import * as dotenv from 'dotenv';

// playwright.config.ts already loads .env, but globalSetup is a separate module and
// may be imported before that side effect is visible — load again (idempotent, quiet
// so the banner never corrupts a JSON reporter). See CLAUDE.md §Reporting pipeline.
dotenv.config({ quiet: true });

// `\d*` after the marker also trips numbered prod envs (`prod1`, `prod01`) while
// still NOT matching `product`/`reproduction` (a letter after the marker fails the
// trailing boundary). Mirror any change into scripts/prod-guard.sh's grep.
const PROD_RE = /(^|[.-])(prod|production)\d*($|[.-])/i;

// Placeholder sentinels (F-08), applied PER-VAR in the loop below — a CHANGEME left in a
// SECONDARY (BASE_URL_ADMIN) refuses too; an unset/empty secondary stays fine (only the
// primary is mandatory). Two subjects, deliberately split: CHANGEME/<> match the raw
// VALUE (not host-shaped); the RFC 2606/6761 reserved example domains match the extracted
// HOSTNAME label-anchored (`(^|\.)…$`) — an unanchored substring falsely refused real
// hosts like qa.example.company.com. NO QA_ALLOW_PROD exemption for placeholders or the
// empty primary: those are config errors, not accepted risks — the override covers the
// prod-marker check ONLY. Keep in lockstep with scripts/prod-guard.sh's two case patterns.
const PLACEHOLDER_VALUE_RE = /changeme|[<>]/i;
const PLACEHOLDER_HOST_RE = /(^|\.)example(\.(com|org|net))?$/i;

function hostOf(url: string): string {
  // WHATWG URL parse so userinfo/ports can't masquerade as the host (see the header
  // comment — this is the F-012 hole). Two scheme-less shapes need the fallback:
  //   • `prod.acme.com` (no port) — new URL() THROWS → caught below.
  //   • `prod.acme.com:8080` (with port) — new URL() does NOT throw: `prod.acme.com`
  //     is a syntactically valid RFC-3986 scheme, so it parses as scheme:path with an
  //     EMPTY hostname. An empty hostname never matches PROD_RE, so treating that
  //     parse as authoritative silently waves prod through — treat empty hostname as
  //     a parse failure and fall back (mirrors the shell guard, which catches it).
  try {
    const h = new URL(url).hostname;
    if (h) return h;
  } catch {
    // fall through to the scheme-less fallback below
  }
  // Not a usable absolute URL (a bare `host[:port]` with no scheme). Strip any
  // `scheme://` (the `//` is required, so a bare `host:port` is never eaten as a
  // scheme), then a protocol-relative `//`, then drop userinfo GREEDILY to the
  // last `@` before any `/ ? #` (mirrors the shell guard — a first-`@` cut leaves
  // part of the password looking like the host), then cut port/path/query/fragment.
  return url
    .replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '')
    .replace(/^\/\//, '')
    .replace(/^[^/?#]*@/, '')
    .replace(/[:/?#].*$/, '');
}

export default function globalProdGuard(): void {
  const allowProd = process.env.QA_ALLOW_PROD === '1';
  if (allowProd) {
    // eslint-disable-next-line no-console
    console.warn(
      '[prod-guard] QA_ALLOW_PROD=1 — prod-MARKER check disabled for this run ' +
        '(placeholder / unconfigured-target checks still apply).',
    );
  }

  // Fail-CLOSED on an unconfigured primary target (F-08) — lockstep with
  // scripts/prod-guard.sh. An empty primary means .env was copied but never set, so
  // REFUSE rather than run the mutating suite against a host the user never chose (the
  // old staging.example.com default ran silently). Placeholder (CHANGEME) detection is
  // PER-VAR in the loop below. Deliberately NOT exempted by QA_ALLOW_PROD — a config
  // error has no risk to accept; the only remedy is editing .env.
  const primary = process.env.BASE_URL_APP ?? process.env.BASE_URL ?? '';
  if (!primary) {
    throw new Error(
      '[prod-guard] REFUSING to run: BASE_URL_APP is empty.\n' +
        'Edit .env and set BASE_URL_APP to your staging/QA target before running the suite.',
    );
  }

  const offenders: string[] = [];
  const placeholders: string[] = [];
  for (const [name, value] of Object.entries(process.env)) {
    if (!/^(BASE_URL[A-Z0-9_]*|API_URL|[A-Z0-9_]*_API_URL)$/.test(name) || !value) continue;
    const host = hostOf(value);
    if (PLACEHOLDER_VALUE_RE.test(value) || PLACEHOLDER_HOST_RE.test(host)) {
      placeholders.push(`${name}=${maskUrl(value)}`);
      continue;
    }
    if (!allowProd && PROD_RE.test(host)) offenders.push(`${name}=${maskUrl(value)} (host: ${host})`);
  }

  if (placeholders.length > 0) {
    throw new Error(
      '[prod-guard] REFUSING to run: a screened URL var (BASE_URL_*/API_URL) is still a placeholder:\n' +
        placeholders.map((o) => `  • ${o}`).join('\n') +
        '\n\nEdit .env and set each to a real staging/QA target.',
    );
  }

  if (offenders.length > 0) {
    throw new Error(
      '[prod-guard] REFUSING to run: a screened URL var (BASE_URL_*/API_URL) looks like PRODUCTION:\n' +
        offenders.map((o) => `  • ${o}`).join('\n') +
        '\n\nThis suite mutates data. Point BASE_URL_* at staging/QA, or set ' +
        'QA_ALLOW_PROD=1 ONLY if you are certain this target is safe to run against.',
    );
  }
}

// mask userinfo credentials before ANY echo of a URL value — .env can carry
// `https://user:pass@host` targets and these throws land in agent transcripts /
// CI logs. Display-only: guard logic always uses the raw value.
function maskUrl(url: string): string {
  // greedy to the LAST pre-path @ — a password containing @ must not leak a fragment
  return url.replace(/^([a-zA-Z]+:\/\/)?[^/?#]*@/, '$1***@');
}
