# Debugging Deep Dive

## Systematic Debugging Workflow

Follow this order. Do not skip to step 5 -- most issues resolve by step 2.

```
1. Read the full error message
   - Expected vs actual value, locator used, call log, line number
   - The call log alone often shows what went wrong

2. Run with --ui to see what happened visually
   - Timeline shows every action, screenshot at failure point
   - npx playwright test tests/failing.spec.ts --ui

3. Enable tracing if not already on
   - use: { trace: 'on' } temporarily in config
   - Compare before/after DOM snapshots per action

4. Check the network tab in trace for API failures
   - Missing responses, 4xx/5xx, CORS errors, slow responses

5. Insert page.pause() at the failure point
   - Inspect live DOM, try selectors in console
   - Step through remaining actions manually

6. Check browser console for JavaScript errors
   - page.on('console') or console tab in trace
   - Hydration errors, unhandled promise rejections
```

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

## Failure-Type Decision Guide

| Failure Type | First Tool | Why |
|---|---|---|
| Element not found (selector wrong) | UI Mode (`--ui`) | See DOM at failure, try selectors with Pick Locator |
| Element not found (timing) | Trace Viewer -- Actions tab | Compare before/after screenshots to see if element appeared after timeout |
| Wrong text / value | Trace Viewer -- Actions tab | Inspect actual DOM content at each step |
| Test hangs / times out | `DEBUG=pw:api` | See which API call is stuck waiting |
| Network / API failure | Trace Viewer -- Network tab | See status codes, payloads, timing |
| Auth / session issues | `page.on('response')` | Check for 401/403, missing cookies/tokens |
| Visual rendering wrong | `--headed --slow-mo=500` | Watch the actual rendering |
| JavaScript error in app | `page.on('console')` | Catch uncaught exceptions and error logs |
| CI-only failure | Trace Viewer from CI artifact | Reproduce exact CI state without running locally |

## page.pause() -- Interactive Debugging

```typescript
test('debug this interaction', async ({ page }) => {
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Add to cart' }).click();

  await page.pause(); // Opens Inspector at this exact point
  // Try selectors in the Inspector console
  // Step through remaining actions manually

  await page.getByRole('button', { name: 'Checkout' }).click();
});
```

Remove `page.pause()` before committing -- it hangs forever in CI. Guard with:
```bash
grep -r "page.pause()" tests/ && echo "ERROR: Remove page.pause() before committing" && exit 1
```

## Console and Network Monitoring

```typescript
// Capture console errors -- reusable fixture
const test = base.extend<{ consoleErrors: string[] }>({
  consoleErrors: async ({ page }, use) => {
    const errors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    page.on('pageerror', (err) => errors.push(`[pageerror] ${err.message}`));
    await use(errors);
  },
});

test('no console errors during checkout', async ({ page, consoleErrors }) => {
  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Pay' }).click();
  await expect(page.getByText('Success')).toBeVisible();
  expect(consoleErrors).toHaveLength(0);
});
```

```typescript
// Capture failed network requests
test('no failed API calls', async ({ page }) => {
  const failedRequests: string[] = [];
  page.on('response', (response) => {
    if (response.status() >= 400 && response.url().includes('/api/')) {
      failedRequests.push(`${response.status()} ${response.url()}`);
    }
  });
  page.on('requestfailed', (request) => {
    failedRequests.push(`FAILED: ${request.url()} ${request.failure()?.errorText}`);
  });

  await page.goto('/dashboard');
  expect(failedRequests).toHaveLength(0);
});
```

```typescript
// Wait for specific API response and inspect it
test('inspect API response', async ({ page }) => {
  await page.goto('/products');
  const responsePromise = page.waitForResponse(
    (resp) => resp.url().includes('/api/products') && resp.status() === 200
  );
  await page.getByRole('button', { name: 'Load products' }).click();
  const response = await responsePromise;
  const body = await response.json();
  console.log('API response:', JSON.stringify(body, null, 2));
  await expect(page.getByRole('listitem')).toHaveCount(body.products.length);
});
```

## Trace Viewer -- CI Failure Analysis

```typescript
// playwright.config.ts -- trace configuration
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  use: {
    trace: 'on-first-retry',  // captures on first retry (recommended for CI)
    // trace: 'on',           // capture always (use temporarily for stubborn failures)
    // trace: 'retain-on-failure',  // captures every run, keeps only failures
  },
});
```

```bash
# View trace from CI artifact
npx playwright show-trace test-results/checkout-chromium/trace.zip

# Or use trace.playwright.dev -- drag and drop the zip file in the browser
```

Reading a trace -- check in order:
1. **Actions tab** -- every Playwright action with before/after screenshots
2. **Console tab** -- browser console output (errors, warnings)
3. **Network tab** -- HTTP requests with status, timing, payloads
4. **Source tab** -- test source highlighting the failing line
5. **Call tab** -- exact arguments and return values of each call

## VS Code Extension

Install **Playwright Test for VS Code** (`ms-playwright.playwright`).

Key capabilities:
- **Run/debug individual tests** -- green play button in gutter next to `test()`
- **Set breakpoints** -- click gutter to set breakpoints; tests pause automatically
- **Pick locator** -- hover elements to get the best selector
- **Show browser** -- check "Show Browser" in testing sidebar during execution
- **Watch mode** -- re-run tests on file save

