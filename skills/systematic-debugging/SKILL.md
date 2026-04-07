---
name: debug
description: "Use when encountering ANY bug, test failure, unexpected behavior, or error — before proposing fixes. Also use when someone says 'fix this', 'it's broken', 'not working', 'debug', or when a test fails. ESPECIALLY use when under time pressure, when you've already tried a fix that didn't work, or when 'just one quick fix' seems obvious. Never skip this for simple-seeming bugs."
---

# Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

**Violating the letter of this process is violating the spirit of debugging.**

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully**
   - Don't skip past errors or warnings
   - Read stack traces completely
   - Note line numbers, file paths, error codes

2. **Reproduce consistently**
   - Can you trigger it reliably? What are the exact steps?
   - If not reproducible → gather more data, don't guess

3. **Check recent changes**
   - Git diff, recent commits, new dependencies, config changes
   - Environmental differences

4. **Gather evidence in multi-component systems**
   For EACH component boundary:
   - Log what data enters component
   - Log what data exits component
   - Verify environment/config propagation
   Run once to gather evidence showing WHERE it breaks, THEN analyze.

5. **Trace data flow**
   - Where does bad value originate?
   - What called this with bad value?
   - Keep tracing up until you find the source
   - Fix at source, not at symptom

### Phase 2: Pattern Analysis

1. **Find working examples** in same codebase
2. **Compare against references** — read reference implementation COMPLETELY (don't skim)
3. **Identify ALL differences** between working and broken
4. **Understand dependencies**, settings, config, assumptions

### Phase 3: Hypothesis and Testing

1. **Form SINGLE hypothesis:** "I think X is root cause because Y"
2. **Test minimally** — SMALLEST possible change, one variable at a time
3. Did it work? → Phase 4. Didn't work? → NEW hypothesis (don't pile fixes)

### Phase 4: Implementation

1. **Create failing test case** — use `/tdd` skill. MUST have before fixing.
2. **Implement single fix** — ONE change, no "while I'm here" improvements
3. **Verify fix** — test passes, no other tests broken, issue resolved
4. **If 3+ fixes failed:** STOP. Question the architecture. Discuss with user before more attempts. This is NOT a failed hypothesis — this is a wrong architecture.

## Defense-in-Depth

When you fix a bug, validate at EVERY layer data passes through:
- **Layer 1:** Entry point validation (reject invalid input at API boundary)
- **Layer 2:** Business logic validation (ensure data makes sense for operation)
- **Layer 3:** Environment guards (prevent dangerous operations in specific contexts)
- **Layer 4:** Debug instrumentation (capture context for forensics)

Single validation: "We fixed the bug." Multiple layers: "We made the bug impossible."

## Condition-Based Waiting (Flaky Tests)

```typescript
// ❌ Guessing at timing
await new Promise(r => setTimeout(r, 50));

// ✅ Waiting for actual condition
await waitFor(() => getResult() !== undefined);
```

Wait for the actual condition, not a guess about how long it takes.

Generic polling function:
```typescript
async function waitFor<T>(
  condition: () => T | undefined | null | false,
  description: string,
  timeoutMs = 5000
): Promise<T> {
  const startTime = Date.now();
  while (true) {
    const result = condition();
    if (result) return result;
    if (Date.now() - startTime > timeoutMs) {
      throw new Error(`Timeout waiting for ${description} after ${timeoutMs}ms`);
    }
    await new Promise(r => setTimeout(r, 10));
  }
}
```

## Root Cause Tracing

When a bug manifests deep in the call stack:

1. **Observe the symptom** — what error, where?
2. **Find immediate cause** — what code directly causes this?
3. **Ask: what called this?** — trace one level up
4. **Keep tracing up** — what value was passed? Where did it come from?
5. **Find original trigger** — the first point where bad data entered

**NEVER fix just where the error appears.** Trace back to the original trigger.

If you can't trace manually, add instrumentation:
```typescript
const stack = new Error().stack;
console.error('DEBUG operation:', { directory, cwd: process.cwd(), stack });
```

Use `console.error()` in tests (not logger — may be suppressed).

## Red Flags — STOP and Return to Phase 1

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "I don't fully understand but this might work"
- "Here are the main problems: [lists fixes without investigation]"
- Proposing solutions before tracing data flow
- "One more fix attempt" (when already tried 2+)
- Each fix reveals new problem in different place

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple" | Simple issues have root causes too. |
| "Emergency, no time" | Systematic is FASTER than thrashing. |
| "Just try this first" | First fix sets the pattern. Do it right. |
| "I see the problem" | Seeing symptoms ≠ understanding root cause. |
| "One more fix" (after 2+) | 3+ failures = architectural problem. |
