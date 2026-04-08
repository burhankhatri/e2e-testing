# Network Mocking Deep Dive

## Decision Flowchart

```
Is this service part of YOUR codebase (your API, your backend)?
├── YES → Do NOT mock. Test the real integration.
│   ├── Slow? → Optimize the service, not the test.
│   ├── Flaky? → Fix the service. Flaky infra is a bug.
│   └── Complex setup? → Use test containers or local dev server.
└── NO → Third-party service you do not own.
    ├── Paid per call? (Stripe, Twilio, SendGrid) → ALWAYS mock.
    ├── Rate-limited? (OAuth, social, maps) → ALWAYS mock.
    ├── Sends side effects? (emails, SMS, webhooks) → ALWAYS mock.
    ├── Slow or unreliable? → ALWAYS mock.
    ├── Free + fast + reliable? (rare) → Consider real. Mock if rate-limited in CI.
    └── Complex multi-step? (OAuth dance) → Mock with HAR. Re-record monthly.
```

## Decision Matrix

| Scenario | Mock? | Strategy |
|---|---|---|
| Your own REST/GraphQL API | Never | Hit real API against local dev or staging |
| Your database (through your API) | Never | Seed via API or fixtures, never mock DB |
| Third-party payment (Stripe) | Always | `route.fulfill()` with expected responses |
| Email service (SendGrid, SES) | Always | Mock API call, verify request payload |
| OAuth providers (Google, GitHub) | Always | Mock token exchange, test your callback |
| Analytics (Segment, Mixpanel) | Always | `route.abort()` to block entirely |
| Feature flags (LaunchDarkly) | Usually | Mock to force specific flag states |
| Webhooks (incoming) | Always | `route.fulfill()` or call your endpoint directly |
| Maps / geocoding APIs | Always | Mock with static responses |
| CDN / static assets | Never | Let them load normally |
| Rate-limited external API | CI: mock | Conditional mocking based on environment |

---

## route.fulfill -- Full Mock

```typescript
await page.route('**/api/create-payment-intent', route =>
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ clientSecret: 'pi_mock_123', amount: 9900 }),
  })
);

// Shorthand: json option (auto contentType, no JSON.stringify)
await page.route('**/api/users', route =>
  route.fulfill({ json: [{ id: 1, name: 'Alice' }] })
);

// Error scenario
await page.route('**/api/confirm-payment', route =>
  route.fulfill({
    status: 402,
    json: { error: { code: 'card_declined', message: 'Declined' } },
  })
);
```

## route.abort -- Block Requests

```typescript
// Block analytics
await page.route(/(google-analytics|segment|hotjar|mixpanel)/, route => route.abort());

// Block images when testing non-visual flows
await page.route('**/*.{png,jpg,gif,svg,webp}', route => route.abort());

// Block by resource type (context-level = all pages)
await context.route('**/*', route => {
  if (['image', 'font', 'media'].includes(route.request().resourceType())) {
    return route.abort();
  }
  return route.continue();
});
```

**Abort reasons**: `'connectionrefused'`, `'connectionreset'`, `'internetdisconnected'`, `'namenotresolved'`, `'timedout'`, `'failed'`, `'aborted'`.

## route.continue -- Pass Through with Modifications

```typescript
// Add auth header to all API calls
await page.route('**/api/**', route =>
  route.continue({
    headers: { ...route.request().headers(), 'X-Test': 'true' },
  })
);

// Simulate slow response (test loading spinners)
await page.route('**/api/dashboard', async route => {
  await new Promise(r => setTimeout(r, 3000));
  await route.continue();
});
```

---

## Request Modification

Change outgoing requests before they reach the server.

