# Authentication Deep Dive

## Storage State Reuse

The foundation pattern. Authenticate once, reuse everywhere.

```typescript
// auth.setup.ts — runs once before all test projects
import { test as setup } from '@playwright/test';

setup('authenticate', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
  await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('/dashboard');
  await page.context().storageState({ path: '.auth/user.json' });
});
```

```typescript
// playwright.config.ts — every test starts authenticated
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'tests',
      use: { storageState: '.auth/user.json' },
      dependencies: ['setup'],
    },
  ],
});
```

Add `.auth/` to `.gitignore`. Auth state files contain session tokens.

---

## API-Based Login (Skip UI)

Faster than browser login. Use for all non-auth tests.

```typescript
// auth.setup.ts — no browser rendering needed
import { test as setup, expect } from '@playwright/test';

setup('authenticate via API', async ({ request }) => {
  const response = await request.post('/api/auth/login', {
    data: { email: process.env.TEST_USER_EMAIL!, password: process.env.TEST_USER_PASSWORD! },
  });
  expect(response.ok()).toBeTruthy();
  await request.storageState({ path: '.auth/user.json' });
});
```

If your app stores tokens in localStorage (not cookies), use page context:

```typescript
setup('API login with localStorage token', async ({ page }) => {
  const { token } = await (await page.request.post('/api/auth/login', {
    data: { email: 'user@test.com', password: 'password' },
  })).json();
  await page.evaluate((t) => localStorage.setItem('authToken', t), token);
  await page.context().storageState({ path: '.auth/user.json' });
});
```

---

## Multi-Role Authentication

```typescript
// playwright.config.ts — one project per role
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    { name: 'admin-tests', use: { storageState: '.auth/admin.json' }, dependencies: ['setup'], testMatch: '**/admin/**' },
    { name: 'member-tests', use: { storageState: '.auth/member.json' }, dependencies: ['setup'], testMatch: '**/member/**' },
    { name: 'unauthenticated', use: { storageState: { cookies: [], origins: [] } }, testMatch: '**/public/**' },
  ],
});

// auth.setup.ts — authenticate all roles
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

Role-switching fixture for comparing roles in a single test:

```typescript
// fixtures/auth.ts
import { test as base, type Page } from '@playwright/test';

type RoleFixtures = { loginAs: (role: 'admin' | 'user' | 'viewer') => Promise<Page> };

export const test = base.extend<RoleFixtures>({
  loginAs: async ({ browser }, use) => {
    const pages: Page[] = [];
    await use(async (role) => {
      const context = await browser.newContext({ storageState: `.auth/${role}.json` });
      const page = await context.newPage();
      pages.push(page);
      return page;
    });
    for (const page of pages) await page.context().close();
  },
});
export { expect } from '@playwright/test';

// usage: compare roles in one test
test('admin sees delete, viewer sees denied', async ({ loginAs }) => {
  const admin = await loginAs('admin');
  await admin.goto('/admin/users');
  await expect(admin.getByRole('button', { name: 'Delete user' })).toBeVisible();
  const viewer = await loginAs('viewer');
  await viewer.goto('/admin/users');
  await expect(viewer.getByText('Access denied')).toBeVisible();
});
```

---

## OAuth Mocking

Intercept the provider redirect and simulate the callback:

```typescript
test('mocked Google OAuth login', async ({ page }) => {
  await page.route('https://accounts.google.com/**', async (route) => {
    const cb = new URL('http://localhost:3000/auth/callback/google');
    cb.searchParams.set('code', 'mock-auth-code-12345');
    cb.searchParams.set('state', route.request().url().match(/state=([^&]+)/)?.[1] || '');
    await route.fulfill({ status: 302, headers: { location: cb.toString() } });
  });
  await page.goto('/login');
  await page.getByRole('button', { name: 'Sign in with Google' }).click();
  await page.waitForURL('/dashboard');
});

