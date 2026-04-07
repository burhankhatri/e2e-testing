# Authentication Deep Dive

## Multi-Role Authentication

When tests need different user roles (admin, member, viewer):

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'admin-tests',
      use: { storageState: '.auth/admin.json' },
      dependencies: ['setup'],
      testMatch: '**/admin/**',
    },
    {
      name: 'member-tests',
      use: { storageState: '.auth/member.json' },
      dependencies: ['setup'],
      testMatch: '**/member/**',
    },
    {
      name: 'unauthenticated',
      use: { storageState: { cookies: [], origins: [] } },
      testMatch: '**/public/**',
    },
  ],
});
```

```typescript
// auth.setup.ts
import { test as setup } from '@playwright/test';

const users = [
  { role: 'admin', email: 'admin@test.com', password: 'admin-pass', path: '.auth/admin.json' },
  { role: 'member', email: 'member@test.com', password: 'member-pass', path: '.auth/member.json' },
];

for (const user of users) {
  setup(`authenticate as ${user.role}`, async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(user.email);
    await page.getByLabel('Password').fill(user.password);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await page.context().storageState({ path: user.path });
  });
}
```

## API Login (Skip UI)

Faster than browser login — use when auth has a POST endpoint:

```typescript
setup('authenticate via API', async ({ request }) => {
  const response = await request.post('/api/auth/login', {
    data: { email: 'user@test.com', password: 'password' },
  });
  expect(response.ok()).toBe(true);

  // Save the cookies from the API response
  const context = await request.storageState();
  // Write to file manually if using raw request context
  await fs.writeFile('.auth/user.json', JSON.stringify(context));
});
```

## NextAuth / Auth.js Patterns

For apps using NextAuth, set the session cookie directly:

```typescript
setup('authenticate with NextAuth', async ({ page }) => {
  // Use the CSRF token flow
  await page.goto('/api/auth/csrf');
  const csrfResponse = await page.evaluate(() => document.body.textContent);
  const { csrfToken } = JSON.parse(csrfResponse!);

  // Post credentials directly
  await page.request.post('/api/auth/callback/credentials', {
    form: {
      csrfToken,
      email: process.env.TEST_USER_EMAIL!,
      password: process.env.TEST_USER_PASSWORD!,
    },
  });

  await page.context().storageState({ path: '.auth/user.json' });
});
```

## Token Refresh Handling

When tokens expire during test suite:

```typescript
// Worker-scoped fixture that refreshes token if expired
export const test = base.extend<{}, { freshAuth: void }>({
  freshAuth: [async ({ browser }, use) => {
    const authFile = '.auth/user.json';
    const state = JSON.parse(await fs.readFile(authFile, 'utf-8'));

    // Check if token is about to expire
    const sessionCookie = state.cookies.find(c => c.name === 'session-token');
    const isExpired = sessionCookie && new Date(sessionCookie.expires * 1000) < new Date();

    if (isExpired) {
      // Re-authenticate
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.goto('/login');
      // ... login flow
      await context.storageState({ path: authFile });
      await context.close();
    }

    await use();
  }, { scope: 'worker' }],
});
```

## Testing Login Flow Itself

For tests that verify the login page, opt OUT of storage state:

```typescript
test.describe('login page', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test('shows error for invalid credentials', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('wrong@test.com');
    await page.getByLabel('Password').fill('wrong');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.getByRole('alert')).toContainText('Invalid credentials');
  });

  test('redirects to dashboard on success', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
    await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
  });
});
```