```typescript
// Override headers (inject auth, feature flags)
await page.route('**/api/**', route =>
  route.continue({
    headers: {
      ...route.request().headers(),
      authorization: 'Bearer test-token-xyz',
      'x-feature-flags': 'new-checkout=true',
    },
  })
);

// Override POST body
await page.route('**/api/orders', route => {
  const original = route.request().postDataJSON();
  return route.continue({
    postData: JSON.stringify({ ...original, coupon: 'TEST50' }),
  });
});

// Redirect to a different URL
await page.route('**/api/v1/**', route =>
  route.continue({ url: route.request().url().replace('/v1/', '/v2/') })
);
```

## Response Modification

Intercept the real response, modify it, then pass it to the browser. Uses `route.fetch()` which makes a real network call.

```typescript
// Override a single field in real data
await page.route('**/api/products/*', async route => {
  const response = await route.fetch();
  const body = await response.json();
  body.stockCount = 2;
  await route.fulfill({ response, body: JSON.stringify(body) });
});

// Inject test data into real response
await page.route('**/api/notifications', async route => {
  const response = await route.fetch();
  const body = await response.json();
  body.notifications.push({ id: 'test', message: 'Export ready', read: false });
  await route.fulfill({ response, json: body });
});

// Override feature flags from real config endpoint
await page.route('**/api/config', async route => {
  const response = await route.fetch();
  const config = await response.json();
  config.featureFlags = { ...config.featureFlags, newCheckout: true };
  await route.fulfill({ response, json: config });
});
```

---

## GraphQL Mocking

Single endpoint, dispatch by operation name.

```typescript
await page.route('**/graphql', async route => {
  const { operationName, variables } = route.request().postDataJSON();

  if (operationName === 'GetUsers') {
    return route.fulfill({
      json: { data: { users: [{ id: '1', name: 'Alice' }, { id: '2', name: 'Bob' }] } },
    });
  }
  if (operationName === 'CreateUser') {
    return route.fulfill({
      json: { data: { createUser: { id: '99', name: variables.input.name } } },
    });
  }
  if (operationName === 'AdminQuery') {
    return route.fulfill({
      json: { data: null, errors: [{ message: 'Not authorized', extensions: { code: 'UNAUTHORIZED' } }] },
    });
  }
  return route.continue(); // unmocked operations hit real server
});
```

---

## HAR Recording Workflow

Record real API traffic once, replay deterministically.

```typescript
// Step 1: RECORD -- run once, commit the .har file
test('record dashboard API traffic', async ({ page }) => {
  await page.routeFromHAR('tests/fixtures/dashboard.har', {
    url: '**/api/**',
    update: true, // record mode
  });
  await page.goto('/dashboard');
  await page.getByRole('tab', { name: 'Analytics' }).click();
});

// Step 2: REPLAY -- serve from HAR, no network
test('dashboard loads with recorded data', async ({ page }) => {
  await page.routeFromHAR('tests/fixtures/dashboard.har', {
    url: '**/api/**', // update: false is default (replay mode)
  });
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: 'Analytics' })).toBeVisible();
});

// Step 3: Handle unmatched requests
await page.routeFromHAR('tests/fixtures/api.har', {
  url: '**/api/**',
  notFound: 'abort',    // strict: fail unmatched
  // notFound: 'fallback', // lenient: let unmatched hit real server
});
```

**HAR maintenance**: Record against staging. Commit `.har` files (JSON, diffable). Re-record monthly or when APIs change. Scope to specific URL patterns. Context-level: `context.routeFromHAR(...)`.

---

## Conditional Mocking

```typescript
// Environment-based: mock in CI, real locally
test.beforeEach(async ({ page }) => {
  if (process.env.CI) {
    await page.route('**/external-api.com/**', route =>
      route.fulfill({ json: { data: 'mocked' } })
    );
  }
});

// Method-based dispatch
await page.route('**/api/users', route => {
  switch (route.request().method()) {
    case 'GET':    return route.fulfill({ json: [{ id: 1, name: 'Alice' }] });
    case 'POST':   return route.fulfill({ status: 201, json: { id: 2, name: 'Bob' } });
    case 'DELETE':  return route.fulfill({ status: 204, body: '' });
    default:        return route.continue();
  }
});

// Query-parameter-based dispatch
await page.route('**/api/users*', route => {
  const url = new URL(route.request().url());
  const role = url.searchParams.get('role');
  const users = [{ id: 1, name: 'Alice', role: 'admin' }, { id: 2, name: 'Bob', role: 'user' }];
  return route.fulfill({ json: role ? users.filter(u => u.role === role) : users });
});
```

