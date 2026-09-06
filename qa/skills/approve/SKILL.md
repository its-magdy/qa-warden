---
description: Record human approval of an ideated case checklist — mints stable row ids and writes the > HUMAN APPROVAL banner reviewer Check 14 (and the planner) read. PRECONDITION — a `.cases.md` must exist (run /qa:ideate first).
argument-hint: "<area/feature> [site=<id>]"
disable-model-invocation: true
---

Record the human approve/prune round for the candidate-case checklist `/qa:ideate`
produced — the structured form of the gate its closing line points at. This runs
**in the main session** (it is interactive); it does NOT delegate to a subagent.

**Interactivity contract (mirrors intake's F-16).** The round uses `AskUserQuestion`,
which exists **only in the main-session toolset — it is NOT available to subagents.**
This includes **forks** (`context: fork`): a fork inherits the parent's history, model and
tools, but `AskUserQuestion` is filtered out of it like the other main-session-only tools —
so `context: fork` is NOT an escape hatch for an interactive skill, and a forked skill that
prompts dead-calls it.
If `AskUserQuestion` is unavailable in your context, do NOT dead-call it or silently
skip the round: fall back to the same batched questions as plain in-chat prose and
read the human's typed reply. **NEVER infer approval from silence** — no answer means
nothing is recorded.

## What to do

1. **Resolve the checklist.** Parse `<area/feature>` and optional `site=` from
   `$ARGUMENTS` (site from the area's `app.context.md` when not passed). Target:
   `specs/_context/<site>/<area>/<feature>.cases.md`. Missing file → "run
   `/qa:ideate <area/feature>` first" and stop.
2. **Present each rule-group + its rows** in batches (≤4 questions per round):
   approve the group / prune named rows / defer named rows / **waive** named rows (out-of-vocab —
   a real case the closed 16-key oracle vocabulary cannot express, e.g. a cross-actor race).
3. **Write back:**
   - a stable id on every row lacking one — `R<rule#>.<letter>` for rule rows,
     `NF.<slug>` for non-functional rows, `C.<slug>` for coupling rows. Ids are
     APPEND-ONLY — never renumbered on later edits.
   - the banner immediately after the `# cases:` H1:
     ```
     > HUMAN APPROVAL — recorded by /qa:approve <YYYY-MM-DD>
     > Scope: R1, R2, R3.a-c, NF.a11y
     > Deferred (not pruned): R4.b — rate-limit
     > Waived (out-of-vocab): NF.race — cross-actor timing (no closed-vocab oracle key expresses it)
     > Pruned: R5 — out of scope
     ```
   - set the row marker to record the verdict — these are FIRST-CLASS states, not just banner
     lines, so a deferred or waived row never looks identical to a not-yet-reviewed `☐`:
     `☑` approved · `⏸` deferred (backlog, revisit later) · `⊘` waived (out-of-vocab, see banner) ·
     `~~strike~~` pruned (out of scope). A bare `☐` still means "not yet reviewed". Deferred, waived,
     and pruned rows all satisfy reviewer Check 14 (they need no scenario); only `☑` approved rows do.
4. **Close by printing the literal next commands — one per approved GROUP, not per row.**
   Do not restate the naming *rule* and leave the user to apply it: derive the slug yourself and
   emit the exact command line they can run, because this is the seam where the chain actually
   trips people (approve speaks in row ids — `R2`, `NF.a11y` — while `/qa:new-spec` wants a
   kebab-case subject slug, and nothing but this step knows both).

   Derive each slug from the group's SUBJECT, not its row id: whole-feature approval → no suffix;
   a scoped group → the subject in kebab-case; a non-functional group → the feature plus the
   quality name. Then print them as a block, e.g.:

   ```
   Next — one spec per approved group:
     /qa:new-spec checkout/coupon-stacking     # R2 — coupon stacking (rows R2.a-c)
     /qa:new-spec checkout/coupon-a11y         # NF.a11y — keyboard + SR labelling
   ```

   A single whole-feature approval collapses to one line (`/qa:new-spec auth/login`). The rule
   behind the derivation lives in `skills/new-spec/SKILL.md` §"Naming a fanned spec" — cite it
   only if the user asks *why* a slug looks the way it does; the command block is the deliverable.
   Deferred/waived rows get NO spec now — revisit deferred later; waived rows stand as logged risk.


## Hard rules
- Writes ONLY this one `.cases.md` — never `specs/<area>/*.md` or `tests/**`.
- Records ONLY what the answers say — no inferred approvals, no scope expansion.

## Honesty
This is process-level provenance, not tamper-evidence — any later session can edit the
banner; git blame is the audit trail. That is why Check 14 stays WARN: a forged banner
can suppress WARNs but cannot unlock a gate.
