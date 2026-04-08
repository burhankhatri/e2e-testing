# Flaky Tests Deep Dive

## 4-Category Taxonomy

Every flaky test falls into one of four categories. Identify the category first, then apply the matching fix.

| Category | Symptom | Root Cause | Diagnosis |
|---|---|---|---|
| **Timing / Async** | Fails intermittently everywhere | Race conditions, missing `await`, arbitrary waits | Fails locally with `--repeat-each=20` |
| **Isolation** | Passes alone, fails in suite | Shared state, data collisions, test ordering | Passes with `--grep "test" --workers=1`, fails in full suite |
| **Environment** | Passes locally, fails in CI | Different OS/viewport/fonts/network, missing deps | Compare CI traces with local traces |
| **Infrastructure** | Random, unrelated to test logic | Browser crash, OOM, DNS, filesystem race | No pattern in failures; errors reference browser internals |

## Diagnosis Flowchart

```
Test is flaky
|
+-- Does it fail locally with --repeat-each=20?
|   |
|   +-- YES --> TIMING / ASYNC issue
|   |           Fix: auto-retrying assertions, waitForResponse, remove waitForTimeout
|   |
|   +-- NO --> Does it fail only in CI?
|       |
|       +-- YES --> ENVIRONMENT issue
|       |           Fix: explicit viewport, reducedMotion, webServer, stub externals
|       |
|       +-- NO --> Does it fail only when run with other tests?
|           |
|           +-- YES --> ISOLATION issue
|           |           Fix: unique data per test, fixtures with cleanup
|           |
|           +-- NO --> INFRASTRUCTURE issue
|                       Fix: Docker, --workers=50%, health checks
```

---

## Fix: Timing and Async Issues

The most common source of flakiness. Replace arbitrary waits with auto-retrying assertions.

```typescript
// FIX 1: Replace waitForTimeout with assertions
// BAD
test('bad: arbitrary wait', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'Refresh' }).click();
  await page.waitForTimeout(3000);
  await expect(page.getByTestId('data-table')).toBeVisible();
});
// GOOD
test('good: auto-retrying assertion', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'Refresh' }).click();
  await expect(page.getByTestId('data-table')).toBeVisible();
});

// FIX 2: Wait for network responses before asserting
// BAD
test('bad: no network wait', async ({ page }) => {
  await page.goto('/users');
  await page.getByRole('button', { name: 'Load More' }).click();
  await expect(page.getByRole('listitem')).toHaveCount(20); // flaky
});
// GOOD
test('good: waits for API', async ({ page }) => {
  await page.goto('/users');
  const responsePromise = page.waitForResponse(
    (resp) => resp.url().includes('/api/users') && resp.status() === 200
  );
  await page.getByRole('button', { name: 'Load More' }).click();
  await responsePromise;
  await expect(page.getByRole('listitem')).toHaveCount(20);
});

// FIX 3: Handle animations and transitions
// BAD
test('bad: clicks during animation', async ({ page }) => {
  await page.getByRole('button', { name: 'Open' }).click();
  await page.getByRole('button', { name: 'Confirm' }).click(); // may miss
});
// GOOD
test('good: waits for stable state', async ({ page }) => {
  await page.getByRole('button', { name: 'Open' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Confirm' }).click();
});

// FIX 4: Use toPass() for multi-step retry blocks
test('good: retry entire assertion block', async ({ page }) => {
  await page.goto('/search');
  await expect(async () => {
    await page.getByLabel('Search').fill('playwright');
    await page.getByRole('button', { name: 'Search' }).click();
    await expect(page.getByTestId('result-count')).toHaveText('10 results');
  }).toPass({ timeout: 15_000, intervals: [1_000, 2_000, 5_000] });
});
```

---

## Fix: Test Isolation Issues

```typescript
// FIX 1: Unique test data per test
// BAD -- all parallel tests use the same email
test('bad: hardcoded data', async ({ page }) => {
  await page.goto('/register');
  await page.getByLabel('Email').fill('test@example.com');
  await page.getByRole('button', { name: 'Register' }).click();
});
// GOOD
test('good: unique data', async ({ page }) => {
  const email = `test-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
  await page.goto('/register');
  await page.getByLabel('Email').fill(email);
  await page.getByRole('button', { name: 'Register' }).click();
  await expect(page.getByText('Welcome')).toBeVisible();
});

