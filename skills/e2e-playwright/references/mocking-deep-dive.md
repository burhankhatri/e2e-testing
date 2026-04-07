# Network Mocking Deep Dive

## Decision: Mock at the boundary, test your stack end-to-end

```
Is this YOUR service (your API, your backend)?
├── YES → Do NOT mock. Test the real integration.
│   ├── Slow? → Optimize the service, not the test.
│   └── Flaky? → Fix the service. Flaky infra is a bug.
└── NO → Third-party service.
    ├── Paid per call (Stripe, Twilio) → ALWAYS mock
    ├── Rate-limited (OAuth, social) → ALWAYS mock
    ├── Slow/unreliable → ALWAYS mock
    └── Free + fast + reliable → Consider real; mock if rate-limited
```

## Full Mock (route.fulfill)

```typescript
await page.route('**/api/create-payment-intent', route =>
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ clientSecret: 'pi_mock_123', amount: 9900 }),
  })
);

// Error scenario
await page.route('**/api/confirm-payment', route =>
  route.fulfill({
    status: 402,
    contentType: 'application/json',
    body: JSON.stringify({ error: { code: 'card_declined', message: 'Declined' } }),
  })
);
```

## Block (route.abort)

```typescript
// Kill analytics, tracking, ads
await page.route('**/analytics.example.com/**', route => route.abort());
await page.route('**/*.{png,jpg,gif}', route => route.abort()); // speed up if images irrelevant
```

## Modify (route.continue with overrides)

```typescript
// Add auth header to all API calls
await page.route('**/api/**', route =>
  route.continue({ headers: { ...route.request().headers(), 'X-Test': 'true' } })
);

// Slow down a response to test loading states
await page.route('**/api/dashboard', async route => {
  await new Promise(r => setTimeout(r, 3000));
  await route.continue();
});
```

## HAR Recording (capture and replay real API responses)

```bash
# Record
npx playwright test --update-har=tests/fixtures/api.har

# Or in code:
await page.routeFromHAR('tests/fixtures/api.har', { update: true });
```

```typescript
// Replay recorded responses
await page.routeFromHAR('tests/fixtures/api.har', {
  url: '**/api/**',
  update: false, // don't re-record
});
```

## Conditional Mocking (CI vs Local)

```typescript
test.beforeEach(async ({ page }) => {
  if (process.env.CI) {
    // Mock flaky external service in CI
    await page.route('**/external-api.com/**', route =>
      route.fulfill({ status: 200, body: JSON.stringify({ data: 'mocked' }) })
    );
  }
  // Locally: hit real service for full integration testing
});
```

## Waiting for Specific Responses

```typescript
// Wait for a specific API call to complete before asserting
const responsePromise = page.waitForResponse(
  resp => resp.url().includes('/api/users') && resp.status() === 200
);
await page.getByRole('button', { name: 'Load' }).click();
const response = await responsePromise;
const data = await response.json();
expect(data.users).toHaveLength(10);
```

## Request Interception (verify payloads)

```typescript
const requests: Request[] = [];
await page.route('**/api/track', route => {
  requests.push(route.request());
  route.fulfill({ status: 200 });
});

await page.getByRole('button', { name: 'Buy' }).click();

// Verify the tracking payload
expect(requests).toHaveLength(1);
const payload = requests[0].postDataJSON();
expect(payload.event).toBe('purchase');
expect(payload.amount).toBe(9900);
```
