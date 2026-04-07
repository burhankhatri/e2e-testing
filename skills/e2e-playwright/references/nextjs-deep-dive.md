# Next.js Deep Dive

## App Router vs Pages Router

App Router pages are server components by default. SSR content is in HTML before Playwright loads — no need to wait for client hydration for static content.

Pages Router pages hydrate client-side. Interactive elements may need `toBeVisible()` waits.

## Middleware Testing

```typescript
test('middleware redirects unauthenticated users', async ({ page }) => {
  // Clear auth state for this test
  await page.context().clearCookies();
  await page.goto('/dashboard');
  await page.waitForURL('/login?redirect=/dashboard');
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
});

test('middleware adds custom headers', async ({ page }) => {
  const responsePromise = page.waitForResponse('**/api/protected');
  await page.goto('/dashboard');
  const response = await responsePromise;
  expect(response.headers()['x-custom-header']).toBeDefined();
});
```

## API Route Handlers

Test directly with `request` fixture — no browser needed:

```typescript
test.describe('API routes', () => {
  test('GET /api/users returns user list', async ({ request }) => {
    const response = await request.get('/api/users');
    expect(response.ok()).toBe(true);
    const data = await response.json();
    expect(data.users).toBeInstanceOf(Array);
    expect(data.users[0]).toHaveProperty('email');
  });

  test('POST /api/users creates a user', async ({ request }) => {
    const response = await request.post('/api/users', {
      data: { name: 'Test User', email: 'new@test.com' },
    });
    expect(response.status()).toBe(201);
    const user = await response.json();
    expect(user.name).toBe('Test User');
  });

  test('DELETE /api/users/:id requires auth', async ({ request }) => {
    const response = await request.delete('/api/users/123');
    expect(response.status()).toBe(401);
  });
});
```

## Dynamic Routes and Params

```typescript
test('dynamic route renders correct product', async ({ page }) => {
  await page.goto('/products/abc-123');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Product');
  // Verify URL params were parsed correctly
  await expect(page.getByTestId('product-id')).toHaveText('abc-123');
});

test('catch-all route handles nested paths', async ({ page }) => {
  await page.goto('/docs/getting-started/installation');
  await expect(page.getByRole('article')).toBeVisible();
});
```

## Streaming and Suspense

```typescript
test('streaming content loads progressively', async ({ page }) => {
  // Slow the data source to see suspense boundaries
  await page.route('**/api/slow-data', async route => {
    await new Promise(r => setTimeout(r, 2000));
    await route.fulfill({
      status: 200,
      body: JSON.stringify({ items: [1, 2, 3] }),
    });
  });

  await page.goto('/streaming-page');

  // Suspense fallback should show immediately
  await expect(page.getByText('Loading...')).toBeVisible();

  // Then real content replaces it
  await expect(page.getByRole('listitem')).toHaveCount(3);
  await expect(page.getByText('Loading...')).not.toBeVisible();
});
```

## ISR / Revalidation

```typescript
test('page revalidates after mutation', async ({ page }) => {
  // Create data
  await page.goto('/admin/posts/new');
  await page.getByLabel('Title').fill('New Post');
  await page.getByRole('button', { name: 'Publish' }).click();
  await expect(page.getByText('Published')).toBeVisible();

  // Check revalidated page shows new data
  await page.goto('/blog');
  await expect(page.getByText('New Post')).toBeVisible();
});
```

## Server Actions (App Router)

```typescript
test('server action submits form', async ({ page }) => {
  await page.goto('/feedback');
  await page.getByLabel('Message').fill('Great product!');

  // Server actions submit as form POST — wait for navigation
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByText('Thank you')).toBeVisible();
});
```

## Environment Variables

```bash
# .env.test (committed — no secrets)
NEXT_PUBLIC_API_URL=http://localhost:3000/api
NEXT_PUBLIC_FEATURE_FLAG_NEW_CHECKOUT=true
DATABASE_URL=postgresql://localhost:5432/test_db

# .env.test.local (gitignored — secrets)
NEXTAUTH_SECRET=test-secret-local
STRIPE_TEST_KEY=sk_test_xxx
```
