# Common Pitfalls -- Complete Reference

The 20 most common Playwright mistakes, organized by category. Each pitfall has BAD vs GOOD code.

---

## Category: Waiting and Timing

### 1. `page.waitForTimeout()` instead of assertions

```typescript
// BAD -- arbitrary delay, slow on fast machines, flaky on slow CI
test('bad: arbitrary wait', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'Load' }).click();
  await page.waitForTimeout(3000);
  await expect(page.getByTestId('chart')).toBeVisible();
});

// GOOD -- auto-retrying assertion waits exactly as long as needed
test('good: auto-retrying assertion', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'Load' }).click();
  await expect(page.getByTestId('chart')).toBeVisible();
});

// GOOD -- wait for a specific network event when data comes from an API
test('good: wait for response', async ({ page }) => {
  await page.goto('/dashboard');
  const responsePromise = page.waitForResponse('**/api/chart-data');
  await page.getByRole('button', { name: 'Load' }).click();
  await responsePromise;
  await expect(page.getByTestId('chart')).toBeVisible();
});
```

### 2. Missing `await` on async operations

```typescript
// BAD -- missing await on click, assertion runs before navigation
test('bad: missing await', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('user@test.com');
  page.getByRole('button', { name: 'Sign in' }).click(); // MISSING AWAIT
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
});

// GOOD
test('good: all actions awaited', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('user@test.com');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
});
```

Prevention: `"@typescript-eslint/no-floating-promises": "error"` in ESLint config.

### 3. `isVisible()` return value instead of `expect().toBeVisible()`

```typescript
// BAD -- resolves once, no retry
test('bad: isVisible check', async ({ page }) => {
  await page.goto('/dashboard');
  const visible = await page.getByTestId('widget').isVisible();
  expect(visible).toBe(true); // fails immediately if not rendered yet
});

// GOOD -- auto-retries for up to 5 seconds
test('good: toBeVisible assertion', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByTestId('widget')).toBeVisible();
});
```

Same applies to `isEnabled()`, `isChecked()`, `textContent()`, `getAttribute()`. Always use `expect(locator)` web-first assertions.

### 4. `expect(await el.textContent()).toBe(x)` -- no retry

```typescript
// BAD -- resolves text once, no retry if content loads asynchronously
test('bad: textContent assertion', async ({ page }) => {
  await page.goto('/product/123');
  const text = await page.getByTestId('price').textContent();
  expect(text).toBe('$49.99');
});

// GOOD -- auto-retrying text assertion
test('good: toHaveText assertion', async ({ page }) => {
  await page.goto('/product/123');
  await expect(page.getByTestId('price')).toHaveText('$49.99');
});
```

### 5. Not waiting for network before asserting

```typescript
// BAD -- clicks and immediately asserts, but data comes from API
test('bad: no network wait', async ({ page }) => {
  await page.goto('/users');
  await page.getByRole('button', { name: 'Load More' }).click();
  await expect(page.getByRole('listitem')).toHaveCount(20);
});

// GOOD -- waits for the API response that populates the list
test('good: waits for API response', async ({ page }) => {
  await page.goto('/users');
  const responsePromise = page.waitForResponse(
    (resp) => resp.url().includes('/api/users') && resp.status() === 200
  );
  await page.getByRole('button', { name: 'Load More' }).click();
  await responsePromise;
  await expect(page.getByRole('listitem')).toHaveCount(20);
});
```

### 6. Clicking during animations

```typescript
// BAD -- modal is animating in, click may miss the target
test('bad: clicks during animation', async ({ page }) => {
  await page.getByRole('button', { name: 'Open' }).click();
  await page.getByRole('button', { name: 'Confirm' }).click();
});

// GOOD -- wait for dialog to be stable before interacting
test('good: waits for stable state', async ({ page }) => {
  await page.getByRole('button', { name: 'Open' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Confirm' }).click();
});
```

### 7. Not handling navigation after form submission

```typescript
// BAD -- assertion runs against the old page being unloaded
test('bad: no navigation handling', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('user@test.com');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});

// GOOD -- wait for URL change, then assert
test('good: waitForURL after navigation', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('user@test.com');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('/dashboard');
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});
```

---

## Category: Locators and Selectors

### 8. CSS selectors instead of role-based locators

