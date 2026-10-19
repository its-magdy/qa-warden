# `hooks/` — the enforcement layer

Three files do the work: `hooks.json` registers two `PreToolUse` hooks on `Edit|Write`,
`assertion-contract.sh` guards the healer and the verifier, `spec-lint.sh` guards writes
into `tests/**` and `page-objects/**`. `hook-lib.sh` holds the guards both share.

## Why this exists, and why it did not until now

This toolkit shipped **no hooks** from its first day, as a stated decision rather than an
oversight (`MERGE-NOTES.md` decision 1, 2026-07): the reviewer was the backstop, *by
discipline*. That decision was right for the reason it gave — **a hook that blocks wrongly
breaks every session**, and a plugin hook fires in every repository its owner opens, not
just in a QA project. A false deny is not a warning an agent can reason past; it is a wall.

What changed is not the risk calculus. It is that the 2026-09-06 audit put a number on the
exposure: the moat holds, and the single thing left exposed is that **the gate is prose**.
Two contracts in particular were load-bearing and unenforced —

- `healer.md` said, in as many words, *"There is no real-time hook enforcing this — the
  reviewer's assertion-coverage checks are the backstop at PR time."*
- `verifier.md` Hard rule 1, shipped only in session 7, is the rule the whole
  generator→verifier split rests on. It was one paragraph of prose one trim pass away
  from vanishing.

So the reversal is **scoped, not wholesale**. A check earns a hook only if it is decidable
from the proposed text alone, with no repository context and no judgment call. Everything
else stays exactly where it was. The reviewer is still the backstop; what moved is the
timing of four lint FAILs and the enforcement of one contract.

## What IS hooked

| Hook | Fires for | Denies |
|---|---|---|
| `assertion-contract.sh` | `agent_type` = `healer` or `verifier`, editing `tests/**/*.spec.ts` | An edit that **removes or rewrites** an assertion that existed before it |
| `assertion-contract.sh` | `agent_type` = `healer` or `verifier`, editing `tests/**/*.oracle.ts` | An edit that **removes or rewrites** any code line of the oracle module (the expected values the spec imports, generator.md F-33). Adding an export stays allowed |
| `assertion-contract.sh` | `agent_type` = `healer` **only** | An edit that **introduces** a network stub (`.route` / `.routeFromHAR` / `.routeWebSocket`, on a page or a context) or a `.clock.*` call where the before-text had none |
| `spec-lint.sh` | any write to `tests/**/*.ts` or `page-objects/**/*.ts` | reviewer Check 1 (assert on a literal), Check 5 (`waitForTimeout` / `networkidle`), Check 9 (raw CSS/XPath), Check 11 (`.only`, `routeFromHAR`) |

The healer stub/clock arm is the newest and is a **different shape** from the others: it guards
against an addition, not a removal, because both constructs turn a red test green *without touching
a single assertion* — so the subset test above cannot see either. A backend that is genuinely down
is the most valuable signal the nightly produces, and `page.clock.runFor(2000)` is a sleep the
`waitForTimeout` ban does not lexically catch. It is **scoped to the healer alone, deliberately**:
the verifier's step-8b fault injection *is* a `page.route`, so widening this arm by one agent would
deny the negative control the whole oracle-defense layer rests on. It compares **counts**, so
healing a locator inside a scenario that legitimately declares a `fault:` step stays allowed.

`routeFromHAR` is the one construct in the network family that is banned outright rather than
governed: a suite served from a recorded HAR asserts the frontend against a frozen backend and
stays green through every server-side regression. It is purely lexical and has no legitimate use
here, so it clears the same bar as the other four. **`page.route` itself is NOT hooked for anyone
but the healer** — a declared `fault:` step compiles to one.

Both are **subset** tests, never equality: adding an assertion passes, removing one does not.
Both scan only the text being written — never the rest of the file — so a pre-existing
violation elsewhere can never make an unrelated correct edit unblockable.

## What is NOT hooked, and why

The audit's framing invites "turn the reviewer into a hook." Most of the reviewer cannot be
one, and saying so precisely is the point of this section.

| Check | Left with the reviewer because |
|---|---|
| 2, 2b, 6, 14 | Need the **paired spec YAML**, the `bugs/` tree or a Playwright run. A `PreToolUse` hook sees one tool call's input. |
| 2c, 2d, 2e | Explicitly judgment. 2c is a WARN *because* it is a judgment call; 2d asks whether a literal matches the oracle's real value. |
| 3 (unlinked `fixme`/`skip`/`fail`) | Decidable at rest, but **order-dependent at write time**: the healer's product-bug path writes the marker and `bugs/<slug>.md` in some order, and a hook denying the marker-first ordering would break the sanctioned path. `/qa-warden:doctor` Check 11c already covers it deterministically once both files exist. |
| 11, credential regex | `reviewer.md` documents this one against itself: *"a deterministic CI running this regex false-FAILs a spec the LLM reviewer would (correctly) reason past."* It carries three carve-outs (presence sentinels, `WRONG_`/`INVALID_` negative fixtures, comment lines) and its own note that the regex is "the floor, not the whole gate" — positional secrets need judgment. Denying on it would block a correct wrong-password test every time, which trains bypass. |
| 11, inline base URLs | `toHaveAttribute('href', 'https://…')` on an external link is a legitimate oracle, not a navigation target. Same false-FAIL shape. |
| 7, 8, 12, 13, 15 | Repository-wide reads (context freshness, `sites[]` table, consumer counts, diff direction). Not available at write time. |
| 2, `fault:` fired-proof | Needs the paired spec: the question is whether a `fault:` step has a `network_response_status` oracle backing it. Lexically invisible. |
| 5, undeclared `page.clock` | Same reason, and it is the arm that matters most for the clock: the *call* is legal, and only the paired spec's `steps:` says whether it was declared. The hook can only catch the healer **introducing** one (which it does); a generator emitting an undeclared clock call is the reviewer's. |
| 11, `page.route`/`page.clock` in `page-objects/**` | Decidable from the text alone, and a candidate — left out to keep this layer small and its deny surface predictable. A POM stub is rare, and the reviewer FAILs it. Revisit if it ever shows up in practice. |

