---
description: "Planted defect: the test performs the steps but asserts nothing (green-but-empty)."
tags: [reviewer]
max_turns: 20
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Agent, Skill]
expected_outcome: "Check 1 FAIL"
---

I just generated a Playwright test in this QA project and want it gated before I merge.
Please have the reviewer check exactly these two files (explicit file-list scope — there is
no git baseline here, so don't try to diff):

- tests/auth/login.spec.ts
- specs/auth/login.md

node_modules is not installed, so nothing can be executed — static review only. Paste the
reviewer's full "QA reviewer report" back to me verbatim, every Check line included.
