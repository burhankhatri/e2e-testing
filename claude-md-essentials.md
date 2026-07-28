## Critical Rules

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
3. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
4. IF A SKILL APPLIES, YOU MUST USE IT — NO RATIONALIZING
5. A SKIPPED TEST IS A FAILING TEST — NEVER SKIP, WEAKEN, OR DELETE A TEST TO GET GREEN
6. IF A TEST CAN'T BE MADE REAL (AUTH, TEST DB, CREDENTIALS) — STOP AND ASK, DON'T MOCK AROUND IT
```

**Enforcement lives in machinery, not prompts.** These rules only hold between
sessions if CI runs the suite on every push — `/start` Step 0 scaffolds
`.github/workflows/tests.yml` before any feature work.

## Workflow Decision Tree

Every task follows this routing. Check skills BEFORE doing anything:

- **New feature or significant change** → `/brainstorm-and-plan` → implement with `/tdd` → verify with `/verify-done`
- **Bug fix** → `/debug` → fix with `/tdd` → verify with `/verify-done`
- **Refactor** → write tests for existing behavior with `/tdd` → refactor → `/verify-done`
- **E2E or integration concern** → `/test-loop` (uses `/e2e-playwright` internally)
- **Completed a major step** → `/code-review`

User instructions override skill workflows. If told "skip brainstorming," follow that lead.