## Safety properties

Every one of these is a deliberate constraint, not an accident of implementation.

1. **Fail-open, always.** Missing `jq`, unparseable payload, unbalanced parens in a source
   line, any internal error → `exit 0`, write proceeds. A bug in this layer degrades to
   "the reviewer catches it at PR time", never to "the agent cannot write a file".
2. **No-op outside a QA project.** The guard is `playwright.config.ts` **and**
   `scripts/prod-guard.ts` in the directory above `tests/`. `playwright.config.ts` alone
   would make this plugin lint every Playwright repository its owner opens.
3. **Comments are stripped before scanning.** The generated specs name the banned
   constructs in their own comments ("settle on the post-condition, never `networkidle`").
   A raw grep would deny the generator for documenting the rule it is obeying.
4. **One escape hatch, `QA_HOOKS_OFF=1`**, disabling the whole layer for a session. One
   greppable variable rather than N per-check toggles. It is *not* fail-closed on a
   placeholder the way `prod-guard` is: this layer protects a review contract, not a
   production database, and an operator who cannot switch a linter off routes around it.
   It must be set in the environment **Claude Code itself was launched with**, or in
   `.claude/settings.json`'s `env` block — a hook process is spawned by the harness and
   never sources the project's `.env`, so putting it there does nothing. This is also why
   it is deliberately absent from `templates/.env.example`.
5. **Deny reasons are actionable.** Each names the reviewer check, quotes the offending
   line, and says what to do instead — for the assertion hook, which agent to hand back to.

## Known limitation

`assertion-contract.sh` keys on the payload's `agent_type`, which the hook schema marks
optional. When it is absent — the main thread, or a harness that stops sending it — the
hook does not fire and the contract is prose again. It is **defence in depth for two known
agents, never the backstop.** `bin/qa-selfcheck` Check 9h guards the wiring; nothing can guard
the field's presence from inside a hook.

## Testing a change here

The hooks are pure stdin→stdout filters, so table-test them directly rather than by
driving an agent:

```bash
jq -nc '{tool_name:"Edit",agent_type:"healer",cwd:"'$PWD'",
         tool_input:{file_path:"'$PWD'/tests/a/b.spec.ts",
                     old_string:"await expect(x).toHaveText(\"42\");",
                     new_string:"await expect(x).toContainText(\"4\");"}}' \
  | ./hooks/assertion-contract.sh | jq .
```

Empty output = allowed. Run the same case with the edit inverted (nothing removed) and
confirm it comes back empty — a gate that never allows is as broken as one that never denies.

For the healer stub/clock arm specifically, the ALLOW cases are the ones worth keeping in a
regression table, because they are what a too-eager pattern would break: the **verifier** adding a
`page.route` probe, the healer re-pointing a locator inside a scenario that already stubs, and a
healer comment that merely *names* `page.route(`. All three must come back empty.

## Known limits (stateless by design — read before "fixing" a deny)

- **The hook cannot tell the verifier's own `expect` from the author's.** It compares the text
  before and after one edit, with no memory of earlier edits. So a step-8b probe that carries an
  `expect` line (or an `expect*` helper call) is allowed IN and denied OUT — through `Edit` and
  through a `Write` of the pre-probe file alike (run-01, O-59). `agents/verifier.md` therefore
  keeps probes injection-only and reverts them with one `Edit` of the inserted lines; the two
  `qa-hooktest` cases "verifier reverts an expect-free probe" / "…carries an expect" pin this.
- **Bash writes are invisible.** The matcher is `Edit|Write`. A `python3 - <<EOF`, `node -e`,
  `perl -i` or `cat > tests/x.spec.ts <<EOF` rewrite never reaches this hook, and the last one
  needs no permission prompt either: Claude Code checks a redirect target against the `Edit`
  allow rules, and the scaffold allows `Edit(tests/**)`. The agents are told to touch `tests/**`
  only with `Edit`/`Write`; the reviewer remains the backstop, as the first paragraph says.
- Any identifier containing `expect` followed by `(` counts as an assertion (`expectLoggedIn(`,
  `reportUnexpectedError(`). That is deliberate: a helper named `expect…` usually wraps one, and
  a false deny costs a handoff sentence while a false allow costs the moat.
