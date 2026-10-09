# Security policy

## Reporting a vulnerability

Report it privately through **[GitHub's private vulnerability reporting](https://github.com/its-magdy/qa-warden/security/advisories/new)**
(Security tab → "Report a vulnerability"). Please don't open a public issue for it.

Include the plugin version (`qa-warden/.claude-plugin/plugin.json`), your Claude Code version, your OS,
and the smallest steps that reproduce it. You'll get an answer in the advisory thread.

## What counts

QA Warden guards against the AI itself loosening a test, and against tests running on production.
In scope:

- A way past the `PreToolUse` hooks (`qa-warden/hooks/`): an edit that weakens or removes an
  assertion, or writes a banned pattern, without being denied.
- A way past either prod-guard layer (`scripts/prod-guard.sh`, `scripts/prod-guard.ts`) that lets a
  run reach a production host.
- Credentials leaking from what the plugin writes or uploads: traces, reports, bug files, the
  nightly workflow's artifacts.
- A shipped permission rule in `templates/settings.json` that allows more than its comment says.

Known limits are documented and not vulnerabilities: a production host with no telltale name can't
be auto-detected (see `templates/CLAUDE.md` §Environment), the hooks only see Claude's own edits, and
`QA_HOOKS_OFF=1` turns them off on purpose.

## Supported versions

Only the latest release gets fixes. Update with `/plugin marketplace update qa-warden` then
`/plugin update qa-warden`.
