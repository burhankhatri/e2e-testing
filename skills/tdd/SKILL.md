---
name: tdd
description: "Enforces strict test-driven development. Use when implementing ANY feature, bugfix, or refactor — before writing implementation code. Also use when someone says 'add tests', 'write tests', 'test this', 'TDD', or when you're about to write production code of any kind. If you're about to write code and there isn't a failing test for it yet, STOP and use this skill."
---

# Test-Driven Development

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

**No exceptions:**
- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

Implement fresh from tests. Period.

## Protecting the Tests

The agent optimizes for green. These rules make green mean true. Every one of them closes a loophole that was actually exploited in real projects using this skill (a July 2026 audit found 18 of 25 E2E tests in one repo permanently `test.skip`-guarded — they had never run once — and Anthropic, METR, and Kent Beck all document agents disabling or deleting tests to pass).

```
1. EVIDENCE THE RED      Run the new test and SHOW its failing output before
                         writing any implementation. It must fail for the
                         right reason — the missing behavior, not an import
                         error or typo. No observed red = the cycle never
                         happened.

2. FIX CODE, NOT TESTS   Never delete, weaken, .skip, or loosen a test to
                         reach green. If you believe the test itself is
                         wrong, STOP, say so explicitly, and get the user's
                         agreement before changing it.

3. SKIPPED = FAILING     "7 passed, 18 skipped" is a red suite. Always
                         report full counts (passed / failed / skipped).
                         A test that has never executed proves nothing.

4. CAN'T MAKE IT REAL?   Missing test user, credentials, test DB, seed
   STOP AND ASK.         data — that one-time setup is the user's call.
                         Ask for it. Do not mock around it. Do not skip.
```

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples, [mocking.md](mocking.md) for mocking guidelines, and [deep-modules.md](deep-modules.md) / [interface-design.md](interface-design.md) for designing testable interfaces.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Red-Green-Refactor Cycle

### RED — Write Failing Test

Write ONE minimal test showing what should happen.

**Requirements:**
- One behavior per test
- Clear descriptive name ("and" in name? Split it)
- Real code, no mocks unless unavoidable

<Good>
```typescript
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };
  const result = await retryOperation(operation);
  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```
Clear name, tests real behavior, one thing
</Good>

<Bad>
```typescript
test('retry works', async () => {
  const mock = jest.fn()
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  await retryOperation(mock);
  expect(mock).toHaveBeenCalledTimes(2);
});
```
Vague name, tests mock not code
</Bad>

### Verify RED — Watch It Fail (MANDATORY, NEVER SKIP)

```bash
npm test path/to/test.test.ts
```

**Show the failing output in your message.** Then confirm:
- Test fails (not errors)
- Failure message is expected
- Fails because feature is missing (not typos)

**Test passes?** You're testing existing behavior. Fix the test.
**Test errors?** Fix the error, re-run until it fails correctly.

Best practice: commit the failing test on its own (`test: ...`) before implementing. The red phase becomes provable in git history.

### GREEN — Minimal Code

Write the SIMPLEST code to pass the test. Nothing more.

Don't add features, refactor other code, or "improve" beyond what the test requires.

### Verify GREEN — Watch It Pass (MANDATORY)

```bash
npm test path/to/test.test.ts
```

Confirm: Test passes, other tests still pass, output pristine, **zero skipped**.

**Test fails?** Fix code, not test.
**Other tests fail?** Fix now.

### REFACTOR — Clean Up

After green only: Remove duplication, improve names, extract helpers.
Keep tests green. Don't add behavior.

### Repeat — Next failing test for next feature.

## Common Rationalizations — All Mean "Delete Code, Start Over"

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. |
| "Keep as reference" | You'll adapt it. That's testing after. Delete means delete. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Just this once" | No. |
| "Test expectation was wrong" | Was it? Or is the code wrong? Investigate before weakening. |
| "Skip it for now, unblock the suite" | A skipped test is a failing test. Fix it or ask the user. |
| "Auth/DB isn't set up, I'll mock it" | Stop and ask for the one-time setup. Mocks here test fiction. |

## Never Weaken a Failing Test

