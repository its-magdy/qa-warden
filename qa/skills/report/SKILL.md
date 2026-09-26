---
description: Aggregate artifacts/last-run.json + reports/*.json into a PR/Slack-ready summary — totals, failure-signature grouping, durations, flake/retry surfacing, parked defects, value ledger. Use at the end of a run-of-record suite run (CI, or QA_RUN_OF_RECORD=1), or ad-hoc when asked "what did the suite just do?"
argument-hint: ""
---

Produce a compact, human-readable summary of the most recent QA run. Pure aggregation
over on-disk artifacts — this skill owns both the run-scope qualification and the summary
template below. It does NOT rerun any tests, does NOT invoke the healer, and does NOT hit
the network.

Inputs:

- `artifacts/last-run.json` (config `json` reporter output). This is the primary
  sink. `dotenv.config({ quiet: true })` keeps it valid JSON, and `/qa-warden:run mode=smoke`
  refreshes it. **Staleness guard:** `/qa-warden:run mode=single` and `/qa-warden:run mode=repeat` pass
  explicit `--reporter=…` (for per-command files) and therefore do NOT refresh
  `last-run.json`, and a re-run in a run-of-record context (CI, or an inherited
  `QA_RUN_OF_RECORD=1`) without `--reporter=line` can silently overwrite the
  smoke stats you assume are there. **Run this scripted freshness check before
  aggregating — do not rely on eyeballing it:**

  ```bash
  # LOCKSTEP with /qa-warden:doctor Check 1 — the gate is single-sourced in
  # scripts/check-last-run.sh — do not re-derive here (the two used to mirror the
  # logic in prose and drifted). Its total = expected+unexpected+skipped+flaky —
  # every RESOLVED test — so an all-red run reads as fresh, never as zero-test
  # (`expected` alone counts only PASSED tests).
  if [ -f scripts/check-last-run.sh ]; then
    # CAPTURE the line — the SCOPE block below needs the recorded test count, and re-running the
    # whole script later just to `sed` `total=` back out of it re-parsed the same JSON a second
    # time (plus a bash fork). One read, reused.
    LR=$(bash scripts/check-last-run.sh artifacts/last-run.json 900); lr_rc=$?
    echo "$LR"
    NRUN=$(printf '%s' "$LR" | sed -nE 's/.*total=([0-9-]+).*/\1/p')
    case $lr_rc in
      0) : ;;                                                                     # fresh — summarize it
      3) echo "no last-run.json — use reports/*.json or refresh" ;;
      4) echo "WARN: last-run.json unparseable — the run-of-record is corrupt; do NOT summarize it" ;;
      5) echo "WARN: recorded 0 tests — do NOT report this as green" ;;
      6) echo "WARN: >15min old — confirm it is the run you intend to summarize" ;;
    esac
  else
    echo "WARN: scripts/check-last-run.sh missing — substrate predates it; re-run /qa-warden:init --resync (do NOT summarize an unverified last-run.json)"
  fi
  ```
  If the recorded count / age don't match the run you meant to summarize, either
  (a) prefer the per-command `reports/*.json` / `artifacts/flake-*.json`, or
  (b) refresh via `/qa-warden:run mode=smoke` or `QA_RUN_OF_RECORD=1 npx playwright test`
  (the config's `json` sink is gated to run-of-record runs — a plain local
  `npx playwright test` does not rewrite `last-run.json`). Do NOT report
  numbers from a `last-run.json` you have not confirmed corresponds to the
  current run.
- Any `reports/*.json` the skill chooses to aggregate (headless runs →
  `reports/headless-<name>.json`), plus `artifacts/flake-*.json` — flake probes
  write `artifacts/flake-<name>.json`, NOT under `reports/` (see `/qa-warden:run mode=repeat`).
  Mutation scores belong here too, but only if a team has added its own producer
  (none ships — e.g. Stryker). Per-command and always current; prefer them when
  `last-run.json` cannot be confirmed fresh.
- `reports/audit-*.md` — the a11y / visual / vocab findings from `/qa-warden:review url=<url>`.
  Surface at least the headline (WCAG violation counts, visual diffs) so the
  audit signal reaches the one place a reviewer looks.
- **`bugs/*.md` with `Status: open` — the parked/known-defect input (F-19).** A
  serious filed defect parked via `test.fixme` + `@regression` (not `@smoke`)
  leaves **no trace in `last-run.json`** — a `fixme` in the smoke grep lane isn't
  even counted as `skipped`. So a report built only from run stats emits an
  unqualified "green to merge" while a human-confirmed live defect sits invisible.
  This scan, plus two more the summary's go/no-go depends on, are single-sourced in
  `scripts/post-run-checks.sh` — the same script `/qa-warden:run mode=smoke`, `/qa-warden:run mode=single` and doctor
  Checks 4/14 call. It surfaces: (1) **open filed defects**, fail-safe — every bug is surfaced
  UNLESS explicitly marked resolved, and the parse is robust to all three authored Status shapes
  (a naive `grep '## Status.*open'` silently misses the two-line heading form and *hides* the
  defect); (2) **unprocessed healer sentinels** — a prior heal escalated and its follow-up never
  ran, so that failure is likely still live even if this run's lane is green; (3) **stray
  unmanaged specs** — invisible to `last-run.json`'s smoke stats yet collected (and possibly red)
  in a full `npx playwright test`, so the go/no-go must be qualified rather than an unqualified
  "green to merge". It exits 0 always and ends with a parseable
  `post-run: sentinels=<n> stray=<n> open-bugs=<n> test-gaps=<n>` line (`test-gaps` are the
  verifier's BLIND/unverified records — not app defects):

  ```bash
  # Guarded like check-last-run.sh above — an older scaffold predates this script, and an
  # unguarded call errors out mid-skill instead of degrading to a named gap.
  if [ -f scripts/post-run-checks.sh ]; then bash scripts/post-run-checks.sh
  else echo "WARN: scripts/post-run-checks.sh missing — substrate predates it; re-run /qa-warden:init --resync. Open defects / sentinels / stray specs are UNCHECKED: do not issue an unqualified go."; fi
  ```
- **Run metadata is NOT in the report** — commit SHA, branch, triggered-by and workflow are
  absent from a Playwright JSON report unless CI explicitly injects them into `config.metadata`.
  Render the template's `## Run metadata` section only when that key is present, and omit the
  whole section otherwise rather than emitting blanks.
- **CI (sharded) runs:** shards emit `blob` reports (per `playwright.config.ts`),
  not JSON. Merge them first — `npx playwright merge-reports --reporter json
  ./all-blob-reports > artifacts/last-run.json` — then summarize the merged JSON.

Output:

- A markdown block written to `reports/summary.md` (single canonical name — matches
  the `reports/summary.md` gitignore entry; it is
  **overwritten** each run, not timestamped, so summaries do not accumulate as VCS
  churn). Contents:
  - **The run SCOPE, stated first — never present a smoke run as a full-suite result (F-27).**
    `last-run.json` is typically the `--grep @smoke` run-of-record (a small curated subset — often
    a handful of tests), NOT the whole suite. Read the scope from `--grep` in `.config.argv` and lead
    the summary with it, so a green smoke lane is never read as "the whole suite passed". NOTE a
    config-level `grep`/`grepInvert` (set in playwright.config.ts — common in CI shards) is NOT
    recoverable here: Playwright serializes a RegExp to `{}` in the JSON report, so `.config.grep`
    always reads as an empty object and cannot be inspected. A run scoped that way therefore still
    looks like "all" — so the "all" branch below QUALIFIES its claim rather than asserting a proven
    full-suite pass:
    ```bash
    # $NRUN comes from the freshness block above — do NOT re-run check-last-run.sh to re-scrape it.
    # Run this in the SAME Bash invocation as that block (the Bash tool starts a fresh shell per
    # call, so a split loses $NRUN AND $lr_rc). If you must split, re-derive BOTH from the printed
    # `last-run:` line — losing $lr_rc alone makes the guard below report "NOT ESTABLISHED" for a
    # perfectly fresh record:
    #   case "$LR" in *fresh*) lr_rc=0 ;; *stale*) lr_rc=6 ;; *) lr_rc=3 ;; esac
    # Only rc 0/6 mean the record is readable. On rc 3/4/5 there is no trustworthy count, and
    # interpolating an unset $NRUN silently emitted "SCOPE: no --grep filter —  tests (treated as
    # full suite)" — a blank where the count belongs, on the ONE line whose whole job is stopping a
    # subset from reading as full-suite green. Say there is no record instead.
    if [ "${lr_rc:-3}" = 0 ] || [ "${lr_rc:-3}" = 6 ]; then
        # Playwright accepts THREE grep spellings and only one is two-token: `--grep @smoke`,
      # `--grep=@smoke` (a single argv element), and `-g @smoke`. Matching just the first sent the
      # other two down the "all" branch — printing "no --grep filter … treated as full suite" for a
      # run that WAS filtered, the exact false-full-suite-green F-27 exists to prevent (and that
      # branch's CAVEAT only warns about config-level grep, so it would not alert the reader).
      SCOPE=$(jq -r '(.config.argv // []) as $a
        | ($a | index("--grep")) as $i | ($a | index("-g")) as $j
        | ( if $i then $a[$i+1]
            elif $j then $a[$j+1]
            else ([$a[] | select(startswith("--grep="))] | first | if . then ltrimstr("--grep=") else null end)
            end ) // "all"' artifacts/last-run.json 2>/dev/null || echo "?")
      NRUN=${NRUN:-?}   # belt-and-braces: never interpolate an empty count
      case "$SCOPE" in
        "@smoke"|*smoke*) echo "SCOPE: smoke run-of-record — $NRUN smoke tests. This is a SUBSET; a full 'npx playwright test' was NOT measured here. Do NOT report this as full-suite green — say 'N smoke tests passed', and if a merge decision needs whole-suite proof, run 'QA_RUN_OF_RECORD=1 npx playwright test' first." ;;
        "all") echo "SCOPE: no --grep filter — $NRUN tests (treated as full suite). CAVEAT: a config-level grep/grepInvert is invisible in the JSON report (a RegExp serializes to {}), so if this record came from a CI shard scoped inside playwright.config.ts it is NOT the whole suite — confirm the run command before reporting full-suite green." ;;
        *)      echo "SCOPE: filtered run ('$SCOPE') — $NRUN tests. Qualify the go/no-go: only the matching subset ran." ;;
      esac
    else
      echo "SCOPE: NOT ESTABLISHED — no readable run-of-record (check-last-run rc=${lr_rc:-3}). Do NOT state a pass/fail count from last-run.json; summarize from reports/*.json and name the lane they cover, or refresh first."
    fi
    ```
    The headline must name the lane: **"N smoke tests passed"**, not an unqualified **"N passed"** —
    the count describes *what ran*, and a smoke subset is not evidence the other lanes are green.
  - **Everything below the SCOPE line** — totals, the failures table, passed-with-retries,
    signature grouping, audit findings, durations, the parked-defects section, and the value
    ledger — renders from
    `${CLAUDE_SKILL_DIR}/reference/report-template.md` (read it; §Template below points there).
    The SCOPE line leads it: only this skill reads `--grep`
    off `.config.argv`, so the anti-false-green qualification originates here (F-27).
  - A one-paragraph lead suitable for a PR comment or `#qa` Slack post.
- Return the full Markdown block VERBATIM as your final response, in addition to writing `reports/summary.md`. Do not summarize, truncate, or replace it with a status line; the block itself is the deliverable the user pastes into a PR or Slack. (This skill runs inline, not as a forked subagent, on purpose: Claude Code refuses a subagent `Write` whose basename matches `report*.md` / `summary*.md` / `findings*.md` / `analysis*.md` (any case), so a fork can never produce the canonical file — run-01, O-43/O-78.)

## Template

The full output template — headline, SCOPE line, totals, failures table, passed-with-retries,
signature grouping, audit findings, parked defects, value ledger and run metadata — lives in
`${CLAUDE_SKILL_DIR}/reference/report-template.md`. **Read that file and render from it**; it is
the sole owner of the report shape, so do not reconstruct the sections from memory.

## Value-ledger derivation (deterministic — reuse, don't re-derive)
- **Bug counts.** The `post-run-checks.sh` scan above ran `bug-status.sh --list-open`, which by
  design prints ONLY still-open bugs — so it gives you `<O>` but NOT `<FIXED>`. Derive the split
  with the canonical classifier (never re-type the resolved-keyword alternation; that duplication
  is what `bug-status.sh` exists to end):
  ```bash
  # <O> open / <FIXED> fixed. --class prints exactly `open` or `resolved` per file.
  # Verifier test-gap records (`*-blind-*.md`, `*-unverified.md`) are contract gaps, not app
  # defects — count them on their own line, or the ledger inflates the defect count (run-01, O-49).
  # One loop over `bugs/*.md` — a second glob such as `bugs/*-unverified.md` aborts under zsh when
  # nothing matches. Each file is routed by name to `defect` or `gap`, then classified:
  # `<O>`/`<FIXED>` are the defect rows, `<G>`/`<GF>` the gap rows.
  for f in bugs/*.md; do
    [ -e "$f" ] || break
    case "$f" in *-blind-*.md|*-unverified.md) kind=gap ;; *) kind=defect ;; esac
    echo "$kind $(bash scripts/bug-status.sh --class "$f")"
  done | sort | uniq -c        # e.g.  3 defect open · 1 defect resolved · 2 gap open
  ```
  **Found-by attribution.** The authored shape is a bolded label with an em-dash and NO colon —
  `- **Found-by** (OPTIONAL) — healer (nightly triage) | generator (authoring) | verifier (authoring) | manual`
  (CLAUDE.md §"Bug-report schema"). Grepping `Found-by:` matches nothing and silently reports every
  bug as `unrecorded` — the same fail-silent parse class this skill calls out for `## Status`.
  Bugs the main session files for a **planner** or **exploration** find carry `planner (authoring)` /
  `exploration (discovery)`; some authors emit the label as a `## Found-by` heading with the value on
  the next line. Count both shapes — a tally that reads only the bold form reported 7 of 12 bugs as
  `unrecorded` in run-01 (O-78):
  ```bash
  { grep -ho '\*\*Found-by\*\*[^—]*—[[:space:]]*[a-z]*' bugs/*.md 2>/dev/null | sed 's/.*—[[:space:]]*//'
    grep -h -A1 '^## Found-by' bugs/*.md 2>/dev/null | grep -v '^## \|^--' | sed 's/^[[:space:]]*//; s/[[:space:]].*//'
  } | sort | uniq -c   # bugs with no match in either shape = unrecorded
  ```
- **Heal counts** from the healer telemetry log, tolerant of absence:
  ```bash
  # `|| echo '{}'` matters: a bare `[ -f X ] && jq …` exits 1 when the log is absent (the Bash tool
  # surfaces that as a failed command), and `add` over an empty log yields `null`, not a usable value.
  { [ -s artifacts/heal-log.jsonl ] && jq -s 'group_by(.classification) | map({(.[0].classification): length}) | add // {}' artifacts/heal-log.jsonl; } || echo '{}'
  ```
- **RULE (double-counting guard):** app defects are counted from `bugs/` ONLY — heal-log rows
  classified `product-bug`/`expected-failure`/`env-infra` correspond to bug files and contribute
  ZERO to the defect count. Verifier test-gap records (`bugs/*-blind-*.md`, `bugs/*-unverified.md`)
  contribute ZERO as well — they say an oracle is decorative or unprobed, not that the app is wrong —
  and go on the "Test-contract gaps" line instead.
- Young projects show 0s everywhere — that is correct, not "no value".

## Grouping rule — by signature, not by test
Group failures (flakes included) by **failure signature** (same error string, same line, same resource timeout), not by test name. Rationale: fixing "TimeoutError on button click" once fixes 6 specs; triaging 6 specs individually wastes the healer.

**Signature extraction:** take the error message, strip volatile parts (timestamps, UUIDs, durations like `after 30000ms`, test-run-id tags), normalize to the error class + the invariant fragment. Group specs under that.

## Flake / retry surfacing
Every retry must surface in the summary. A test that passes only on retry-3 is **flaky, not passing** — list it under a "passed-with-retries" table so the flake SLO has data to enforce against. Do not hide retries.

## Durations (flake SLO context)
- p50 and p95 spec durations.
- Slowest N=5 specs — these are healer candidates if they are ALSO flaky.
- Total wall-clock vs the **prior `reports/summary.md`** baseline — flag >20% regression. Do **NOT** read the baseline from `artifacts/last-run.json`: the `json` reporter overwrites it on every run-of-record run, so it only ever holds the just-finished run — comparing to it yields the run vs itself (always ~0%) and a real 2× regression is never flagged. **Read it BEFORE writing this run's `reports/summary.md`** — that file is overwritten, not timestamped (see Output above), so writing first destroys the only baseline and silently reproduces the compare-the-run-to-itself bug this paragraph exists to prevent. Use the prior LOCAL `reports/summary.md` when present (it is gitignored and overwritten each run — no committed baseline exists); when there is no prior local file, omit the trend line rather than compare the run to itself. Teams that want cross-clone/CI trends must archive summaries out-of-repo.

## Example invocation
```bash
/qa-warden:report                               # aggregates last-run.json + reports/*.json → reports/summary.md
gh pr comment $PR --body-file reports/summary.md   # post to PR (--body-file takes the path directly)
```
(`/qa-warden:report` takes no arguments — it aggregates whatever on-disk artifacts are current. There is no `--since=` flag; trend comparison is done by reading the prior LOCAL `reports/summary.md` when present — gitignored, not committed — never a CLI arg.)

## Gotchas
- **Missing JSON** — the primary machine-readable sink is `artifacts/last-run.json` (the config's json reporter writes it on every run-of-record run: CI, or `QA_RUN_OF_RECORD=1` as `/qa-warden:run mode=smoke` sets — a bare local `npx playwright test` does not refresh it); `reports/*.json` exist only when a per-command run (`/qa-warden:run mode=single`, `/qa-warden:run mode=repeat`) wrote one, and are OPTIONAL enrichment. So the hard-fail condition is **neither `artifacts/last-run.json` NOR any `reports/*.json` present** — do NOT fail just because `reports/` is empty (F-020): a normal smoke run leaves `reports/` empty yet has a complete `last-run.json`. Read `last-run.json` first, fold in any `reports/*.json`, and only fail loudly when both sources are absent.
- **Signature grouping is fuzzy** — use word-boundary substring match, not regex full-match. Over-specific grouping degenerates to 1 group per spec (= ungrouped).
- **Do not LLM-summarize failures** — extract deterministically. LLM paraphrasing loses the error string, which is how humans grep-to-fix.
- **Collapse long sections** with `<details>` so PR comments stay scannable.

## References
- Playwright JSON reporter: https://playwright.dev/docs/test-reporters#json-reporter
