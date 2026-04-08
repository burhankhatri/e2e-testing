# Skill Hardening: Prevent Shallow Testing

**Goal:** Harden 4 skills (/tdd, /e2e-playwright, /start, /verification) so agents cannot satisfy testing requirements superficially — testing only extracted helpers, writing smoke tests instead of feature tests, or weakening assertions to silence failures.

**Architecture:** Surgical additions to 4 existing SKILL.md files. No new files, no restructuring.

**Motivation:** In a real session, an agent ran `/start` and shipped a 343-line Canvas page, 131 lines of API routes, auto-link behavior changes, and 2 bug fixes — all with only pure helper unit tests and "page loads" smoke tests. Every skill gate was technically passed but substantively hollow.

---

### Task 1: Add "Test the Behavior, Not the Helper" anti-pattern to `/tdd`

**Files:**
- Modify: `skills/tdd/SKILL.md`

- [ ] **Step 1: Insert new anti-pattern after existing list (after line 122)**

  Add anti-pattern #6 and a Behavior Coverage Checklist:

  ```markdown
  6. **Testing the helper, not the behavior** — Extracting a pure function, testing it, and calling the feature "tested"

  If you extract `validateRuleBody()` and write 5 tests for it, the API route that *calls* `validateRuleBody()` is still untested. Helper tests verify transformation logic. They do NOT verify:
  - Auth checks on the route
  - Database queries executing correctly
  - Error responses from the handler
  - The full request→response contract

  **Behavior Coverage Checklist — for each type of code you wrote, verify:**

  | Code you wrote | What test do you owe? |
  |---|---|
  | API route handler | Test that calls the route and checks request→response (integration or E2E) |
  | UI component with interactions | E2E test that clicks/types/drags and verifies outcomes |
  | Bug fix | Regression test that reproduces the original symptom |
  | Navigation change | E2E test that clicks nav and verifies destination renders |
  | State management logic | Test through the UI or API that triggers it, not the store directly |
  | Extracted helper/utility | Unit test — but this DOES NOT replace the above. Both are required. |

  **The rule:** A helper test is a bonus. The behavior test is the requirement.
  ```

- [ ] **Step 2: Verify the edit**
  Read `skills/tdd/SKILL.md` and confirm the new section appears after the existing anti-patterns, before the "Gate function before adding mocks" section.

---

### Task 2: Add "Never Weaken a Failing Test" rule to `/tdd`

**Files:**
- Modify: `skills/tdd/SKILL.md`

- [ ] **Step 1: Add rationalization row to the existing table (after line 114)**

  Add this row to the "Common Rationalizations" table:

  ```markdown
  | "Test expectation was wrong" | Was it? Or is the code wrong? Investigate before weakening. |
  ```

- [ ] **Step 2: Insert new rule section after the rationalizations table**

  ```markdown
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

  Weakening an assertion is deleting the test with extra steps.
  ```

- [ ] **Step 3: Verify the edit**
  Read `skills/tdd/SKILL.md` and confirm both additions are present: the new rationalization row and the new "Never Weaken a Failing Test" section.

---

### Task 3: Add "Feature Tests vs Smoke Tests" + Navigation Tests to `/e2e-playwright`

**Files:**
- Modify: `skills/e2e-playwright/SKILL.md`

