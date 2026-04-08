---
name: test-loop
description: "Use when you need to autonomously iterate through test-fix cycles without human intervention. Use when someone says 'make it work', 'run tests and fix', 'iterate until green', 'take yourself out of the loop', 'fix until tests pass', or when the agent is going in circles on the same problem. Also use when setting up a new integration, adding a new agent, or doing any work where automated tests can drive the development instead of manual prompting."
---

# Test Automation Loop

> The core insight: if the agent is going in circles, it needs a test — not more prompts. Write the test. Let the agent iterate against it. Walk away.

## The testing.md Pattern

Every project should have a `testing.md` at the root (or in relevant submodule folders) containing EVERYTHING the agent needs to run tests autonomously:

### Template:

```markdown
# Testing Guide

## Environment Setup
- Required env vars: [list with descriptions]
- Database: [commands to start/seed test DB]
- Services: [docker-compose, external APIs]
- Test user: [how to create/seed test data]

## Running Tests

### Unit Tests
Command: `npm test`
Location: `tests/unit/`

### Integration Tests
Command: `npm run test:integration`
Env vars needed: [list]
What they test: [scope description]

### E2E Tests (Playwright)
Command: `npx playwright test`
Setup: `npx playwright install chromium`
Base URL: [how it's configured]
Auth: [how test auth works]
Location: `tests/e2e/`

## Debugging Failed Tests
- Single test: `npm test -- -t "test name"`
- Headed browser: `npx playwright test --headed`
- Traces: `npx playwright show-trace test-results/*/trace.zip`
- Verbose: `npm test -- --verbose`
```

**Create this file FIRST** if it doesn't exist. The agent cannot iterate autonomously without it.

## The Autonomous Loop

```
1. Read testing.md
2. Set up the test environment (DB, env vars, services)
3. Ensure screenshot capture is enabled:
   - Verify playwright.config.ts has screenshot: 'on'
   - Verify video: 'retain-on-failure' is set
   - Verify trace: 'on-first-retry' is set
4. Run the relevant test suite
5. If tests fail:
   a. Analyze failure output carefully (Phase 1 of /debug)
   b. Check screenshot/trace artifacts in test-results/:
      - Screenshots: what does the page look like at the failure point?
      - Trace: open with `npx playwright show-trace` for DOM + network + console
      - Diff images (*-diff.png): for visual regression failures, what changed?
   c. Form hypothesis about root cause
   d. Fix the code (using /tdd — failing test → fix → verify)
   e. Run tests again
   f. Repeat until ALL tests pass
6. If tests pass:
   a. Run visual regression suite if project uses toHaveScreenshot():
      npx playwright test --grep @visual --repeat-each=3
   b. Run full suite MULTIPLE TIMES to catch flakiness
   c. Use /verify-done before claiming success
```

### Key Rules:

- **Run multiple times** to catch flaky behavior:
  ```bash
  # E2E stability check
  npx playwright test --repeat-each=3 --reporter=line

  # Unit/integration stability
  for i in 1 2 3; do npm test; done
  ```

- **Add diagnostic logs** when you can't figure out a failure — don't guess:
  ```typescript
  console.log('[DEBUG] State before action:', JSON.stringify(state));
  console.log('[DEBUG] API response:', JSON.stringify(response));
  console.log('[DEBUG] Element visible:', await element.isVisible());
  ```
  Run with logs → analyze output → THEN fix. Remove debug logs after.

- **If stuck after 3 attempts** → stop, escalate to the user with:
  - What you tried
  - What the evidence shows
  - Your hypothesis about the architectural issue

## Creating New Integrations — Full Autonomous Cycle

When adding a new API, agent, service, or integration:

### Step 1: Read All Documentation
- Web search for official docs
- Read API references, auth guides, examples
- Understand full scope before writing anything

### Step 2: Create Raw Output Script
- Build minimal script that calls the real API/agent
- Dump raw output (JSON/text) to a file
- Now you have REAL data, not assumptions

### Step 3: Triangulate
- You have TWO sources: official docs + actual raw output
- Compare them. Note discrepancies.
- Use both to inform your parser/integration

### Step 4: Build Parser/Integration with TDD
- Write failing tests based on Steps 1-3
- Implement minimal code to pass
- Add unit tests as you go

### Step 5: Integration Tests
- Run against the real API/service
- Does it start? Stop? Output in expected format?
- If tests fail → go back to Step 4
- Re-run integration tests

### Step 6: E2E Tests (if applicable)
- Wire into UI/application
- Write Playwright tests for user-facing flow (use `/e2e-playwright`)
- Run, fix, run again

### Step 7: Update Documentation
- Update README, API docs, testing.md
- Add new integration to registries/menus

**This entire cycle can run without human intervention** if testing.md and the plan are well-specified.

## Bug Reproduction via Automated Tests

When a bug is found (manually or reported):

1. Write a test that reproduces the EXACT bug behavior
2. Verify test FAILS (confirms it catches the bug)
3. Fix the code
4. Verify test PASSES
5. Run full suite for regressions
6. Run the specific test multiple times to confirm stability

This test permanently prevents the bug from returning.

## Screenshot-Driven Debugging

When test output alone isn't enough to diagnose a failure, use artifacts:

### Quick diagnosis commands:

```bash
# Re-run failing test with full capture
npx playwright test tests/e2e/failing.spec.ts --trace on --screenshot on --video on

# View the trace (richest artifact — DOM snapshots, network, console)
npx playwright show-trace test-results/failing-chromium/trace.zip

# List all screenshots from last run
ls test-results/*/test-*.png

# List all visual regression diffs
ls test-results/*/*-diff.png
```

### Visual regression failure diagnosis:

When a `toHaveScreenshot()` assertion fails, Playwright generates three images:

| File | Content |
|------|---------|
| `*-expected.png` | Committed baseline |
| `*-actual.png` | Current render |
| `*-diff.png` | Red overlay showing differences |

**Diagnosis steps:**
1. Compare expected vs actual — is this an intentional UI change?
2. If intentional: `npx playwright test --update-snapshots` → commit baselines
3. If unintentional: the diff shows exactly which region changed — fix the CSS/layout
4. Re-run to confirm fix

### When to escalate artifact capture:

| Situation | Action |
|-----------|--------|
| Test fails, error message is clear | No extra capture needed |
| Test fails, unclear why element isn't visible | Check screenshot at failure point |
| Test intermittently fails | Enable trace: 'on', run with --repeat-each=10 |
| Visual regression diff is confusing | Compare trace DOM snapshots at the assertion step |
| Test fails only in CI | Download CI trace artifact, compare with local trace |

## When To Use This Skill vs Others

| Situation | Skill |
|-----------|-------|
| Agent keeps going in circles | **Use this** — write a test, iterate against it |
| Single bug to fix | `/debug` → `/tdd` → `/verify-done` |
| New feature from scratch | `/brainstorm-and-plan` → `/tdd` |
| Need E2E tests written | `/e2e-playwright` |
| Full integration with no human | **Use this** — the full autonomous cycle |
