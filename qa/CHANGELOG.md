# Changelog

All notable consumer-facing changes to the `qa` plugin.

The **last published build was `0.2.0` (2026-07-24)**. Everything below landed in the
repository since then and is released as **`0.3.0`**: a feature release on the published
`0.1.0 → 0.2.0` line, with no breaking change to the spec format or the `/qa:*` surface.
`.claude-plugin/plugin.json` reads `0.3.0`; tag the build with `claude plugin tag ./qa`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/). Versions are the
number in `plugin.json`, which is also the key the installer caches under
(`~/.claude/plugins/cache/<marketplace>/qa/<version>/`) — so **two different builds must
never carry the same number**, or the second one has no way to announce itself.

---

## [Unreleased]

Thirteen working sessions closing the 2026-09-06 audit (all four blocks). Four structural
changes a consumer cannot infer from a file diff, three deliberate decisions to change
nothing, and a large body of correctness work.

### Added — the generator/verifier split

`/qa:gen` is now a **two-call chain**: the `generator` compiles a spec to a `.spec.ts`, and a
new `verifier` agent checks it independently. Agent count 6 → 7.

- The split is enforced by a **prohibition, not a file boundary**: the verifier may not edit
  any `expect(...)`, locator, or asserted value. A mis-compile goes back to the generator with
  a `<file>:<line>`; a decorative oracle goes back to the planner. Without that rule the
  self-grading would just move one agent over.
- **Exactly one agent may declare `Write(artifacts/route-manifests/**)`, and it must be the
  verifier.** The route manifest is the ship signal and is gated on verification passing — if
  the generator reclaims the write, the gate detaches from the thing it gates.
- The generator keeps its name and its step numbers (`8a`–`8d`): those are shared vocabulary
  across reviewer Checks 2b/6, doctor 13/15b, the basis template and `DESIGN.md`.
- Enforced by new doctor **Check 9g**.

### Added — the `hooks/` enforcement layer

Two `PreToolUse` hooks now ship at the plugin root (auto-discovered; no `plugin.json` key).
This **reverses** a "no PreToolUse hooks" stance that had been stated as deliberate in ten
places — and the reversal is narrower than it sounds.

- `assertion-contract.sh` denies the healer or the verifier an edit that **removes or rewrites**
  an assertion. It is a **subset test, never equality**: adding assertions passes, and only the
  weakening direction is blocked. It compares matcher + asserted literal, masking the
  `expect(...)` *argument* (re-pointing a locator is the healer's actual job) and stripping
  options objects (`{ timeout: N }` is a sanctioned widen).
- `spec-lint.sh` covers the lexical bans that are decidable from the proposed text alone.
- **The bar for inclusion was "decidable from the proposed text alone."** Three reviewer checks
  deliberately did *not* clear it and remain the reviewer's job by discipline: Check 11's
  credential regex (documented as false-FAILing valid specs), Check 11's inline-URL gate (it
  false-FAILs a legitimate `toHaveAttribute('href', 'https://…')` oracle), and Check 3 (decidable
  at rest but order-dependent at write time). **The hooks are a floor, not a gate.**
- Plugin hooks fire in **every repository their owner opens**, so the layer is scoped by a
  two-file project marker (`playwright.config.ts` **and** `scripts/prod-guard.ts` — the config
  alone would lint every Playwright repo you own).
- Escape hatch: **`QA_HOOKS_OFF=1`**. It must be set in Claude Code's own environment — a hook
  never sources the project `.env`, which is why it is deliberately absent from `.env.example`.
- **Fail-open is proven, not asserted**: no `jq`, garbage stdin, empty stdin, missing
  `hook-lib.sh`, unbalanced parens in a source line — all exit 0.
- Enforced by new doctor **Check 9h**. Note its first arm exists because a dangling or
  non-executable hook command does **not** block: the harness logs an error and the write
  proceeds, so a broken gate reads as shipped while enforcing nothing.

### Added — `fault:` and `clock:` situation steps

Network interception (`page.route`) and `page.clock` are now available to the planner and
generator, unlocking Interfaces and Time cases that `/qa:ideate` had been enumerating and the
planner had been dropping for want of the APIs.

- **These are not oracle keys.** The oracle vocabulary stays at **16**. A stub sets up a
  *situation*; the oracle asserts the app's *degradation*, and existing keys already cover it.
- **Pair every `fault:` with `network_response_status: { url, status }`.** A `fault:` whose glob
  matches nothing is otherwise **silent** — the real server answers, the app behaves normally,
  and every oracle passes for the wrong reason. Asserting the injected status makes a missed
  stub go **red**, because the real response carries a different one.
- `advance:` vs `advance_idle:` is load-bearing: `runFor` fires **every** timer, `fastForward`
  fires each due timer **at most once**. `clock.install()` must precede navigation.
- **`routeFromHAR` replay is refused, not missing.** A suite served from a frozen backend stays
  green through every server-side regression, which inverts the economic thesis of the toolkit.
  It is now a lexical ban in `spec-lint.sh`. `recordHar` is also not shipped — a recorded HAR
  carries `Authorization`/`Cookie` request headers.