---

## Mock with Fixture Pattern

Centralize mocking in a Playwright fixture. Tests opt-in/out per service.

```typescript
// tests/fixtures/mock-fixtures.ts
import { test as base } from '@playwright/test';

type MockOptions = { mockPayments: boolean; mockEmail: boolean; mockAnalytics: boolean };

export const test = base.extend<MockOptions>({
  mockPayments: [true, { option: true }],
  mockEmail: [true, { option: true }],
  mockAnalytics: [true, { option: true }],
  page: async ({ page, mockPayments, mockEmail, mockAnalytics }, use) => {
    if (mockPayments) {
      await page.route('**/api/payments/**', r => r.fulfill({ json: { status: 'succeeded' } }));
    }
    if (mockEmail) {
      await page.route('**/api/send-email', r => r.fulfill({ json: { messageId: 'mock_456' } }));
    }
    if (mockAnalytics) {
      await page.route('**/{segment,google-analytics,mixpanel}.**/**', r => r.abort());
    }
    await use(page);
  },
});
export { expect } from '@playwright/test';
```

```typescript
// tests/checkout.spec.ts -- uses defaults (all mocked)
import { test, expect } from './fixtures/mock-fixtures';

test('checkout sends confirmation', async ({ page }) => {
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Pay $99.00' }).click();
  await expect(page.getByText('Confirmation email sent')).toBeVisible();
});

// Override: real payments for nightly integration
test.describe('nightly', () => {
  test.use({ mockPayments: false });
  test('real Stripe test mode', async ({ page }) => { /* ... */ });
});
```

---

## Error Simulation

```typescript
// 500 server error
await page.route('**/api/users', r => r.fulfill({ status: 500, json: { error: 'Internal Server Error' } }));

// Network failure
await page.route('**/api/users', r => r.abort('connectionrefused'));

// Timeout (delay > app's fetch timeout)
await page.route('**/api/users', async r => {
  await new Promise(resolve => setTimeout(resolve, 30_000));
  await r.fulfill({ json: [] });
});

// Intermittent failure then recovery
let count = 0;
await page.route('**/api/users', r => {
  count++;
  return count <= 2
    ? r.fulfill({ status: 503, json: { error: 'Unavailable' } })
    : r.fulfill({ json: [{ id: 1, name: 'Alice' }] });
});
```

---

## Waiting for Requests / Verifying Payloads

```typescript
// Wait for response before asserting
const responsePromise = page.waitForResponse(r => r.url().includes('/api/users') && r.status() === 200);
await page.getByRole('button', { name: 'Load' }).click();
const data = await (await responsePromise).json();
expect(data.users).toHaveLength(10);

// Verify outgoing payload
const reqPromise = page.waitForRequest('**/api/users');
await page.getByRole('button', { name: 'Create' }).click();
expect((await reqPromise).postDataJSON()).toMatchObject({ name: 'Alice' });

// Wait for multiple sequential API calls
const [validate, submit] = await Promise.all([
  page.waitForResponse('**/api/cart/validate'),
  page.waitForResponse('**/api/orders'),
  page.getByRole('button', { name: 'Place order' }).click(),
]);

// Capture all requests to an endpoint
const requests: Request[] = [];
await page.route('**/api/track', route => { requests.push(route.request()); route.fulfill({ status: 200 }); });
await page.getByRole('button', { name: 'Buy' }).click();
expect(requests[0].postDataJSON().event).toBe('purchase');
```

