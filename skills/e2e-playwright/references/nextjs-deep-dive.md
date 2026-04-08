# Next.js Deep Dive

## Playwright Config for Next.js

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? '50%' : undefined,

  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['iPhone 14'] } },
  ],

  webServer: {
    command: process.env.CI
      ? 'npm run build && npm run start' // production build in CI
      : 'npm run dev',                   // dev server locally
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: { NODE_ENV: process.env.CI ? 'production' : 'test' },
  },
});
```

Use `npm run dev` locally for fast feedback. Use `npm run build && npm run start` in CI to test the real production artifact. Turbopack: `npx next dev --turbopack`.

---

## App Router -- Server Components and SSR

App Router pages are server components by default. SSR content is in HTML before Playwright loads -- no need to wait for client hydration for static content.

```typescript
test.describe('App Router pages', () => {
  test('home page renders server component content', async ({ page }) => {
    await page.goto('/');
    // SSR content is already in the HTML
    await expect(page.getByRole('heading', { name: 'Welcome', level: 1 })).toBeVisible();
    await expect(page.getByRole('navigation', { name: 'Main' })).toBeVisible();
  });

  test('nested layouts persist across navigation', async ({ page }) => {
    await page.goto('/dashboard/analytics');
    const sidebar = page.getByRole('navigation', { name: 'Dashboard' });
    await expect(sidebar).toBeVisible();

    // Navigate to sibling route -- layout persists, no full reload
    await sidebar.getByRole('link', { name: 'Settings' }).click();
    await page.waitForURL('/dashboard/settings');
    await expect(sidebar).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
  });
});
```

---

## Streaming and Suspense Boundaries

```typescript
test('loading state shows while data streams in', async ({ page }) => {
  // Slow down the API to expose the loading/suspense state
  await page.route('**/api/dashboard/stats', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    await route.continue();
  });

  await page.goto('/dashboard');
  await expect(page.getByRole('progressbar')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  await expect(page.getByRole('progressbar')).toBeHidden();
});

test('suspense boundary shows fallback then resolves', async ({ page }) => {
  await page.goto('/products');
  // Playwright auto-waits -- assert the final state
  await expect(page.getByRole('listitem')).toHaveCount(12);
});
```

---

## Middleware Testing

```typescript
test.describe('middleware', () => {
  test('unauthenticated user redirected to login', async ({ page }) => {
    await page.context().clearCookies();
    await page.goto('/dashboard');
    expect(page.url()).toContain('/login');
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
  });

  test('redirect preserves the return URL', async ({ page }) => {
    await page.context().clearCookies();
    await page.goto('/dashboard/settings');
    const url = new URL(page.url());
    expect(url.pathname).toBe('/login');
    expect(
      url.searchParams.get('callbackUrl') || url.searchParams.get('returnTo')
    ).toContain('/dashboard/settings');
  });

  test('middleware sets security headers', async ({ page }) => {
    const response = await page.goto('/');
    const headers = response!.headers();
    expect(headers['x-frame-options']).toBe('DENY');
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['referrer-policy']).toBe('strict-origin-when-cross-origin');
  });

  test('middleware rewrites based on locale', async ({ page, context }) => {
    await context.setExtraHTTPHeaders({ 'Accept-Language': 'fr-FR,fr;q=0.9' });
    await page.goto('/');
    await expect(page.getByText('Bienvenue')).toBeVisible();
  });

  test('middleware blocks unauthorized API access', async ({ request }) => {
    const response = await request.get('/api/admin/users');
    expect(response.status()).toBe(401);
  });
});
```

---

## Route Groups and Parallel Routes

```typescript
test.describe('route groups', () => {
  test('(marketing) layout renders marketing nav', async ({ page }) => {
    await page.goto('/about');
    await expect(page.getByRole('navigation', { name: 'Marketing' })).toBeVisible();
    await expect(page.getByRole('navigation', { name: 'Dashboard' })).not.toBeVisible();
  });

  test('(app) layout renders app nav', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page.getByRole('navigation', { name: 'Dashboard' })).toBeVisible();
  });
});