- `assertion-contract.sh` gains a **healer-only** arm denying an edit that *introduces* a
  `page.route`/`page.clock`: both make a red test green without touching a single assertion, so
  the subset test is blind to them. Scoped to the healer alone on purpose — the verifier's
  step-8b injection *is* a `page.route`.
- Known limit, recorded rather than filled: there is still **no request-side oracle** (you
  cannot assert the request the client sent).
- Enforced by new doctor **Check 9i**.

### Added — `test lock:` and Playwright 1.63.0

- `lock:` is adopted as a `TestDetails` field. **The generator owns both sides of it; the planner
  authors nothing**, because `lock:` is a `TestDetails` field rather than spec YAML.
- **`lock:` has no runtime observable at all**, so unlike `fault:` it has no oracle-key proof.
  The only thing that makes a lock mean anything is the second occurrence of its own symbol, so
  the proof is a **pairing** proof and it lives in doctor, not the vocabulary. New **Check 9l**,
  counted per **site, not per file** (two same-lock tests in one file genuinely do exclude each
  other under `fullyParallel`, so a file-granular count would fail a pairing that holds).
- Three properties were reproduced on a real 1.63.0 fixture rather than trusted: a lock-sharing
  pair **split across shards** runs concurrently; a locked test inside a hooked `describe.parallel`
  **stalls its unlocked neighbour**; a **singleton lock overlaps everything**.
- Playwright pinned **1.61.1 → 1.63.0** for anyone upgrading from 0.2.0 (the repo passed through
  1.62.1 in between, which was never published either). All four lockstep sites move together —
  `@playwright/test`, `overrides.playwright`, `overrides.playwright-core`, and the version-pinned
  `npx` argument in `.mcp.explore.json` — enforced by doctor **Check 8b**.
- Doctor Check 13's isolation-marker grep no longer WARNs on a spec isolated only by a lock.

### Decided — three evaluations that deliberately changed nothing

These are **verdicts, not omissions**. Each was worked as a full item and closed on the evidence.