test('OAuth failure shows error', async ({ page }) => {
  await page.route('https://accounts.google.com/**', async (route) => {
    const cb = new URL('http://localhost:3000/auth/callback/google');
    cb.searchParams.set('error', 'access_denied');
    await route.fulfill({ status: 302, headers: { location: cb.toString() } });
  });
  await page.goto('/login');
  await page.getByRole('button', { name: 'Sign in with Google' }).click();
  await expect(page.getByRole('alert')).toContainText(/authentication failed|access denied/i);
});
```

Alternative -- bypass OAuth via a test-only backend endpoint (fastest):

```typescript
setup('inject OAuth session via API', async ({ request }) => {
  await request.post('/api/test/create-session', {
    data: { email: 'oauth-user@test.com', provider: 'google', role: 'user' },
  });
  await request.storageState({ path: '.auth/oauth-user.json' });
});
```

---

## NextAuth / Auth.js Patterns

```typescript
setup('NextAuth credentials login', async ({ page }) => {
  await page.goto('/api/auth/csrf');
  const { csrfToken } = JSON.parse((await page.evaluate(() => document.body.textContent))!);

  await page.request.post('/api/auth/callback/credentials', {
    form: { csrfToken, email: process.env.TEST_USER_EMAIL!, password: process.env.TEST_USER_PASSWORD! },
  });
  await page.context().storageState({ path: '.auth/user.json' });
});
```

NextAuth with a mocked OAuth provider (intercept token exchange + userinfo):

```typescript
setup('NextAuth Google login (mocked)', async ({ page }) => {
  await page.route('https://oauth2.googleapis.com/token', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ access_token: 'mock', token_type: 'Bearer', id_token: 'mock' }) }));
  await page.route('https://www.googleapis.com/oauth2/v2/userinfo', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ id: '1', email: 'test@gmail.com', name: 'Test User' }) }));
  await page.goto('/api/auth/callback/google?code=mock-code&state=mock-state');
  await page.waitForURL('/dashboard');
  await page.context().storageState({ path: '.auth/google-user.json' });
});
```

---

## MFA / 2FA Testing

**Strategy 1 -- Real TOTP** (most reliable). Install `otpauth`:

```typescript
// helpers/totp.ts
import * as OTPAuth from 'otpauth';
export function generateTOTP(secret: string): string {
  return new OTPAuth.TOTP({
    secret: OTPAuth.Secret.fromBase32(secret), digits: 6, period: 30, algorithm: 'SHA1',
  }).generate();
}

// tests/mfa-login.spec.ts
test('login with TOTP', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('mfa-user@test.com');
  await page.getByLabel('Password').fill('password');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Enter your authentication code')).toBeVisible();
  await page.getByLabel('Authentication code').fill(generateTOTP(process.env.MFA_TOTP_SECRET!));
  await page.getByRole('button', { name: 'Verify' }).click();
  await page.waitForURL('/dashboard');
});
```

**Strategy 2 -- Backend bypass**: Backend accepts `000000` when `NODE_ENV=test`.

**Strategy 3 -- Mock the verification endpoint**:

```typescript
test('login with mocked MFA', async ({ page }) => {
  // ... login steps that reach the MFA screen ...
  await page.route('**/api/auth/verify-mfa', (route) => route.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify({ success: true }),
  }));
  await page.getByLabel('Verification code').fill('123456');
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page).toHaveURL('/dashboard');
});
```

---

## Password Reset Flow

Intercept the reset email API to capture the token, then complete the flow:

```typescript
test('complete password reset flow', async ({ page }) => {
  let resetToken = '';
  await page.route('**/api/auth/forgot-password', async (route) => {
    const response = await route.fetch();
    resetToken = (await response.json()).resetToken;
    await route.fulfill({ response });
  });

  await page.goto('/forgot-password');
  await page.getByLabel('Email').fill('user@test.com');
  await page.getByRole('button', { name: 'Send reset link' }).click();
  await expect(page.getByText('Reset link sent')).toBeVisible();
  expect(resetToken).toBeTruthy();

  await page.goto(`/reset-password?token=${resetToken}`);
  await page.getByLabel('New password', { exact: true }).fill('NewSecurePass456!');
  await page.getByLabel('Confirm new password').fill('NewSecurePass456!');
  await page.getByRole('button', { name: 'Reset password' }).click();
  await expect(page.getByText('Password reset successfully')).toBeVisible();
});

test('expired reset token shows error', async ({ page }) => {
  await page.goto('/reset-password?token=expired-token');
  await page.getByLabel('New password', { exact: true }).fill('NewPass!');
  await page.getByLabel('Confirm new password').fill('NewPass!');
  await page.getByRole('button', { name: 'Reset password' }).click();
  await expect(page.getByRole('alert')).toContainText(/expired|no longer valid/i);
});
```

---

## Session Timeout Detection

```typescript
test('redirects to login after session expires', async ({ page, context }) => {
  await page.goto('/dashboard');
  const cookies = await context.cookies();
  const sc = cookies.find(c => ['session', 'sid', 'connect.sid'].includes(c.name));
  if (sc) await context.clearCookies({ name: sc.name });
  await page.goto('/settings');
  await expect(page).toHaveURL(/\/login/);
  await expect(page.getByText(/session.*expired|please.*log in/i)).toBeVisible();
});

