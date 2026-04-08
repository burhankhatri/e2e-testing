# Fixtures Deep Dive

## Quick Reference

| Mechanism | Scope | Cleanup guaranteed? | Parallelism-safe? | Use for |
|---|---|---|---|---|
| `test.extend()` fixture | per-test | Yes (via `use()`) | Yes | Most setup/teardown needs |
| Worker-scoped fixture | per-worker | Yes | Yes (isolated per worker) | Expensive resources: DB, auth state |
| Auto fixture | per-test or per-worker | Yes | Yes | Side effects that must always run |
| Option fixture | configurable | Yes | Yes | Parameterized values: locale, role, viewport |
| `beforeEach` / `afterEach` | per-test | No (`afterEach` skipped on crash) | Yes | Simple one-off setup, no cleanup |
| `beforeAll` / `afterAll` | per-worker | No (`afterAll` skipped on crash) | Dangerous if mutating shared state | Read-only diagnostics |

**The rule**: If it needs cleanup, use a fixture. If it doesn't need cleanup and is simple, a hook is acceptable. When in doubt, use a fixture.

---

## 1. Test-Scoped Fixtures

Everything before `use()` is setup; everything after is teardown. Teardown runs even if the test crashes.

```typescript
// fixtures.ts
import { test as base, expect, Page } from '@playwright/test';

type TodoFixtures = {
  todoPage: TodoPage;
};

class TodoPage {
  constructor(private page: Page) {}

  async addTodo(text: string) {
    await this.page.getByPlaceholder('What needs to be done?').fill(text);
    await this.page.getByPlaceholder('What needs to be done?').press('Enter');
  }

  async todos() {
    return this.page.getByTestId('todo-item');
  }
}

export const test = base.extend<TodoFixtures>({
  todoPage: async ({ page }, use) => {
    // Setup
    await page.goto('/todos');
    const todoPage = new TodoPage(page);

    // Hand the fixture to the test
    await use(todoPage);

    // Teardown -- runs even if test fails or crashes
    await page.evaluate(() => localStorage.clear());
  },
});

export { expect };
```

```typescript
// todos.spec.ts
import { test, expect } from './fixtures';

test('add a todo item', async ({ todoPage }) => {
  await todoPage.addTodo('Buy milk');
  await expect(await todoPage.todos()).toHaveCount(1);
});
```

---

## 2. Worker-Scoped Fixtures

Created once per worker process, not once per test. Cannot depend on test-scoped fixtures (`page`, `context`, `request`).

The second type parameter in `base.extend<TestFixtures, WorkerFixtures>` is for worker-scoped fixtures.

```typescript
// fixtures.ts
import { test as base } from '@playwright/test';

type WorkerFixtures = {
  dbConnection: DatabaseClient;
  authToken: string;
};

export const test = base.extend<{}, WorkerFixtures>({
  dbConnection: [async ({}, use) => {
    const db = await DatabaseClient.connect(process.env.DB_URL!);
    await use(db);
    await db.disconnect();
  }, { scope: 'worker' }],

  authToken: [async ({}, use) => {
    const response = await fetch(`${process.env.API_URL}/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'test-user',
        password: process.env.TEST_PASSWORD,
      }),
    });
    const { token } = await response.json();
    await use(token);
    // No teardown needed -- token expires on its own
  }, { scope: 'worker' }],
});
```

### Worker fixture with seeded data

```typescript
export const test = base.extend<{}, { seededDb: DatabaseClient }>({
  seededDb: [async ({}, use, workerInfo) => {
    const dbName = `test_db_worker_${workerInfo.workerIndex}`;
    const db = await DatabaseClient.connect(process.env.DB_URL!);
    await db.query(`CREATE DATABASE IF NOT EXISTS ${dbName}`);
    await db.query(`USE ${dbName}`);
    await db.seed('tests/fixtures/seed.sql');
    await use(db);
    await db.query(`DROP DATABASE ${dbName}`);
    await db.disconnect();
  }, { scope: 'worker' }],
});
```

### Worker fixture for compiled assets

```typescript
export const test = base.extend<{}, { assetServer: { url: string } }>({
  assetServer: [async ({}, use) => {
    const server = await startStaticServer({ dir: './dist', port: 0 });
    await use({ url: `http://localhost:${server.port}` });
    await server.close();
  }, { scope: 'worker' }],
});
```

---

## 3. Auto Fixtures -- Side Effects That Must Always Run

Auto fixtures run for every test without being explicitly requested. Use `{ auto: true }`. There is no per-test opt-out.

```typescript
import { test as base, expect } from '@playwright/test';

