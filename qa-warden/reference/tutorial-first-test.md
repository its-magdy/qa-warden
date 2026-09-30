# Tutorial: author your first test

**You will learn to:**
- turn a plain-language feature into an AI-written [Playwright](glossary.md) test,
- watch that test pass,
- **prove it would catch a bug** — so you know what "green" is worth.

This is a guided walkthrough. Follow it top to bottom, in order. Every step shows what you'll
see back, so you always know you're on track. When you're done you'll have one real, passing,
human-readable test — and you'll have seen the plugin do the thing that makes it different:
**refuse to pass when the check is a lie.**

> **What this runs against.** You run this against **your own app** on a non-production URL
> (localhost or staging). It uses a sign-in flow as the example — substitute your own
> feature names; the shape is identical. *(A zero-setup bundled demo app is on the
> roadmap — until then you supply the app.)*
>
> **You don't write or read test code.** The AI writes the [test](glossary.md) (the
> TypeScript). You read the human-readable [spec](glossary.md) and watch a video — that's
> the whole review surface. New words link to the **[glossary](glossary.md)**; you don't
> need to learn them first.

---

## Before you start

You need, once:
- the plugin installed — run these two commands in Claude Code:
  `/plugin marketplace add its-magdy/qa-warden`, then
  `/plugin install qa-warden@qa-warden --scope project`,
- **your app running and reachable** on a **non-production** URL (localhost or staging),
- a **test account** that already exists in that app (an email + password you can use) — unless
  your app has no login.

No Playwright knowledge required.

---

## Step 1 — stamp the project

```
/qa-warden:init
```
Run this **once** per project. It drops the runtime files in (config, scripts, a policy file,
a `.env.example`, and a `.env` made from it) and installs dependencies. You'll see one
`[qa-scaffold] created <file>` line per file, then `[qa-scaffold] done.` and a short **`Next:`**
list of the commands to run — the same path this tutorial walks you through.

Now **open the `.env` that init created** and set the URL and the test account — **never point at
production:**
```
BASE_URL_APP=http://localhost:3000        # your localhost or staging (a URL, not a real site)
QA_USER_EMAIL=member@example.test          # your existing test account
QA_USER_PASSWORD=your-test-password
```
No login in your app? Leave `QA_USER_*` blank: explore then drafts the site as `auth_mode: none`
(tests run signed-out) with a `# REVIEW:` line for you to confirm.

Check it worked: run `/qa-warden:doctor` — a healthy setup prints a short summary with **no ❌ blockers**. If it warns that `BASE_URL_APP` is empty or a placeholder and says "Setup is NOT ready yet — fill in .env", fix `.env` first. Doctor is read-only and **offline**: it confirms your config files, scripts, and the stock `.env` variables (including `BASE_URL_APP`) are in place — it does **not** reach `BASE_URL_APP` over the network. The next step (`/qa-warden:explore`) is what actually opens your app in a browser and confirms the URL really works.

## Step 2 — let the AI look at your app

```
/qa-warden:explore
```
The exploration agent opens your app in a real browser and writes a short **[context](glossary.md)**
file (`specs/_context/app.context.md`) describing what it found — the sites, how login works,
the naming. The **first** run writes it as a `draft:` — open that file, fix anything wrong, and
confirm it: delete the `draft:` line and the `> REVIEW:` banner, resolve any `# REVIEW:` notes,
and set `last_verified:` to today's date.

> You're teaching the AI the lay of the land once. **Heads-up:** the first time you run
> `/qa-warden:new-spec` for a new area (next step), it will *also* do a one-time deeper exploration of
> just that area — so Step 3 may open the browser again for a moment. That's expected.

## Step 3 — draft the spec

```
/qa-warden:new-spec auth/login
```
`auth/login` is the **[area](glossary.md)/feature** you're testing — a real value you type, not a
placeholder. The planner opens the sign-in screen and writes a human-readable **[spec](glossary.md)**
at `specs/auth/login.md`. Open it. The important part is the fenced **[oracle](glossary.md)** — the
plugin's definition of "correct." A complete spec looks like this:

```yaml
name: successful login
tags: [smoke, auth]                 # @smoke = the fast gate Step 6 runs
site: app                           # which app (matches app.context.md)
data:
  user:
    email: "member@example.test"    # inlined into the step below
    password_env: "QA_USER_PASSWORD" # the password comes from your .env, never written here
steps:
  - "Go to the login page"
  - "Fill Email with {{data.user.email}}"
  - "Fill Password with the test account's password"
  - "Click Sign in"
oracle:                             # closed vocabulary — 16 allowed keys
  url_matches: "/tasks"             # we land on the task list
  text_visible: "My tasks"          # the page actually rendered
```

Read the oracle like a sentence: *end up on `/tasks` with "My tasks" visible.* **This is your
one job:** read the oracle and ask *"would this actually catch the bug I care about?"* You can
do that without ever reading the TypeScript. (Notice the password is never written in the spec —
it comes from `QA_USER_PASSWORD` in your `.env`.)

## Step 4 — compile it and run it green

