---
name: e2e-playwright
description: "Battle-tested Playwright E2E testing patterns for Next.js/React apps. Use when writing, running, debugging, or fixing Playwright tests. Also triggers on 'e2e', 'end-to-end', 'playwright', 'browser test', 'UI test', 'integration test with browser', 'flaky test', 'test keeps failing'. Covers locators, assertions, fixtures, auth, network mocking, flaky test diagnosis, Next.js-specific patterns, and debugging workflows."
---

# Playwright E2E Testing

> Production-tested patterns from the TestDino Playwright Skill. Every pattern includes when (and when *not*) to use it.

## Golden Rules

1. **`getByRole()` over CSS/XPath** — resilient to markup changes, mirrors how users see the page
2. **Never `page.waitForTimeout()`** — use `expect(locator).toBeVisible()` or `page.waitForURL()`
3. **Web-first assertions** — `expect(locator)` auto-retries; `expect(await locator.textContent())` does NOT
4. **Isolate every test** — no shared state, no execution-order dependencies
5. **`baseURL` in config** — zero hardcoded URLs in tests
6. **Retries: `2` in CI, `0` locally** — surface flakiness where it matters
7. **Traces: `'on-first-retry'`** — rich debugging artifacts without CI slowdown
8. **Fixtures over globals** — share state via `test.extend()`, not module-level variables
9. **One behavior per test** — multiple related `expect()` calls are fine
10. **Mock external services only** — never mock your own app; mock third-party APIs, payment gateways, email

**Deep dives available in `references/` directory — read them when working on the relevant topic.**

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

---

## Next.js Config (App Router + Pages Router)

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? '50%' : undefined,
  reporter: process.env.CI ? 'html' : 'list',

  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'on',
    video: 'retain-on-failure',
  },

  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,
      animations: 'disabled',
    },
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['iPhone 14'] } },
  ],

  webServer: {
    command: process.env.CI
      ? 'npm run build && npm run start'  // production build in CI
      : 'npm run dev',                    // dev server locally
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      NODE_ENV: process.env.CI ? 'production' : 'test',
    },
  },
});
```

**Environment variables:** Next.js loads `.env.test` automatically when `NODE_ENV=test`. Use `.env.test` for non-secret test config (committed), `.env.test.local` for secrets (gitignored).

**Gitignore additions:**
```
.env*.local
playwright-report/
playwright/.auth/
test-results/
blob-report/
```

**Do NOT gitignore screenshot baselines.** The `*.spec.ts-snapshots/` directories created by `toHaveScreenshot()` MUST be committed — they are the source of truth for visual regression tests. Only ephemeral artifacts (`test-results/`, `playwright-report/`) should be ignored.

---

## Locators — Priority Order

Use the first one that works:

```typescript
page.getByRole('button', { name: 'Submit' })         // 1. Role (ALWAYS preferred)
page.getByLabel('Email address')                      // 2. Label (form fields)
page.getByText('Welcome back')                        // 3. Text (non-interactive content)
page.getByPlaceholder('Search...')                     // 4. Placeholder
page.getByAltText('Company logo')                     // 5. Alt text (images)
page.getByTitle('Close dialog')                       // 6. Title attribute
page.getByTestId('checkout-summary')                  // 7. Test ID (last resort)
page.locator('css=.legacy-widget')                    // 8. CSS/XPath (absolute last resort)
```

### Role locator cheat sheet:

```typescript
// Buttons — matches <button>, <input type="submit">, role="button"
page.getByRole('button', { name: 'Save changes' })

// Links — matches <a href>
page.getByRole('link', { name: 'View profile' })

// Headings — use level to target h1-h6
page.getByRole('heading', { name: 'Dashboard', level: 1 })

// Text inputs — by accessible name (label)
page.getByRole('textbox', { name: 'Email' })

// Checkboxes and radios
page.getByRole('checkbox', { name: 'Remember me' })
page.getByRole('radio', { name: 'Monthly billing' })

// Dropdowns — <select> elements
page.getByRole('combobox', { name: 'Country' })

// Navigation landmarks
page.getByRole('navigation', { name: 'Main' })

// Dialogs
page.getByRole('dialog', { name: 'Confirm deletion' })

