---
description: Coherently retire a feature — dry-run inventory of all linked artifacts, consumer-checked deletion, tsc + list verification
argument-hint: "<area/feature>"
disable-model-invocation: true
---

Retire `$ARGUMENTS` coherently — every linked artifact accounted for, nothing shared
deleted, harness verified green afterwards. Git history is the archive: there is no
`--keep-plan` flag; recover anything via `git log`/`git checkout`.

## What to do

1. **Build the plan (dry run — no writes yet).** Resolve the feature (+ `site:` from
   the spec's YAML), then build the full plan as a table with a per-file verdict:

   **DELETE**
   - `specs/<area>/<feature>.md`
   - `tests/<area>/<feature>.spec.ts`
   - `tests/<area>/<feature>.metamorphic.spec.ts`
   - `artifacts/route-manifests/<area>/<feature>.json` — removes the spec from the
     impact graph; CORRECT for a retired feature (a stale manifest is worse).
   - `specs/_context/<site>/<area>/<feature>.basis.md` + `.cases.md`

   **CONSUMER-CHECKED** — delete only if nothing else uses it:
   - **Guard first — a MISSING search tool must never read as "no consumers ⇒ DELETE" (D-4).** The consumer-checks below use `rg`; if ripgrep is absent, `rg -l …` emits nothing and exit-non-zero, which — if trusted — false-reads as "unused ⇒ DELETE" and orphans a still-shared page-object. Set the search command ONCE and use `$RG` on EVERY consumer-check line below, so the fallback is mechanical, not a prose substitution the reader might forget on one line (m-9): `RG="rg -l"; command -v rg >/dev/null 2>&1 || RG="grep -rlE"` (`grep -rlE` — the `-E` matters: the patterns below are regex alternations; both forms are always allowlisted and have the same list-files-with-matches semantics). Do NOT proceed on an empty result from a tool that never ran — fail-closed, exactly as healer step 6 ("if EMPTY, STOP").
   - Each page-object/component the spec imports:
     `$RG "<Class>|<fixtureName>" tests/ page-objects/` EXCLUDING the files being
     retired — capture into a variable, inspect, then act (mirror healer step 6's
     discipline). Non-empty ⇒ KEEP (shared; list the consumers).
   - Same for schemas/factories via `jq -r '.factories[]?'` over the REMAINING
     route manifests.
   - **The generator's shared oracle-constants module** `tests/<area>/<feature>.oracle.ts`
     (or `.shared.ts`) — the generator emits it and imports it into the parent
     `.spec.ts` (generator §6); the verifier's twins import the same module (verifier
     §8a). Consumer-check it like a POM:
     `$RG "<feature>\.oracle|<feature>\.shared" tests/ page-objects/` EXCLUDING the
     files being retired. Non-empty ⇒ KEEP (another spec imports the constants; list
     consumers). Empty ⇒ DELETE — otherwise it orphans as a dead module `tsc` won't
     flag (nothing imports it, nothing errors) (F-34).

   **KEEP**
   - `bugs/*.md` referencing the spec — historical record; append one line:
     `> Note: referencing spec retired <date> by /qa:retire.`
   - `fixtures/auth.<site>.json` + `tests/<site>.setup.ts` — per-site, shared — NEVER touch.
   - The area context file — **resolve its path from the retired spec's `basis:` field /
     the (site, area) mapping, NOT a bare `specs/_context/<site>/<area>.md`
     name-equals-area assumption (F-35).** The area *dir* and its context *file* name can
     diverge (a `catalog/` area whose context actually lives in
     `specs/_context/<site>/products.md`), so `<area>.md` may point at a nonexistent file
     and silently MISS a genuinely-orphaned context. Read the spec's `basis:`/`site:` to
     find the real area-context file (the same resolution reviewer Check 7/8 uses). If
     this was the area's LAST feature, report THAT file as orphaned and offer; never
     auto-delete.

2. **Print the table and STOP** for explicit confirmation (blast-radius confirm,
   like `/qa:batch-fix`). No confirmation, no deletion.

3. **Execute.** Per confirmed file, delete through the **sanctioned deletion script**
   (one exact path per call — never a glob):
   ```bash
   bash scripts/retire-delete.sh <exact-path>
   ```
   `retire-delete.sh` is the ONE delete path the shipped `.claude/settings.json`
   permits: the deny-list blocks `rm`, `find … -delete`, and `truncate` directly
   (deny beats allow and can't be interactively approved), so an inline
   `find … -delete` here is **denied** and retire's execute phase silently no-ops
   (F-031). The `Bash(bash scripts/retire-delete.sh*)` allow lets the wrapper run;
   its internal guards refuse anything outside the retire-able dirs (specs/ tests/
   page-objects/ steps/ bugs/ fixtures/ artifacts/ reports/), any glob, `..`
   traversal, absolute path, symlink, or non-file. Pass `--dry-run` to preview.
   Then Edit `fixtures/test.ts` to remove the fixtures of any POM actually deleted —
   else tsc breaks on the dangling import.

4. **Verify:**
   ```bash
   npx tsc --noEmit
   npx playwright test --list --reporter=line >/dev/null
   ```

5. **Report** deleted/kept/why, the impact-graph note (manifest removed → `/qa:impact`
   no longer sees this feature), and the orphaned-area note if it applies. Remind:
   git history is the archive.
