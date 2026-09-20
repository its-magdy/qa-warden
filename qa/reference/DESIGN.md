# QA-Toolkit — Design rationale (the *why*)

This is the small, durable "why" behind the `qa` plugin. It deliberately does **not**
restate operational facts — the oracle vocabulary, the reviewer's checks, the command
catalog, the argument shapes, the page-object rules. Those live in exactly one home each
(see [Where the operational facts live](#where-the-operational-facts-live)) and change as
the agents change. Everything here is meant to survive those mechanics changing.

If you want to *use* the plugin, read `README.md` and run `/qa:help`. This doc is for
maintainers deciding whether a design decision still holds.

## Contents
- [The economic thesis](#the-economic-thesis)
- [Why the oracle defenses exist](#why-the-oracle-defenses-exist)
  - [The generator does not grade itself](#the-generator-does-not-grade-itself)
- [How we differ from — and complement — official Playwright Test Agents](#how-we-differ-from--and-complement--official-playwright-test-agents)
- [Why context is tiered and dated](#why-context-is-tiered-and-dated)
- [CLI vs MCP: why the split](#cli-vs-mcp-why-the-split)
- [Honest limits & decisions that didn't pan out](#honest-limits--decisions-that-didnt-pan-out)
- [Site routing is tag-based, not path-based](#site-routing-is-tag-based-not-path-based)
- [Where the operational facts live](#where-the-operational-facts-live)

---

## The economic thesis

**AI authors, Playwright replays, AI triages only on failure.**

The expensive thing about an LLM-driven test is running the LLM. A pure-agentic nightly
suite (an agent drives the browser live for every test, every night) is expensive, flaky,
leaks memory, and — when wired through a consumer subscription — violates ToS. A
100-test nightly run that way costs on the order of **$3,000/month**.

So we only run the LLM where it is genuinely irreplaceable — **authoring** a spec and its
test, and **triaging** a failure. The nightly regression run is plain `npx playwright
test`: deterministic, no agent in the loop, **~$0 LLM cost**. Generate once, replay
forever. That single decision is ~90% of the cost win and takes the same suite to roughly
**$5–50/month** at API rates (or a flat subscription).

The corollary is a hard rule: **do not run an LLM on a green build.** The healer is
invoked *only* on a failing test. Running an agent over passing tests is the single
biggest wasted token budget in naïve AI-QA rollouts.

This pattern is not ours alone — Meta (TestGen-LLM), Airbnb, Microsoft (Playwright
Agents: Planner/Generator/Healer), Stripe, and Uber all converged on "AI authors +
deterministic replay" independently. Where it is the *wrong* model: pure behavioral
simulation (does a realistic shopper convert?) keeps agents live at runtime — that is a
different oracle (economic/behavioral, not correctness) and belongs in separate infra.

---

## Why the oracle defenses exist

The most dangerous failure is **not** a flaky test. It is a test that stays **green while
no longer exercising what it claims to test** — the "green-but-empty" or silent
false-pass. LLM-authored tests are especially prone to it: an agent will happily find a
new UI path that turns green, or quietly weaken an assertion, or write
`expect(true).toBe(true)` and call it a smoke test. (This is the most-reported failure
mode in the practitioner literature — the "93% coverage, 34% mutation score" genre.)

Every oracle defense in the toolkit is a specific answer to *that* problem. The **why**
behind each — the operational lists themselves live in CLAUDE.md and `agents/reviewer.md`:

- **A closed oracle vocabulary** exists so an assertion cannot be free-form. "Should look
  right" is unfalsifiable; a fixed set of keys forces every assertion to mean something a
  reviewer can check.
- **Step→assertion coverage** exists because the cheapest way to fake a passing test is to
  perform the steps and assert nothing. Requiring a real, failable `expect()` per step is
  the primary structural defense.
- **Assert intent, not observed behavior.** The oracle is written from what *correct*
  means (captured at intake as the test basis), not from what the app happens to do today.
  Encoding observed behavior means encoding today's bug as tomorrow's expected result — a
  passing test that certifies the defect. This is why the assertion contract is authored by
  the planner and is *sacred*: the healer may fix selectors and waits but must never touch
  assertions, and a changed-text failure escalates back to the planner rather than being
  "healed" away.
- **Metamorphic relations** exist as a check that needs no ground-truth answer. Instead of
  "is this output correct?" they ask "does an invariant-preserving transform of the input
  keep the output equal?" (reorder a cart → total unchanged; add-then-remove → identical
  state). That property makes them unusually well-suited to LLM-authored oracles, which
  cannot be trusted to know the right answer but *can* be trusted to preserve an invariant.
- **A structured output schema** exists so `passed=true` is not a word the agent can just
  emit — it must be backed by populated evidence fields (order id, observed total, …).
  (Convention — not mechanically validated; see CLAUDE.md §"Oracle defense".)

There are **no PreToolUse hooks** in this toolkit. There is no real-time guard that blocks
a weakened assertion the instant it is written. That is a deliberate decision, not an
oversight: the **reviewer is the backstop, by discipline**. It is load-bearing precisely
because nothing else enforces the assertion contract at PR time. Every agent that writes
must hold the line itself and rely on the reviewer to catch what slips.

### The generator does not grade itself

The oracle defenses above are only worth what their *evidence* is worth, and one piece of
that evidence used to be produced by an interested party. Until the compiler/verifier split,
a single `generator` agent both wrote the `expect(...)` and then decided, at its own steps
8b/8c, whether that `expect` catches an injected defect. Three properties made that
arrangement worse than it looks:

1. **The cheapest path is CATCHES.** A BLIND verdict costs the agent a bug file, a
   `test.fixme`, a withheld manifest and an escalation it must justify; CATCHES costs one
   comment. The incentive points the wrong way at exactly the moment the toolkit is deciding
   whether an assertion is real.
2. **The output is durable and trusted, not transient.** The `// verified: must_fail_when
   "…" → CATCHES` annotation persists in the test file. Reviewer **Check 2b** reads it as
   evidence; `/qa:doctor` Check 15b re-checks it — but only against the *spec's* invariant
   text, never against any record that a probe actually ran. **Nothing in the toolkit can
   detect a fabricated stamp.** A self-serving verdict therefore does not decay; it hardens
   into the record.
3. **The same blind spot writes both the test and its twin.** Metamorphic twins are supposed
   to be an independent restatement of the invariant. Authored by the agent that wrote the
   parent, a twin inherits that agent's model of the invariant and agrees with the parent
   *for the wrong reason* — which the reviewer then reads as corroboration. That is strictly
   worse than having no twin.

So `agents/verifier.md` is a separate agent, with its own `model: opus` pin, and one
prohibition that is the whole point: **it may not edit any `expect(...)`, locator, matcher or
asserted value.** When an oracle comes back BLIND it must diagnose and hand back — a
mis-compile to the generator, a decorative oracle to the planner — rather than adjusting the
assertion until the probe reads the way it wants. An agent that can rewrite what it is
grading is not a verifier.

This is the one place the toolkit buys an epistemic improvement rather than another check:
the other defenses add *more* judgments, while this one changes *who makes* an existing one.
The cost is a second subagent call per `/qa:gen` at authoring time only. Nightly replay is
still agent-free, so the "~$0 nightly" claim is untouched.

---

## How we differ from — and complement — official Playwright Test Agents

Microsoft shipped official **Playwright Test Agents** (Planner, Generator, Healer) in
Playwright **1.56** (Oct 2025), and 1.59/1.60 doubled down: agentic video receipts, a CLI
trace-analysis path, ARIA snapshots with geometry, and deeper Playwright MCP
integration (bundled with the framework itself since 1.62, via `npx playwright mcp`). That trio — explore → plan → generate → heal, with `.webm` receipts and
`npx playwright trace` — is *architecturally almost identical* to this toolkit's
planner/generator/healer + exploration + MCP-for-exploration. Any QA lead evaluating this
in 2026 will (correctly) ask: **"Why not just use the agents Microsoft now ships and
auto-updates with every Playwright release?"** The honest answer has two halves.

**What we do NOT claim as a differentiator.** The author/replay/heal *mechanics* are now
commodity. Microsoft maintains them, ships them with the framework, and improves them on
Playwright's cadence — which is faster than any third-party plugin can match. Re-implementing
that trio is a standing maintenance liability, and we should treat it as one. Where the
official agents are ahead (trace tooling, MCP surface, video receipts), prefer their
substrate over re-inventing it.

**What IS the moat — the oracle-defense + governance layer.** Microsoft's agents write a
plan, write tests, and heal them. What they deliberately do **not** provide is any defense
against a test that is *green but wrong*. This toolkit's real value is the layer the
official agents don't have:

- a **closed 16-key oracle vocabulary** — assertions can't be free-form "looks right"; every
  spec is mechanically checkable and every mirror is byte-verified in lockstep;
- a **load-bearing reviewer** that BLOCKS green-but-empty / green-but-wrong / launder-the-bug
  tests at PR time (Checks 1–2e, 14) — the official generator has no equivalent gate;
- the **intake → ideate → approve rigor lane** — human-grounded oracles with provenance
  stamps and an explicit human approval gate, not just an auto-generated plan;
- **metamorphic twins + step-8b fault injection** (both owned by the `verifier`) — proof each oracle actually goes RED on its
  declared defect, so a decorative assertion can't ship green;
- **conditional-park (P-14)** over `test.fail(true)` — a caught product bug is tracked, not
  laundered into the green roll-up.

**Positioning, therefore:** treat the official Planner/Generator/Healer as a *substrate we
can rebase onto* (inherit their upgrades for free) and keep our differentiation as the
oracle-defense + governance layer on top. Even before any such rebase, this is the framing
to lead with: *we are not a competitor to Playwright Agents — we are the correctness-and-governance
layer that a QA org needs on top of them.* The deeper the official agents get at authoring
and healing, the MORE valuable a rigorous oracle layer becomes — it is the one thing that
does not get cheaper as the mechanics commoditize.

---

## Why context is tiered and dated

Selectors drift faster than any document can be regenerated. A long-lived
selector/vocabulary catalog becomes a "God Object" that is confidently wrong past ~100
routes — the dominant page-object-scaling failure mode. Commercial tools (Stagehand,
Octomind, ZeroStep) all abandoned the static-catalog pattern for the same reason.

So context is split by **volatility**, not stuffed into one file:

- a small, always-loaded **hot tier** (durable facts: sites, auth, env, naming),
- **lazily-written specialist** files per (site, area), each **dated** and carrying a
  volatility tier, and
- **cold** selectors pulled live from the accessibility tree at generate time, never
  cached in a doc.

The line budgets (~80 / ~150) are tunable defaults; the validated principle is
"small always-loaded core + lazy specialists," which is what keeps the context window from
rotting as the app grows.

Two decisions here are worth recording because the obvious alternative is wrong:

- **Staleness is volatility-tiered, not a flat interval.** A single uniform threshold
  over-warns on stable surfaces and under-warns on volatile ones — a flat 30 days would let
  an auth or payments area drift three weeks past when it should have re-warned.
- **It stays time-based (with tiers), not event-driven.** The claim that event-driven
  refresh (on deploy, on auth change) categorically beats scheduled refresh **did not
  survive verification.** Event triggers remain a *future additive* layer, not a
  replacement for dated tiers.

---

## CLI vs MCP: why the split

The toolkit uses `@playwright/cli` (+ skill) as the default transport for the healer,
generator, and nightly runs, and reaches for Playwright MCP (bundled with Playwright
1.62+ via `npx playwright mcp`; the standalone `@playwright/mcp` package is legacy)
only for first-contact exploration. The reasoning is narrower than "CLI is cheaper," which is **not** true:

- **CLI wins on predictability and hygiene.** Its tool-schema overhead is tiny (~68 tokens
  vs MCP's ~3,600–4,200 always-loaded), context stays near-flat across many steps, and it
  does not exhibit MCP's documented idle memory growth / orphaned-process leaks. Across 100+
  nightly tests that context-window hygiene compounds.
- **MCP wins on wall-clock and, with caching on, on billed $/test.** The "MCP ~28% cheaper
  per test with prompt caching / ~2–3× faster per 10-step flow" figures are **illustrative /
  unverified internal estimates, not a sourced benchmark** (F-21) — and they cut *against* the
  published finding that the CLI is ~4–10× cheaper in *tokens* (Microsoft's own guidance now
  recommends the CLI over MCP for coding agents), so if anything they understate the CLI's
  advantage. Treat them as directional. **"CLI always wins" is still wrong on wall-clock** —
  MCP's live AX tree is faster for first contact — but do not cite these percentages as fact.
- **MCP's live AX tree is genuinely better for first contact**, when the agent knows
  nothing about the app.

So the split is about *predictability, memory-leak avoidance, and pairing cleanly with a
filesystem-native coding agent* — not raw $/test. That is why the healer reads `trace.zip`
from disk (the cheapest, CI-safe repeat loop) and why MCP stays out of the default project
config until you are actually authoring or healing.

---

## Honest limits & decisions that didn't pan out

These concessions are the most valuable part of this doc. Do not let a future pass quietly
delete them to make the toolkit sound more complete than it is.

- **A green a11y gate ≠ accessible.** Automated scanners (`@axe-core/playwright`) catch
  only ~20–30% of WCAG issues by success-criterion count (16 of ~50 SC, per Deque) — though ~57% by issue *volume* (F-20: the SC figure was overstated as 30–40%; the volume figure is Deque-sourced and accurate — high-frequency issues like alt-text/contrast dominate counts and are exactly what scanners catch). Worse, **AI-generated a11y fixes
  routinely satisfy the scanner while making the screen-reader experience worse** — adding
  `aria-label="button"` to a button that already had visible text, `alt="image"` to a
  decorative image. A human with a screen reader must review a11y fixes; never auto-merge a
  scanner-pass diff.
- **There is no automated mutation gate for `.spec.ts`.** Mutation testing (Stryker)
  covers **pure-TS units only** — helpers, reducers, factories that run in Node — because
  its instrumentation assumes Node execution and it ships no browser runner. For browser
  tests, `must_fail_when:` is optional to *declare* — but once declared it IS enforced:
  reviewer Check 2b FAILs a spec whose invariant isn't reified as an oracle, and the
  the verifier's step-8b negative control fault-injects it to prove the oracle goes red
  (see below); the agent-driven mutation skill was removed to keep the toolkit lean.
  Automated mutation coverage for browser tests is an open gap, not a shipped feature.
- **Visual regression needs a specialist past the obvious.** Self-hosted Playwright
  screenshot diffs catch gross layout breakage; the long tail (perceptual, cross-viewport,
  cross-browser) needs visual-AI. Applitools' 1B+ training-image model is a genuine moat you
  cannot self-host — pair with it (or Chromatic/Percy/Argos) for visually-critical UI.
- **MCP can be cheaper and faster per test than CLI** — see the section above. The CLI
  default is a hygiene decision, and honesty requires saying so.
- **No hooks ship.** The reviewer is the only enforcement of the assertion contract, by
  discipline. If a fork wants real-time enforcement it must add its own hooks.
- **Non-vacuity of ordinary oracles is LLM-judgment, not mechanical.** The generator's
  step-8b negative-control injection proves an assertion *actually fails on the defect* —
  but it runs **only** for declared `must_fail_when:`/`fail_if:` invariants. A plain
  happy-path oracle is *counted* (present, in-vocab, non-orphan) but never falsification-
  tested, so a **mis-chosen-but-valid** key ships green: e.g. a "filter to exactly one
  result" scenario asserted with `text_visible` (true on the unfiltered page too) instead
  of `count_equals`. Reviewer **Check 2c** (oracle discriminating-power) WARNs on this by
  *reasoning about intent vs. oracle* — it is a judgment call the closed vocab cannot prove
  mechanically. Keep the reviewer on a capable model; **do not** port it to a deterministic
  CI check and expect the same protection. This used to be operator discipline — no agent pinned
  a `model:`, so the reviewer could silently run its judgment checks (2b/2c/2d/2e/14) on a cost
  tier, and A-04's advisory made that degradation visible rather than silent (a guard, not a pin).
  **That is now a pin:** every agent declares an explicit `model:` — `reviewer`, `ideation` and
  `planner` and the new `verifier` on **opus**, the other three on **sonnet**. A pin RAISES the floor; it does not close
  the hole — and note it also LOWERS the ceiling: an operator running `claude --model opus` who
  invokes a sonnet-pinned agent gets sonnet, because the pin (priority 3) beats the session model
  (priority 4). The pin is a fixed tier, not a minimum. Claude
  Code resolves a subagent's model in this order: (1) the `CLAUDE_CODE_SUBAGENT_MODEL` env var,
  (2) a per-invocation `model` parameter, (3) this frontmatter pin, (4) the session model — so the
  pin sits at priority 3 and an env var or a caller-supplied override silently beats it. **Verified**
  (code.claude.com/docs/en/model-config.md, "Subagent Model Fallback", requires
  `"availableModels": [...]` + `"enforceAvailableModels": true` in settings): an org `availableModels`
  allowlist that excludes the pinned model does not fail the request — Claude Code falls back to the
  subagent's inherited model (the parent session's), warning in interactive sessions which model was
  substituted; a family-alias match (an older permitted version of the same tier) is tried before
  falling back to the inherited model. **This is exactly why A-04's advisory is kept rather than retired:** the pin covers
  the common case, and the advisory is the only thing that surfaces the uncommon one. The rule the split follows: an agent whose weak output
  surfaces as a *red test* (exploration, generator, healer — all grounded by a live AX
  snapshot or an actual run) can inherit a cheaper tier safely; an agent whose weak output is a
  *silently missing* finding — an unenforced assertion contract, an unenumerated case — cannot.
  **The `verifier` is on the silent side and is pinned to opus for the same reason the planner
  is.** Its output is a CATCHES/BLIND verdict, and a wrong CATCHES produces no red test: it
  produces a `// verified:` comment that reviewer Check 2b trusts and that `/qa:doctor` Check 15b
  only re-checks against the *spec*, never against any record that a probe ran. Nothing
  downstream can detect a fabricated stamp — which is also why the verifier must be a different
  agent from the one that wrote the assertion (see §"The generator does not grade itself").
  **The `planner` was moved to opus because this rule had it on the wrong side.** Its output is the
  *oracle*, and nothing downstream compares an oracle to reality — F-38 below says so outright, and
  the two backstops it names are both scoped by the planner's own text: step-8b injects only against
  invariants the planner chose to *declare*, and Check 2c's blocking FAIL is *title-anchored* (F-39),
  so a vaguer planner title silently downgrades the reviewer's FAIL to a WARN. A planner omission
  therefore produces no red test and no finding — it shrinks the net. It is also the cheapest agent
  to raise (16 turns, 3 reads, 1 write, no browser loop) and runs only at authoring time, so the
  "~$0 nightly" claim — which rests on agent-free replay — is untouched.
  A-04's advisory survives in reduced form: it now names the five checks as LLM-reasoned and WARNs
  only if the pin appears to have been overridden. The durable fix is to lift the prose "broken
  if…" statement into `must_fail_when:` (planner) so step-8b covers it.
- **The prod-guard rails are prose, so they are guarded by coverage, not by wording.** Ten skills
  carry the rail in two deliberately different lead forms with materially different bodies (each
  names the specific hole it plugs). Prose mirrors cannot `source` a file, so the copies can only
  be compared — but comparing the TEXT would fire on every edit and get the check disabled. What
  is invariant is that the guard is invoked and that a non-zero exit stops the skill, which is what
  **doctor Check 9bd** compares against `scripts/prod-guard-rails.txt`. The clause that actually
  needs guarding is the STOP: `flake-check` shipped once running the guard and ignoring its exit
  code, which on a repeat-each run multiplies the blast radius rather than reducing it. Building
  this check reproduced that same class of bug — a file-wide grep for the STOP clause passed a
  mutation test because an unrelated "STOP and ask" sat one line below the rail, so the comparison
  is scoped to the invocation line.
- **Turn budgets are a fail-safe; `maxTurns` is only a runaway ceiling.** Every agent states a
  turn budget in prose, and each one ends in a *behavior*: the healer files a bug and reverts the
  patch, the reviewer emits `reviewer inconclusive` (§"Fail-closed on inconclusive",
  `agents/reviewer.md`; CI keys on the FAIL verdict it carries),
  exploration and ideation write what they have under an incompleteness banner. The harness
  `maxTurns` field runs **none** of that — it hard-stops and returns output marked PARTIAL. So the
  two are not interchangeable and `maxTurns` must never be set *at* the prose number: pinned at
  the budget it would replace "file a bug and revert" with a half-applied patch and no bug, which
  is the exact silent-failure class this toolkit exists to prevent. Each agent therefore pins a
  ceiling strictly ABOVE its prose budget — an ordering **doctor Check 9bc now enforces**
  (nothing else compared the two: they live in different halves of different files, so a bump to
  either silently inverted the invariant with every check green) (planner 10→16, generator 16→22, verifier 18→24, ideation 20→28, exploration 30→40; reviewer 15→45, the widest gap, because its
  whole-tree fallback is not a wrap-up but a full alternate execution mode DESIGNED to exceed
  the budget — and because a cut-off there is uniquely dangerous: CI keys on a reviewer FAIL, so
  a hard-stop before the verdict is written reads as GREEN. The durable guard is the
  verdict-first rule (`agents/reviewer.md` §Inputs: write `PARTIAL REVIEW` + `FAIL
  (inconclusive-partial)` BEFORE the judgment pass, then revise N upward), which degrades to a
  truthful under-count instead of a false green; the ceiling only bounds a runaway;
  healer 14→24 because `HEALER_TURN_BUDGET` can raise the prose budget at runtime and the env var
  cannot raise the ceiling with it; verifier 18→24 because its budget-exhaustion fallback WRITES
  — it withholds the route manifest and files a durable `…-unverified.md` — so a hard-stop before
  the fallback would leave a green, twin-less, unverified spec looking finished). The agent's own fail-safe fires first; the harness only
  catches a genuine runaway. Same shape as the model pins: a rule that lived only in prose now
  also has the harness mechanism behind it, without the mechanism displacing the rule.
  **Caveat: the harness mechanism's reliability is unconfirmed.** `doctor` Check 9bc verifies the
  *ordering* of the two numbers, not that `maxTurns` itself fires — anthropics/claude-code#41143
  reports an agent pinned at `maxTurns: 10` running 70+ turns unimpeded, filed and closed
  not-planned. If that holds on the CLI version this toolkit's users run, `maxTurns` is
  best-effort, not a guaranteed backstop, and the agent's own prose-budget self-policing — not
  the harness ceiling — is the fail-safe actually doing the work. Re-verify empirically (drive an
  agent past its stated budget and confirm it is actually cut off) rather than trusting a green
  9bc as proof the runaway case is caught.
- **Parked defects are parked CONDITIONALLY, not `test.fail(true)` (P-14).** An unconditional
  `test.fail(true)` marks a test expected-to-fail for *any* reason — Playwright cannot scope
  which step must fail (playwright#27902) — so a later unrelated regression or a partial fix
  stays folded into the green roll-up: a laundered-green nightly blind spot. The generator
  parks a known defect **conditioned on the observed defective value** (`test.fail(<observed>
  ===<buggy>, 'bugs/…')`, the Playwright analogue of pytest's `xfail(raises=…)`) with the
  correct-value oracle asserted below it, so a *different* failure surfaces as unexpected.
  Reviewer Check 3 + `/qa:doctor` Check 11c cross-check that a parked marker's bug stays
  `Status: open`, recovering the cleanup signal the conditional form gives up (it
  self-neutralizes silently on fix).
- **No relational / exact-equality oracle key.** The closed 16-key vocab cannot directly
  express "A is byte-identical to B" or "this value *equals* a computed total exactly" —
  `value_between` only bounds one number against constants. This is deliberate (a relational
  key the reviewer couldn't structurally validate would weaken the closed-vocab guarantee).
  Sanctioned workarounds and the recipe for adding a new key beyond the current 16 if a project needs it are in
  `templates/CLAUDE.md` §"Honest limit — the relational / exact-equality gap".
- **Single-vendor multi-agent review shares blind spots.** All-Claude agents converge on
  the same failure modes under adversarial pressure (Nature 2026: a single compromised
  planner drops group accuracy 10–40%). For compliance-relevant specs a human *may*
  optionally re-run the reviewer checks through a non-Claude model — this is **pilot-only**,
  human-invoked, not a default. See `agents/reviewer.md` §"Cross-vendor reviewer note".
- **Plugin fixes do not auto-propagate to already-stamped substrate (F-015/F-016).** A
  Claude Code plugin ships the *brain* (agents + skills, which auto-update on upgrade)
  but the runtime *body* (`package.json`, `playwright.config.ts`, `prod-guard.*`, pinned
  deps) is **stamped once** by the skip-if-exists scaffold. So fixing a bug in a template
  file corrects every *new* project but leaves every *existing* one on the old copy — and the
  project deny-list (correctly) forbids agents from patching those files in place, so there
  is no silent auto-repair. The remedy is deliberately **human-invoked, not automatic**:
  `/qa:doctor` *detects* substrate drift (compares each stamped file against the shipped
  template) and `/qa:init --resync` *repairs* it (force-refresh toolkit-owned files, backing
  each up to `.qa-bak`, preserving `.env`/`CLAUDE.md`/user files). Automatic propagation is
  intentionally not offered — force-rewriting a project's build config on every plugin
  upgrade is more dangerous than a flagged, backed-up, opt-in resync.
- **The `.claude/settings.json` deny-list is defense-in-depth, NOT a hard boundary (S-2).** Claude Code
  matches permission rules on the *command string* (evaluated deny → ask → allow, first match), so it
  cannot inspect an interpreter's program text: with `Bash(awk *)` allowed, `awk 'BEGIN{system("rm -rf …")}'`
  matches the *allow* and the inner `rm` is never independently checked against `deny: Bash(rm *)`. We now
  deny the known escape idioms (`find … -delete`/`-exec`, `awk … system`, GNU `sed …e`), but these are
  substring denies defeatable by whitespace/quoting, and macOS `sed` lacks the `e` command entirely — so
  the sed patterns are Linux-CI-only and leaky. The same limitation means the deny-list cannot stop an
  *allowed* utility from writing a protected file through a side channel: `sort -o <file>`, `cat >`/`tee`
  redirection, `sed`'s `w` command, and `awk '… > "file"'` all write via primitives (`sort`/`cat`/`sed`/`awk`)
  that must stay allowed for the toolkit's own read/parse paths — enumerating every such vector is a losing
  game (which is itself the argument that the deny-list is not, and cannot be, the boundary). By the same
  token the **reviewer** subagent is `Read, Bash` and its read-only contract is prose, not an enforced
  per-agent allowlist (Claude Code scopes `Bash` per *project*, not per *agent*), so it too rests on the
  cooperative-agent assumption below, not on a hard guard. The **real** containment is not the deny-list: it is the
  QA-scoped `Write`/`Edit` allowlist (agents can only write `tests/`,`specs/`,`bugs/`,… ), per-prompt
  approval on anything unmatched, and the macOS OS-level Bash sandbox. Treat the deny-list as raising the
  bar on the *cooperative-agent / accidental-footgun* case, and do NOT rely on it as a prompt-injection
  boundary — a robust guard would need a `PreToolUse` hook, which this toolkit deliberately does not ship.
- **Green-but-incomplete: an approved case that never became a test.** Distinct from the wrong-spec
  gap below — here the human approved the *right* case, but it was silently dropped between the
  `.cases.md` checklist and the spec's `scenarios:` (the reviewer's Check 1/2 catch green-but-empty
  and 2b/2c/2d catch green-but-wrong, but neither proves an approved case was *built*). This made the
  human approval gate advisory: a lead reading a green suite believed the approved scope was tested.
  **reviewer Check 14** (approved-case traceability, WARN) closes the *silence* — it reads the
  `.cases.md` `> HUMAN APPROVAL` banner and WARNs on any approved case with no scenario and no waiver
  (a "Deferred"/"pruned" banner note or a `# waived:` spec note). It is a WARN, not a FAIL, because
  approval is free-text prose today; the deterministic-FAIL upgrade path is per-row case ids + a
  scenario `covers:` field (see §"Traceability" in `test-case-ideation.md`). A waiver that *fans* a
  case to a sibling spec (`# waived: … → specs/x.md`) only counts as descoping if that spec **exists** —
  otherwise the case is unbuilt AND its stated home is a phantom, so Check 14 keeps the WARN and
  `/qa:coverage` dim-5b lists the dead destination (the case reads as "handled" in both tools while
  nothing tests it). This does NOT close the wrong-spec gap below — it makes the approval gate
  load-bearing, not the completeness of the plan.
- **The un-closeable gap: a wrong spec is un-automatable.** Every defense above guards
  against *drift inside a correct spec*. If the human writes a YAML that does not reflect the
  real business rule, no oracle defense fixes it — metamorphic relations *narrow* the gap but
  do not close it. Completeness of *what* to test is undecidable, which is why the human
  approval gate on the ideation checklist is mandatory and non-negotiable.
- **The reviewer's two residual blind spots inside that gap (F-38/F-39).** Two specific, known ways a
  *wrong-but-agreed* spec slips even the oracle-fidelity checks — both facets of the un-closeable gap above,
  named here so they are a known ceiling, not a surprise:
  - **oracle↔test agreement is not oracle↔reality (F-38).** Check 2d compares the compiled `expect` against
    the oracle *literal* — if the oracle AND the test both assert the same *wrong* value (a "successful login"
    scenario whose oracle and test both key on `url_matches:"/login"` pre-submit), 2d passes because they
    agree; nothing compares either against a real observation. The backstops are the judgment checks (2c,
    title-vs-oracle) and the verifier's step-8b (which injects against the *declared* invariant, not against
    reality). Cheap future assist: capture one real observation at gen time and have the reviewer flag an
    oracle value that matches *no* observed value.
  - **Check 2c's mechanical FAIL is title-anchored, gameable from prose (F-39).** 2c FAILs a
    non-discriminating oracle only when an "exactly one/N" intent appears verbatim in the
    title/`must_fail_when`; the identical under-asserted oracle with that intent in *prose/comments only*
    downgrades to a non-blocking WARN — so softening the title wording ships the same dishonesty green.
    Broadening 2c to parse prose is deferred deliberately: it trades a concrete title-gaming path for added
    false-positive risk on a load-bearing gate.

---

## Site routing is tag-based, not path-based

A multi-site suite has to send `admin` specs at the admin baseURL. The obvious mechanism is a
Playwright project with a `testMatch` on `tests/admin/**` — routing by directory. This toolkit
routes by the **`@site:<id>` tag** the generator always emits instead, so `site=admin` alone sends
a spec to the admin baseURL wherever its area folder lives. Area directories stay a pure
organization choice, and `/qa:new-spec refund-partial site=admin` routes correctly without an
`admin/` folder.

**The trap in re-introducing a path-routed project:** Playwright **ANDs** a project's `testMatch`
with its `grep`. So once a project filters on both, a correctly-tagged spec whose area directory
does not match the project path satisfies neither project's full predicate — it matches nothing and
**runs nowhere**, silently. That is not a red — it is an absence: no result is reported for the
spec at all, so nothing in the roll-up distinguishes "never ran" from "was never written."
If a path-routed project is ever added, it must be tag-routed too.

## Where the operational facts live

Every fact below has exactly one authoritative home. Do not copy them here — point to them.

| Fact | Authoritative home |
|---|---|
| Oracle vocabulary (the 16 keys) + per-key argument shapes | `templates/CLAUDE.md` (stamped SoT). The **authoritative mirror list** is CLAUDE.md §"Test case format contract" — keys are ENUMERATED (an actual editable list) in `agents/planner.md`, `agents/generator.md`, reviewer Check 4, `scripts/oracle-keys.txt`, and `/qa:coverage`'s `KEYS_RE` grep — **those** are the sites to change in the same commit when adding/removing a key. `/qa:new-spec` and `/qa:review url=<url>` **defer** to CLAUDE.md and hold **no key list** (defer-only — nothing to edit there; F-03). The arg-shape table lives in CLAUDE.md + `planner.md`/`generator.md` (reviewer defers to CLAUDE.md for the arg-shape *contract*, though Check 4 does state shapes inline as counter-examples — so treat reviewer as a fifth, unguarded mirror). **The CLAUDE.md <-> planner.md pair is now guarded by doctor Check 9bb**, which compares shape EXPRESSIONS only (trailing prose deliberately differs and is not compared). generator.md's Oracle->expect mapping and DOCUMENTATION.md's numbered table are NOT comparable with that extractor — generator states shapes as INSTANTIATED examples (`{ locator: ..., n: 3 }`), DOCUMENTATION.md as a numbered table with shortened notes — so **doctor Check 9be** guards those two on the one thing that survives every format: the set of ARGUMENT NAMES, which is precisely what a mis-compile gets wrong (`{ count }` for `{ locator, n }` → the generator reads `.n` and drops the assertion). Normalising to arg names is also what keeps it quiet: `{ cookies?, localStorage? }` and `{ cookies?: [...], localStorage?: { key: value } }` compare equal. generator legitimately pins only 13 of 16 (attribute_equals / element_state / network_response_status are grouped as "straightforward one-line expect mappings"), so absence there is silent and only a pinned shape is compared. **reviewer Check 4 remains hand-kept** — it states shapes inline as prose counter-examples, deliberately quoting WRONG shapes (`count_equals: { count: 1 }`) beside right ones, so an arg-name extractor cannot tell a counter-example from a claim without reading the sentence. Change all ENUMERATING copies in one commit. |
| Reviewer checks (the full check suite) | `agents/reviewer.md` |
| Command catalog + workflow order | skill frontmatter under `skills/**`; `skills/help/SKILL.md` (or run `/qa:help`) |
| Skill invocation policy (who may invoke each `/qa:*`) | The `disable-model-invocation:` / `context:` frontmatter of each `skills/*/SKILL.md`, plus §"Why the invocation policy is what it is" below for the reasoning. Every skill is one of three shapes — see that section before adding a new one. |
| Page-object reuse rules | `templates/CLAUDE.md` §"Page-object reuse layer" |
| Subagent roster (models, tools, who-writes-what) | `templates/CLAUDE.md` §"Subagent roster" + `agents/**` |
| Prod-guard, env-loading, writable-path policy | `templates/CLAUDE.md` (policy). The shell guard implementation is `templates/scripts/prod-guard.sh`; the enforced `globalSetup` layer is `templates/scripts/prod-guard.ts` — their marker regexes must stay in lockstep. |
| Test-case ideation — operational mechanics (lens definitions, per-kind processes, artifact shapes) | `skills/intake/SKILL.md` + `agents/ideation.md` + the templates under `templates/specs/_context/_templates/`. The rationale + research grounding live in `reference/test-case-ideation.md` (which, per the maintenance rule below, must not restate the mechanics). |
| PR/Slack summary shape (totals, failures table, signature grouping, value ledger) | `skills/report/reference/report-template.md` — sole owner (moved out of `skills/report/SKILL.md` §"Template", which now points at it, to keep the skill under the ~5k-token ceiling), alongside the SCOPE line it derives from `--grep` in `.config.argv`. The shape used to live in a separate `report-summarizer` skill that `/qa:report` pointed at; the two carried divergent copies (report said "top 5 failing tests" vs. the summarizer's top-3-by-signature) and needed doctor Check 22 to police the split. Both that second file and that check are now retired — one file owns the shape, so there is no pointer to dangle. |

### Why the invocation policy is what it is

Custom commands were merged into skills upstream, so `commands/x.md` and `skills/x/SKILL.md`
both produce `/qa:x`. This plugin uses `skills/` exclusively (doctor Check 9d fails if a
`commands/` directory reappears) — the command side supports neither `context: fork` nor
`allowed-tools` nor bundled files. Three shapes, and a new `/qa:*` must pick one deliberately:

- **`disable-model-invocation: true`** — a user types it, Claude never reaches for it. Every
  skill with side effects: writes source or specs, deletes, drives a browser, or records a
  human decision. `/qa:approve` is the load-bearing case — it stamps the HUMAN APPROVAL banner
  that reviewer Check 14 reads, so a model able to invoke it could rubber-stamp its own test
  plan and the gate becomes fiction. `/qa:retire` and `/qa:init` are the destructive cases.
- **`context: fork` + `background: false`** — read-only analysis whose working output is bulky
  and whose *conclusion* is small. The fork keeps the walk out of the caller's context.
  **Constraint: the caller sees ONLY what a forked skill returns**, so every forked skill must
  say so in its body and return its full result, never a summary. A skill that interviews the
  user, or that already delegates to a subagent, must NOT be forked — a fork cannot pause for
  an answer, and forking a delegator just double-nests.
- **default (neither)** — read-only, cheap, and safe for Claude to reach for on its own.
  `/qa:explore` MUST stay here: `agents/planner.md` and `agents/healer.md` both STOP on stale
  context and rely on the orchestrator re-running `/qa:explore` and re-invoking them.
  `disable-model-invocation` there silently converts a documented-automatic handoff into a
  manual step. This was found and reverted during the migration; do not re-add it.

The general test: **can some agent or documented workflow reach this skill without a human
typing it?** If yes, it cannot be `disable-model-invocation: true`, however side-effecting it
looks.

**Maintenance rule:** if you find yourself about to document a mechanic here (a key, a
check, a command), stop — it belongs in one of the homes above. This file only holds the
reasoning that would still be true if that mechanic changed.

**F-ids:** comments across the plugin cite finding ids (`F04`, `F15`, `F-017`, `F51`, …).
These are historical review-pass anchors, not references — they resolve to no file in this
repo; the surrounding comment carries the actual failure mode. Treat them as changelog
breadcrumbs and do not add new ones without the failure description alongside.
