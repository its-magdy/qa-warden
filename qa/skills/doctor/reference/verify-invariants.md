# `--verify-invariants` — executable `must_fail_when` (targeted fault injection)

THE single source of the injection mechanism. Two consumers read this file and must not
diverge: the `/qa:doctor --verify-invariants` mode, and the **verifier** subagent.
The **verifier**'s Process step 8b runs this exact injection inline on every new spec that declares a
`must_fail_when:`/`fail_if:`. Do not invent a divergent mechanism in either place.

`must_fail_when:` is optional to *declare* (CLAUDE.md §"Test case format contract")
but enforced once declared — reviewer **Check 2b** proves each invariant is
*reified as an oracle*, but not that the oracle *actually catches* the defect. This flag closes that last gap with
a **targeted, per-invariant fault injection** — far cheaper than full mutation
testing (which the toolkit dropped to stay lean), because it injects only the ONE
named defect each `must_fail_when` describes and asserts the test goes red.

The mechanism is black-box-safe (it never touches app source) and has **two
injection arms** — pick per invariant:
- **backend/behaviour invariants** ("a token is written on an invalid path",
  "an order is created on a failed checkout") → `page.route()` fabricates the
  defect at the network boundary (example below);
- **rendered-value invariants** ("the total is charged outside range", "the
  confirmation text is removed") → a throwaway `page.evaluate(() => { … })` DOM
  mutation that corrupts exactly the value/text the oracle reads — cleaner than a
  network mock here because it needs no plausible backend response (it cannot
  fabricate an "impossible state"; it only corrupts what is already on screen).

Run the governed scenario under the injection and assert it now **FAILS**.
`page.route()` example for
`must_fail_when: "a token is written on any invalid-credential path"`:

```ts
// TEMP probe — not committed. Inject the defect: make a failed login return a token.
await page.route('**/api/auth/login', async (route) => {
  await route.fulfill({ status: 401, json: { error: 'Invalid', token: 'INJECTED' } });
});
// Run the wrong-password scenario. If the test STILL PASSES, its oracle does not
// enforce the invariant → the must_fail_when is decorative. It MUST go red here.
```

For each `must_fail_when`/`fail_if` in the spec: derive the smallest injection
(one of the two arms above) that simulates exactly that defect, run the governed
scenario under the injection, and report **CATCHES ✅** (test went red — invariant
is executable) or **BLIND ❌** (test stayed green — the oracle looks right but
doesn't actually fail on the defect; kick back to the planner — or to the generator if the oracle key is right and only the compiled `expect` is mis-wired). This is
opt-in and slower, so it is not part of the default read-only pass — run it on
security/negative-path specs where a silent-under-assertion is most costly.

**CATCHES requires two facts from the same run:** the governed scenario went red
under injection, **and** the failure output attributes the red to the invariant's
own compiled `expect` — match the reported `file:line` (or locator+matcher text)
against the expect that reifies this invariant. A red raised by a *different*
assert, or an action/navigation timeout, is **INCONCLUSIVE, not CATCHES** — a
co-assertion masked the probe; narrow the injection so it corrupts only what this
invariant's oracle reads and re-run. Do not comment out sibling assertions to
isolate — parse the failure attribution instead (one run, no restore step to get
wrong). An invariant that stays INCONCLUSIVE after a narrowed probe escalates
exactly like BLIND.

**Every injection run MUST pass `--retries=0 --reporter=line`** — the
run-of-record clobber-guard (why: CLAUDE.md §Reporting pipeline). These runs are
*deliberately red*; a bare run in a run-of-record context would record an
injected red as the suite's run-of-record. The default read-only pass writes
nothing; this opt-in mode must LEAVE nothing: the TEMP probe goes inside the existing
scenario for the one run and is reverted before you report — `git status --short tests/`
must show no change you made when you finish, and no report or run-of-record file is written.

**Relationship to the verifier.** The **verifier already runs this exact injection inline** at authoring (its Process step 8b, on every new spec that declares a `must_fail_when`/`fail_if`), and blocks a BLIND oracle before the spec ever ships — this file's mode is the **on-demand / CI re-check** of the same mechanism (re-verify after an app change, batch-verify a directory, or gate compliance specs). Both share the one mechanism defined in this file; keep them in sync.
