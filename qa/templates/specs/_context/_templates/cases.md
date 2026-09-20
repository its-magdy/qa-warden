<!--
CANDIDATE-CASE CHECKLIST template — written by /qa:ideate from the .basis.md.
This is a PLAN of what to test, NOT runnable tests. A human approves/prunes, then
each approved group → /qa:new-spec → /qa:gen.
☐ = pending approval · ☑ = approved · ~~strike~~ = pruned.
Group = one spec; its examples = that spec's scenarios. Delete this comment.

FORMAT NOTE (F-20): these rows are a HUMAN-REVIEW checklist (free-text, comment-flavored),
NOT a lintable structured schema. /qa:new-spec re-parses the prose. Two things guard against a
silently-dropped approved case: (1) the reviewer's **Check 14** (approved-case traceability) reads
this file's `> HUMAN APPROVAL` banner + rows and WARNs, per case, on an approved row that has no
scenario and no waiver — the per-case (LLM-judged, prose→scenario) signal; (2) /qa:coverage dim-5 is
the COARSE count companion (approved-case COUNT vs scenario count — it cannot verify each specific
row landed). Approval is read from the BANNER (a "Scope: …" / "Deferred: …" prose list), since the
☐/☑ boxes are often left un-flipped. The banner + the per-row ids are MINTED by `/qa:approve`
(hand-editing the banner remains the offline fallback). A conscious drop should be named under "Deferred"/"pruned" in
the banner OR carry a `# waived: <case> — <reason>` note in the spec (both suppress the Check 14
WARN). To upgrade Check 14 from WARN to a deterministic CI FAIL, give each row a stable id and have
the planner/generator carry `covers: [<id>]` on each scenario (see reference/test-case-ideation.md).
-->

# cases: <area>/<feature>   (kind: <kind>)

> HUMAN APPROVAL — recorded by /qa:approve <YYYY-MM-DD>     <!-- /qa:approve writes this banner
> Scope: <approved ids>  · Deferred: <ids — reason>  · Pruned: <ids — reason>
     and stamps row ids (R<rule#>.<letter> / NF.<slug> / C.<slug>, append-only — do not hand-renumber). -->

Rule: <blue-card rule text>
  ☐ [Function/happy]      <one-line case>            → oracle: text_visible                 risk: high  @smoke
  ☐ [Data/boundary]       <one-line case>            → oracle: text_visible + value_between  risk: high  @regression
  ☐ [Data/invalid]        <one-line case>            → oracle: error_shown + no_order_created risk: med   @regression
  ☐ [Operations/abuse]    <one-line case>            → oracle: element_state                 risk: high  @regression
  ☐ [Time/concurrency]    <one-line case>            → oracle: OUT-OF-VOCAB (race — see below)  coverage: partial  risk: med  @regression
  ☐ [Platform/a11y]       <one-line case>            → oracle: a11y_violations_below         risk: med   @regression
<!-- Each row: → oracle: <key(s)>  risk: <lvl>  @smoke|@regression.
     • TAG COLUMN drives the compiled spec's `tags:` — set @smoke for the thin critical path, @regression otherwise.
     • MULTI-KEY: most money/error-path cases need 2+ keys (text_visible + value_between; error_shown + no_order_created).
       List all keys the case needs — a single key silently under-specifies.
     • OUT-OF-VOCAB: a real case with no closed-vocab oracle (a concurrency race, a relational A==B equality)
       is marked `→ oracle: OUT-OF-VOCAB (<reason>)  coverage: partial` — NOT struck through and NOT dropped.
       This keeps the limit reviewable and stops it being mistaken for covered. A declared-required nonfunctional
       need whose only candidate is OUT-OF-VOCAB does NOT count as satisfied (see Critic).
     • IMPORTED rows (via the manual-cases-import recipe): `☐ [imported/<source> <ext-id>] <title> → oracle: <key(s)> risk: <lvl> @tag`
       — the external id IS the row id; `[also: …]` appends a duplicate source. -->

Rule: <next rule>
  ☐ ...

<!-- NON-FUNCTIONAL / CROSS-CUTTING group — a11y, dependency-failure, idempotency, and other
cases that do NOT map cleanly to a single blue rule (they attach to or cut across several). List them
here rather than forcing them under one rule. Each still routes to a spec: a11y usually rides the
feature's happy-path spec as an extra oracle; a dep-failure case may be its own negative spec.
A declared-required nonfunctional case listed here MUST land in a spec's `oracle:` (or be waived in that
spec's Open questions) — it must not evaporate between this checklist and the .md. -->
Non-functional / cross-cutting:
  ☐ [Platform/a11y]       <feature> form has no critical/serious violations  → oracle: a11y_violations_below  risk: med  @regression  → rides: <which spec>
  ☐ [Coupling/<channel>:<other-area>] oracle still holds under <the coupled rule's variation, e.g. multi-unit>  → oracle: <key(s)>  risk: <lvl>  @regression
<!-- COUPLING rows — one per basis `couples_with:` entry (a sibling area whose rule can invalidate an
oracle here). Exercise the oracle UNDER the coupling's variation (the multi-unit state, the unpublished
record) so an equality/aggregate oracle's precondition is TESTED, not assumed. The Critic WARNs on a
`couples_with:` entry with no matching [Coupling/*] row. Advisory (HTSM completeness reminder), not a gate. -->


Lens coverage: Structure ✓ · Function ✓ · Data ✓ · Operations ✓ · Time ✓ · Platform ✓ · Interfaces ✓ · Error-guessing ✓
<!-- every lens MUST appear, with ✓ or "0 — <reason>" -->

Critic:
  ⚠ WARN: <thin lens, if any — your judgment call, not a blocker>
  ⚠ WARN: <basis couples_with entry with no [Coupling/*] row — coupling completeness reminder, not a blocker>
  ⚠ WARN: <basis inputs[] partition with no matching row — F-19>
  ✗ FAIL: <declared non-functional need with zero matching cases — blocks until resolved>

Flow to specs: each rule above → one /qa:new-spec; its examples → that spec's scenarios:.

<!-- bug kind:
Regression case (@regression, MUST carry must_fail_when — advisory intent record):
  ☐ reproduces "<bug>" → asserts "<fixed behavior>"  → oracle: <key(s)>  risk: high  @regression   must_fail_when: "<defect it must catch>"
Metamorphic twins (via metamorphic-relations skill): <2-3 invariant twins>
Bug-class scan (WARN — consider, not required): same defect pattern may exist in <X>, <Y>
-->

<!-- enhancement kind:
New-behavior cases: <lens-rotated cases for what changed>
Regression set (from /qa:impact <route|field|factory|area|operation|source>): <affected existing specs>
  (GraphQL app? route= collapses to /graphql and discriminates nothing — use operation=.
   Business rule changed rather than code? source=<name> finds the basis rules standing on it.)
Safe fallback: full suite still runs as regression (npx playwright test) — impact selection
does NOT replace it.
-->