```typescript
// BAD -- brittle CSS selectors break on any DOM change
test('bad: CSS selectors', async ({ page }) => {
  await page.locator('.form-group:nth-child(3) input.form-control').fill('new value');
  await page.locator('button.btn.btn-primary.submit-btn').click();
  await expect(page.locator('.alert.alert-success')).toBeVisible();
});

// GOOD -- role-based locators are resilient to implementation changes
test('good: accessible locators', async ({ page }) => {
  await page.getByLabel('Display name').fill('new value');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('alert')).toHaveText('Settings saved');
});
```

Priority: `getByRole()` > `getByLabel()` > `getByPlaceholder()` > `getByText()` > `getByTestId()` > CSS.

### 9. Not using `exact: true` for ambiguous names

```typescript
// BAD -- matches "Log", "Log out", "Log in", "Logging"
test('bad: ambiguous match', async ({ page }) => {
  await page.getByRole('button', { name: 'Log' }).click();
});

// GOOD -- matches only "Log" exactly
test('good: exact match', async ({ page }) => {
  await page.getByRole('button', { name: 'Log', exact: true }).click();
});
```

### 10. `page.$()` / `page.$$()` instead of locators

```typescript
// BAD -- ElementHandle resolves once, goes stale after DOM changes
test('bad: page.$ usage', async ({ page }) => {
  const button = await page.$('.add-to-cart');
  if (button) await button.click();
  const count = await page.$$('.cart-item');
  expect(count.length).toBe(1);
});

// GOOD -- locators are lazy, re-evaluate on every action
test('good: locator usage', async ({ page }) => {
  await page.getByRole('button', { name: 'Add to cart' }).first().click();
  await expect(page.getByTestId('cart-item')).toHaveCount(1);
});
```

### 11. `page.evaluate()` for things locators can do

```typescript
// BAD -- bypasses auto-waiting, no actionability checks
test('bad: evaluate for DOM interaction', async ({ page }) => {
  const text = await page.evaluate(() =>
    document.querySelector('[data-testid="username"]')?.textContent
  );
  expect(text).toBe('John');
  await page.evaluate(() => {
    (document.querySelector('button.save-btn') as HTMLButtonElement)?.click();
  });
});

// GOOD -- locators with auto-waiting and retry
test('good: locator methods', async ({ page }) => {
  await expect(page.getByTestId('username')).toHaveText('John');
  await page.getByRole('button', { name: 'Save' }).click();
});
```

Reserve `evaluate()` for reading `window.__APP_STATE__`, `localStorage`, or computed styles.

### 12. `page.waitForSelector` instead of locator assertions

```typescript
// BAD -- old Puppeteer-style API
test('bad: waitForSelector', async ({ page }) => {
  await page.waitForSelector('.submit-btn');
  await page.click('.submit-btn');
});

// GOOD -- locator-based assertion
test('good: locator assertion', async ({ page }) => {
  await expect(page.getByRole('button', { name: 'Submit' })).toBeVisible();
  await page.getByRole('button', { name: 'Submit' }).click();
});
```

---

## Category: Test Isolation and State

### 13. Shared mutable state between tests

```typescript
// BAD -- module-level variable shared across parallel workers
let userId: string;
test.beforeAll(async ({ request }) => {
  const res = await request.post('/api/users', { data: { email: 'shared@test.com' } });
  userId = (await res.json()).id;
});
test('bad: uses shared state', async ({ page }) => {
  await page.goto(`/users/${userId}`);
});

// GOOD -- test-scoped fixture with unique data
const test = base.extend<{ testUser: { id: string; email: string } }>({
  testUser: async ({ request }, use) => {
    const email = `user-${Date.now()}-${Math.random().toString(36).slice(2)}@test.com`;
    const res = await request.post('/api/users', { data: { email } });
    const user = await res.json();
    await use({ id: user.id, email });
    await request.delete(`/api/users/${user.id}`);
  },
});
test('good: isolated data per test', async ({ page, testUser }) => {
  await page.goto(`/users/${testUser.id}`);
  await expect(page.getByText(testUser.email)).toBeVisible();
});
```

### 14. Module-level variables for test data dependencies