// FIX 2: Worker-scoped fixtures for expensive shared resources
const test = base.extend<{}, { workerAccount: { email: string; id: string } }>({
  workerAccount: [async ({ request }, use) => {
    const email = `worker-${Date.now()}-${Math.random().toString(36).slice(2)}@test.com`;
    const res = await request.post('/api/users', { data: { email, password: 'TestP@ss123!' } });
    const account = await res.json();
    await use({ email, id: account.id });
    await request.delete(`/api/users/${account.id}`);
  }, { scope: 'worker' }],
});

// FIX 3: Clean up client-side state in fixture teardown
const testWithCleanup = base.extend({
  cleanPage: async ({ page }, use) => {
    await use(page);
    await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
    await page.context().clearCookies();
  },
});

// FIX 4: Isolate tests that cannot run in parallel (last resort)
test.describe.serial('checkout wizard', () => {
  test('step 1: add items', async ({ page }) => {
    await page.goto('/shop');
    await page.getByRole('button', { name: 'Add Widget' }).click();
  });
  test('step 2: enter shipping', async ({ page }) => {
    await page.goto('/checkout/shipping');
    await page.getByLabel('Address').fill('123 Test St');
    await page.getByRole('button', { name: 'Continue' }).click();
  });
});
```

Finding the polluter:
```bash
# Run tests one by one to find which test pollutes state
npx playwright test --workers=1 --reporter=list