```
/qa-warden:gen specs/auth/login.md
```
`/qa-warden:gen` runs **two** AIs in a row. First the *generator* turns the spec into a real
[test](glossary.md) at `tests/auth/login.spec.ts`, runs it once, and leaves it **green**. Then a
second AI — the *verifier*, which did not write the test — checks that the green means something.
For every **[must_fail_when](glossary.md)** (or `fail_if`) rule a spec declares — "this test must
go red when *that* breaks" — it deliberately breaks that behaviour behind the scenes and confirms
your test actually turns **red**. An assertion that stays green even when the thing it checks is
broken is the one failure this whole toolkit exists to catch, and the AI that wrote the assertion
is the last one you'd ask to grade it. This simple example declares no `must_fail_when`, so the
verifier has nothing to break here — which is why Step 7 has you prove it by hand.

The verifier also saves a short **`.webm` video** of the run — open it and watch the AI drive your
real sign-in flow. *That video is your proof it tested the real thing* — you never read the
`.spec.ts`.

## Step 5 — let the gatekeeper check it

```
/qa-warden:review
```
The **[reviewer](glossary.md)** confirms every step is actually asserted, every assertion is in the
closed vocabulary, and nothing is green-but-empty. You'll get a short **PASS** report. (On a real
pull request — a "PR", the change you ask a teammate to merge — a FAIL here *blocks the merge*.)

## Step 6 — run the smoke gate

```
/qa-warden:run mode=smoke
```
Runs the `@smoke`-tagged tests with **no AI in the loop** — exactly what your nightly does, at
~$0. The summary leads with a one-line roll-up like `SMOKE: PASS (1/1)`. The test passes — **but passing isn't the point yet.** A green test
only matters if it would go *red* on a real problem. Let's prove it does.

---

## Step 7 — prove the test doesn't lie (no code needed)

A passing test is worthless if it passes no matter what. Here's how to prove yours is real —
by making the check *false* and watching it refuse to stay green:

1. Open `specs/auth/login.md`.
2. In the `oracle:`, change `text_visible: "My tasks"` to something the app never shows, e.g.
   `text_visible: "Totally wrong text"`.
3. Recompile: `/qa-warden:gen specs/auth/login.md`. Because the oracle is now deliberately false, the test
   **can't pass** — `/qa-warden:gen` runs it once and reports it **red ❌ right there**. The generator
   never loosens an assertion to go green, and a wrong expectation isn't a product bug, so it stops
   and reports red. `/qa-warden:run mode=smoke` then shows it red too.

It goes **red ❌**, with the failing step and a link to a **[trace](glossary.md)** — open it at
[trace.playwright.dev](https://trace.playwright.dev) (no install) and *see* every step and where
it stopped. **This is the whole point:** the oracle said "Totally wrong text" must be visible, the
app didn't show it, so the test refused to pass. Now change the oracle back to `"My tasks"`,
re-run step 3 (`/qa-warden:gen` again), and it's green again.

> **What happens in real life when a test goes red.** You won't hand-break tests — the nightly
> does it for you. When a run fails, you run `/qa-warden:heal <test-id>` (the `<test-id>` is printed in
> the red output). The **[healer](glossary.md)** reads the trace and:
> - if a button just moved or was renamed (**locator drift**), it patches the [locator](glossary.md)
>   and the test goes green — *it never changes what you asserted*;
> - if the app itself is genuinely broken, it never "fixes" the test to hide the bug: a defect the
>   spec already documents (`must_fail_when`/`fail_if`) stays **red on purpose**; a new, undocumented
>   bug is **filed in `bugs/`** and the test is marked as a known, tracked failure (an *expected
>   failure*, not green);
> - if your app's wording changed on purpose, it hands the spec back to the planner to update the
>   oracle — it will **not** silently rewrite your check.
>
> That boundary — fix the plumbing, never quietly weaken the contract — is why a green suite here
> means something.

---

## What just happened

You went from a plain-language feature to a test that **passes when the app is right and fails
when the check is wrong** — and you never wrote or read test code. The AI drafted; you read the
spec and watched the video; the reviewer enforced; and you saw the test refuse to lie.

**Honest limit (so green stays meaningful):** a test is only as good as its oracle. The plugin
fights weak oracles hard (the reviewer, `must_fail_when`, metamorphic twins), but **no tool can
prove an oracle is *complete*.** That's why your one standing job is the habit from Step 3: for
each spec, skim the oracle and ask *"would this catch the bug I actually care about?"* If you're
unsure, that's the signal to ask a developer.

## Where to go next

- **Test your own feature:** `/qa-warden:new-spec <your-area>/<your-feature>`, then repeat steps 3–6.
- **Not a coder, but you're the one signing off?** Read **[reviewing-without-code.md](reviewing-without-code.md)** — how to judge a test by its oracle + video (never the code), and the moments the plugin stops for your decision.
- **You already have manual test cases?** Run `/qa-warden:import-cases <area/feature>` with your export — see **[how-to-import-manual-cases.md](how-to-import-manual-cases.md)** for the full walkthrough.
- **A P1 / money / compliance flow?** Use the **[rigor lane](glossary.md)**:
  `/qa-warden:explore mode=area site=<id> area=<area>` → `/qa-warden:intake` → `/qa-warden:ideate` → `/qa-warden:approve` before `/qa-warden:new-spec` — it pins *what correct means* first.
- **Stuck / what's next?** Ask `/qa-warden:help` from inside your project.
- **Every command, in full:** the repo's `DOCUMENTATION.md` — or, from inside a project, ask `/qa-warden:help <command>` (every command self-documents; use this if you only have the installed plugin and not the repo checkout). **Why it works this way:** `DESIGN.md` (beside this file).