// Exact matching — prevents "Log" matching "Log out"
page.getByRole('button', { name: 'Log', exact: true })
```

**For deeper locator strategy guidance, read `references/locators-deep-dive.md`**

---

## Assertions — Web-First vs Non-Retrying

### Web-first (auto-retry) — ALWAYS prefer:

```typescript
await expect(page.getByRole('heading')).toBeVisible();
await expect(page.getByRole('heading')).toHaveText('Dashboard');
await expect(page.getByRole('listitem')).toHaveCount(5);
await expect(page.getByRole('button')).toBeEnabled();
await expect(page.getByLabel('Name')).toHaveValue('Jane');
await expect(page.getByTestId('card')).toHaveClass(/active/);
await expect(page.getByRole('checkbox')).toBeChecked();
await expect(page.getByRole('dialog')).not.toBeVisible();
```

### Non-retrying — only for already-resolved values:

```typescript
const title = await page.title();
expect(title).toBe('Health Check');

const response = await page.request.get('/api/users');
expect(response.status()).toBe(200);
```

### Polling assertion — non-DOM async conditions:

```typescript
await expect.poll(() => getUserCount()).toBe(10);
```

### Retry block — multiple assertions that must pass together:

```typescript
await expect(async () => {
  const count = await page.getByRole('listitem').count();
  expect(count).toBeGreaterThan(0);
}).toPass();
```

**Critical mistake:** `expect(await locator.textContent()).toBe('x')` — this resolves ONCE with no retry. Use `await expect(locator).toHaveText('x')` instead.

---

## Visual Regression

### When to use:

| Scenario | Visual regression? |
|----------|-------------------|
| Component library / design system | **Yes** — catch unintended style side effects |
| Layout after CSS refactor | **Yes** — verify no regressions |
| Pages with live API data | **No** — content changes break screenshots |
| Real-time dashboards | **No** — dynamic content always diffs |

### Quick reference:

```typescript
// Full page baseline
await expect(page).toHaveScreenshot('homepage.png');

// Element-level (smaller, more stable)
await expect(page.getByTestId('nav')).toHaveScreenshot('nav.png');

// Full scrollable page
await expect(page).toHaveScreenshot('pricing.png', { fullPage: true });

// With masking for dynamic content
await expect(page).toHaveScreenshot('profile.png', {
  mask: [page.getByTestId('timestamp'), page.getByTestId('avatar')],
});
```

### Baseline workflow:

```bash
# Generate baselines (first run or after intentional UI change)
npx playwright test --update-snapshots

