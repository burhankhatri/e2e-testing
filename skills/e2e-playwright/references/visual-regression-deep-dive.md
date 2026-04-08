# Visual Regression Deep Dive

## When To Use

| Scenario | Visual regression? | Why |
|----------|-------------------|-----|
| Component library / design system | **Yes** | Catch unintended style side effects across components |
| Layout stability after refactor | **Yes** | Verify no CSS regressions |
| Redesign / rebrand | **Yes** | Baseline before + after, review all diffs |
| Landing pages with fixed content | **Yes** | Content is stable, screenshots are deterministic |
| Pages with live API data | **No** | Content changes every load — always flaky |
| Real-time dashboards | **No** | Dynamic charts, timestamps, counters |
| Heavy animation pages | **Carefully** | Must disable animations; even then, transitions cause diffs |

## `toHaveScreenshot()` — Core API

### Basic usage — full page:

```typescript
test('homepage layout', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('homepage.png');
});
```

First run: generates baseline in `tests/e2e/homepage.spec.ts-snapshots/homepage.png`.
Subsequent runs: compares current render against baseline.

### Element-level screenshot:

```typescript
test('button hover state', async ({ page }) => {
  await page.goto('/components');
  const button = page.getByRole('button', { name: 'Submit' });
  await button.hover();
  await expect(button).toHaveScreenshot('submit-button-hover.png');
});
```

Use element-level for component regression. Smaller images = faster comparison, fewer false positives.

### Full-page screenshot:

```typescript
test('full page layout', async ({ page }) => {
  await page.goto('/pricing');
  await expect(page).toHaveScreenshot('pricing-full.png', { fullPage: true });
});
```

`fullPage: true` scrolls and captures the entire page, not just the viewport.

### With threshold options:

```typescript
await expect(page).toHaveScreenshot('dashboard.png', {
  maxDiffPixelRatio: 0.01,     // Allow 1% pixel diff (anti-aliasing, sub-pixel)
  threshold: 0.2,              // Per-pixel color difference tolerance (0-1)
  animations: 'disabled',      // Freeze CSS animations and transitions
  fullPage: true,
});
```

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `maxDiffPixels` | number | — | Absolute max differing pixels |
| `maxDiffPixelRatio` | number | — | Max ratio of differing pixels (0-1) |
| `threshold` | number | 0.2 | Per-pixel color diff tolerance (0=exact, 1=any) |
| `animations` | `'disabled'` \| `'allow'` | `'disabled'` | Freeze CSS animations before capture |
| `fullPage` | boolean | false | Capture entire scrollable page |
| `mask` | Locator[] | — | Regions to mask (rendered as colored boxes) |
| `maskColor` | string | `'#FF00FF'` | Color of mask overlay |

## Masking Dynamic Content

Pages with dates, avatars, ads, or random content need masking to prevent false positives:

```typescript
test('profile page layout', async ({ page }) => {
  await page.goto('/profile');

  await expect(page).toHaveScreenshot('profile.png', {
    mask: [
      page.getByTestId('timestamp'),       // Dynamic date/time
      page.getByTestId('avatar'),           // Random/user-specific
      page.getByTestId('ad-slot'),          // Third-party ad content
      page.getByTestId('activity-feed'),    // Live-updating content
    ],
  });
});
```

Masks render as solid-color boxes in the screenshot. The masked region is excluded from comparison entirely.

**Alternative: freeze dynamic content with JavaScript**

When masking isn't sufficient (e.g., content affects layout), inject JS to freeze it:

```typescript
test('freeze clock before screenshot', async ({ page }) => {
  await page.goto('/dashboard');

  // Replace all dynamic timestamps with a fixed value
  await page.evaluate(() => {
    document.querySelectorAll('[data-testid="timestamp"]').forEach((el) => {
      el.textContent = 'Jan 1, 2025 12:00 PM';
    });
  });

  await expect(page).toHaveScreenshot('dashboard-frozen.png');
});
```

Use freezing over masking when dynamic content affects layout (e.g., long vs short timestamps shift adjacent elements).

**When to mask vs freeze vs skip:**
- Mask 1-3 small regions that don't affect layout — masking works fine
- Content affects layout (variable-length text, dynamic heights) — freeze via `page.evaluate()`
- More than half the page is dynamic — visual regression is the wrong tool, use functional assertions

## Baseline Management

### Generate baselines (first time or after intentional changes):

```bash
# Generate/update ALL baselines
npx playwright test --update-snapshots

# Update baselines for specific test file only
npx playwright test tests/e2e/homepage.spec.ts --update-snapshots
```

### Commit baselines to git:

```bash
# Baselines live alongside test files
git add tests/e2e/*.spec.ts-snapshots/
git commit -m "test: update visual regression baselines"
```

