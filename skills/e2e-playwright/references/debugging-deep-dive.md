# Debugging Deep Dive

## Tool Selection

| Tool | Command | Best For |
|---|---|---|
| UI Mode | `npx playwright test --ui` | Interactive exploration, visual timeline |
| Inspector | `PWDEBUG=1 npx playwright test` | Step-through, selector playground |
| Trace Viewer | `npx playwright show-trace trace.zip` | Post-mortem CI failures |
| Headed | `npx playwright test --headed` | Watching browser live |
| Slow motion | `--headed --slow-mo=500` | Following fast interactions |
| `page.pause()` | Insert in test code | Pause at exact point |
| Verbose logs | `DEBUG=pw:api npx playwright test` | Every API call with timing |
| VS Code | Playwright Test extension | Breakpoints, pick locator |

## page.pause() — Interactive Debugging

```typescript
test('debug this interaction', async ({ page }) => {
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Add to cart' }).click();

  await page.pause();  // Opens Inspector at this exact point
  // Try selectors in the Inspector console
  // Step through remaining actions manually

  await page.getByRole('button', { name: 'Checkout' }).click();
});
```

## Console and Network Monitoring

```typescript
// Capture console errors
test('no console errors during checkout', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text());
  });

  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Pay' }).click();
  await expect(page.getByText('Success')).toBeVisible();

  expect(errors).toHaveLength(0);
});

// Capture failed network requests
test('no failed API calls', async ({ page }) => {
  const failedRequests: string[] = [];
  page.on('response', response => {
    if (response.status() >= 400 && response.url().includes('/api/')) {
      failedRequests.push(`${response.status()} ${response.url()}`);
    }
  });

  await page.goto('/dashboard');
  expect(failedRequests).toHaveLength(0);
});
```

## Trace Viewer — CI Failure Analysis

```typescript
// Enable rich traces in config
export default defineConfig({
  use: {
    trace: 'on-first-retry',  // default — captures on retry
    // trace: 'on',           // capture always (more data, slower)
    // trace: 'retain-on-failure',  // keep only from failed tests
  },
});
```

```bash
# View trace from CI artifact
npx playwright show-trace test-results/checkout-chromium/trace.zip

# Trace shows:
# - Timeline of every action
# - DOM snapshot at each step
# - Network waterfall
# - Console messages
# - Before/after screenshots
```

## Screenshot Comparison

```bash
# Take screenshot at failure point
npx playwright test --screenshot=only-on-failure

# Screenshots saved to test-results/<test-name>/
# Compare CI screenshot with local to spot environment differences
```

## Verbose API Logging

```bash
# See every Playwright API call with timestamps
DEBUG=pw:api npx playwright test tests/checkout.spec.ts

# Output shows:
# pw:api navigating to "http://localhost:3000/checkout"  +15ms
# pw:api waiting for getByRole('button', { name: 'Pay' })  +234ms
# pw:api clicking getByRole('button', { name: 'Pay' })  +12ms
```

## Common Debug Scenarios

### "Element not found"
1. Check if element exists: `await page.getByRole('button', { name: 'Submit' }).count()`
2. Check if visible: add `page.pause()` before the failing line
3. Check if page loaded: verify URL with `console.log(page.url())`
4. Check if in iframe: use `page.frameLocator('iframe').getByRole(...)`

### "Strict mode violation" (multiple matches)
1. Count matches: `.count()` to see how many
2. Add specificity: scope to parent, use `exact: true`, filter
3. Use `nth(0)` as last resort

### "Test timeout"
1. Increase timeout for specific test: `test.setTimeout(60000)`
2. Check for missing `await`
3. Check if waiting for element that never appears (wrong selector)
4. Check if server is actually running