type AutoFixtures = {
  blockAnalytics: void;
  consoleErrors: string[];
  failOnJSError: void;
};

export const test = base.extend<AutoFixtures>({
  // Block all analytics/tracking requests
  blockAnalytics: [async ({ page }, use) => {
    await page.route(/google-analytics|segment|hotjar|mixpanel/, (route) =>
      route.abort()
    );
    await use();
  }, { auto: true }],

  // Capture console errors and fail if unexpected
  consoleErrors: [async ({ page }, use) => {
    const errors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    await use(errors);
    const unexpected = errors.filter((e) => !e.includes('Expected warning'));
    if (unexpected.length > 0) {
      throw new Error(`Unexpected console errors:\n${unexpected.join('\n')}`);
    }
  }, { auto: true }],

  // Fail test on uncaught page errors
  failOnJSError: [async ({ page }, use) => {
    const errors: Error[] = [];
    page.on('pageerror', (err) => errors.push(err));
    await use();
    if (errors.length > 0) {
      throw new Error(`Uncaught page errors:\n${errors.map((e) => e.message).join('\n')}`);
    }
  }, { auto: true }],
});
```

### Worker-scoped auto fixture

```typescript
export const test = base.extend<{}, { devServer: void }>({
  devServer: [async ({}, use) => {
    const proc = await startDevServer({ port: 3000 });
    await use();
    await proc.kill();
  }, { auto: true, scope: 'worker' }],
});
```

---

## 4. Option Fixtures -- Parameterized, Configurable Per Project

Declared with `{ option: true }`. Overridable in `playwright.config.ts` under `use`, or with `test.use()` in describe blocks.

```typescript
// fixtures.ts
import { test as base, expect, Page } from '@playwright/test';

type OptionFixtures = {
  userRole: 'admin' | 'editor' | 'viewer';
  locale: string;
  defaultTimeout: number;
};

type DerivedFixtures = {
  authenticatedPage: Page;
};

export const test = base.extend<OptionFixtures & DerivedFixtures>({
  // Options with defaults
  userRole: ['viewer', { option: true }],
  locale: ['en-US', { option: true }],
  defaultTimeout: [5000, { option: true }],

  // Derived fixture consumes the options
  authenticatedPage: async ({ page, userRole, locale, defaultTimeout }, use) => {
    page.setDefaultTimeout(defaultTimeout);
    await page.goto(`/login?locale=${locale}`);
    const credentials = {
      admin: { email: 'admin@test.com', password: 'admin-pass' },
      editor: { email: 'editor@test.com', password: 'editor-pass' },
      viewer: { email: 'viewer@test.com', password: 'viewer-pass' },
    };
    const { email, password } = credentials[userRole];
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await use(page);
  },
});

export { expect };
```

### Override per project in config

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  projects: [
    {
      name: 'admin-tests',
      testDir: './tests/admin',
      use: { userRole: 'admin', locale: 'en-US' },
    },
    {
      name: 'viewer-fr',
      testDir: './tests/viewer',
      use: { userRole: 'viewer', locale: 'fr-FR' },
    },
  ],
});
```

### Override per describe block

```typescript
import { test, expect } from './fixtures';

test.describe('admin settings', () => {
  test.use({ userRole: 'admin' });

  test('can access settings page', async ({ authenticatedPage }) => {
    await authenticatedPage.goto('/settings');
    await expect(authenticatedPage.getByRole('heading')).toHaveText('Admin Settings');
  });
});
```