Baselines ARE the source of truth. They MUST be committed. If they're not in git, CI can't compare against them.

### Update workflow after intentional UI change:

```
1. Make the UI change
2. Run: npx playwright test (visual tests will FAIL — expected)
3. Review the diff images in test-results/:
   - *-expected.png (old baseline)
   - *-actual.png (current render)
   - *-diff.png (highlighted differences)
4. If diff is correct: npx playwright test --update-snapshots
5. Commit updated baselines with the UI change
```

### Diff images:

When a visual test fails, Playwright generates three files in `test-results/`:

| File | Content |
|------|---------|
| `*-expected.png` | The committed baseline |
| `*-actual.png` | What the browser rendered this run |
| `*-diff.png` | Red overlay highlighting every differing pixel |

These are the primary debugging artifacts. In CI, upload `test-results/` as an artifact to access them.

## CI Consistency

### The font rendering problem:

macOS, Linux, and Windows render fonts differently. A baseline generated on macOS will fail on Linux CI even with zero code changes.

**Solutions (pick one):**

**Option A: Platform-specific baselines (simplest)**

Playwright auto-appends platform to snapshot names. Baselines stored per-platform:

```
tests/e2e/homepage.spec.ts-snapshots/
  homepage-chromium-darwin.png   # macOS baseline
  homepage-chromium-linux.png    # Linux baseline
```

Generate Linux baselines in Docker:

```bash
docker run --rm -v $(pwd):/work -w /work mcr.microsoft.com/playwright:v1.50.0-noble \
  npx playwright test --update-snapshots
```

**Option B: Docker everywhere (most consistent)**

Run ALL visual regression tests in Docker, locally and in CI:

```bash
# Local
docker run --rm -v $(pwd):/work -w /work mcr.microsoft.com/playwright:v1.50.0-noble \
  npx playwright test tests/e2e/visual/

# CI — already Linux, just match the image version
```

One platform = one set of baselines = zero cross-platform diffs.

**Option C: Generous threshold (pragmatic)**

```typescript
// playwright.config.ts
expect: {
  toHaveScreenshot: {
    maxDiffPixelRatio: 0.02,  // 2% tolerance absorbs font rendering diffs
    animations: 'disabled',
  },
},
```

Works when you care about layout, not pixel-perfect rendering.

### Other CI considerations:

- **`animations: 'disabled'`** — always set this; animation frame timing varies by CI machine speed
- **Consistent viewport** — set in config, not browser default (which varies by OS)
- **No GPU acceleration** — CI typically runs headless without GPU; WebGL tests may differ

## Config Additions for Visual Regression

Add to `playwright.config.ts`:

```typescript
export default defineConfig({
  // ... existing config ...

  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,
      animations: 'disabled',
    },
  },

  // Organize visual tests in their own directory (optional)
  projects: [
    {
      name: 'visual',
      testMatch: /.*\.visual\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        screenshot: 'on',
      },
    },
    // ... other projects ...
  ],
});
```

## Tagging for Selective Updates

Tag visual tests with `@visual` so you can update baselines selectively:

```typescript
test('homepage layout @visual', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('homepage.png', {
    animations: 'disabled',
  });
});

test('pricing layout @visual', async ({ page }) => {
  await page.goto('/pricing');
  await expect(page).toHaveScreenshot('pricing.png', {
    animations: 'disabled',
  });
});
```

```bash
# Update only visual test baselines
npx playwright test --grep @visual --update-snapshots

# Run only visual tests
npx playwright test --grep @visual
```

## Platform-Agnostic Snapshots with `snapshotPathTemplate`

Strip the platform suffix so baselines work cross-platform (requires Docker for generation):

```typescript
// playwright.config.ts
export default defineConfig({
  snapshotPathTemplate: '{testDir}/{testFileDir}/{testFileName}-snapshots/{arg}{-projectName}{ext}',
  // Omits {-snapshotSuffix} which includes the platform name (linux, darwin, win32).
  // This means snapshots are platform-agnostic — you MUST generate them in Docker.
});
```

This is cleaner than maintaining per-platform baselines, but requires that ALL baseline generation happens in Docker.

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| `maxDiffPixelRatio: 0` | Fails on sub-pixel rendering differences | Use `0.01` minimum |
| Screenshot of full page with live API data | Content changes every load | Mock the API or mask dynamic regions |
| Not committing baselines | CI has nothing to compare against | `git add` the snapshots directory |
| Updating baselines without reviewing diff | Hides real regressions | Always review `*-diff.png` before `--update-snapshots` |
| One giant full-page screenshot per page | Hard to diagnose which component changed | Element-level screenshots for components, full-page for layout |
| Visual tests in same file as functional tests | Different failure modes, different retry needs | Separate `*.visual.spec.ts` files |