---

## Contract Validation

Verify mocks still match real API shape. Run weekly or when APIs change.

```typescript
test.describe('mock contract validation', () => {
  test('payment mock matches real API shape', async ({ request }) => {
    const realBody = await (await request.post('/api/create-payment-intent', {
      data: { amount: 9900, currency: 'usd' },
    })).json();

    const mockBody = { clientSecret: 'pi_mock_secret_123', amount: 9900, currency: 'usd' };

    expect(Object.keys(mockBody).sort()).toEqual(Object.keys(realBody).sort());
    for (const key of Object.keys(mockBody)) {
      expect(typeof mockBody[key]).toBe(typeof realBody[key]);
    }
  });
});
```

---

## WebSocket Mocking Basics

Playwright does not intercept WebSocket frames via `page.route()`.

```typescript
// Block WebSocket upgrade entirely
await page.route('**/ws/**', route => route.abort());

// Redirect third-party WS to local mock server
await page.addInitScript(() => {
  const Real = window.WebSocket;
  (window as any).WebSocket = class extends Real {
    constructor(url: string, protocols?: string | string[]) {
      super(url.includes('third-party-ws.com') ? 'ws://localhost:9999/mock' : url, protocols);
    }
  };
});
```

---

## URL Pattern Reference

| Pattern | Matches | Does NOT Match |
|---|---|---|
| `**/api/users` | `/api/users`, `/v2/api/users` | `/api/users/1` |
| `**/api/users*` | `/api/users`, `/api/users?page=1` | `/api/users/1` |
| `**/api/users/**` | `/api/users/1`, `/api/users/1/orders` | `/api/users` |
| `**/api/users/*/orders` | `/api/users/1/orders` | `/api/users/1/2/orders` |
| `**/*.{png,jpg}` | `/logo.png`, `/deep/img.jpg` | `/file.svg` |
| `/\/api\/users\/\d+$/` (regex) | `/api/users/123` | `/api/users/abc` |

---

## Anti-Patterns

| Don't | Problem | Do Instead |
|---|---|---|
| Mock your own API | Testing a fiction. Frontend/backend may be incompatible. | Hit real API. Mock only third-party. |
| Mock everything for speed | Tests pass, app breaks. | Mock only external boundaries. |
| Never mock anything | Slow, flaky, fails when Stripe is down. | Mock third-party. CI != uptime monitor. |
| Use outdated mocks | Mock shape drifts from real API. | Contract validation tests. Re-record HAR monthly. |
| Stub fetch via `page.evaluate` | Fragile, breaks on navigation. | `page.route()` intercepts at network layer. |
| Copy-paste mock data everywhere | One API change = 40 file edits. | Centralize in fixtures or shared data. |
| Set up routes after `page.goto()` | Requests fire before route is registered. | `page.route()` before `page.goto()`. |
| Forget fulfill/continue/abort | Request hangs, test times out. | Every handler must call exactly one. |
| Use `page.on('request')` to mock | Read-only; cannot modify requests. | `page.route()` for interception. |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Route never fires | URL pattern mismatch | `page.on('request', r => console.log(r.url()))` to debug. Check glob vs query strings. |
| Test times out | Handler throws or never resolves | Wrap in try/catch. Ensure every path calls fulfill/continue/abort. |
| Real data despite mock | Service worker or different context | `context.route()` instead. `serviceWorkers: 'block'` in config. |
| `route.fetch()` infinite loop | Overlapping handlers re-trigger | One handler per URL pattern. `route.fetch()` skips its own handler. |
| HAR returns wrong responses | Dynamic body (timestamps, CSRF) | Re-record. Use `notFound: 'fallback'` for unmatched. |
| Works locally, fails in CI | Different base URL/port | Use `**/api/users` glob (host-agnostic). |
| Wrong response from correct route | Multiple routes match same URL | `page.unroute()` before re-registering. |