test('shows expiry warning and extends session', async ({ page }) => {
  let extended = false;
  await page.route('**/api/auth/session', (route) => route.fulfill({
    status: 200, contentType: 'application/json',
    body: JSON.stringify({ valid: true, expiresIn: 120 }),
  }));
  await page.route('**/api/auth/refresh', (route) => {
    extended = true;
    return route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ valid: true, expiresIn: 3600 }) });
  });
  await page.goto('/dashboard');
  await page.getByRole('button', { name: /extend|stay logged in/i }).click({ timeout: 10000 });
  expect(extended).toBe(true);
});
```

---

## Token Refresh Patterns

Worker-scoped fixture that checks session validity and re-authenticates if expired:

```typescript
export const test = base.extend<{}, { freshAuth: void }>({
  freshAuth: [async ({ browser }, use) => {
    const statePath = '.auth/user.json';
    if (fs.existsSync(statePath)) {
      const ctx = await browser.newContext({ storageState: statePath });
      const page = await ctx.newPage();
      if ((await page.request.get('/api/auth/me')).ok()) { await ctx.close(); await use(); return; }
      await ctx.close();
    }
    // Re-authenticate
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await page.goto('/login');
    await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
    await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('/dashboard');
    await ctx.storageState({ path: statePath });
    await ctx.close();
    await use();
  }, { scope: 'worker' }],
});
```

Verify the app's built-in token refresh works:

```typescript
test('app refreshes expired access token', async ({ page }) => {
  await page.goto('/dashboard');
  await page.context().clearCookies({ name: 'access_token' }); // keep refresh_token
  const refreshPromise = page.waitForResponse('**/api/auth/refresh');
  await page.getByRole('button', { name: 'Load data' }).click();
  expect((await refreshPromise).status()).toBe(200);
  await expect(page.getByTestId('data-table')).toBeVisible();
});
```

---

## Logout Verification

```typescript
test.use({ storageState: '.auth/user.json' });

test('logout redirects and blocks re-access', async ({ page }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: /user menu|profile/i }).click();
  await page.getByRole('menuitem', { name: 'Log out' }).click();
  await expect(page).toHaveURL('/login');
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/login/);
});

test('logout clears cookies and localStorage', async ({ page, context }) => {
  await page.goto('/dashboard');
  await page.getByRole('button', { name: /user menu|profile/i }).click();
  await page.getByRole('menuitem', { name: 'Log out' }).click();
  expect((await context.cookies()).filter(c => ['session', 'sid', 'token'].includes(c.name))).toHaveLength(0);
  expect(await page.evaluate(() => localStorage.getItem('authToken'))).toBeNull();
});

test('logout from all devices', async ({ page }) => {
  let called = false;
  await page.route('**/api/auth/logout-all', async (route) => {
    called = true;
    await route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' });
  });
  await page.goto('/settings/security');
  await page.getByRole('button', { name: 'Log out of all devices' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm' }).click();
  expect(called).toBe(true);
  await expect(page).toHaveURL(/\/login/);
});
```

---

## Testing the Login Flow Itself

Opt OUT of storage state to test the login page as an unauthenticated user:

```typescript
test.describe('login page', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test('invalid credentials show error', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('wrong@test.com');
    await page.getByLabel('Password').fill('wrong');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.getByRole('alert')).toContainText('Invalid credentials');
  });

  test('successful login redirects to dashboard', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(process.env.TEST_USER_EMAIL!);
    await page.getByLabel('Password').fill(process.env.TEST_USER_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page).toHaveURL('/dashboard');
  });
});
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `storageState` file not found | Setup project did not run | Add `dependencies: ['setup']` to project config |
| Tests pass locally, fail in CI | Stale auth state | Delete `.auth/` in CI before setup runs |
| 401 errors mid-suite | Token expired during run | Use the `freshAuth` worker fixture above |
| OAuth tests hit real provider | Route pattern mismatch | Log `route.request().url()` to check actual redirect URL |
| NextAuth CSRF mismatch | Missing CSRF token | Fetch `/api/auth/csrf` first, pass token in form data |
| MFA code rejected | TOTP clock drift | Use `otpauth` library with server's shared secret |
| Parallel workers share state | Single auth file | Use per-worker fixture with `parallelIndex` |
| Page shows unauthenticated after login | App reads localStorage, not cookies | Save state from page context, not `request` context |
| Cookie missing after `clearCookies` | Wrong cookie name | Log `await context.cookies()` to find exact name |
| Stored auth has expired cookies | Setup ran too long ago | Re-run setup; use shorter expiry in test env |
