---
name: code-review
description: "Use when a major project step has been completed and needs review against the plan and coding standards. Also use when someone says 'review this', 'check my code', 'is this ready', or when a significant chunk of implementation is done. Use after completing tasks from an implementation plan, before creating PRs, or when asked to assess code quality."
---

# Code Review

## Two-Stage Review Process

### Stage 1: Spec Compliance

Before assessing quality, verify the code does what was asked:

1. **Compare implementation against the spec/plan** — requirement by requirement
2. **Is anything missing?** — features specified but not implemented
3. **Is anything extra?** — features added that weren't requested (YAGNI violation — remove them)
4. **Are deviations justified?** — if the implementation differs from the plan, is it a genuine improvement or a problematic departure?

**If spec compliance fails:** Fix gaps before moving to Stage 2. Don't review quality of incomplete work.

### Stage 2: Code Quality

1. **Error handling** — are errors caught, logged, and handled appropriately? Are edge cases covered?
2. **Type safety** — proper types, no `any` unless justified, interfaces match contracts
3. **Naming** — clear, descriptive, consistent with codebase conventions
4. **Organization** — separation of concerns, single responsibility, loose coupling
5. **Test coverage** — are tests meaningful? Do they test behavior, not implementation?
6. **Security** — input validation, no hardcoded secrets, SQL injection, XSS
7. **Performance** — obvious N+1 queries, unnecessary re-renders, missing indexes

### Issue Categories

- **Critical** (must fix) — blocks merge, breaks functionality, security vulnerability
- **Important** (should fix) — code smell, missing edge case, poor naming, missing test
- **Suggestion** (nice to have) — style preference, minor optimization, alternative approach

### Review Output Format

```
## Spec Compliance: ✅ PASS / ❌ FAIL

[If FAIL: list missing/extra items]

## Code Quality

### Strengths
- [What was done well — always acknowledge before critiquing]

### Critical Issues
- [File:line] Description. Fix: [specific suggestion]

### Important Issues
- [File:line] Description. Fix: [specific suggestion]

### Suggestions
- [File:line] Description. Consider: [alternative]

## Verdict: APPROVED / CHANGES REQUESTED
```

### Principles

- **Always acknowledge what was done well** before highlighting issues
- **Be specific** — file, line, concrete suggestion, not vague "improve error handling"
- **Provide code examples** for non-obvious fixes
- **Don't nitpick style** if the codebase has no established convention
- **Check the tests** — are they testing real behavior or mock existence?
- **Verify independently** — don't trust claims, check the actual code/output