```typescript
// Use test.only() to focus the debugger on one test
test.only('debug this specific test', async ({ page }) => {
  await page.goto('/products');

  // Set a VS Code breakpoint on this line, then inspect `page` in debug panel
  const productCard = page.getByRole('listitem').filter({ hasText: 'Widget' });
  await expect(productCard).toBeVisible();

  await productCard.getByRole('button', { name: 'Add to cart' }).click();
  await expect(page.getByTestId('cart-count')).toHaveText('1');
});
```

## Verbose API Logging

```bash
# See every Playwright API call with timestamps
DEBUG=pw:api npx playwright test tests/slow-test.spec.ts

# Output:
# pw:api navigating to "http://localhost:3000/checkout"  +15ms
# pw:api waiting for getByRole('button', { name: 'Pay' })  +234ms
# pw:api clicking getByRole('button', { name: 'Pay' })  +12ms

# Browser protocol messages (very verbose -- use sparingly)
DEBUG=pw:protocol npx playwright test tests/slow-test.spec.ts

# Combine channels
DEBUG=pw:api,pw:browser npx playwright test tests/slow-test.spec.ts
```

## Screenshot Comparison

```typescript
// playwright.config.ts -- automatic screenshots on failure
export default defineConfig({
  use: {
    screenshot: 'only-on-failure', // saved to test-results/<test-name>/
  },
});
```

```typescript
// Manual screenshot at a specific point for debugging
test('debug visual state', async ({ page }) => {
  await page.goto('/checkout');
  await page.getByLabel('Promo code').fill('SAVE20');
  await page.getByRole('button', { name: 'Apply' }).click();

  await page.screenshot({ path: 'test-results/before-discount.png', fullPage: true });

  await expect(page.getByTestId('discount-amount')).toHaveText('-$20.00');
});
```

## Common Debug Scenarios

### "Element not found"
1. Check count: `await page.getByRole('button', { name: 'Submit' }).count()`
2. Check visibility: add `page.pause()` before the failing line
3. Check page loaded: `console.log(page.url())`
4. Check iframe: `page.frameLocator('iframe').getByRole(...)`

### "Strict mode violation" (multiple matches)
1. Count: `.count()` to see how many
2. Add specificity: scope to parent, use `exact: true`, filter
3. Use `.nth(0)` or `.first()` as last resort

### "Test timeout"
1. Check missing `await` (most common cause)
2. Check if waiting for element that never appears (wrong selector)
3. Check if server is running: `console.log(page.url())`
4. Increase timeout for specific test: `test.setTimeout(60_000)`

### "Execution context was destroyed"
1. Page navigated during an assertion
2. Add `await page.waitForURL()` after navigation trigger
3. Or use `await expect(page).toHaveURL(/pattern/)` which auto-retries

## Anti-Patterns

### Adding `waitForTimeout` to fix timing issues

```typescript
// BAD -- arbitrary delays mask the real problem
await page.getByRole('button', { name: 'Submit' }).click();
await page.waitForTimeout(3000);
await expect(page.getByText('Success')).toBeVisible();

// GOOD -- wait for the actual condition
await page.getByRole('button', { name: 'Submit' }).click();
await expect(page.getByText('Success')).toBeVisible();
```

If the default 5s timeout is insufficient, investigate *why* it is slow, then:
- Fix the performance issue
- Increase specific assertion timeout: `{ timeout: 15_000 }`
- Wait for a prerequisite: `await page.waitForResponse('**/api/submit')`

### Using `console.log` instead of proper tools

```typescript
// BAD -- 20 console.log calls scattered through the test
await page.goto('/dashboard');
console.log('page loaded');
console.log('button found:', await el.isVisible());
console.log('button text:', await el.textContent());

// GOOD -- one page.pause() and inspect everything interactively
await page.goto('/dashboard');
await page.pause();
```

### Debugging in CI without traces

```typescript
// BAD
export default defineConfig({ use: { trace: 'off' } });

// GOOD
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  use: { trace: 'on-first-retry' },
});
```

### Leaving `page.pause()` or `test.only()` in committed code

```typescript
// BAD -- skips other tests and hangs in CI
test.only('focused test', async ({ page }) => {
  await page.pause(); // hangs forever in CI
});

// Guard during development if needed
if (!process.env.CI) {
  await page.pause();
}
```

## Troubleshooting Table

| Symptom | Likely Cause | Fix |
|---|---|---|
| Inspector does not open with `PWDEBUG=1` | Headless mode or workers > 1 | `--headed --workers=1` |
| Trace is empty or missing | `trace: 'off'` or test did not retry | `trace: 'on'` temporarily |
| UI Mode shows stale results | File watcher did not pick up changes | Stop, clear `test-results/`, restart |
| `page.pause()` does nothing | Not headed and PWDEBUG not set | `--headed` or `PWDEBUG=1` |
| Screenshots blank or wrong size | Viewport not set | Set `viewport` in config |
| Verbose logs overwhelming | Using `pw:protocol` | Use `DEBUG=pw:api` instead |
| Trace file too large | `trace: 'on'` for all tests | `trace: 'on-first-retry'` |
| VS Code does not detect tests | Wrong `testDir` or `testMatch` | Check config paths match |
| Network events not firing | Listener attached after `goto()` | Attach `page.on()` before navigation |