test.describe('parallel routes', () => {
  test('dashboard shows both analytics and notifications slots', async ({ page }) => {
    await page.goto('/dashboard');
    // @analytics and @notifications parallel route slots render side by side
    await expect(page.getByTestId('analytics-panel')).toBeVisible();
    await expect(page.getByTestId('notifications-panel')).toBeVisible();
  });

  test('parallel route slot shows fallback on error', async ({ page }) => {
    // Force the analytics API to fail to trigger the error boundary
    await page.route('**/api/analytics', (route) =>
      route.fulfill({ status: 500, body: 'Internal Server Error' })
    );
    await page.goto('/dashboard');
    await expect(page.getByTestId('analytics-error')).toBeVisible();
    // Other slot still renders normally
    await expect(page.getByTestId('notifications-panel')).toBeVisible();
  });
});
```

---

## Dynamic Routes and Params

```typescript
test.describe('dynamic routes', () => {
  test('[slug] page renders correct content', async ({ page }) => {
    await page.goto('/blog/nextjs-testing-guide');
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Next.js Testing Guide');
    await expect(page.getByText('Page not found')).toBeHidden();
  });

  test('non-existent slug shows 404', async ({ page }) => {
    const response = await page.goto('/blog/this-post-does-not-exist');
    expect(response?.status()).toBe(404);
    await expect(page.getByRole('heading', { name: '404' })).toBeVisible();
  });

  test('catch-all route handles nested paths', async ({ page }) => {
    await page.goto('/docs/getting-started/installation');
    await expect(page.getByRole('heading', { name: 'Installation' })).toBeVisible();
  });

  test('query parameters work with dynamic routes', async ({ page }) => {
    await page.goto('/products?category=electronics&sort=price-asc');
    await expect(page.getByRole('heading', { name: 'Electronics' })).toBeVisible();
    const prices = await page.getByTestId('product-price').allTextContents();
    const nums = prices.map((p) => parseFloat(p.replace('$', '')));
    expect(nums).toEqual([...nums].sort((a, b) => a - b));
  });
});
```

---

## API Route CRUD Testing

Test directly with the `request` fixture -- no browser needed.

```typescript
test.describe('API routes -- CRUD', () => {
  test('GET /api/products returns product list', async ({ request }) => {
    const response = await request.get('/api/products');
    expect(response.ok()).toBeTruthy();
    const body = await response.json();
    expect(body.products).toBeInstanceOf(Array);
    expect(body.products[0]).toHaveProperty('id');
    expect(body.products[0]).toHaveProperty('name');
    expect(body.products[0]).toHaveProperty('price');
  });

  test('POST /api/products creates a product', async ({ request }) => {
    const response = await request.post('/api/products', {
      data: { name: 'Test Product', price: 29.99, description: 'Created by Playwright' },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.product.name).toBe('Test Product');
  });

  test('POST /api/products validates required fields', async ({ request }) => {
    const response = await request.post('/api/products', { data: { name: '' } });
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body.error).toContainEqual(expect.objectContaining({ field: 'price' }));
  });

  test('PUT /api/products/:id updates a product', async ({ request }) => {
    // Create
    const createRes = await request.post('/api/products', {
      data: { name: 'Original', price: 10.00 },
    });
    const { product } = await createRes.json();

    // Update
    const updateRes = await request.put(`/api/products/${product.id}`, {
      data: { name: 'Updated', price: 20.00 },
    });
    expect(updateRes.ok()).toBeTruthy();
    const updated = await updateRes.json();
    expect(updated.product.name).toBe('Updated');
    expect(updated.product.price).toBe(20.00);

    // Cleanup
    await request.delete(`/api/products/${product.id}`);
  });

  test('DELETE /api/products/:id requires auth', async ({ request }) => {
    const response = await request.delete('/api/products/123');
    expect(response.status()).toBe(401);
  });
});