---

## 5. Typed Fixtures in TypeScript

Always define an interface for fixtures. This gives autocomplete, catches typos at compile time, and documents the fixture contract.

```typescript
import { test as base, expect, Page, APIRequestContext } from '@playwright/test';

// Separate interfaces for test vs worker scopes
interface TestFixtures {
  adminPage: Page;
  editorPage: Page;
  apiClient: APIRequestContext;
}

interface WorkerFixtures {
  sharedToken: string;
}

export const test = base.extend<TestFixtures, WorkerFixtures>({
  sharedToken: [async ({}, use) => {
    const res = await fetch(`${process.env.API_URL}/auth/service-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ secret: process.env.SERVICE_SECRET }),
    });
    const { token } = await res.json();
    await use(token);
  }, { scope: 'worker' }],

  apiClient: async ({ playwright, sharedToken }, use) => {
    const ctx = await playwright.request.newContext({
      baseURL: process.env.API_URL,
      extraHTTPHeaders: { Authorization: `Bearer ${sharedToken}` },
    });
    await use(ctx);
    await ctx.dispose();
  },

  adminPage: async ({ browser }, use) => {
    const ctx = await browser.newContext({ storageState: 'auth/admin.json' });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },

  editorPage: async ({ browser }, use) => {
    const ctx = await browser.newContext({ storageState: 'auth/editor.json' });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },
});

export { expect };
```

---

## 6. Composing Fixtures with `mergeTests()`

Use when you have multiple fixture files (auth, API, UI) and tests need several of them. Each file owns its concerns.

```typescript
// fixtures/auth.ts
import { test as base, Page } from '@playwright/test';

type AuthFixtures = { authenticatedPage: Page };

export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('user@example.com');
    await page.getByLabel('Password').fill('password123');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await use(page);
  },
});
```

```typescript
// fixtures/api.ts
import { test as base, APIRequestContext } from '@playwright/test';

type ApiFixtures = { apiClient: APIRequestContext };

export const test = base.extend<ApiFixtures>({
  apiClient: async ({ playwright }, use) => {
    const api = await playwright.request.newContext({
      baseURL: 'https://api.example.com',
      extraHTTPHeaders: { Authorization: `Bearer ${process.env.API_TOKEN}` },
    });
    await use(api);
    await api.dispose();
  },
});
```

```typescript
// fixtures/index.ts
import { mergeTests } from '@playwright/test';
import { test as authTest } from './auth';
import { test as apiTest } from './api';

export const test = mergeTests(authTest, apiTest);
export { expect } from '@playwright/test';
```

```typescript
// dashboard.spec.ts
import { test, expect } from './fixtures';

test('dashboard loads user data', async ({ authenticatedPage, apiClient }) => {
  // Both fixtures available from separate files
  const data = await apiClient.get('/users/me');
  await expect(authenticatedPage.getByRole('heading')).toContainText('Dashboard');
});
```

### Layered composition (chaining `.extend()`)

When fixtures from layer 2 depend on layer 1, chain instead of merging.

```typescript
// Layer 1: database
const dbTest = base.extend<{}, { db: DatabaseClient }>({
  db: [async ({}, use) => {
    const db = await DatabaseClient.connect(process.env.DB_URL!);
    await use(db);
    await db.disconnect();
  }, { scope: 'worker' }],
});

// Layer 2: auth depends on db
const authTest = dbTest.extend<{ authenticatedPage: Page }>({
  authenticatedPage: async ({ page, db }, use) => {
    const user = await db.createTestUser();
    await page.goto('/login');
    await page.getByLabel('Email').fill(user.email);
    await page.getByLabel('Password').fill(user.password);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await use(page);
    await db.deleteUser(user.id);
  },
});

export const test = authTest;
```

---

## 7. Fixture Dependencies and Ordering

Request fixtures by name in the destructured first argument. Playwright resolves the dependency graph automatically. Teardown runs in reverse dependency order.

```typescript
import { test as base, expect, APIRequestContext, Page } from '@playwright/test';