- **Split `exploration` into hot/area agents → KEEP ONE AGENT.** A split needs a prohibition to
  carry it (the verifier's `expect()` ban is what makes the generator split work); the
  provisioning lens came back empty for the first time; and the split would not have fixed the
  footgun anyway, since every live bad instance is an under-specified *area* invocation. **What
  shipped instead**: the silent `mode=hot` default was fixed, five live bad `/qa:explore`
  invocations in the toolkit's own text were corrected, and doctor **Check 9j** was added.
- **Merge `/qa:coverage` into `/qa:impact` → KEEP TWO COMMANDS.** They have different argument
  shapes, different per-script `allowed-tools` that a merge would widen, and one is a read-only
  query that would inherit a writing contract. The shared logic was **extracted** instead
  (following the `spec-links.sh` precedent). New doctor **Check 9k**.
- **Playwright 1.63.0 → initially STAY, then reversed.** Session 10 read 1.63.0's own `.d.ts` and
  shipped runner bundle and refuted two of three claimed features, so the bump was declined. It
  was reversed once `test lock:` turned out to be the thing the bump actually enabled. Session
  10's real output was doctor **Check 8b** widened to all four lockstep sites, which is what made
  the eventual bump safe.

### Changed — correctness and safety

- **Healer could not execute its own process** — turn budget was below its own documented floor.
- **`/qa:new-spec` silently destroyed an existing spec.** Fixed.
- Generator read `mutates_server_state` from the wrong file.
- Reviewer FAILed on a form the planner never emits.
- `invariant_holds_when:` had two incompatible shapes.
- A silent **third permission tier**: eight `resync-set` members sat inside a `Write(specs/**)` /
  `Write(fixtures/**)` allow glob, so an agent could clobber `_templates/basis.md` with **no
  prompt at all**, corrupting every later `/qa:intake`.
- `approve`'s `⊘` waived rows matched neither reviewer waiver form, so a correctly-waived case
  warned forever.
- **All 7 agents now pin `model:` in frontmatter** (`opus` for planner/ideation/reviewer/
  verifier, `sonnet` for exploration/generator/healer). This reverses an earlier no-pin
  decision. Cost impact is authoring-time only — the nightly Playwright replay is unchanged.
- `report/SKILL.md` brought back under the size ceiling (21,725 → 17,695 bytes); **no skill now
  exceeds it.**
- Prod-guard `.ts` ↔ `.sh` parity audited differentially (55 cases, 54 identical verdicts; the
  one divergence is diagnostic-only and both layers still refuse).

### Changed — plugin layout

All `/qa:*` entry points now live at `skills/<name>/SKILL.md`. The old `commands/` directory is
gone (0.2.0 shipped 21 commands + 6 skills; this build ships 23 skills and no `commands/`). A
`commands/x.md` and a `skills/x/SKILL.md` both define `/qa:x`, so the two layouts coexisting is
invisible until behaviour diverges — doctor **Check 9d** now fails on a reappearance.

### Changed — doctor

**27 → 43 checks** for anyone coming from 0.2.0.

Check 9 also gained a **CLAUDE.md vocabulary containment** sub-check, which closes the widest
hole in the upgrade path itself. `CLAUDE.md` is shared-ownership, so `--resync` skips it *and*
Check 9's byte-compare skips it — both right in isolation, but together they meant the one file
every new authoring feature is documented in was the one file an upgrade could not deliver, and
nothing said so. It now WARNs per missing toolkit-owned symbol (manifest:
`scripts/claude-md-vocab.txt`), naming the reason and the template to diff against. Symbols, not
sections, on measurement: across the 0.2.0 → this-release upgrade the `## ` heading set is
identical (19 = 19) while the 93 new lines land inside ten pre-existing sections, so a
section-level diff would have reported green on precisely this release.

---

## Upgrading from 0.2.0

Verified end-to-end on a scratch project stamped from the published 0.2.0 build, on
2026-09-20. The numbers below are measured, not estimated.

```sh
# 1. Update the plugin, then restart Claude Code.
# 2. Refresh the toolkit-owned substrate (20 of 30 files change; each is backed up to .qa-bak):
/qa:init --resync
# 3. Re-run the plain init — --resync does NOT merge permissions:
/qa:init
# 4. Chromium 1228 -> 1243 (Chrome 149 -> 153). --resync runs `npm install` but NOT this:
bash scripts/init.sh        # or: npx playwright install chromium
# 5. Check what is left:
/qa:doctor
```

### Step 3 is not optional

`--resync` refreshes files; it does **not** run the `.claude/settings.json` permission merge.
A 0.2.0 project that only resyncs is missing **37 permission rules** this build needs (measured).
The plain `/qa:init` is idempotent and does the additive `jq` merge.

Doctor will nudge you, but only partly: **Check 9f is scoped to `mcp__` entries**, so it reports 2 of
those 37 and nothing covers the other 35 `Bash`/`Edit` rules. Run step 3 even if doctor is quiet.

### Four permission rules must be deleted BY HAND

The settings merge is an additive union — it can add a rule but can never remove one. Doctor
**Check 9c** names them; delete each from `.claude/settings.json`:

| Retired rule | Why it must go |
|---|---|
| `Bash(sed *e)` | Over-blocks ordinary `sed`; a deny cannot be interactively approved |
| `Bash(sed *e *)` | Same |
| `Bash(sed *e;*)` | Same |
| `Bash(printenv)` | **Security.** Auto-approves a bare `printenv` — a dump of every `.env` secret loaded in that shell (`QA_ADMIN_PASSWORD`, `QA_TOTP_SECRET`, `QA_CLIENT_CERT_PASSPHRASE`) straight into the transcript. Nothing ever consumed it; the mandated form is the scoped `printenv $base_url_env`, still covered by `Bash(printenv *)`. |

The replacements for the `sed` rules are `Bash(sed *e'*)` and `Bash(sed *e"*)`.

### Three files `--resync` will never touch — merge them by hand

These are shared-ownership by design (you edit them), so the resync skips them. Measured drift
from the 0.2.0 templates:

| File | Drift | What you lose by skipping it |
|---|---|---|
| `CLAUDE.md` | **122 lines, +13.5 KB** | **All four structural features of this release.** After a clean, green `--resync` the project's `CLAUDE.md` contains **zero** mentions of `lock:`, `fault:`, `clock:` or `verifier`. The in-project agents read this file, not the plugin. **Doctor now names this gap** — see below. |
| `.gitignore` | 9 lines | The `*.qa-bak` rule, among others — see below. |
| `.env.example` | 8 lines | New optional seed/config vars. |

Diff each against `<plugin>/templates/` and port what you want.

`CLAUDE.md` is the one that costs you a feature rather than a convenience, so it is no longer
silent. Doctor's **CLAUDE.md vocabulary containment** sub-check (Check 9, new in this release)
greps your stamped `CLAUDE.md` for the toolkit-owned symbols in
`scripts/claude-md-vocab.txt` and WARNs per missing symbol with the reason and the template path
to diff against. On a freshly-resynced 0.2.0 project it emits exactly four warnings — `fault:`,
`clock:`, `lock:`, `verifier` — and they clear as you port the prose across.

It **warns rather than fails**: the repair is a hand-merge, not a command, and a repair the
toolkit cannot perform for you should not red your CI. It matches on symbol *presence* anywhere
in the file, so rewording and your own additions are free — only a deletion is reported.

### `--resync` litters files your old `.gitignore` does not cover

The `*.qa-bak` ignore rule shipped **after** 0.2.0, and `.gitignore` is one of the files
`--resync` will not overwrite. On the scratch project the resync produced **13 untracked
`.qa-bak` files, none of them ignored** — all of them commit-bait on the next `git add -A`.

Either add `*.qa-bak` to `.gitignore` before step 2, or review and delete the backups after.

### What a clean upgrade looks like

On the scratch project, after steps 1–4, `/qa:doctor` exits **0** with only the four
hand-delete warnings above, the four `CLAUDE.md` vocabulary warnings until you merge that file,
plus two environment notes (`ripgrep` not installed, no `artifacts/last-run.json` yet).
`playwright lockstep: 3/3 … at 1.63.0 ✅`, and no substrate drift.
