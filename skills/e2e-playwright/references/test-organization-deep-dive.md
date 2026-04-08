# Test Organization Deep Dive

## Rule: group by feature, run in parallel, each test owns its own state

```
How many tests do you have?
|
+-- < 20 (small)
|   +-- Flat: all .spec.ts in tests/
|   +-- No subdirs needed. Tags optional.
|
+-- 20-200 (medium)
|   +-- Feature subdirs: tests/auth/, tests/checkout/
|   +-- @smoke tag for critical-path subset
|   +-- Shared fixtures in tests/fixtures/
|
+-- 200+ (large)
|   +-- Top split: tests/e2e/, tests/api/, tests/visual/
|   +-- Feature subdirs under each
|   +-- Multiple CI pipelines via tags + sharding
```

## File Structure by Project Size

**Small** -- flat, one file per feature:
```
tests/
  auth.spec.ts
  dashboard.spec.ts
  checkout.spec.ts
playwright.config.ts
```

**Medium** -- feature directories:
```
tests/
  auth/
    login.spec.ts
    signup.spec.ts
    password-reset.spec.ts
  checkout/
    cart.spec.ts
    payment.spec.ts
  fixtures/
    auth.fixture.ts
playwright.config.ts
```

**Large** -- top-level type split:
```
tests/
  e2e/
    auth/
    checkout/
    admin/
  api/
    users.spec.ts
    orders.spec.ts
  visual/
    homepage.spec.ts
  fixtures/
    auth.fixture.ts
    db.fixture.ts
playwright.config.ts
```

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| File name | `kebab-case.spec.ts` | `password-reset.spec.ts` |
| `test.describe()` | Title Case, feature name | `'Password Reset'` |
| `test()` | `should ...` or `user can ...` | `'should send reset email'` |
| Fixtures | `kebab-case.fixture.ts` | `auth.fixture.ts` |
| Page objects | `PascalCase` in `kebab.page.ts` | `login.page.ts` / `LoginPage` |

## test.describe() Grouping

Max 2 levels of nesting. If you need a third, split into a separate file.

```typescript
// tests/auth/login.spec.ts
test.describe('Login', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
  });

  test('should login with valid credentials', async ({ page }) => {
    await page.getByLabel('Email').fill('user@example.com');
    await page.getByLabel('Password').fill('pass123');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page).toHaveURL('/dashboard');
  });

  test('should show error for invalid password', async ({ page }) => {
    await page.getByLabel('Email').fill('user@example.com');
    await page.getByLabel('Password').fill('wrong');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.getByRole('alert')).toHaveText('Invalid credentials');
  });

  // One level of nesting -- acceptable
  test.describe('Rate Limiting', () => {
    test('should lock after 5 failed attempts', async ({ page }) => {
      for (let i = 0; i < 5; i++) {
        await page.getByLabel('Password').fill('wrong');
        await page.getByRole('button', { name: 'Sign in' }).click();
      }
      await expect(page.getByRole('alert')).toContainText('Account locked');
    });
  });
});
```

## Tagging with @smoke, @critical, @visual

Tag in the test title string. Filter with `--grep`.

```typescript
test('should process credit card @smoke', async ({ page }) => {
  // Critical path -- runs on every push
});

test('should handle declined card @regression', async ({ page }) => {
  // Full regression -- nightly
});

test('should render 3D Secure flow @slow', async ({ page }) => {
  test.slow(); // Triples timeout
});

test('should show PayPal button', async ({ page }) => {
  test.fixme(); // Known broken -- JIRA-1234
});

test('should skip Apple Pay on non-webkit', async ({ page, browserName }) => {
  test.skip(browserName !== 'webkit', 'Apple Pay only on Safari');
});
```

**Tag a whole describe block:**
```typescript
test.describe('Payment Edge Cases @regression', () => {
  test('network timeout during payment', async ({ page }) => { /* ... */ });
  test('currency conversion edge case', async ({ page }) => { /* ... */ });
});
```

## Filtering Tests (CLI)

