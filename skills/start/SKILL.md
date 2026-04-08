---
name: start
description: "Master orchestrator skill that kicks off the full development pipeline. Routes tasks through the correct skill chain (brainstorm, debug, tdd, e2e, verify) based on task type. Guarantees testing.md exists, Playwright E2E tests are written, and nothing is claimed done without verification. Use when starting any new task, feature, bugfix, or refactor."
---

# /start — Development Pipeline Orchestrator

> One command to rule them all. Routes your task through the right skills, guarantees test infrastructure, and won't let you claim done without proof.

## Usage

```
/start <task description>
```

## Pipeline

You MUST follow this sequence exactly. No shortcuts. No skipping steps.

---

### Step 0: Test Infrastructure

**This step runs EVERY time, before anything else. Do NOT skip any sub-step.**

Check if `testing.md` exists at the project root.

**If it does NOT exist:**

1. Explore the project to discover:
   - Package manager (npm, pnpm, yarn, bun)
   - Test frameworks already installed (vitest, jest, playwright, etc.)
   - Scripts in `package.json` (test, test:e2e, test:integration, etc.)
   - Existing test files and their locations
   - Required environment variables
   - Database or service dependencies
2. Create `testing.md` using the template below, filled in with **real values from this project**:

```markdown
# Testing Guide

## Environment Setup
- Package manager: [detected]
- Required env vars: [list with descriptions]
- Database: [commands to start/seed test DB, or "none"]
- Services: [docker-compose, external APIs, or "none"]

## Running Tests

### Unit Tests
Command: `[detected or recommend]`
Location: `tests/unit/`

### Integration Tests
Command: `[detected or recommend]`
Location: `tests/integration/`

### E2E Tests (Playwright)
Command: `npx playwright test`
Setup: `npx playwright install chromium`
Base URL: `[detected from config or recommend]`
Location: `tests/e2e/`

## Debugging Failed Tests
- Single test: `[framework-specific command]`
- Headed browser: `npx playwright test --headed`
- Traces: `npx playwright show-trace test-results/*/trace.zip`
```

3. **Install Playwright if not already installed.** This is NOT optional. Run:
   ```bash
   npm install -D @playwright/test && npx playwright install chromium
   ```
4. **Create `playwright.config.ts` if it doesn't exist.** Use the config template from `/e2e-playwright`.
5. **Create `tests/e2e/` directory** if it doesn't exist.
6. Commit: `git commit -m "chore: add test infrastructure (testing.md, playwright)"`

**If it exists:** Read it. Then verify Playwright is installed (`npx playwright --version`). If not, install it now before proceeding.

---

### Step 1: Route the Task

Read CLAUDE.md. Classify the task as one of:

| Type | Route | Next step |
|------|-------|-----------|
| **feature** | New functionality or significant change | Step 2 (Design) |
| **bugfix** | Something is broken | Step 3 (use `/debug` first) |
| **refactor** | Restructure without behavior change | Step 4 (write tests for existing behavior first) |
| **e2e-only** | Only adding/fixing E2E tests | Step 5 |

---

### Step 2: Design (features only)

Run `/brainstorm-and-plan` with the task description.

- The plan MUST include Playwright E2E tests for every user-facing flow
- The plan MUST include integration tests for every API route
- Wait for user approval before writing any code

After approval, proceed to Step 4.

---

### Step 3: Root Cause Analysis (bugfixes only)

Run `/debug` to investigate the bug.

- Do NOT guess at fixes
- Trace to root cause first
- Once root cause is identified, proceed to Step 4

---

### Step 4: Implement with TDD

Run `/tdd` for every implementation step.

For each piece of work:
1. Write a failing test
2. Run it — confirm RED
3. Write minimal code to pass
4. Run it — confirm GREEN
5. Refactor if needed
6. Commit with conventional commit message

**Commit after every green cycle**, not at the end.

**Test Debt Handoff — before moving to Step 5:**

Review the `/tdd` Behavior Coverage Checklist. List every E2E test owed:
```
E2E debts from Step 4:
- [ ] [describe the user workflow that needs an E2E test]
- [ ] [describe the nav change that needs a navigation test]
- [ ] [describe the bug fix that needs a browser-level regression test]
```

Carry this list into Step 5. Every item MUST be covered before Step 6.

---

### Step 5: E2E Coverage

```
╔══════════════════════════════════════════════════════════════════╗
║  THIS STEP IS MANDATORY. YOU MUST NOT SKIP IT.                  ║
║                                                                  ║
║  "Playwright is not installed" → INSTALL IT (Step 0 should      ║
║  have done this — if it didn't, install it now).                 ║
║                                                                  ║
║  "It would require significant setup" → THAT IS THE WORK.       ║
║  Do the setup. That's what this step is for.                     ║
║                                                                  ║
║  "The user already approved without E2E" → The user approved     ║
║  the PLAN. This pipeline requires E2E. Write them.               ║
║                                                                  ║
║  "Unit tests already cover this" → Unit tests are not E2E.       ║
║  E2E tests run a real browser. Write them.                       ║
║                                                                  ║
║  There is NO valid reason to skip this step.                     ║
╚══════════════════════════════════════════════════════════════════╝
```

**Before writing tests, verify Playwright works:**

```bash
npx playwright --version  # Must output a version number
```

If this fails, run: `npm install -D @playwright/test && npx playwright install chromium`

**Then run `/e2e-playwright`** to write E2E tests covering:

- **Features**: Every user-facing flow introduced or changed
- **Bugfixes**: A test that reproduces the original bug and confirms the fix
- **Refactors**: Tests proving existing behavior is preserved
- **API routes**: Request/response tests via Playwright's `request` fixture

**After writing E2E tests, confirm they pass:**

```bash
npx playwright test --repeat-each=3
```

If any test is flaky, diagnose and fix before proceeding. Do NOT move on with flaky tests.

**Commit screenshot baselines:**

If any tests use `toHaveScreenshot()`, Playwright generates baseline images in `*.spec.ts-snapshots/` directories. These MUST be committed — they are the source of truth for visual regression.

```bash
# Check for generated screenshot baselines
find tests/e2e -name "*.spec.ts-snapshots" -type d

# If any exist, stage and commit them
git add tests/e2e/**/*.spec.ts-snapshots/
git commit -m "test: add Playwright screenshot baselines"
```

Do NOT skip this. Without committed baselines, `toHaveScreenshot()` will fail on subsequent runs.

**Screenshot requirement check:**

Before answering the quality gate, run this check:

```bash
# Did this task change anything visual (CSS, HTML structure, styles, colors, layout)?
git diff HEAD~1 --stat -- '*.html' '*.css' '*.tsx' '*.jsx' '*.scss'
```

If that diff is non-empty, you MUST have at least one `toHaveScreenshot()` call in your E2E tests. No exceptions. No "computed style is good enough." No "N/A." Screenshots and computed-style assertions serve different purposes — screenshots catch visual regressions you didn't think to assert on.

If you don't have one yet, write it now before proceeding.

**E2E Quality Gate — answer ALL before proceeding to Step 6:**

Every question below must be answered YES or DOES-NOT-APPLY. "N/A" is NOT a valid answer for questions that apply to your task. If you're unsure whether a question applies, the answer is YES it applies — write the test.

```
╔══════════════════════════════════════════════════════════════════╗
║  BEFORE proceeding: answer these questions honestly.            ║
║                                                                  ║
║  □ Do tests exercise the feature's primary user workflow?        ║
║    ("Page loads" is NOT a workflow)                               ║
║                                                                  ║
║  □ For bugfixes: does a test reproduce the original bug?         ║
║                                                                  ║
║  □ For nav changes: do tests click nav items and verify          ║
║    they route to the correct page with correct content?          ║
║                                                                  ║
║  □ For API changes: do tests hit the actual endpoints and        ║
║    verify responses?                                             ║
║                                                                  ║
║  □ Would these tests catch a regression if someone broke         ║
║    this feature tomorrow?                                        ║
║                                                                  ║
║  □ Did you change CSS, HTML, styles, colors, or layout?          ║
║    → Then at least one test MUST use toHaveScreenshot().          ║
║    → "Computed style assertions cover it" is NOT sufficient.     ║
║    → Screenshots catch regressions you didn't think to assert.   ║
║                                                                  ║
║  □ Are screenshot baselines committed?                           ║
║    → Run: find tests/e2e -name "*.spec.ts-snapshots" -type d     ║
║    → If empty after a UI change, this gate FAILS.                ║
║                                                                  ║
║  If ANY answer is NO → stay in Step 5 and write the missing      ║
║  tests. Then re-run --repeat-each=3 and re-answer this gate.     ║
║  Do NOT proceed until all boxes are checked.                     ║
║                                                                  ║
║  "Page loads without 404" is baseline, not coverage.             ║
╚══════════════════════════════════════════════════════════════════╝
```

**Check every item from the Test Debt Handoff list (Step 4).** Each debt must map to a passing E2E test. Uncovered debts = stay in Step 5.

**If E2E tests are not written and passing, Step 6 (verify) MUST fail.**

---

### Step 6: Verify

Run `/verify-done`.

- Run the FULL test suite (unit + integration + e2e)
- Show fresh output as evidence
- Do NOT claim complete until verification passes

**If verification fails:** Go back to the relevant step and fix. Do not skip re-verification.

---

## Quick Reference

```
/start add user authentication
  → Step 0 (testing.md) → Step 1 (feature) → Step 2 (brainstorm)
  → Step 4 (tdd) → Step 5 (e2e) → Step 6 (verify)

/start fix login redirect loop
  → Step 0 (testing.md) → Step 1 (bugfix) → Step 3 (debug)
  → Step 4 (tdd) → Step 5 (e2e) → Step 6 (verify)

/start extract auth into middleware
  → Step 0 (testing.md) → Step 1 (refactor) → Step 4 (tdd)
  → Step 5 (e2e) → Step 6 (verify)

/start add e2e tests for checkout
  → Step 0 (testing.md) → Step 1 (e2e-only) → Step 5 (e2e)
  → Step 6 (verify)
```