# Commit baselines — they are the source of truth
git add tests/e2e/**/*.spec.ts-snapshots/
git commit -m "test: add/update Playwright screenshot baselines"
```

**CRITICAL:** Screenshot baselines MUST be committed. Without them, `toHaveScreenshot()` fails on the next run because there's nothing to compare against. Never gitignore `*.spec.ts-snapshots/` directories.

**For thresholds, CI consistency, masking strategies, and anti-patterns, read `references/visual-regression-deep-dive.md`**

---

## Authentication

### Storage state reuse (default pattern):

```typescript
// global-setup.ts — run once before all tests
import { chromium, type FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const { baseURL } = config.projects[0].use;
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto(`${baseURL}/login`);
  await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
  await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('**/dashboard');
  await context.storageState({ path: '.auth/user.json' });
  await browser.close();
}
export default globalSetup;
```

```typescript
// playwright.config.ts
export default defineConfig({
  globalSetup: require.resolve('./global-setup'),
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

**Add `.auth/` to `.gitignore`** — auth state files contain session tokens.

**For multi-role auth, API login, and NextAuth patterns, read `references/authentication-deep-dive.md`**

---

## Fixtures — Prefer Over Hooks

**Rule:** If it needs cleanup, use a fixture. If it doesn't and is simple, a hook is okay.

```typescript
// fixtures.ts
import { test as base, expect } from '@playwright/test';

export const test = base.extend<{ todoPage: TodoPage }>({
  todoPage: async ({ page }, use) => {
    // Setup
    await page.goto('/todos');
    const todoPage = new TodoPage(page);
    await use(todoPage);    // Hand to test
    // Teardown — runs even if test crashes
    await page.evaluate(() => localStorage.clear());
  },
});

// Worker-scoped (expensive, shared across tests in one worker)
export const test = base.extend<{}, { dbConnection: DatabaseClient }>({
  dbConnection: [async ({}, use) => {
    const db = await DatabaseClient.connect(process.env.DB_URL!);
    await use(db);
    await db.disconnect();
  }, { scope: 'worker' }],
});
```

| Mechanism | Cleanup guaranteed? | Use for |
|---|---|---|
| `test.extend()` fixture | Yes (via `use()`) | Most setup/teardown |
| Worker-scoped fixture | Yes | Expensive resources: DB, auth tokens |
| Auto fixture | Yes | Side effects that must always run |
| `beforeEach`/`afterEach` | No (skipped on crash) | Simple one-off setup |

---

## Network Mocking — External Services Only

**Decision:** Mock at the boundary, test your stack end-to-end.

| Service | Mock? | Why |
|---|---|---|
| Your own API | **Never** | This IS the integration you're testing |
| Your database (through API) | **Never** | Data round-trips are the point |
| Stripe / payments | **Always** | Costs money, rate-limited |
| SendGrid / email | **Always** | Side effects, no UI to assert |
| OAuth providers | **Always** | Redirect-heavy, CAPTCHAs |
| Analytics | **Always** | Fire-and-forget, slows tests |
| Feature flags | **Usually** | Control test conditions deterministically |

```typescript
// Mock a third-party payment API
await page.route('**/api/create-payment-intent', route =>
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ clientSecret: 'pi_mock_123', amount: 9900 }),
  })
);

// Block analytics entirely
await page.route('**/analytics.example.com/**', route => route.abort());

// Wait for a specific API response
const responsePromise = page.waitForResponse('**/api/users');
await page.getByRole('button', { name: 'Load' }).click();
await responsePromise;
```

**For HAR recording, conditional mocking, and advanced patterns, read `references/mocking-deep-dive.md`**

---

## Flaky Test Diagnosis

### Taxonomy — identify the category first:

| Category | Symptom | Diagnosis |
|---|---|---|
| **Timing/Async** | Fails intermittently everywhere | Fails with `--repeat-each=20` locally |
| **Test Isolation** | Fails only with other tests | Passes with `--workers=1 --grep "this test"` |
| **Environment** | Fails only in CI | Compare CI traces with local |
| **Infrastructure** | Random, unrelated to test logic | No pattern, browser internal errors |

### Decision tree:

```
Fails locally with --repeat-each=20?
├── YES → TIMING issue: missing await, waitForTimeout, race condition
└── NO → Fails only in CI?
    ├── YES → ENVIRONMENT: viewport, fonts, slower machines, missing deps
    └── NO → Fails only with other tests?
        ├── YES → ISOLATION: shared state, DB leaks, localStorage
        └── NO → INFRASTRUCTURE: browser crash, OOM, DNS
```

### Fixes for timing (most common):

```typescript
// ❌ Arbitrary wait
await page.waitForTimeout(3000);
await expect(page.getByTestId('chart')).toBeVisible();

// ✅ Auto-retrying assertion
await expect(page.getByTestId('chart')).toBeVisible();

// ❌ Clicks without waiting for network
await page.getByRole('button', { name: 'Load More' }).click();
await expect(page.getByRole('listitem')).toHaveCount(20);

// ✅ Wait for API response first
const responsePromise = page.waitForResponse(
  resp => resp.url().includes('/api/users') && resp.status() === 200
);
await page.getByRole('button', { name: 'Load More' }).click();
await responsePromise;
await expect(page.getByRole('listitem')).toHaveCount(20);

// ❌ Click during animation
await page.getByRole('button', { name: 'Open' }).click();
await page.getByRole('button', { name: 'Confirm' }).click();

// ✅ Wait for dialog to stabilize
await page.getByRole('button', { name: 'Open' }).click();
await expect(page.getByRole('dialog')).toBeVisible();
await page.getByRole('button', { name: 'Confirm' }).click();
```

### Stability validation:

```bash
# Burn-in: run 10 times to confirm stability
npx playwright test tests/checkout.spec.ts --repeat-each=10

# Run in isolation to rule out state leaks
npx playwright test -g "adds item" --workers=1

# Full parallel to expose isolation issues
npx playwright test --fully-parallel --workers=4
```

---

## Debugging Workflow

Follow this order. Most issues resolve by step 2.

```
1. Read the full error message
   └─ Check references/common-pitfalls.md for known patterns
2. Run with --ui to see what happened visually
   └─ Timeline shows every action + screenshot at failure
3. Enable tracing: use: { trace: 'on' } temporarily
4. Check network tab in trace for API failures
   └─ Missing responses, 4xx/5xx, CORS
5. Insert page.pause() at failure point
   └─ Inspect live DOM, try selectors in console
6. Check browser console for JS errors
   └─ page.on('console') or console tab in trace
```

### Commands:

```bash
npx playwright test --ui                           # Interactive UI mode
npx playwright test --headed                       # See browser
npx playwright test --headed --slow-mo=500         # Slow motion
PWDEBUG=1 npx playwright test tests/login.spec.ts  # Step-through inspector
npx playwright show-trace test-results/*/trace.zip # View CI trace
DEBUG=pw:api npx playwright test                   # Verbose API logs
```

### ESLint rule to catch missing awaits:

```json
{ "rules": { "@typescript-eslint/no-floating-promises": "error" } }
```

---

## Common Pitfalls (Top 10)

| # | Pitfall | Fix |
|---|---|---|
| 1 | `page.waitForTimeout()` | Web-first assertion: `expect(locator).toBeVisible()` |
| 2 | Missing `await` | `await` every Playwright call. Enable `no-floating-promises`. |
| 3 | CSS selectors | `getByRole()` > `getByLabel()` > `getByText()` > `getByTestId()` |
| 4 | `isVisible()` return value | `expect(locator).toBeVisible()` (auto-retry) |
| 5 | `expect(await el.textContent())` | `await expect(el).toHaveText(...)` (auto-retry) |
| 6 | Shared state between tests | Fixtures with cleanup, isolated test data |
| 7 | Hardcoded URLs | `baseURL` in config |
| 8 | Mocking own app | Only mock third-party services |
| 9 | Module-level variables | Fixtures via `test.extend()` |
| 10 | No traces in CI | `trace: 'on-first-retry'` in config |

**For all 20 pitfalls with full code examples, read `references/common-pitfalls.md`**

---

## Next.js Specific Patterns

### App Router — server components render before Playwright sees the page:

```typescript
test('home page renders server component', async ({ page }) => {
  await page.goto('/');
  // SSR content is already in HTML by the time Playwright loads
  await expect(page.getByRole('heading', { name: 'Welcome', level: 1 })).toBeVisible();
});
```

### Loading states with streaming/suspense:

```typescript
test('loading skeleton during data streaming', async ({ page }) => {
  // Slow the API to expose loading state
  await page.route('**/api/dashboard/stats', async route => {
    await new Promise(r => setTimeout(r, 2000));
    await route.continue();
  });
  await page.goto('/dashboard');
  await expect(page.getByRole('progressbar')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Stats' })).toBeVisible();
});
```

### API routes:

```typescript
test('API route returns expected data', async ({ request }) => {
  const response = await request.get('/api/users');
  expect(response.ok()).toBe(true);
  const data = await response.json();
  expect(data.users).toHaveLength(3);
});
```

### Client-side navigation:

```typescript
test('client-side navigation preserves state', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('textbox', { name: 'Search' }).fill('test query');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.waitForURL('/settings');
  await page.getByRole('link', { name: 'Dashboard' }).click();
  await page.waitForURL('/dashboard');
  // Client navigation preserved — check if state survives
  await expect(page.getByRole('textbox', { name: 'Search' })).toHaveValue('test query');
});
```

**For middleware testing, route groups, parallel routes, and NextAuth patterns, read `references/nextjs-deep-dive.md`**

---

## Reference Files

For deep dives, read the relevant file in `references/`:

| File | When to read |
|---|---|
| `locators-deep-dive.md` | Decision flowchart, 12+ element types, frame locators, shadow DOM, regex |
| `authentication-deep-dive.md` | Multi-role, API login, OAuth mocking, session timeout, NextAuth, MFA |
| `fixtures-deep-dive.md` | Worker-scoped, auto, option, typed fixtures, mergeTests, anti-patterns |
| `mocking-deep-dive.md` | Decision flowchart, HAR recording, conditional mocking, contract validation |
| `common-pitfalls.md` | 20+ pitfalls organized by category with BAD/GOOD code examples |
| `nextjs-deep-dive.md` | App Router, middleware, server actions, API CRUD, ISR, NextAuth |
| `flaky-tests-deep-dive.md` | 4-category taxonomy, fix patterns, quarantine, prevention checklist |
| `debugging-deep-dive.md` | Systematic workflow, failure-type decision guide, VS Code, anti-patterns |
| `visual-regression-deep-dive.md` | `toHaveScreenshot()`, baselines, thresholds, masking, `@visual` tagging |
| `screenshots-and-media-deep-dive.md` | Capture profiles, video, traces, per-iteration loop debugging |
| `ci-pipeline-deep-dive.md` | GitHub Actions, GitLab CI, sharding, artifacts, coverage, Docker Compose |
| `page-object-model-deep-dive.md` | POM vs fixtures vs factory functions, async init, decision flowchart |
| `test-data-management-deep-dive.md` | Factory patterns, faker, unique IDs for parallel, DB seeding, cleanup |
| `clock-and-time-mocking-deep-dive.md` | `page.clock`, countdowns, session timeouts, timezone handling |
| `iframes-and-shadow-dom-deep-dive.md` | `frameLocator()`, cross-origin, shadow DOM piercing, payment widgets |
| `api-testing-deep-dive.md` | `request` fixture, CRUD patterns, auth headers, GraphQL, API seeding |
| `test-organization-deep-dive.md` | Feature-based structure, tagging, filtering, smoke subsets for loops |