test.describe('API routes -- through UI', () => {
  test('form submission calls API and shows result', async ({ page }) => {
    await page.goto('/products/new');
    await page.getByLabel('Product name').fill('Widget');
    await page.getByLabel('Price').fill('19.99');
    await page.getByRole('button', { name: 'Create product' }).click();
    await expect(page.getByText('Product created successfully')).toBeVisible();
    await page.waitForURL('/products/**');
  });
});
```

---

## Server Actions (App Router)

```typescript
test.describe('server actions', () => {
  test('form action submits and shows confirmation', async ({ page }) => {
    await page.goto('/feedback');
    await page.getByLabel('Message').fill('Great product!');
    // Server actions submit as form POST -- wait for navigation/response
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('Thank you')).toBeVisible();
  });

  test('server action with validation shows errors', async ({ page }) => {
    await page.goto('/feedback');
    // Submit empty form
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('Message is required')).toBeVisible();
  });

  test('server action updates data and revalidates page', async ({ page }) => {
    await page.goto('/settings');
    await page.getByLabel('Display name').fill(`User-${Date.now()}`);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('alert')).toHaveText('Settings saved');
    // Server action should revalidate -- check updated data persists
    await page.reload();
    await expect(page.getByLabel('Display name')).not.toHaveValue('');
  });
});
```

---

## ISR and Revalidation Testing

```typescript
test.describe('ISR / revalidation', () => {
  test('page revalidates after mutation', async ({ page }) => {
    await page.goto('/admin/posts/new');
    const title = `Post-${Date.now()}`;
    await page.getByLabel('Title').fill(title);
    await page.getByRole('button', { name: 'Publish' }).click();
    await expect(page.getByText('Published')).toBeVisible();

    // Revalidated page shows new data
    await page.goto('/blog');
    await expect(page.getByText(title)).toBeVisible();
  });

  test('on-demand revalidation via API', async ({ page, request }) => {
    // Trigger revalidation endpoint
    const revalidateRes = await request.post('/api/revalidate', {
      data: { path: '/blog', secret: process.env.REVALIDATION_SECRET },
    });
    expect(revalidateRes.ok()).toBeTruthy();

    // Page should serve fresh content
    await page.goto('/blog');
    await expect(page.getByRole('article')).toHaveCount(10);
  });

  test('stale page serves cached then revalidates', async ({ page }) => {
    // First visit -- served from cache
    await page.goto('/blog');
    await expect(page.getByRole('article').first()).toBeVisible();

    // Trigger a data change via API
    await page.request.post('/api/posts', {
      data: { title: `Fresh-${Date.now()}`, body: 'New content' },
    });

    // ISR revalidation happens in background -- next visit gets fresh data
    // Use expect.poll for eventual consistency
    await expect(async () => {
      await page.reload();
      const articles = await page.getByRole('article').allTextContents();
      expect(articles.join(' ')).toContain('Fresh-');
    }).toPass({ timeout: 30_000, intervals: [2_000, 5_000] });
  });
});
```

---

## Hydration Testing

```typescript
test.describe('hydration', () => {
  test('no hydration errors in console', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto('/');
    await page.getByRole('button', { name: 'Get started' }).click();

    const hydrationErrors = consoleErrors.filter(
      (e) => e.includes('Hydration') || e.includes('did not match')
    );
    expect(hydrationErrors).toEqual([]);
  });

  test('interactive elements work after hydration', async ({ page }) => {
    await page.goto('/');
    const counter = page.getByTestId('counter-value');
    await expect(counter).toHaveText('0');
    await page.getByRole('button', { name: 'Increment' }).click();
    await expect(counter).toHaveText('1');
  });
});
```

---

## Authentication with NextAuth.js

```typescript
// playwright.config.ts -- auth projects
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    {
      name: 'authenticated',
      use: { storageState: 'playwright/.auth/user.json' },
      dependencies: ['setup'],
    },
    { name: 'unauthenticated', testMatch: '**/*.unauth.spec.ts' },
  ],
});
```

```typescript
// tests/auth.setup.ts
import { test as setup, expect } from '@playwright/test';

