# API Testing Deep Dive

## Rule: use API calls for speed, not as a replacement for E2E

API tests validate contracts and seed data. UI tests validate what users see. Use both.

```
Why am I making an API call in a test?
|
+-- Testing the API itself (contracts, status codes)?
|   +-- Standalone API test with `request` fixture. No browser launched.
|
+-- Setting up data before a UI test?
|   +-- API seeding in a fixture. 10-100x faster than UI clicks.
|
+-- Cleaning up after a UI test?
|   +-- API teardown in fixture's cleanup phase.
|
+-- Testing a GraphQL backend?
|   +-- POST to /graphql with query + variables. Always check `errors`.
```

## request Fixture -- CRUD Basics

The `request` fixture provides `APIRequestContext` with `baseURL` from config. No browser launched.

```typescript
test('full CRUD lifecycle', async ({ request }) => {
  // POST -- create
  const createResp = await request.post('/api/users', {
    data: { name: 'Jane', email: `jane-${Date.now()}@test.example.com`, role: 'editor' },
  });
  expect(createResp.status()).toBe(201);
  const created = await createResp.json();

  // GET -- read
  const getResp = await request.get(`/api/users/${created.id}`);
  expect(getResp.ok()).toBeTruthy();
  const user = await getResp.json();
  expect(user.name).toBe('Jane');

  // PUT -- full update
  const putResp = await request.put(`/api/users/${created.id}`, {
    data: { name: 'Jane Smith', email: user.email, role: 'admin' },
  });
  expect(putResp.ok()).toBeTruthy();

  // PATCH -- partial update
  const patchResp = await request.patch(`/api/users/${created.id}`, {
    data: { role: 'viewer' },
  });
  expect((await patchResp.json()).role).toBe('viewer');

  // DELETE
  const delResp = await request.delete(`/api/users/${created.id}`);
  expect(delResp.status()).toBe(204);

  // Verify gone
  expect((await request.get(`/api/users/${created.id}`)).status()).toBe(404);
});
```

## Auth Headers and Custom Request Context

```typescript
test('bearer token + custom headers', async ({ request }) => {
  const resp = await request.get('/api/protected/resource', {
    headers: {
      Authorization: 'Bearer eyJhbGciOiJIUzI1NiIs...',
      'X-Request-ID': 'test-correlation-123',
    },
  });
  expect(resp.ok()).toBeTruthy();
});

test('form-encoded OAuth token exchange', async ({ request }) => {
  const resp = await request.post('/api/oauth/token', {
    form: { grant_type: 'client_credentials', client_id: 'app', client_secret: 'secret' },
  });
  expect(await resp.json()).toHaveProperty('access_token');
});
```

For reusable authenticated request fixtures, see `authentication-deep-dive.md`.

## API Test File Structure

Separate project in config -- no browser launched.

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    {
      name: 'api',
      testDir: './tests/api',
      use: { baseURL: 'https://api.example.com' },
    },
    {
      name: 'e2e',
      testDir: './tests/e2e',
      use: { baseURL: 'https://app.example.com', browserName: 'chromium' },
    },
  ],
});
```

```typescript
// tests/api/users.spec.ts
test.describe('Users API', () => {
  test.describe('GET /api/users', () => {
    test('returns paginated list', async ({ request }) => {
      const resp = await request.get('/api/users', { params: { page: 1, limit: 5 } });
      expect(resp.status()).toBe(200);
      const body = await resp.json();
      expect(body.users.length).toBeLessThanOrEqual(5);
      expect(body.pagination).toMatchObject({
        page: 1, limit: 5, total: expect.any(Number),
      });
    });

    test('filters by role', async ({ request }) => {
      const { users } = await (await request.get('/api/users', {
        params: { role: 'admin' },
      })).json();
      for (const user of users) {
        expect(user.role).toBe('admin');
      }
    });
  });

  test.describe('POST /api/users', () => {
    test('rejects duplicate email', async ({ request }) => {
      const email = `dupe-${Date.now()}@test.example.com`;
      await request.post('/api/users', { data: { name: 'First', email } });
      const resp = await request.post('/api/users', { data: { name: 'Second', email } });
      expect(resp.status()).toBe(409);
    });
  });
});
```

## API Seeding Before UI Tests

```typescript
test('edit product seeded via API', async ({ page, request }) => {
  // Seed
  const resp = await request.post('/api/products', {
    data: { name: `Widget-${Date.now()}`, price: 9.99 },
  });
  const product = await resp.json();

  // UI test
  await page.goto(`/products/${product.id}/edit`);
  await page.getByLabel('Name').fill('Updated Widget');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Updated Widget')).toBeVisible();

  // Teardown
  await request.delete(`/api/products/${product.id}`);
});
```

## Response Validation Cheat Sheet

```typescript
// Status
expect(resp.status()).toBe(200);
expect(resp.ok()).toBeTruthy();           // 200-299

// Headers
expect(resp.headers()['content-type']).toContain('application/json');

// Partial object match
expect(user).toMatchObject({ id: 42, name: expect.any(String) });

// Array contains
expect(user.permissions).toEqual(expect.arrayContaining(['read', 'write']));

// Nested object
expect(user.profile).toMatchObject({ avatar: expect.stringMatching(/^https:\/\//) });

// ISO date format
expect(new Date(user.createdAt).toISOString()).toBe(user.createdAt);
```

## GraphQL Testing

All GraphQL goes through `POST` to a single endpoint. Always check both `data` and `errors`.

```typescript
const GQL = '/graphql';

test('query with variables', async ({ request }) => {
  const resp = await request.post(GQL, {
    data: {
      query: `
        query GetUser($id: ID!) {
          user(id: $id) { id name email posts { id title } }
        }
      `,
      variables: { id: '42' },
    },
  });
  const { data, errors } = await resp.json();
  expect(errors).toBeUndefined();
  expect(data.user).toMatchObject({ id: '42', name: expect.any(String) });
});

test('mutation', async ({ request }) => {
  const resp = await request.post(GQL, {
    data: {
      query: `
        mutation CreatePost($input: CreatePostInput!) {
          createPost(input: $input) { id title status }
        }
      `,
      variables: { input: { title: 'New Post', body: 'Content', status: 'DRAFT' } },
    },
  });
  const { data, errors } = await resp.json();
  expect(errors).toBeUndefined();
  expect(data.createPost.status).toBe('DRAFT');
});

test('GraphQL validation error', async ({ request }) => {
  const resp = await request.post(GQL, {
    data: {
      query: `mutation CreatePost($input: CreatePostInput!) {
        createPost(input: $input) { id }
      }`,
      variables: { input: { title: '' } },
    },
  });
  // GraphQL returns 200 even on errors
  const { errors } = await resp.json();
  expect(errors).toBeDefined();
  expect(errors[0].extensions?.code).toBe('BAD_USER_INPUT');
});
```

## Anti-Patterns

| Don't | Problem | Do |
|---|---|---|
| Skip status code assertion | Silent 500s pass as "working" | Always check `status()` or `ok()` |
| Use API tests as a replacement for E2E | Misses rendering bugs, JS errors, a11y | API tests validate contracts; E2E validates UX |
| Hardcode auth tokens in test files | Tokens expire, leak into git | Use env vars via `process.env` |
| Seed via UI when API exists | 10-100x slower | `request.post()` in fixture |
| Forget cleanup after API seeding | Data accumulates across runs | Delete in fixture teardown |
| Ignore `errors` in GraphQL responses | GraphQL returns 200 even on failure | Always assert `errors` is undefined for success |
| Share API context across parallel tests | Cookie/header state leaks | Create fresh context per test or fixture |