A test that fails is telling you something. Investigate the code, not the assertion.

```
Test expected 32px, got 20px.
❌ Lower assertion to 16px → test passes → ship it
✅ Investigate: Why is it 20px? Is the CSS wrong? Did the fix not work?
```

**Only three valid reasons to change a test assertion:**

1. **Test had a bug** — the expectation was wrong from the start (e.g., wrong constant, copy-paste error)
2. **Requirements changed** — the expected behavior genuinely shifted (document why)
3. **Testing implementation details** — the test was brittle; rewrite to test behavior instead

If none of these apply, the test caught a real problem. Fix the code.

**The anti-pattern in action:**
- Calendar cells should be 32px (per the bug fix making them mobile-friendly)
- Test finds they're actually 20px
- Agent lowers the assertion to ≥16px "to be safe"
- The bug fix didn't actually work — and the weakened test will never catch it

Weakening an assertion is deleting the test with extra steps. So is `test.skip`. So is an `.or()` assertion that accepts a failure state.

## Testing Anti-Patterns

1. **Testing mock behavior** — Assert on real component behavior, not mock existence
2. **Test-only methods in production** — Move to test utilities
3. **Mocking without understanding** — Understand side effects first, mock minimally
4. **Incomplete mocks** — Mirror real API response structure completely
5. **Tests as afterthought** — Testing IS implementation, not optional follow-up
6. **Testing the helper, not the behavior** — Extracting a pure function, testing it, and calling the feature "tested"
7. **Vendor-shaped mocks** — a mock that hard-codes a third party's response format silently becomes fiction when you switch providers. Assert on YOUR contract, keep the vendor shape in one place, and re-run the suite after any provider change.

If you extract `validateRuleBody()` and write 5 tests for it, the API route that *calls* `validateRuleBody()` is still untested. Helper tests verify transformation logic. They do NOT verify:
- Auth checks on the route
- Database queries executing correctly
- Error responses from the handler
- The full request→response contract

**Behavior Coverage Checklist — two levels, both required:**

**Write NOW (unit/integration — during TDD in `/start` Step 4):**

| Code you wrote | Test to write now |
|---|---|
| API route handler | Integration test that calls the handler, checks status + response body |
| Bug fix | Regression test that reproduces the original symptom |
| State management logic | Test through the API or function that triggers the flow |
| Extracted helper/utility | Unit test — but this DOES NOT replace tests for the code that calls it |

**Owe for E2E (browser tests — written in `/start` Step 5):**

| Code you wrote | E2E test owed |
|---|---|
| UI component with interactions | E2E that clicks/types/drags and verifies outcomes |
| Navigation change | E2E that clicks nav item, verifies URL + destination content |
| Bug fix with UI symptoms | E2E that reproduces the original user-visible bug |
| New page or route | E2E that navigates to it and tests the primary workflow |

**Before leaving TDD, list your E2E debts.** Write them down — they carry forward to Step 5. Example:
```
E2E debts from Step 4:
- Canvas page: drag entry→project creates rule, future entries auto-link
- Navigation: sidebar + mobile nav show Canvas, clicking navigates correctly
- Bug fix: calendar cells are ≥32px on mobile viewport
```

**The rule:** A helper test is a bonus. The behavior test is the requirement.

**Gate function before adding mocks:**
1. "What side effects does the real method have?"
2. "Does this test depend on any of those side effects?"
3. "Do I fully understand what this test needs?"

If unsure: Run test with real implementation FIRST, observe, THEN add minimal mocking. Mock at system boundaries only (see [mocking.md](mocking.md)) — and prefer a real test DB over a mocked one.

## Bug Fix Flow

1. Write a test that reproduces the exact bug
2. Verify the test FAILS (confirms it catches the bug)
3. Fix the code
4. Verify the test PASSES
5. Run full suite for regressions

## Verification Checklist

Before marking work complete:
- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing — failing output was SHOWN
- [ ] Each test failed for expected reason
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass — full counts reported, ZERO skipped
- [ ] No test was skipped, weakened, or deleted to reach green
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Edge cases and errors covered

Can't check all boxes? You skipped TDD. Start over.
