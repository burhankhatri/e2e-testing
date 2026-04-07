# CLAUDE.md — Development Methodology

## Critical Rules

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST  
3. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
4. IF A SKILL APPLIES, YOU MUST USE IT — NO RATIONALIZING
```

## Workflow Decision Tree

Every task follows this routing. Check skills BEFORE doing anything:

- **New feature or significant change** → `/brainstorm-and-plan` → implement with `/tdd` → verify with `/verify-done`
- **Bug fix** → `/debug` → fix with `/tdd` → verify with `/verify-done`
- **Refactor** → write tests for existing behavior with `/tdd` → refactor → `/verify-done`
- **E2E or integration concern** → `/test-loop` (uses `/e2e-playwright` internally)
- **Completed a major step** → `/code-review`

## Skill Priority

When multiple skills could apply:
1. **Process skills first** (brainstorm-and-plan, debug) — determine HOW to approach
2. **Implementation skills second** (tdd, e2e-playwright) — guide execution
3. **Verification last** (verify-done, code-review) — confirm quality

"Let's build X" → brainstorm-and-plan first, then tdd.
"Fix this bug" → debug first, then tdd.
"Add E2E tests" → e2e-playwright.
"Make it work end-to-end without me" → test-loop.

## The Inverted Testing Pyramid

For AI-assisted development, prioritize integration and E2E tests over unit tests:

- **E2E tests (most)** — agent runs real browser, catches UX bugs, full stack
- **Integration tests (many)** — real APIs, real DB, catches contract breaks
- **Unit tests (some)** — agents are already good at small details

The goal: write tests, let the agent iterate through the test-fix cycle, walk away. Come back when green. If the agent is going in circles on a problem, it needs a test, not more prompts.

## File Conventions

| File | Purpose |
|------|---------|
| `CLAUDE.md` | This file — routing and rules |
| `testing.md` | How to run all test suites (env vars, setup, commands) |
| `docs/specs/*.md` | Design documents from brainstorming |
| `docs/plans/*.md` | Implementation plans |
| `tests/unit/` | Unit tests |
| `tests/integration/` | Integration tests |
| `tests/e2e/` | Playwright E2E tests |
| `.worktrees/` | Git worktrees for isolated feature work (gitignored) |

## My Preferences

- User instructions override skill workflows. If I say "skip brainstorming," follow my lead.
- When creating git worktrees, prefer `.worktrees/` directory (gitignored).
- Commit frequently with conventional commit messages.
- DRY. YAGNI. Small focused files over large ones.