interface Fixtures {
  apiContext: APIRequestContext;
  testUser: { id: string; email: string };
  userPage: Page;
}

export const test = base.extend<Fixtures>({
  // Level 0: no dependencies
  apiContext: async ({ playwright }, use) => {
    const ctx = await playwright.request.newContext({
      baseURL: process.env.API_URL,
    });
    await use(ctx);
    await ctx.dispose();      // teardown 3rd (last)
  },

  // Level 1: depends on apiContext
  testUser: async ({ apiContext }, use) => {
    const response = await apiContext.post('/test/users', {
      data: { email: `user-${Date.now()}@test.com`, role: 'editor' },
    });
    const user = await response.json();
    await use(user);
    await apiContext.delete(`/test/users/${user.id}`);  // teardown 2nd
  },

  // Level 2: depends on page AND testUser
  userPage: async ({ page, testUser }, use) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(testUser.email);
    await page.getByLabel('Password').fill('default-test-password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await use(page);
    // teardown 1st (reverse order)
  },
});

export { expect };
```

**Teardown order**: `userPage` -> `testUser` (deletes user) -> `apiContext` (disposes).

### Overriding built-in fixtures

```typescript
export const test = base.extend({
  // Override built-in context to add custom headers
  context: async ({ browser }, use) => {
    const context = await browser.newContext({
      extraHTTPHeaders: {
        'X-Test-ID': `test-${Date.now()}`,
        'Accept-Language': 'en-US',
      },
      permissions: ['geolocation'],
      geolocation: { latitude: 37.7749, longitude: -122.4194 },
    });
    await use(context);
    await context.close();
  },

  // Override built-in page to block images
  page: async ({ context }, use) => {
    const page = await context.newPage();
    await page.route('**/*.{png,jpg,jpeg,gif,svg}', (route) => route.abort());
    await use(page);
  },
});
```

---

## 8. `beforeAll`/`afterAll` vs Fixtures

### When hooks are acceptable

```typescript
// Simple navigation -- no teardown needed, hook is fine
test.beforeEach(async ({ page }) => {
  await page.goto('/dashboard');
});

test('shows welcome message', async ({ page }) => {
  await expect(page.getByRole('heading')).toHaveText('Welcome');
});
```

### When hooks are NOT acceptable

```typescript
// BAD: cleanup in afterEach is not guaranteed on crash
test.beforeEach(async ({ page }) => {
  await page.evaluate(() => localStorage.setItem('debug', 'true'));
});
test.afterEach(async ({ page }) => {
  await page.evaluate(() => localStorage.clear()); // may not run!
});

// GOOD: fixture teardown always runs
export const test = base.extend<{ debugMode: void }>({
  debugMode: async ({ page }, use) => {
    await page.evaluate(() => localStorage.setItem('debug', 'true'));
    await use();
    await page.evaluate(() => localStorage.clear()); // guaranteed
  },
});
```

### `beforeAll` -- worker-level hooks

Only receives worker-scoped fixtures (`request`, `browser`). Does NOT receive `page` or `context`.

```typescript
// Acceptable: read-only health check, no mutable state
test.beforeAll(async ({ request }) => {
  const response = await request.get('/api/health');
  expect(response.ok()).toBeTruthy();
});
```

### Side-by-side comparison

| | `beforeAll`/`afterAll` | Worker-scoped fixture |
|---|---|---|
| Cleanup guaranteed | No | Yes |
| Access to `page` | No | No (same) |
| Parallel safety | Dangerous with mutable state | Safe (isolated per worker) |
| Can share values to tests | Only via `let` (mutable state anti-pattern) | Yes, via fixture argument |
| Best use case | Read-only precondition checks | Everything else |

---

## 9. Anti-Patterns

### 1. Global mutable state in `beforeAll`

```typescript
// BAD: mutable state shared across parallel tests
let testUser: { id: string; email: string };

