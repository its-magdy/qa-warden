---
description: Enumerate a CHECKLIST of candidate test cases for a feature/bug/enhancement via the ideation subagent (SFDIPOT lens fan-out + de-dup + risk-rank + completeness critic). Reads the .basis.md; produces .cases.md for you to approve/prune. Does NOT write specs or tests. PRECONDITION — a `.basis.md` must exist (run /qa:intake first).
argument-hint: "<area/feature> [site=<id>]"
disable-model-invocation: true
---

Delegate to the `ideation` subagent to turn the feature's **test basis** into
a reviewable **candidate-case checklist** — the "decide *what* to test" step that sits
between `/qa:intake` and `/qa:new-spec`.

**No argument given?** If `$ARGUMENTS` is empty, do **NOT** proceed — print the block below
verbatim and stop:

```
Usage:  /qa:ideate <area/feature> [site=<id>]
List candidate test cases for ONE feature (run /qa:intake first to capture its basis). For example:

  /qa:ideate auth/login            brainstorm cases for sign-in
  /qa:ideate tasks/update-task     brainstorm cases for editing a task

First time? Follow ${CLAUDE_PLUGIN_ROOT}/reference/tutorial-first-test.md.
```

Design rationale (maintainers, not required to run): the plugin's
`reference/test-case-ideation.md`.

Parse `$ARGUMENTS` for `<area/feature>` and optional `site=` (default `app`; must match a
`sites[].id` in `specs/_context/app.context.md` — same rule as `/qa:intake`), and pass the
RESOLVED basis path to the subagent in the delegation prompt — never leave `<site>` for it to guess.

The subagent reads
`specs/_context/<site>/<area>/<feature>.basis.md` and:

1. **Routes on `kind:`** in the basis — `feature` (broad SFDIPOT fan-out), `bug`
   (narrow: regression case + metamorphic twins + bug-class scan), `enhancement` (new
   cases + `/qa:impact` regression set), `refactor` (regression + invariance twins),
   `characterization` (narrow: one golden-master pin of observed behavior per pinned
   rule — every row carries `(provisional pin)` + the `@characterization` tag, no
   `must_fail_when:`; the invariant is "unchanged", not "correct").
2. **Rotates the full SFDIPOT lenses** (Structure/Function/Data/Interfaces/Platform/Operations/Time +
   error-guessing), logging every empty lens explicitly — never a silent skip.
3. **De-dups, risk-ranks** (NIST single-factor+pairwise first; RCRCRC change-proximity).
4. **Runs the completeness critic** — WARN on thin lenses; FAIL only on a declared-but-
   absent non-functional need (deterministic contradiction).
5. **Writes** `specs/_context/<site>/<area>/<feature>.cases.md`, grouped by rule so each
   group maps to one spec (its examples → that spec's `scenarios:`).

## Preconditions (the subagent enforces, but check first)
- The `.basis.md` MUST exist. If not, run `/qa:intake <area/feature>` first.
- Blocking 🔴 open questions in the basis MUST be resolved first — ideation refuses
  otherwise (you cannot enumerate cases honestly against an unknown oracle).

## After it returns
- → Run `/qa:approve <area/feature>` — the structured in-chat approve/prune round that
  mints row ids and records the `> HUMAN APPROVAL` banner reviewer Check 14 reads.
  (Fallback, offline: approve/prune by editing the file and write the banner yourself —
  same format; the command is the paved path, not the only path.) This is the human gate;
  do not rubber-stamp: completeness is undecidable and the critic's recall is unvalidated,
  so a thin lens is a prompt for *your* judgment, not a guarantee. For each approved group
  then: `/qa:new-spec <area/feature-case>`.
- For `bug`/`enhancement`: remember the full suite still runs as the safe-fallback
  regression (`npx playwright test`) — impact selection never replaces it.

## Hard rules
- This command NEVER writes `tests/**` or a `.spec` — checklist only.
- Do not skip the human approval step. The whole point of a separate `ideate` stage is
  to catch a missing/wrong case at the cheapest point, before it is baked into code.