const authFile = 'playwright/.auth/user.json';

setup('authenticate via credentials', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('test@example.com');
  await page.getByLabel('Password').fill(process.env.TEST_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('/dashboard');
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  await page.context().storageState({ path: authFile });
});
```

```typescript
// tests/dashboard.spec.ts -- runs with authenticated storageState
test('authenticated user sees dashboard', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  await expect(page.getByText('test@example.com')).toBeVisible();
});
```

---

## Pages Router (getServerSideProps / getStaticProps)

Pages Router pages hydrate client-side. Interactive elements may need `toBeVisible()` waits.

```typescript
test.describe('Pages Router', () => {
  test('getServerSideProps renders fetched data', async ({ page }) => {
    await page.goto('/blog');
    await expect(page.getByRole('heading', { name: 'Blog', level: 1 })).toBeVisible();
    await expect(page.getByRole('article')).toHaveCount(10);
  });

  test('getStaticProps shows pre-rendered content', async ({ page }) => {
    await page.goto('/about');
    await expect(page.getByRole('heading', { name: 'About Us' })).toBeVisible();
    await expect(page.getByText('Founded in 2020')).toBeVisible();
  });

  test('client-side navigation with next/link', async ({ page }) => {
    await page.goto('/blog');
    const navPromise = page.waitForURL('/blog/my-first-post');
    await page.getByRole('link', { name: 'My First Post' }).click();
    await navPromise;
    await expect(page.getByRole('heading', { name: 'My First Post', level: 1 })).toBeVisible();
  });
});
```

---

## Environment Variables

```bash
# .env.test (committed -- no secrets)
NEXT_PUBLIC_API_URL=http://localhost:3000/api
NEXT_PUBLIC_FEATURE_FLAG_NEW_CHECKOUT=true
DATABASE_URL=postgresql://localhost:5432/test_db

# .env.test.local (gitignored -- secrets)
NEXTAUTH_SECRET=test-secret-local
STRIPE_TEST_KEY=sk_test_xxx
```

```bash
# .gitignore
.env*.local
playwright-report/
playwright/.auth/
test-results/
```

---

## Multiple webServer Entries (Next.js + API Backend)

```typescript
webServer: [
  {
    command: 'npm run dev:api',
    url: 'http://localhost:4000/health',
    reuseExistingServer: !process.env.CI,
  },
  {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
],
```

---

## Anti-Patterns

| Do Not | Problem | Do Instead |
|---|---|---|
| `waitForTimeout(3000)` after navigation | Wasteful and fragile | `waitForURL('/path')` or `expect(locator).toBeVisible()` |
| Import and call `getServerSideProps` directly | Depends on req/res context Playwright cannot provide | Navigate to the page and verify rendered output |
| Mock your own API routes with `page.route()` | Tests a fiction; API bugs hidden | Let real API handle requests; mock only externals |
| `page.goto('http://localhost:3000/path')` | Breaks on port/host change | `page.goto('/path')` with `baseURL` in config |
| `npm run build && npm run start` locally | Extremely slow feedback loop | `npm run dev` with `reuseExistingServer: true` |
| Test `next/image` by checking URL paths | URLs change between dev/prod (`/_next/image`) | Assert on alt text, visibility, `naturalWidth > 0` |
| Skip `.env.test` | Values scatter across config and tests | `.env.test` for shared, `.env.test.local` for secrets |
| Call server actions as functions | Bound to Next.js runtime, fails outside request | Trigger through UI (form submissions, button clicks) |
| Ignore console errors in SSR tests | Hydration mismatches indicate real bugs | `page.on('console')` + fail on hydration warnings |