test.beforeAll(async ({ request }) => {
  const res = await request.post('/api/users', {
    data: { email: 'shared@test.com' },
  });
  testUser = await res.json(); // shared mutable state!
});

test.afterAll(async ({ request }) => {
  await request.delete(`/api/users/${testUser.id}`); // may not run
});

test('test 1', async ({ page }) => {
  // What if another worker also has a testUser with the same email?
});
```

```typescript
// GOOD: worker-scoped fixture -- isolated per worker, guaranteed cleanup
export const test = base.extend<{ testUser: { id: string; email: string } }>({
  testUser: async ({ request }, use) => {
    const res = await request.post('/api/users', {
      data: { email: `user-${Date.now()}@test.com` },
    });
    const user = await res.json();
    await use(user);
    await request.delete(`/api/users/${user.id}`);
  },
});
```

### 2. Cleanup in `afterEach` instead of fixture teardown

```typescript
// BAD: afterEach not guaranteed to run on crash
test.beforeEach(async ({ page }) => {
  await page.evaluate(() => localStorage.setItem('debug', 'true'));
});
test.afterEach(async ({ page }) => {
  await page.evaluate(() => localStorage.clear()); // skipped on crash
});
```

```typescript
// GOOD: fixture teardown always runs
export const test = base.extend<{ debugMode: void }>({
  debugMode: async ({ page }, use) => {
    await page.evaluate(() => localStorage.setItem('debug', 'true'));
    await use();
    await page.evaluate(() => localStorage.clear());
  },
});
```

### 3. Fixture that does too many things

```typescript
// BAD: one fixture doing unrelated concerns
export const test = base.extend({
  everything: async ({ page }, use) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('user@test.com');
    await page.getByLabel('Password').fill('password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.request.post('/api/products', { data: { name: 'Widget' } });
    await page.route(/analytics/, (r) => r.abort());
    await page.evaluate(() => localStorage.setItem('locale', 'en'));
    await use(page);
  },
});
```

```typescript
// GOOD: separate fixtures, single responsibility each
export const test = base.extend({
  authenticatedPage: async ({ page }, use) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('user@test.com');
    await page.getByLabel('Password').fill('password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await use(page);
  },

  testProduct: async ({ request }, use) => {
    const res = await request.post('/api/products', { data: { name: 'Widget' } });
    const product = await res.json();
    await use(product);
    await request.delete(`/api/products/${product.id}`);
  },

  blockAnalytics: [async ({ page }, use) => {
    await page.route(/analytics/, (r) => r.abort());
    await use();
  }, { auto: true }],
});
```

### 4. Over-abstracting with fixture factories

```typescript
// BAD: fixture factory -- good luck debugging which fixture ran
const createFixture = (role: string, permissions: string[], options: object) =>
  base.extend({
    [`${role}Page`]: async ({ page }, use) => {
      await setupRole(page, role, permissions, options);
      await use(page);
    },
  });

const adminTest = createFixture('admin', ['read', 'write', 'delete'], { mfa: true });
const editorTest = createFixture('editor', ['read', 'write'], { mfa: false });
```

```typescript
// GOOD: explicit fixtures -- boring but readable and debuggable
export const test = base.extend({
  adminPage: async ({ browser }, use) => {
    const ctx = await browser.newContext({ storageState: 'auth/admin.json' });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },

  editorPage: async ({ browser }, use) => {
    const ctx = await browser.newContext({ storageState: 'auth/editor.json' });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },
});
```

### 5. Not typing fixtures in TypeScript

```typescript
// BAD: no type parameter -- no autocomplete, no compile-time errors
export const test = base.extend({
  myFixture: async ({ page }, use) => {
    await use({ count: 42 });
  },
});
// myFixture.cont -- no autocomplete, typos not caught
```

```typescript
// GOOD: explicit type interface
interface MyFixtures {
  myFixture: { count: number };
}