# If test X passes alone but fails after test Y:
npx playwright test tests/y.spec.ts tests/x.spec.ts --workers=1
```

---

## Fix: Environment Issues

```typescript
// playwright.config.ts -- environment-consistent configuration
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  use: {
    // Disable CSS animations for deterministic behavior
    contextOptions: { reducedMotion: 'reduce' },
    // Explicit viewport -- same locally and in CI
    viewport: { width: 1280, height: 720 },
  },
  // Higher timeouts for slower CI machines
  timeout: process.env.CI ? 60_000 : 30_000,
  expect: { timeout: process.env.CI ? 10_000 : 5_000 },
  // Start app automatically in CI
  webServer: {
    command: 'npm run start',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

```typescript
// Stub flaky external services -- auto fixture
const test = base.extend({
  stubExternals: [async ({ page }, use) => {
    await page.route(/google-analytics|segment|hotjar|intercom/, (route) => route.abort());
    await page.route('**/api.external-service.com/**', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '{"status":"ok"}' })
    );
    await use();
  }, { auto: true }],
});
```

```bash
# Match CI viewport locally
npx playwright test --project=chromium

# Run in Docker to match CI environment exactly
docker run --rm -v $(pwd):/work -w /work mcr.microsoft.com/playwright:latest npx playwright test

# Compare traces: download CI trace artifact, view locally
npx playwright show-trace path/to/ci-trace.zip
```

---

## Quarantine Strategy

When you cannot fix a flaky test immediately, quarantine it so it does not block CI.

```typescript
// Option 1: test.fixme() -- skips with a reason
test.fixme('checkout with promo code applies discount', async ({ page }) => {
  // TODO(JIRA-1234): Flaky due to race condition in promo service
  // Fails ~10% of runs. Root cause: /api/promo responds after rendering
  await page.goto('/checkout');
  await page.getByLabel('Promo code').fill('SAVE20');
  await page.getByRole('button', { name: 'Apply' }).click();
  await expect(page.getByTestId('discount')).toHaveText('-$20.00');
});

// Option 2: test.fail() -- inverts: passes only if it fails
// CI alerts you when it starts passing so you can remove the annotation
test.fail('known broken: export to PDF', async ({ page }) => {
  await page.goto('/reports');
  await page.getByRole('button', { name: 'Export PDF' }).click();
  await expect(page.getByText('PDF ready')).toBeVisible({ timeout: 10_000 });
});

// Option 3: @flaky tag -- quarantine with grep filter
test('@flaky checkout race condition', async ({ page }) => {
  // CI: npx playwright test --grep-invert @flaky
  // Nightly: npx playwright test --grep @flaky --retries=5
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Place Order' }).click();
  await expect(page.getByText('Order confirmed')).toBeVisible();
});
```

CI configuration for quarantine:
```yaml
# .github/workflows/tests.yml
jobs:
  e2e-tests:
    steps:
      - name: Run stable tests
        run: npx playwright test --grep-invert @flaky

  flaky-monitoring:
    schedule:
      - cron: '0 3 * * *'
    steps:
      - name: Run flaky tests with retries
        run: npx playwright test --grep @flaky --retries=5 --reporter=json
```

---

## Detection Strategies

### Burn-in testing
```bash
# Run suspicious test 50 times
npx playwright test -g "checkout flow" --repeat-each=50 --reporter=line

# Must pass 50/50 to be considered stable
# Run burn-in locally or in nightly jobs, not on every PR
```

### Custom flaky reporter
```typescript
// flaky-reporter.ts
import type { Reporter, TestCase, TestResult } from '@playwright/test/reporter';

class FlakyReporter implements Reporter {
  private flakyTests: { name: string; file: string; retries: number }[] = [];

  onTestEnd(test: TestCase, result: TestResult) {
    if (result.retry > 0 && result.status === 'passed') {
      this.flakyTests.push({ name: test.title, file: test.location.file, retries: result.retry });
    }
  }

  onEnd() {
    if (this.flakyTests.length > 0) {
      console.log('\n--- FLAKY TESTS ---');
      for (const t of this.flakyTests) {
        console.log(`  ${t.file} > "${t.name}" (needed ${t.retries} retries)`);
      }
    }
  }
}
export default FlakyReporter;
```

Register in config:
```typescript
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  reporter: [['html'], ['./flaky-reporter.ts']],
});
```

---

## Auto-Retry Configuration

```typescript
export default defineConfig({
  retries: process.env.CI ? 2 : 0, // retry in CI, fail fast locally
  use: {
    trace: 'on-first-retry',       // capture trace on retry
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },
});
```

Tests that pass on retry are still flaky -- retries are a safety net, not a fix. Track retry counts.

---

## Prevention Checklist

```typescript
// playwright.config.ts -- flake-resistant configuration
export default defineConfig({
  fullyParallel: true,                          // expose isolation issues early
  forbidOnly: !!process.env.CI,                 // fail if test.only() left in code
  retries: process.env.CI ? 2 : 0,             // detect (not hide) flakiness
  timeout: 30_000,
  expect: { timeout: 5_000 },
  use: {
    trace: 'on-first-retry',                   // always capture traces on retry
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    contextOptions: { reducedMotion: 'reduce' }, // disable animations
    viewport: { width: 1280, height: 720 },     // explicit, same everywhere
  },
  webServer: {
    command: 'npm run start',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

In every test:
```typescript
test('stable test example', async ({ page }) => {
  const newName = `User-${Date.now()}`;        // unique data
  await page.goto('/profile');                  // relative path (baseURL)
  await page.getByRole('textbox', { name: 'Display name' }).fill(newName); // role locator
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('alert')).toHaveText('Profile updated'); // auto-retry
  await expect(page.getByRole('textbox', { name: 'Display name' })).toHaveValue(newName);
});
```

---

## Anti-Patterns

| Do Not | Problem | Do Instead |
|---|---|---|
| Increase timeout to 120s | Masks root cause, slows CI | Diagnose the race condition |
| `page.waitForTimeout(N)` | Too slow on fast machines, too fast on slow | `expect(locator).toBeVisible()`, `waitForResponse()` |
| Ignore flaky tests | Erodes trust, real bugs slip through | Diagnose or quarantine with `test.fixme()` |
| `--retries=3` and call it fixed | Hides flakiness, does not fix it | Use retries to *detect*, check retry counts |
| `test.describe.serial()` everywhere | Hides isolation bugs, slows suite | Fix isolation; serial is last resort |
| Mock everything | Removes confidence in real system | Mock only external third-party services |
| `--repeat-each=100` on every PR | Multiplies CI time 100x | Burn-in locally or in nightly jobs |

## Troubleshooting

| Symptom | Category | Fix |
|---|---|---|
| "Timeout 5000ms" intermittently | Timing | `waitForResponse()` or increase `expect.timeout` |
| Passes alone, fails in suite | Isolation | Module-level `let`, shared DB rows, localStorage |
| Passes locally, fails in CI | Environment | Compare traces, check viewport/fonts/reducedMotion |
| "Target closed" / "Browser closed" | Infrastructure | `--workers=50%`, check CI memory limits |
| Fails differently every time | Timing + Isolation | `trace: 'on'`, compare multiple failing traces |
| Passes 99/100 | Timing (rare race) | `--repeat-each=200`, add `waitForResponse()` |
| Visual comparison flaky | Environment | `maxDiffPixelRatio`, explicit fonts, Docker |
