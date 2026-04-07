# Fixtures Deep Dive

## Auto Fixtures — Side Effects That Must Always Run

```typescript
export const test = base.extend<{ blockAnalytics: void }>({
  blockAnalytics: [async ({ page }, use) => {
    await page.route('**/analytics.example.com/**', route => route.abort());
    await use();
  }, { auto: true }],  // runs for every test without requesting it
});
```

## Composing Fixtures

```typescript
// Layer 1: database fixture
const dbTest = base.extend<{}, { db: DatabaseClient }>({
  db: [async ({}, use) => {
    const db = await DatabaseClient.connect(process.env.DB_URL!);
    await use(db);
    await db.disconnect();
  }, { scope: 'worker' }],
});

// Layer 2: add auth on top
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

## Parameterized Fixtures

```typescript
// Test with multiple viewport sizes
const test = base.extend<{ viewport: { width: number; height: number } }>({
  viewport: [{ width: 1280, height: 720 }, { option: true }],
});

// Override per test
test.describe('mobile layout', () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test('shows hamburger menu', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('button', { name: 'Menu' })).toBeVisible();
  });
});
```

## Fixture vs Hook Decision

| Need cleanup? | Complex setup? | Use |
|---|---|---|
| Yes | Any | Fixture (`test.extend`) |
| No | Yes | Fixture (for encapsulation) |
| No | No (1 line) | `beforeEach` is fine |

```typescript
// Hook is fine here — simple, no cleanup
test.beforeEach(async ({ page }) => {
  await page.goto('/');
});

// Fixture needed here — cleanup required
export const test = base.extend({
  tempFile: async ({}, use) => {
    const path = await createTempFile();
    await use(path);
    await fs.unlink(path);  // cleanup guaranteed
  },
});
```
