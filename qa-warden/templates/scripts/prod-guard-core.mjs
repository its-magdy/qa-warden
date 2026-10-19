// prod-guard-core.mjs — the ONE prod-guard verdict. Plain ESM, no dependencies.
//
// Both prod-guard layers ask THIS file, so they cannot disagree on what "prod" means:
//   • scripts/prod-guard.ts (the enforced Playwright globalSetup) imports screenTargets().
//   • scripts/prod-guard.sh (the agent-run shell guard) runs it once as a CLI:
//       node scripts/prod-guard-core.mjs screen [url ...]
//     and turns the machine-readable lines it prints into its human output.
// Before this file each layer parsed hosts its own way (sed in the .sh, `new URL()` in the .ts),
// and doctor kept four hand-mirrored literals in lockstep with greps. Measured on three URLs —
// `https://prod.acme.com\@staging.acme.dev`, `https://PROD%2Eacme.com` and a fullwidth
// `https://ｐｒｏｄ.acme.com` — the shell guard PASSED a host that WHATWG URL parsing (what a
// browser navigates to) resolves as prod.acme.com. One parser, one verdict.
//
// What it decides (unchanged from the two layers it replaces, except where WHATWG parsing
// intentionally changes the host):
//   • the screened var-name set: BASE_URL* (incl. the bare BASE_URL single-site forks use), API_URL
//     and *_API_URL — the test-data-seed create/delete-users path drives the API host directly, so a
//     prod API_URL with a real admin token would mutate production rows outside a BASE_URL-only
//     guard (B-3). Empty values are skipped: only the PRIMARY is mandatory.
//   • the primary: BASE_URL_APP, else BASE_URL. A SET-but-EMPTY BASE_URL_APP does NOT fall through to
//     BASE_URL (nullish, not falsy) — empty primary → refusal.
//   • host extraction: WHATWG `new URL().hostname` (scheme stripped case-insensitively, userinfo can
//     never masquerade as the host, `\` is `/` for http(s), percent-encoding and IDNA/fullwidth
//     forms are decoded the way a browser decodes them). Scheme-relative (`//host`) and scheme-less
//     `host[:port]` values go through the same parser too (see hostOf) — nothing is hand-stripped
//     ahead of it; a hand strip runs only when the parser rejects the value outright.
//   • placeholder sentinels (F-08), per var: CHANGEME / `<` / `>` anywhere in the VALUE; the RFC
//     2606/6761 reserved example domains LABEL-ANCHORED on the HOST (an unanchored substring falsely
//     refused qa.example.company.com). No env escape: a placeholder is a config error.
//   • the prod marker: `(^|[.-])(prod|production)\d*($|[.-])` on the host, case-insensitive — not a
//     bare `prod` substring (that false-positives on product/reproduction), but admin-prod,
//     shop.production.acme and numbered prod1/prod01 do trip.
//   • QA_ALLOW_PROD=1 (exactly "1") lifts the prod-MARKER check ONLY.
// Residual limit: a prod host with no telltale name (www.acme.com, an IP literal, `prodapi`) cannot
// be auto-detected — keep every BASE_URL_* on staging/QA explicitly.
//
// Toolkit-owned and edit-denied (.claude/settings.json); /qa-warden:init --resync refreshes it and
// /qa-warden:doctor Check 8 compares it with the plugin's copy.

import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const TARGET_NAME_RE = /^(BASE_URL[A-Z0-9_]*|API_URL|[A-Z0-9_]*_API_URL)$/;
export const PROD_RE = /(^|[.-])(prod|production)\d*($|[.-])/i;
export const PLACEHOLDER_VALUE_RE = /changeme|[<>]/i;
// `\.?` before `$`: a fully-qualified `example.com.` names the same reserved domain.
export const PLACEHOLDER_HOST_RE = /(^|\.)example(\.(com|org|net))?\.?$/i;

/**
 * The host a URL value points at.
 * @param {string} value
 * @returns {string}
 */