export const test = base.extend<MyFixtures>({
  myFixture: async ({ page }, use) => {
    await use({ count: 42 });
  },
});
// myFixture.count -- autocomplete works, typos caught at compile time
```

---

## 10. Decision Guide

```
I need to set up something before tests run.
|
+-- Does it create a resource that MUST be cleaned up?
|   |
|   +-- YES --> Use a fixture (setup before use(), teardown after)
|   |   |
|   |   +-- Is the resource expensive and safe to share across tests?
|   |   |   +-- YES --> Worker-scoped fixture: { scope: 'worker' }
|   |   |   +-- NO  --> Test-scoped fixture (default)
|   |   |
|   |   +-- Should every test get this automatically?
|   |   |   +-- YES --> Auto fixture: { auto: true }
|   |   |   +-- NO  --> Regular fixture (test declares it in args)
|   |   |
|   |   +-- Should the value be configurable per project?
|   |       +-- YES --> Option fixture: { option: true }
|   |       +-- NO  --> Regular fixture with hardcoded setup
|   |
|   +-- NO --> Hook is acceptable
|       |
|       +-- Per-test setup?  --> beforeEach
|       +-- One-time per worker?  --> beforeAll (read-only checks only)
|
+-- Am I combining fixtures from multiple domains?
|   +-- Do they depend on each other?
|   |   +-- YES --> Chain with .extend()
|   |   +-- NO  --> mergeTests() from separate files
|
+-- Am I wrapping page interactions for reuse?
    +-- Just encapsulation, no setup/teardown --> Page Object Model (class)
    +-- Needs lifecycle management --> Fixture that creates the POM instance
```

### Fixtures vs Page Objects vs Helpers

| Mechanism | Owns lifecycle? | Reusable across tests? | Best for |
|---|---|---|---|
| Fixture | Yes (setup + teardown) | Yes, via `test.extend` | Resources with cleanup: DB, auth, temp files |
| Page Object | No (just wraps page) | Yes, via import | Encapsulating page interactions |
| Helper function | No | Yes, via import | Stateless utilities: generate data, format URLs |
| Fixture + POM | Yes | Yes | POM that needs setup (navigate) and teardown (clear state) |

```typescript
// Fixture that creates and manages a POM
export const test = base.extend<{ checkout: CheckoutPage }>({
  checkout: async ({ page }, use) => {
    await page.goto('/checkout');
    const checkout = new CheckoutPage(page);
    await use(checkout);
    await checkout.clearCart();
  },
});
```

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot use a test-scoped fixture in a worker-scoped fixture` | Worker fixture depends on `page`, `context`, or test-scoped custom fixture | Worker fixtures can only depend on other worker fixtures or built-in worker fixtures (`browser`, `playwright`) |
| `Fixture "X" has already been registered` | Two fixture files define the same name and are both extended | Use `mergeTests()` instead of chaining `.extend()`, or rename one fixture |
| Fixture teardown not running | Used `afterEach` instead of the `use()` callback pattern | Move cleanup after `await use()` inside the fixture |
| `beforeAll` can't access `page` | `page` is test-scoped; `beforeAll` only gets worker-scoped fixtures | Use worker-scoped fixture, or move logic to `beforeEach` |
| Test hangs inside fixture | `await use()` was never called | Ensure every code path calls `await use(value)` exactly once |
| Fixture runs but test doesn't see the value | Fixture not declared in test's destructured arguments | Add the fixture name to the test signature: `async ({ myFixture }) => {}` |
| Option fixture value ignored | `test.use()` called inside `test()` instead of `test.describe()` | `test.use()` must be at top level of a `describe` block or file, not inside a test |
| Auto fixture not running | Fixture file not imported -- custom `test` is not used | Import `test` from your fixture file, not from `@playwright/test` |
| Fixture timeout | Fixture setup takes longer than test timeout | Set `timeout` in fixture options: `[async ({}, use) => { ... }, { timeout: 30000 }]` |
| Worker fixture recreated unexpectedly | Test file imported wrong `test` object | Ensure all files use the same extended `test` export |
