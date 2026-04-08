---
name: verify-done
description: "Use when about to claim work is complete, fixed, passing, or done — before committing, creating PRs, or moving to the next task. Also use when you're about to say 'Done!', 'All tests pass', 'Ready for review', 'Fixed', or ANY positive statement about work state. If you haven't run the verification command in this message, you cannot claim it passes."
---

# Verification Before Completion

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## What Each Claim Requires

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| "Tests pass" | Test command output: 0 failures | Previous run, "should pass" |
| "Linter clean" | Linter output: 0 errors | Partial check, extrapolation |
| "Build succeeds" | Build command: exit 0 | Linter passing, "looks good" |
| "Bug fixed" | Test original symptom: passes | Code changed, assumed fixed |
| "Regression test works" | Red-green cycle verified | Test passes once |
| "Requirements met" | Line-by-line checklist | Tests passing |
| "E2E coverage" | `npx playwright test` output: 0 failures | "Playwright not installed", unit tests only |

## E2E Gate (when invoked from /start)

If this verification was triggered by the `/start` pipeline, you MUST verify that Playwright E2E tests exist and pass:

```bash
npx playwright test
```

If this command fails because Playwright is not installed or no E2E tests exist, **verification FAILS**. Go back to Step 5 of `/start` and do the work. Do not rationalize skipping E2E.

## Test Proportionality Check

Before claiming completion, assess whether tests are proportional to the code you shipped.

**For each piece of production code, identify its test:**

| Production code you wrote | Required test (AT MINIMUM) |
|---|---|
| API route handler (GET/POST/PUT/DELETE) | Integration test or E2E that calls the route, checks status + body |
| UI component with interactions (>50 lines) | E2E that clicks/types/drags and verifies outcomes |
| Bug fix (any) | Regression test that reproduces the original symptom |
| Navigation change (sidebar, mobile nav, routes) | E2E that clicks nav item and verifies destination |
| Extracted helper/utility | Unit test — BUT the feature using it also needs its own test |
| State management / data flow change | Test through the UI or API that triggers the flow |

**Proportionality failures (verification MUST fail if any apply):**

- 200+ lines of UI code shipped with 0 component/E2E tests covering interactions
- API routes shipped with only input-validation helper tests (route handler itself untested)
- Bug fix shipped without a regression test reproducing the original symptom
- Navigation added/changed without an E2E test clicking the nav and verifying the destination
- "All N tests pass" where N hasn't increased despite new production code

**The check:** Look at `git diff --stat` for the work being verified. For every production file changed, point to the test that covers it. If you can't point to one, go back and write it.

## Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

## Red Flags — STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Trusting agent success reports without independent verification
- ANY wording implying success without having run verification

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ tests ≠ build |
| "Agent said success" | Verify independently |
| "Partial check is enough" | Partial proves nothing |

## The Bottom Line

Run the command. Read the output. THEN claim the result.

This is non-negotiable.