```bash
# By tag
npx playwright test --grep @smoke
npx playwright test --grep @regression
npx playwright test --grep-invert @slow        # everything except @slow

# By file or directory
npx playwright test tests/auth/
npx playwright test tests/checkout/payment.spec.ts

# By test name
npx playwright test --grep "should login"

# By project
npx playwright test --project=chromium

# Combine
npx playwright test --grep @smoke --project=chromium

# Single test by line number
npx playwright test tests/auth/login.spec.ts:15
```

## Config-Based Tag Projects

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    { name: 'smoke', testMatch: '**/*.spec.ts', grep: /@smoke/ },
    { name: 'regression', testMatch: '**/*.spec.ts', grep: /@regression/ },
    { name: 'all', testMatch: '**/*.spec.ts', grepInvert: /@slow/ },
  ],
});
```

## Smoke Test Subset for Loop Iterations

When iterating in a test-fix loop, run only smoke tests to get fast feedback.

```typescript
// Tag your happy-path tests @smoke
test('user can login @smoke', async ({ page }) => { /* ... */ });
test('user can add to cart @smoke', async ({ page }) => { /* ... */ });
test('user can checkout @smoke', async ({ page }) => { /* ... */ });

// Then iterate:
// npx playwright test --grep @smoke
// Fix failures, re-run. Only expand to full suite when smoke is green.
```

## Parallel vs Serial

**Default: always parallel.** Set `fullyParallel: true`.

```typescript
// playwright.config.ts
export default defineConfig({
  fullyParallel: true,
  workers: process.env.CI ? 1 : undefined, // all cores locally
});
```

**Multi-step flows -- use `test.step()`, not `serial`:**

```typescript
test('user completes onboarding', async ({ page }) => {
  await test.step('enter company name', async () => {
    await page.goto('/onboarding');
    await page.getByLabel('Company name').fill('Acme');
    await page.getByRole('button', { name: 'Next' }).click();
  });
  await test.step('select plan', async () => {
    await page.getByRole('radio', { name: 'Pro' }).check();
    await page.getByRole('button', { name: 'Next' }).click();
  });
  await test.step('confirm', async () => {
    await page.getByRole('button', { name: 'Complete' }).click();
    await expect(page.getByText('Welcome to Acme')).toBeVisible();
  });
});
```

## Monorepo -- separate `testDir` per project

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    { name: 'web-app', testDir: './apps/web/tests', use: { baseURL: 'http://localhost:3000' } },
    { name: 'admin', testDir: './apps/admin/tests', use: { baseURL: 'http://localhost:3001' } },
  ],
});
// Run: npx playwright test --project=web-app
```

## Annotation Cheat Sheet

| Annotation | Effect | When |
|---|---|---|
| `test.skip()` | Skip entirely | Feature not available in env/browser |
| `test.skip(cond, reason)` | Conditional skip | Browser-specific or env-specific |
| `test.fixme()` | Skip + mark "needs fix" | Known bug, not yet fixed |
| `test.slow()` | Triple timeout | Inherently slow workflows |
| `test.fail()` | Expect failure; fail if it passes | Document known bug with regression guard |

## Anti-Patterns

| Don't | Problem | Do |
|---|---|---|
| One file with 80+ tests | Slow, hard to navigate, bad parallelism | 5-15 tests per file, split by feature |
| `test1`, `test2`, `it works` | Failure tells you nothing | Describe behavior: `should reject expired card` |
| 3+ levels of `test.describe` | Hard to read, hard to find in reports | Max 2 levels; split deeper nesting into files |
| `test.describe.serial()` as default | Kills parallelism, hidden dependencies | Each test sets up its own state |
| Test 2 depends on data from test 1 | Breaks when run alone or in parallel | Each test creates its own data via API/fixture |
| No `@smoke` tag subset | Full suite is too slow for iteration | Tag critical-path tests, run `--grep @smoke` in loops |
| `beforeAll` for parallel test data | Runs per worker, not per test | Use per-test fixtures |