```typescript
// BAD -- test B depends on test A creating the product
let productId: string;
test('test A: creates product', async ({ request }) => {
  const res = await request.post('/api/products', { data: { name: 'Widget' } });
  productId = (await res.json()).id;
});
test('test B: edits product', async ({ page }) => {
  await page.goto(`/products/${productId}/edit`); // undefined if A didn't run
});

// GOOD -- each test is self-contained
test('creates and edits product', async ({ page, request }) => {
  const res = await request.post('/api/products', { data: { name: `Widget-${Date.now()}` } });
  const { id } = await res.json();
  await page.goto(`/products/${id}/edit`);
  await page.getByLabel('Name').fill('Updated Widget');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Updated Widget')).toBeVisible();
  await request.delete(`/api/products/${id}`);
});
```

### 15. `beforeAll` for per-test setup

```typescript
// BAD -- one user shared across all tests, mutations leak
test.beforeAll(async ({ request }) => {
  await request.post('/api/users', { data: { email: 'shared@test.com', name: 'Original' } });
});
test('updates user name', async ({ page }) => {
  await page.goto('/users/shared@test.com');
  await page.getByLabel('Name').fill('Updated'); // mutates shared state
  await page.getByRole('button', { name: 'Save' }).click();
});

// GOOD -- each test creates its own user
test('updates user name', async ({ page, request }) => {
  const email = `user-${Date.now()}@test.com`;
  await request.post('/api/users', { data: { email, name: 'Original' } });
  await page.goto(`/users/${email}`);
  await page.getByLabel('Name').fill('Updated');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByLabel('Name')).toHaveValue('Updated');
});
```

### 16. No cleanup in afterEach (when not using fixtures)

```typescript
// BAD -- leftover state bleeds into next test
test('bad: no cleanup', async ({ page }) => {
  await page.evaluate(() => localStorage.setItem('theme', 'dark'));
});

// GOOD -- fixtures handle cleanup automatically, even on crash
const test = base.extend({
  cleanPage: async ({ page }, use) => {
    await use(page);
    await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
    await page.context().clearCookies();
  },
});
```

---

## Category: Configuration and Organization

### 17. Hardcoded URLs

```typescript
// BAD -- breaks when switching environments
test('bad: hardcoded URL', async ({ page }) => {
  await page.goto('http://localhost:3000/login');
});

// GOOD -- baseURL in config, relative paths in tests
// playwright.config.ts: use: { baseURL: process.env.BASE_URL || 'http://localhost:3000' }
test('good: relative URL', async ({ page }) => {
  await page.goto('/login');
});
```

### 18. No traces in CI

```typescript
// BAD -- no way to debug CI failures
export default defineConfig({ use: { trace: 'off' } });

// GOOD -- capture traces on retry for post-mortem debugging
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  use: { trace: 'on-first-retry' },
});
```

### 19. Giant test files with no organization

```typescript
// BAD -- flat list, no grouping, no shared context
test('admin can view users', async ({ page }) => { /* ... */ });
test('admin can delete user', async ({ page }) => { /* ... */ });
test('viewer cannot delete user', async ({ page }) => { /* ... */ });

// GOOD -- grouped by role, scoped configuration
test.describe('admin users', () => {
  test.use({ storageState: '.auth/admin.json' });
  test.beforeEach(async ({ page }) => { await page.goto('/admin/users'); });

  test('can view user list', async ({ page }) => {
    await expect(page.getByRole('table')).toBeVisible();
  });
  test('can delete a user', async ({ page }) => {
    await page.getByRole('row').first().getByRole('button', { name: 'Delete' }).click();
    await expect(page.getByRole('dialog')).toBeVisible();
  });
});
```

Max 2 levels of `test.describe`. Split into separate files instead of deep nesting.

### 20. No `test.step()` for complex flows

```typescript
// BAD -- 30 lines of actions with no structure, trace is unreadable
test('bad: flat checkout flow', async ({ page }) => {
  await page.goto('/products');
  await page.getByRole('button', { name: 'Add Widget' }).click();
  await page.getByRole('link', { name: 'Cart' }).click();
  await page.getByRole('button', { name: 'Checkout' }).click();
  await page.getByLabel('Email').fill('user@test.com');
  await page.getByRole('button', { name: 'Pay' }).click();
  await expect(page.getByText('Order confirmed')).toBeVisible();
});

// GOOD -- logical steps, clear in traces and reports
test('good: structured checkout', async ({ page }) => {
  await test.step('add item to cart', async () => {
    await page.goto('/products');
    await page.getByRole('button', { name: 'Add Widget' }).click();
    await expect(page.getByTestId('cart-count')).toHaveText('1');
  });
  await test.step('complete payment', async () => {
    await page.getByRole('link', { name: 'Cart' }).click();
    await page.getByRole('button', { name: 'Checkout' }).click();
    await page.getByLabel('Email').fill('user@test.com');
    await page.getByRole('button', { name: 'Pay' }).click();
    await expect(page.getByText('Order confirmed')).toBeVisible();
  });
});
```

