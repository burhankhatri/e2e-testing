# Screenshots & Media Deep Dive

## Capture Modes

### Config-level settings:

```typescript
// playwright.config.ts
export default defineConfig({
  use: {
    screenshot: 'on',               // Every test — best for loop debugging
    // screenshot: 'only-on-failure', // Conservative — less artifact noise
    // screenshot: 'off',            // No screenshots

    video: 'retain-on-failure',     // Record all, keep only failures
    // video: 'on',                  // Keep all recordings (large files)
    // video: 'on-first-retry',     // Only on retry
    // video: 'off',                // No video

    trace: 'on-first-retry',       // Capture trace on retry (recommended default)
    // trace: 'on',                 // Every test (most data, slowest)
    // trace: 'retain-on-failure',  // Record all, keep only failures
    // trace: 'off',                // No traces
  },
});
```

### Recommended profiles:

| Profile | `screenshot` | `video` | `trace` | When |
|---------|-------------|---------|---------|------|
| **Loop debugging** | `'on'` | `'retain-on-failure'` | `'on-first-retry'` | Agent iterating autonomously |
| **CI default** | `'on'` | `'retain-on-failure'` | `'on-first-retry'` | Standard CI runs |
| **Local dev** | `'off'` | `'off'` | `'off'` | Fast feedback, no artifact noise |
| **Full audit** | `'on'` | `'on'` | `'on'` | Investigating stubborn flaky test |
| **Visual regression** | `'on'` | `'off'` | `'on-first-retry'` | Screenshot comparison focus |

## Manual Screenshots at Workflow Steps

Config-level screenshots capture at test boundaries. For debugging specific steps within a test, capture manually:

```typescript
test('checkout flow', async ({ page }) => {
  await page.goto('/products');
  await page.screenshot({ path: 'screenshots/step-1-products.png' });

  await page.getByRole('button', { name: 'Add to cart' }).click();
  await page.screenshot({ path: 'screenshots/step-2-added-to-cart.png' });

  await page.getByRole('link', { name: 'Cart' }).click();
  await page.screenshot({ path: 'screenshots/step-3-cart.png' });

  await page.getByRole('button', { name: 'Checkout' }).click();
  await page.waitForURL('/checkout');
  await page.screenshot({ path: 'screenshots/step-4-checkout.png' });
});
```

### Screenshot options:

```typescript
await page.screenshot({
  path: 'screenshots/full-page.png',
  fullPage: true,                    // Capture entire scrollable page
});

await page.screenshot({
  path: 'screenshots/viewport-only.png',
  // fullPage defaults to false — captures visible viewport only
});

// Element-level screenshot
const card = page.getByTestId('product-card').first();
await card.screenshot({ path: 'screenshots/product-card.png' });

// With clipping (specific region)
await page.screenshot({
  path: 'screenshots/header.png',
  clip: { x: 0, y: 0, width: 1280, height: 80 },
});
```

## Per-Iteration Screenshots for Loop Debugging

When the agent is iterating through test-fix cycles (via `/test-automation-loop`), screenshots provide visual context that test output alone cannot:

### Naming convention:

```typescript
// Structured naming for loop iterations
const iterationDir = `test-results/loop-iteration-${iterationNumber}`;
await page.screenshot({
  path: `${iterationDir}/step-${stepNumber}-${description}.png`,
  fullPage: true,
});

// Examples:
// test-results/loop-iteration-1/step-1-page-load.png
// test-results/loop-iteration-1/step-2-after-click.png
// test-results/loop-iteration-2/step-1-page-load.png  (after fix attempt)
```

### Fixture for automatic per-step capture:

```typescript
import { test as base } from '@playwright/test';

type DebugCapture = {
  snap(description: string): Promise<void>;
};

export const test = base.extend<{ debugCapture: DebugCapture }>({
  debugCapture: async ({ page }, use, testInfo) => {
    let stepCount = 0;
    const capture: DebugCapture = {
      async snap(description: string) {
        stepCount++;
        const dir = testInfo.outputDir;
        await page.screenshot({
          path: `${dir}/step-${String(stepCount).padStart(2, '0')}-${description}.png`,
          fullPage: true,
        });
      },
    };
    await use(capture);
  },
});

// Usage in tests:
test('checkout flow', async ({ page, debugCapture }) => {
  await page.goto('/products');
  await debugCapture.snap('products-loaded');

  await page.getByRole('button', { name: 'Add to cart' }).click();
  await debugCapture.snap('item-added');
  // ...
});
```

## Video Recording

### When video beats screenshots:

| Scenario | Screenshot | Video |
|----------|-----------|-------|
| Static layout check | Best | Overkill |
| Animation or transition bug | Misses the issue | **Captures the motion** |
| Multi-step flow with timing | Multiple screenshots needed | **Single file, full context** |
| Diagnosing race condition | Snapshot at wrong moment | **Shows exact sequence** |
| Artifact size concern | Small (KB) | Large (MB) |

### Video output:

```
test-results/
  checkout-chromium/
    video.webm          # Full test recording
```

Videos are saved per-test. With `'retain-on-failure'`, passing test videos are auto-deleted.

### Embedding video path in test info:

```typescript
test('long workflow', async ({ page }, testInfo) => {
  // After test, video path is available:
  const videoPath = await page.video()?.path();
  if (videoPath) {
    testInfo.attachments.push({
      name: 'video',
      path: videoPath,
      contentType: 'video/webm',
    });
  }
});
```

## Trace Files

Traces are the richest debugging artifact. A single `.zip` file contains:

- DOM snapshot at every action
- Network waterfall (requests + responses)
- Console messages
- Screenshots at each step (automatically)
- Action log with timing

### Viewing traces:

```bash
# From CI artifact or local test-results
npx playwright show-trace test-results/checkout-chromium/trace.zip

# Opens interactive viewer with:
# - Timeline of actions
# - DOM inspector at each point
# - Network panel
# - Console panel
# - Before/after screenshots per action
```

### When to use traces vs screenshots vs video:

| Need | Best artifact |
|------|--------------|
| "What did the page look like?" | Screenshot |
| "What happened step by step?" | Trace |
| "What did the animation look like?" | Video |
| "What API calls were made?" | Trace |
| "What console errors occurred?" | Trace |
| "Quick visual sanity check" | Screenshot |
| "Full post-mortem of CI failure" | Trace |

## Artifact Organization

### Default directory structure:

```
test-results/                         # Auto-generated by Playwright
  checkout-chromium/
    test-finished-1.png              # Auto-screenshot (if screenshot: 'on')
    trace.zip                        # Trace file (if trace enabled + retry)
    video.webm                       # Video (if video enabled + failure)
  login-chromium/
    test-finished-1.png
playwright-report/                    # HTML report
  index.html
  data/
blob-report/                          # Sharded report fragments (CI only)
```

### Gitignore — always add:

```
test-results/
playwright-report/
blob-report/
playwright/.auth/
screenshots/          # Manual capture directory
```

### Cleanup:

Playwright auto-cleans `test-results/` on each run. Manual `screenshots/` directories are NOT auto-cleaned — add cleanup to your test setup or CI pipeline:

```bash
# Clean before run
rm -rf test-results/ screenshots/
npx playwright test
```

## Agent Debugging Pattern

When the autonomous loop agent can't diagnose a failure from test output alone:

```
1. Enable full capture temporarily:
   - Set screenshot: 'on', video: 'on', trace: 'on' in config
2. Re-run the failing test:
   npx playwright test tests/e2e/failing.spec.ts --headed
3. Inspect artifacts in test-results/:
   - Screenshots: what does the page look like at each step?
   - Trace: what network requests fired? Any console errors?
   - Video: does the interaction happen in the right order?
4. Correlate visual state with the assertion failure
5. Fix the issue
6. Restore original capture mode (screenshot: 'on', video: 'retain-on-failure')
7. Re-run to confirm fix
```

This pattern is integrated into the `/test-automation-loop` skill's failure diagnosis step.