- [ ] **Step 1: Insert new section after Golden Rules (after line 25, before the "---" separator)**

  ```markdown
  ---

  ## Feature Tests vs Smoke Tests

  Not all E2E tests are equal. Know what tier you're writing.

  | Tier | What it tests | Example | Sufficient for feature coverage? |
  |------|--------------|---------|----------------------------------|
  | **Smoke** | Page loads, no 404, no crash | `goto('/canvas'); expect(heading).toBeVisible()` | **NO** — baseline only |
  | **Feature** | User completes a real workflow | Drag entry to project → rule created → future entries auto-link | **YES** — this is the goal |
  | **Navigation** | Links route correctly, active states work | Click "Canvas" in sidebar → URL is /canvas → heading visible | **Required when nav changes** |

  **The rule:** Every feature shipped MUST have at least one tier-2 (feature) E2E test. Smoke tests are free but DO NOT count toward feature coverage.

  **Ask yourself:** "If someone broke this feature tomorrow, would my E2E tests catch it?" If the answer is "only if they deleted the entire page" — you wrote smoke tests, not feature tests.

  ### Navigation Tests — Required When Nav Changes

  When you add or modify navigation (sidebar items, mobile tab bar, header links, route changes), you MUST write tests that verify:

  1. Nav item is visible at the correct viewport (desktop sidebar, mobile tab bar)
  2. Clicking it navigates to the correct URL
  3. Destination page renders its primary content (not just "no 404")
  4. Active/selected state highlights correctly

  **Desktop + Mobile navigation test template:**

  ```typescript
  import { test, expect } from '@playwright/test';

  test.describe('Navigation — Desktop', () => {
    test.use({ viewport: { width: 1280, height: 800 } });

    test('sidebar contains Canvas link and navigates correctly', async ({ page }) => {
      await page.goto('/');
      const sidebar = page.getByRole('navigation');
      const canvasLink = sidebar.getByRole('link', { name: 'Canvas' });
      await expect(canvasLink).toBeVisible();
      await canvasLink.click();
      await page.waitForURL('/canvas');
      await expect(page.getByRole('heading', { name: 'Canvas' })).toBeVisible();
    });
  });

  test.describe('Navigation — Mobile', () => {
    test.use({ viewport: { width: 375, height: 812 } });

    test('mobile tab bar contains Canvas and navigates correctly', async ({ page }) => {
      await page.goto('/');
      const tabBar = page.getByRole('navigation', { name: /mobile|tab/i });
      const canvasTab = tabBar.getByRole('link', { name: 'Canvas' });
      await expect(canvasTab).toBeVisible();
      await canvasTab.click();
      await page.waitForURL('/canvas');
      await expect(page.getByRole('heading', { name: 'Canvas' })).toBeVisible();
    });
  });
  ```

  Adapt names/selectors to the actual app. The structure is: find nav → find link → click → verify URL → verify content.
  ```

- [ ] **Step 2: Verify the edit**
  Read `skills/e2e-playwright/SKILL.md` and confirm the new section appears between "Golden Rules" and "Next.js Config".

---

### Task 4: Strengthen `/start` Step 5 E2E Quality Gate

**Files:**
- Modify: `skills/start/SKILL.md`

- [ ] **Step 1: Insert E2E Quality Gate after "confirm they pass" (after line 176)**

  Add between the `--repeat-each=3` confirmation and the "If E2E tests are not written" line:

  ```markdown
  **E2E Quality Gate — answer ALL before proceeding to Step 6:**

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
  ║  If ANY answer is NO → go back and write real feature tests.     ║
  ║  "Page loads without 404" is baseline, not coverage.             ║
  ╚══════════════════════════════════════════════════════════════════╝
  ```
  ```

- [ ] **Step 2: Verify the edit**
  Read `skills/start/SKILL.md` and confirm the quality gate appears between the `--repeat-each=3` block and the "If E2E tests are not written" line.

---

### Task 5: Add Test Proportionality Check to `/verification`

**Files:**
- Modify: `skills/verification/SKILL.md`

- [ ] **Step 1: Insert new section after E2E Gate (after line 52)**

  ```markdown
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
  ```

- [ ] **Step 2: Verify the edit**
  Read `skills/verification/SKILL.md` and confirm the new section appears between the "E2E Gate" section and the "Patterns" section.

---

### Task 6: Commit all changes

- [ ] **Step 1: Stage all modified skill files**
  ```bash
  git add skills/tdd/SKILL.md skills/e2e-playwright/SKILL.md skills/start/SKILL.md skills/verification/SKILL.md docs/plans/2026-04-08-skill-hardening.md
  ```

- [ ] **Step 2: Commit**
  ```bash
  git commit -m "feat: harden skills against shallow testing patterns

  - /tdd: add 'Test the Behavior, Not the Helper' anti-pattern
  - /tdd: add 'Never Weaken a Failing Test' rule
  - /e2e-playwright: add Feature vs Smoke tests + navigation test template
  - /start: add E2E Quality Gate self-check in Step 5
  - /verification: add test proportionality check"
  ```

Plan saved. Ready to execute?