export function hostOf(value) {
  // The WHATWG parser decides every host it can. Nothing is hand-stripped before it runs: a strip
  // that cuts userinfo at `@` first reads `//prod.acme.com\@staging.acme.dev` as staging, while the
  // parser (and a browser) treats `\` as `/` and resolves prod.acme.com.
  // 1. An absolute URL. An EMPTY hostname is not a verdict: `prod.acme.com:8080` parses as
  //    scheme `prod.acme.com:` + path, and an empty host never matches the marker.
  try {
    const host = new URL(value).hostname;
    if (host) return host;
  } catch {
    // not absolute
  }
  // 2. Scheme-relative (`//host`, `/\host`, `\\host`): resolved against a special-scheme base,
  //    exactly as a browser resolves it on an http(s) page. A value with no authority of its own
  //    (`prod.acme.com`, a path) resolves to the base host — then it is not scheme-relative.
  const BASE_HOST = 'prod-guard-base.invalid';
  try {
    const host = new URL(value, `http://${BASE_HOST}/`).hostname;
    if (host && host !== BASE_HOST) return host;
  } catch {
    // not resolvable
  }
  // 3. A bare `host[:port]` with no scheme: the WHOLE value under `http://`, so the parser still
  //    owns userinfo, `\`, percent-encoding and IDNA (`PROD%2Eacme.com:8080`,
  //    `prod.acme.com\@staging.acme.dev` both resolve to prod.acme.com). Skipped for a value that
  //    already names a `scheme://` — prefixing one would make the scheme the host.
  const hasScheme = /^\s*[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(value);
  if (!hasScheme) {
    try {
      const host = new URL(`http://${value.trim()}`).hostname;
      if (host) return host;
    } catch {
      // not parseable
    }
  }
  // 4. The parser rejected the value outright (e.g. an invalid punycode label). Judge the host as
  //    written: strip a `scheme://` or leading slashes, treat `\` as `/` (as the parser would for
  //    http(s)), drop userinfo GREEDILY to the last `@` before any `/ ? #`, cut port/path/query.
  return value
    .trim()
    .replace(/\\/g, '/')
    .replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '')
    .replace(/^\/+/, '')
    .replace(/^[^/?#]*@/, '')
    .replace(/[:/?#].*$/, '')
    .toLowerCase();
}

/**
 * Display-only credential mask — the guard logic always uses the raw value. Greedy to the LAST
 * pre-path `@`, so a password containing `@` never leaks a fragment.
 * @param {string} value
 * @returns {string}
 */
export function maskUrl(value) {
  return value.replace(/^([a-zA-Z]+:\/\/)?[^/?#]*@/, '$1***@');
}

/**
 * The verdict for ONE value: 'placeholder' | 'prod' | 'ok'.
 * @param {string} value
 * @param {boolean} allowProd
 * @returns {{ host: string, verdict: 'placeholder' | 'prod' | 'ok' }}
 */
export function screenValue(value, allowProd) {
  const host = hostOf(value);
  if (PLACEHOLDER_VALUE_RE.test(value) || PLACEHOLDER_HOST_RE.test(host)) {
    return { host, verdict: 'placeholder' };
  }
  if (!allowProd && PROD_RE.test(host)) return { host, verdict: 'prod' };
  return { host, verdict: 'ok' };
}

/**
 * The screened var names present in `env`, sorted.
 * @param {Record<string, string | undefined>} env
 * @returns {string[]}
 */
export function targetNames(env) {
  return Object.keys(env)
    .filter((name) => TARGET_NAME_RE.test(name))
    .sort();
}

/**
 * The whole verdict: every screened env var with a non-empty value, then every argument URL.
 * @param {Record<string, string | undefined>} env
 * @param {string[]} [args]
 */
export function screenTargets(env, args = []) {
  const allowProd = env.QA_ALLOW_PROD === '1';
  const primary = env.BASE_URL_APP ?? env.BASE_URL ?? '';
  const primaryEmpty = primary === '';
  /** @type {{ kind: 'target' | 'argument', name: string, value: string, host: string, verdict: 'placeholder' | 'prod' | 'ok' }[]} */
  const results = [];
  for (const name of targetNames(env)) {
    const value = env[name];
    if (!value) continue;
    results.push({ kind: 'target', name, value, ...screenValue(value, allowProd) });
  }
  args.forEach((value, i) => {
    if (!value) return;
    results.push({ kind: 'argument', name: String(i + 1), value, ...screenValue(value, allowProd) });
  });
  const refused = primaryEmpty || results.some((r) => r.verdict !== 'ok');
  return { allowProd, primary, primaryEmpty, results, verdict: refused ? 'REFUSED' : 'PASS' };
}

// --- CLI mode (what scripts/prod-guard.sh runs) -------------------------------------------------
// Machine-readable, one TAB-separated record per line; the shell prints the human text itself
// (masking each value with its own mask()), so nothing here echoes a URL value.
//   node prod-guard-core.mjs names
//     <NAME>                                    one per screened var set in the environment
//   node prod-guard-core.mjs screen [url ...]
//     primary   set|empty
//     target    <NAME>  ok|placeholder|prod  <host>
//     argument  <N>     ok|placeholder|prod  <host>     N = 1-based position of the url argument
//     verdict   PASS|REFUSED                            always the LAST line
// A missing `verdict` line means the core did not finish — the shell guard refuses on that.
function cli(argv) {
  const [mode, ...rest] = argv;
  // A host is printed inside a TAB-separated line: never let a control character split it.
  const clean = (s) => s.replace(/[\u0000-\u001f\u007f]/g, '?');
  if (mode === 'names') {
    for (const name of targetNames(process.env)) {
      if (process.env[name]) console.log(name);
    }
    return 0;
  }
  if (mode === 'screen') {
    const result = screenTargets(process.env, rest);
    const lines = [`primary\t${result.primaryEmpty ? 'empty' : 'set'}`];
    for (const r of result.results) {
      lines.push(`${r.kind}\t${r.name}\t${r.verdict}\t${clean(r.host)}`);
    }
    lines.push(`verdict\t${result.verdict}`);
    console.log(lines.join('\n'));
    return 0;
  }
  console.error('usage: node prod-guard-core.mjs names | screen [url ...]');
  return 2;
}

// Run the CLI only when this file is the entry point, never on import from prod-guard.ts.
// Compared as real paths: Node resolves the entry module through symlinks (macOS /var is
// /private/var), argv[1] does not.
function isEntryPoint() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}
if (isEntryPoint()) {
  process.exitCode = cli(process.argv.slice(2));
}