---

## Category: Mocking and External Dependencies

### Over-mocking -- mocking your own API

```typescript
// BAD -- mocking your own API removes confidence
test('bad: mocks own API', async ({ page }) => {
  await page.route('**/api/users/me', (route) =>
    route.fulfill({ status: 200, body: JSON.stringify({ name: 'Test User' }) })
  );
  await page.goto('/dashboard');
  await expect(page.getByText('Test User')).toBeVisible(); // passes even if API is broken
});

// GOOD -- mock only external third-party services
test('good: real API, mocked externals', async ({ page }) => {
  await page.route(/google-analytics|segment|intercom/, (route) => route.abort());
  await page.route('**/api.stripe.com/**', (route) =>
    route.fulfill({ status: 200, body: JSON.stringify({ status: 'succeeded' }) })
  );
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
});
```

### Ignoring console errors during tests

```typescript
// BAD -- real errors go unnoticed
test('bad: ignores console errors', async ({ page }) => {
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Pay' }).click();
});

// GOOD -- capture and assert no console errors
test('good: monitors console errors', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });

  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Pay' }).click();
  await expect(page.getByText('Success')).toBeVisible();

  expect(errors).toHaveLength(0);
});
```

### try/catch around expect -- swallows real failures

```typescript
// BAD -- assertion errors silently swallowed
test('bad: try/catch around assertion', async ({ page }) => {
  await page.goto('/dashboard');
  try {
    await expect(page.getByRole('alert')).toBeVisible({ timeout: 2_000 });
    await page.getByRole('button', { name: 'Dismiss' }).click();
  } catch { /* swallowed */ }
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});

// GOOD -- use count() for conditional logic, soft assertions for non-critical checks
test('good: no try/catch', async ({ page }) => {
  await page.goto('/dashboard');
  const alertCount = await page.getByRole('alert').count();
  if (alertCount > 0) {
    await page.getByRole('button', { name: 'Dismiss' }).click();
    await expect(page.getByRole('alert')).not.toBeVisible();
  }
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});
```

---

## Quick Lookup Table

| # | Pitfall | One-Line Fix |
|---|---|---|
| 1 | `waitForTimeout()` | `expect(locator).toBeVisible()` |
| 2 | Missing `await` | Add `await` + `no-floating-promises` ESLint rule |
| 3 | `isVisible()` check | `expect(locator).toBeVisible()` |
| 4 | `textContent()` assertion | `expect(locator).toHaveText()` |
| 5 | No network wait | `page.waitForResponse()` before asserting |
| 6 | Click during animation | `expect(dialog).toBeVisible()` before clicking inside |
| 7 | No navigation handling | `page.waitForURL()` after form submit |
| 8 | CSS selectors | `getByRole()`, `getByLabel()`, `getByTestId()` |
| 9 | Ambiguous name match | `{ exact: true }` on `getByRole` |
| 10 | `page.$()` / `page.$$()` | `page.locator()` or `page.getByRole()` |
| 11 | `page.evaluate()` overuse | Use locator methods; reserve `evaluate` for JS APIs |
| 12 | `waitForSelector` | `expect(locator).toBeVisible()` |
| 13 | Shared mutable state | Test-scoped fixtures with unique data |
| 14 | Module-level test data | Create data inside each test or via fixtures |
| 15 | `beforeAll` for per-test setup | Use `beforeEach` or test-scoped fixtures |
| 16 | No cleanup | Fixtures with teardown via `use()` callback |
| 17 | Hardcoded URLs | `baseURL` in config, relative paths |
| 18 | No traces in CI | `trace: 'on-first-retry'` |
| 19 | Flat test files | `test.describe()` blocks, max 2 levels |
| 20 | No `test.step()` | Wrap logical phases in named steps |
