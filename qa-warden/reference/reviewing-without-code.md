# Reviewing AI-written tests (without reading code)

The AI writes the test code. Your job is **not** to read it — it's to judge whether the test
checks the *right thing*, and to step in at the few moments that need a human. This guide is
how you do both without reading a line of TypeScript.

> Haven't authored a test yet? Do the **[tutorial](tutorial-first-test.md)** first. New terms
> link to the **[glossary](glossary.md)**.

---

## The one thing to internalize: green ≠ correct

A passing (green) test *feels* like proof. It isn't. An AI can write a test that runs every
step and asserts **nothing meaningful** — it touches the feature without ever checking the
result was right. That "green but empty" test is the single failure mode this whole plugin
exists to prevent, and the reason your review matters.

The plugin fights it hard (see *What the plugin already checks* below), but **no tool can prove
a test checks *enough*.** That last judgment is yours. The good news: it takes one habit, not a
code review.

## The habit: say what it should prove — *before* you look

For each new test, **before** you check whether it's green:

1. Write one plain sentence: *"This test should prove that ___."*
   — e.g. *"…that a member cannot edit another member's task."*
2. Open the spec's **[oracle](glossary.md)** (the `oracle:` block in
   `specs/<area>/<feature>.md` — plain Markdown, no code) and check it actually asserts that.
3. If you can't tell whether it does, that's your signal to **ask a developer** — don't
   rubber-stamp the green.

Why *before*: once you see a green checkmark, the mind wants to agree with it (a well-studied
trap called **automation bias**). Deciding what the test *should* prove first keeps you honest.

## Your three review surfaces — none of them is code

You never open the `.spec.ts`. You review three things:

| Surface | What it is | What you check |
|---|---|---|
| **The oracle** | the `oracle:` block in the Markdown [spec](glossary.md) | does it assert what you said it should prove? is the *value* right — "403", not just "a response came back"? |
| **The confirmation video** | a `.webm` screen recording the verifier saves when a test is first created | did it drive the *real* flow you care about? |
| **The [trace](glossary.md)** (on failure) | a step-by-step replay at [trace.playwright.dev](https://trace.playwright.dev) — no install | *why* it failed — a real bug, or the test looking in the wrong place? |

If the oracle reads right, the video shows the real flow, it's green, **and you've checked it
covers the case you care about** — trust it. If any of those feels off, ask.

## What the plugin already checks for you

Your judgment is the last line, not the only one. Before a test can merge, automated gates run.
Treat them as a **first-line filter, not a replacement for your eyes**:

- the **[reviewer](glossary.md)** blocks any test with a step that isn't asserted, an assertion
  checking the *wrong value*, or an out-of-vocabulary "should look right" check;
- **[must_fail_when](glossary.md)**: the generator deliberately breaks the feature at authoring
  time and refuses to ship a test that stays green on the bug;
- **[metamorphic twins](glossary.md)**: extra tests that catch a spec that's subtly wrong.

So the common weak-test patterns are caught mechanically. What's left for you is the one thing a
machine can't judge: *is this checking the thing that matters?*

## When you must stop and decide — the gates

Most of the loop runs without you. A few moments need a human — and the plugin **stops for you**
at each. Everything in the right-hand column waits for your call:

| The plugin does this on its own (you still see the diff at review) | It STOPS and waits for your decision when… |
|---|---|
| re-points a moved or renamed button ([locator](glossary.md) drift) — and shows you the one-line diff to approve | a target looks like **production** — it refuses outright |
| adds a wait for a slow page | it would **delete or retire** a test/feature (`/qa-warden:retire` lists everything and waits) |
| retries a failed test a couple of times in CI, flagging it **flaky** if it only passes on a retry | a **batch fix** would edit many tests at once (`/qa-warden:batch-fix` shows the one pattern and waits) |
| replays the whole suite nightly, with no AI | it's deciding **what to test** — you approve the checklist (`/qa-warden:approve`) |
| — | it hits a **real product bug** — it files a bug you'll see and marks the test as a known, tracked failure; it never quietly "fixes" the test to hide the bug |

The **[healer](glossary.md)** is the clearest example: a teammate who fixes routine drift on its
own but **asks before anything significant**. It re-points a moved button — but shows you the
diff and never commits it for you (*zero silent commits*); a genuine bug becomes a filed report
you see; an intentional wording change goes back to update the spec. It **never** quietly weakens
what a test checks.

## The honest limits — when to bring in a developer

- **Completeness can't be automated.** The gates prove a test isn't *empty* or *wrong-valued*;
  they can't prove it covers *every* case that matters. That coverage judgment is yours (the
  habit above).
- **The sharpest oracles sometimes need a developer.** Pinning an exact error message or a
  specific API status is more precise when someone can look at the app's internals. A non-coder
  gets *working* tests; a developer can make the checks *stronger*. If a test feels vague
  ("it just checks the page loaded"), that's a good moment to ask one to enrich the oracle —
  show them the `oracle:` block in `specs/<area>/<feature>.md` (and, if it's failing, the trace).
- **You own "what to test."** The AI proposes; you approve. A checklist it generated is a plan,
  not a guarantee.

## In one line

**Read the oracle, watch the video, and for each test ask *"would this catch the bug I care
about?"*** — the plugin handles the mechanical checks and stops for you at the moments that
matter; judging whether a test covers *enough* stays your call.
