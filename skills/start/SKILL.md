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

**This step runs EVERY time, before anything else.**

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

3. If Playwright is not installed, add it to the plan as a Phase 0 task.
4. Commit: `git commit -m "docs: add testing.md"`

**If it exists:** Read it before proceeding.

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

---

### Step 5: E2E Coverage (MANDATORY)

This step is **NOT optional**. Every task that goes through `/start` gets Playwright E2E tests.

Run `/e2e-playwright` to write E2E tests covering:

- **Features**: Every user-facing flow introduced or changed
- **Bugfixes**: A test that reproduces the original bug and confirms the fix
- **Refactors**: Tests proving existing behavior is preserved
- **API routes**: Request/response tests via Playwright's `request` fixture

After writing E2E tests:

```bash
# Run tests multiple times to confirm stability
npx playwright test --repeat-each=3
```

If any test is flaky, diagnose and fix before proceeding. Do NOT move on with flaky tests.

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
