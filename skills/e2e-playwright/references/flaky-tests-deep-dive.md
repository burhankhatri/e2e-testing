# Flaky Tests Deep Dive

## Isolation Strategies

### Data isolation — unique data per test:

```typescript
import { randomUUID } from 'crypto';

test('create user with unique email', async ({ page, request }) => {
  const unique = randomUUID().slice(0, 8);
  const email = `test-${unique}@example.com`;

  await page.goto('/register');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('password123');
  await page.getByRole('button', { name: 'Register' }).click();
  await expect(page.getByText('Welcome')).toBeVisible();
});
```

### Database isolation — seed and clean per test:

```typescript
export const test = base.extend<{ cleanDb: void }>({
  cleanDb: [async ({}, use) => {
    // Setup: seed test data
    await fetch('http://localhost:3000/api/test/seed', { method: 'POST' });
    await use();
    // Teardown: clean up
    await fetch('http://localhost:3000/api/test/cleanup', { method: 'POST' });
  }, { auto: true }],
});
```

### localStorage / cookies isolation:

```typescript
// Fixtures handle this automatically — each test gets a fresh context
// But if you're using beforeEach, clean up explicitly:
test.afterEach(async ({ page }) => {
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
});
```

## Test Ordering Issues

```bash
# Find the polluter: run tests one by one
npx playwright test --workers=1 --reporter=list

# If test X passes alone but fails after test Y:
npx playwright test tests/y.spec.ts tests/x.spec.ts --workers=1
# If it fails: Y is polluting X's state
```

## CI-Specific Diagnosis

```bash
# Match CI viewport locally
npx playwright test --project=chromium --viewport-size=1280,720

# Run in Docker to match CI environment
docker run --rm -v $(pwd):/work -w /work mcr.microsoft.com/playwright:latest npx playwright test

# Compare traces: download CI trace artifact, view locally
npx playwright show-trace path/to/ci-trace.zip
```

## Burn-In Testing

```bash
# Run suspicious test 50 times
npx playwright test -g "checkout flow" --repeat-each=50 --reporter=line

# If it fails even once in 50 runs, it's flaky — fix it
# Common threshold: must pass 50/50 to be considered stable
```

## Auto-Retry Configuration

```typescript
// playwright.config.ts
export default defineConfig({
  retries: process.env.CI ? 2 : 0,  // retry in CI, not locally
  use: {
    trace: 'on-first-retry',         // capture trace on retry
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },
});
```

Tests that pass on retry are still flaky — retries are a safety net, not a fix.
