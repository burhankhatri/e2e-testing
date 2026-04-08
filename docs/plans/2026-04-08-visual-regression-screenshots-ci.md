# Visual Regression, Screenshots & CI Pipeline — Implementation Plan

**Goal:** Add 4 new reference deep-dives and update 3 existing skill files to incorporate visual regression testing, screenshot/media capture for loop debugging, CI pipeline guidance, and POM patterns.

**Architecture:** All changes are markdown skill files. No code dependencies. New files go in `skills/e2e-playwright/references/`. Updates touch `SKILL.md`, `test-automation-loop/SKILL.md`, and `start/SKILL.md`.

**Tech Stack:** Playwright `toHaveScreenshot()`, `page.screenshot()`, trace/video config, GitHub Actions YAML, GitLab CI YAML.

---

### Task 1: Create `references/visual-regression-deep-dive.md`

**Files:**
- Create: `skills/e2e-playwright/references/visual-regression-deep-dive.md`

- [ ] **Step 1: Create the visual regression deep dive**

```markdown
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

**When to mask vs when NOT to screenshot:**
- Mask 1-3 small regions → masking works fine
- More than half the page is dynamic → visual regression is wrong tool, use functional assertions

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
├── homepage-chromium-darwin.png   # macOS baseline
├── homepage-chromium-linux.png    # Linux baseline
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
- **No GPU acceleration** — CI typically runs headless without GPU; Playwright handles this, but WebGL tests may differ

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

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| `maxDiffPixelRatio: 0` | Fails on sub-pixel rendering differences | Use `0.01` minimum |
| Screenshot of full page with live API data | Content changes every load | Mock the API or mask dynamic regions |
| Not committing baselines | CI has nothing to compare against | `git add` the snapshots directory |
| Updating baselines without reviewing diff | Hides real regressions | Always review `*-diff.png` before `--update-snapshots` |
| One giant full-page screenshot per page | Hard to diagnose which component changed | Element-level screenshots for components, full-page for layout |
| Visual tests in the same file as functional tests | Different failure modes, different retry needs | Separate `*.visual.spec.ts` files |
```

- [ ] **Step 2: Verify file is well-formed**
  Run: `wc -l skills/e2e-playwright/references/visual-regression-deep-dive.md`
  Expected: file exists with ~200 lines

- [ ] **Step 3: Commit**
  `git add skills/e2e-playwright/references/visual-regression-deep-dive.md && git commit -m "docs: add visual regression deep dive reference"`

---

### Task 2: Create `references/screenshots-and-media-deep-dive.md`

**Files:**
- Create: `skills/e2e-playwright/references/screenshots-and-media-deep-dive.md`

- [ ] **Step 1: Create the screenshots and media deep dive**

```markdown
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

export const test = base.extend<{ debugCapture: DebugCapture }>({
  debugCapture: async ({ page }, use, testInfo) => {
    let stepCount = 0;
    const capture = {
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
├── checkout-chromium/
│   ├── test-finished-1.png          # Auto-screenshot (if screenshot: 'on')
│   ├── trace.zip                    # Trace file (if trace: 'on-first-retry' + retry)
│   └── video.webm                   # Video (if video: 'retain-on-failure' + failure)
├── login-chromium/
│   └── test-finished-1.png
playwright-report/                    # HTML report
├── index.html
├── data/
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
```

- [ ] **Step 2: Verify file is well-formed**
  Run: `wc -l skills/e2e-playwright/references/screenshots-and-media-deep-dive.md`
  Expected: file exists with ~200 lines

- [ ] **Step 3: Commit**
  `git add skills/e2e-playwright/references/screenshots-and-media-deep-dive.md && git commit -m "docs: add screenshots and media deep dive reference"`

---

### Task 3: Create `references/ci-pipeline-deep-dive.md`

**Files:**
- Create: `skills/e2e-playwright/references/ci-pipeline-deep-dive.md`

- [ ] **Step 1: Create the CI pipeline deep dive**

```markdown
# CI Pipeline Deep Dive

## GitHub Actions — Complete Workflow

### Basic workflow with artifact upload:

```yaml
# .github/workflows/playwright.yml
name: Playwright Tests
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Cache Playwright browsers
        id: playwright-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: playwright-${{ runner.os }}-${{ hashFiles('package-lock.json') }}

      - name: Install Playwright browsers
        if: steps.playwright-cache.outputs.cache-hit != 'true'
        run: npx playwright install --with-deps chromium

      - name: Install Playwright system deps
        if: steps.playwright-cache.outputs.cache-hit == 'true'
        run: npx playwright install-deps chromium

      - name: Run Playwright tests
        run: npx playwright test

      - name: Upload test results
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30

      - name: Upload test artifacts
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
          retention-days: 7
```

**Key details:**
- `if: ${{ !cancelled() }}` — uploads artifacts even on failure (critical for debugging)
- Separate retention: reports (30 days) vs raw artifacts (7 days)
- Browser cache saves ~1 minute per run
- `--with-deps` installs system libraries on first run; `install-deps` on cache hit

### Sharded workflow (parallel execution):

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        shard: [1/4, 2/4, 3/4, 4/4]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - name: Cache Playwright browsers
        id: playwright-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: playwright-${{ runner.os }}-${{ hashFiles('package-lock.json') }}
      - name: Install Playwright browsers
        if: steps.playwright-cache.outputs.cache-hit != 'true'
        run: npx playwright install --with-deps chromium
      - name: Install Playwright system deps
        if: steps.playwright-cache.outputs.cache-hit == 'true'
        run: npx playwright install-deps chromium

      - name: Run Playwright tests
        run: npx playwright test --shard=${{ matrix.shard }}

      - name: Upload blob report
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: blob-report-${{ strategy.job-index }}
          path: blob-report/
          retention-days: 1

  merge-reports:
    if: ${{ !cancelled() }}
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci

      - name: Download blob reports
        uses: actions/download-artifact@v4
        with:
          path: all-blob-reports
          pattern: blob-report-*
          merge-multiple: true

      - name: Merge reports
        run: npx playwright merge-reports --reporter html ./all-blob-reports

      - name: Upload merged report
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

**Sharding notes:**
- `fail-fast: false` — let all shards finish even if one fails
- Each shard uploads `blob-report/` (lightweight serialized results)
- Merge job combines all fragments into one HTML report
- Visual regression baselines work normally — each shard reads the same committed snapshots

### Config for CI:

```typescript
// playwright.config.ts — CI-aware settings
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? '50%' : undefined,
  reporter: process.env.CI
    ? [['blob'], ['html', { open: 'never' }]]
    : 'list',
  use: {
    trace: 'on-first-retry',
    screenshot: 'on',
    video: 'retain-on-failure',
  },
});
```

`reporter: [['blob'], ['html']]` — blob for sharded merge, HTML for browsing. Both in CI.

## GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - test

playwright:
  stage: test
  image: mcr.microsoft.com/playwright:v1.50.0-noble
  script:
    - npm ci
    - npx playwright test
  artifacts:
    when: always
    paths:
      - playwright-report/
      - test-results/
    expire_in: 7 days
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
```

**Docker image advantage:** `mcr.microsoft.com/playwright` includes browsers + system deps. No separate install step. Consistent font rendering across all runs.

## Artifact Management

### What to upload:

| Artifact | Contents | Retention | Size |
|----------|----------|-----------|------|
| `playwright-report/` | HTML report with embedded screenshots | 30 days | 1-10 MB |
| `test-results/` | Screenshots, videos, traces, diff images | 7 days | 10-500 MB |
| `blob-report/` | Sharded report fragments | 1 day (merge, then discard) | 1-5 MB |

### Downloading and viewing artifacts:

```bash
# Download from GitHub Actions UI or CLI:
gh run download <run-id> -n playwright-report

# View HTML report:
npx playwright show-report playwright-report/

# View trace from artifact:
npx playwright show-trace test-results/checkout-chromium/trace.zip
```

### Artifact size control:

```typescript
// Limit video size — shorter timeout, smaller files
export default defineConfig({
  timeout: 30_000,       // 30s max per test
  use: {
    video: {
      mode: 'retain-on-failure',
      size: { width: 1280, height: 720 },  // Smaller than default
    },
  },
});
```

## Visual Regression in CI

### Baseline management across branches:

```
main branch:
  └── tests/e2e/*.spec.ts-snapshots/   # Committed baselines (source of truth)

feature branch:
  └── UI change → visual test fails → expected
  └── Developer reviews diff images in CI artifact
  └── npx playwright test --update-snapshots (locally or in CI)
  └── Commits updated baselines with the PR
```

### PR workflow for visual changes:

```
1. Developer changes CSS/layout
2. CI runs → visual test fails
3. CI uploads test-results/ as artifact
4. Developer downloads, reviews:
   - *-expected.png (old baseline)
   - *-actual.png (new render)
   - *-diff.png (differences highlighted)
5. If intentional: update baselines locally, push
6. If unintentional: fix the CSS, push
7. CI re-runs → visual test passes
```

### Updating baselines in CI (automated):

```yaml
# Optional: auto-update baselines on a labeled PR
- name: Update baselines
  if: contains(github.event.pull_request.labels.*.name, 'update-baselines')
  run: |
    npx playwright test --update-snapshots
    git add tests/e2e/*.spec.ts-snapshots/
    git commit -m "test: update visual regression baselines" || true
    git push
```

Use with caution — only for trusted contributors. Always review the diff in the PR.

## Docker for Consistent Rendering

### When to use Docker:

| Scenario | Docker? | Why |
|----------|---------|-----|
| Visual regression in CI | **Yes** | Consistent font rendering across runs |
| Functional tests in CI | Optional | GitHub Actions ubuntu-latest works fine |
| Local development | **No** | Slower startup, harder to debug |
| Flaky visual tests across platforms | **Yes** | Eliminates platform differences |

### Run locally in Docker:

```bash
# Run tests in Docker (same environment as CI)
docker run --rm \
  -v $(pwd):/work \
  -w /work \
  mcr.microsoft.com/playwright:v1.50.0-noble \
  npx playwright test

# Generate baselines in Docker (for CI consistency)
docker run --rm \
  -v $(pwd):/work \
  -w /work \
  mcr.microsoft.com/playwright:v1.50.0-noble \
  npx playwright test --update-snapshots
```

## Reporter Configuration

### CI reporters:

```typescript
// playwright.config.ts
reporter: process.env.CI
  ? [
      ['blob'],                              // For sharded merge
      ['html', { open: 'never' }],           // Browsable report
      ['junit', { outputFile: 'results.xml' }], // For CI test summary
    ]
  : [
      ['list'],                              // Console output locally
    ],
```

### JUnit for CI test summaries:

Many CI systems (GitHub Actions, GitLab, Jenkins) parse JUnit XML to show test results inline:

```yaml
# GitHub Actions — publish test summary
- name: Publish test results
  uses: dorny/test-reporter@v1
  if: ${{ !cancelled() }}
  with:
    name: Playwright Tests
    path: results.xml
    reporter: java-junit
```
```

- [ ] **Step 2: Verify file is well-formed**
  Run: `wc -l skills/e2e-playwright/references/ci-pipeline-deep-dive.md`
  Expected: file exists with ~250 lines

- [ ] **Step 3: Commit**
  `git add skills/e2e-playwright/references/ci-pipeline-deep-dive.md && git commit -m "docs: add CI pipeline deep dive reference"`

---

### Task 4: Create `references/page-object-model-deep-dive.md`

**Files:**
- Create: `skills/e2e-playwright/references/page-object-model-deep-dive.md`

- [ ] **Step 1: Create the POM deep dive**

```markdown
# Page Object Model Deep Dive

## Decision Guide: POM vs Fixtures vs Helpers

| Question | POM | Fixture | Helper |
|----------|-----|---------|--------|
| Reused across 3+ test files? | **Yes** | Maybe | No |
| Has 5+ interactions on one page? | **Yes** | No | No |
| Needs setup/teardown? | No (use fixture to instantiate) | **Yes** | No |
| One-off utility? | No | No | **Yes** |
| Expensive resource (DB, auth)? | No | **Yes** (worker-scoped) | No |

### Rules of thumb:

- **1 test file uses it** → inline code or helper function
- **2-3 test files use it** → fixture
- **4+ test files use it + complex page** → POM class + fixture to instantiate it
- **Needs cleanup** → always a fixture (POM alone has no cleanup mechanism)

## Basic POM Pattern

```typescript
// pages/LoginPage.ts
import { type Page, type Locator } from '@playwright/test';

export class LoginPage {
  private readonly emailInput: Locator;
  private readonly passwordInput: Locator;
  private readonly submitButton: Locator;
  private readonly errorMessage: Locator;

  constructor(private page: Page) {
    this.emailInput = page.getByLabel('Email');
    this.passwordInput = page.getByLabel('Password');
    this.submitButton = page.getByRole('button', { name: 'Sign in' });
    this.errorMessage = page.getByRole('alert');
  }

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }

  // Expose locators for assertions in tests — don't assert inside POM
  get error() { return this.errorMessage; }
  get heading() { return this.page.getByRole('heading', { name: 'Sign in' }); }
}
```

### What belongs in a POM method:
- Navigation (`goto()`)
- Actions (`login()`, `addToCart()`, `search()`)
- Locator getters (`get error()`, `get heading()`)

### What does NOT belong:
- Assertions (`expect(...)` — these go in tests)
- Test data (hardcoded users, products)
- State management (tracking login status)

## POM with Playwright Fixtures

Wire POM classes into `test.extend()` so tests receive page objects as parameters:

```typescript
// fixtures.ts
import { test as base, expect } from '@playwright/test';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';

type Pages = {
  loginPage: LoginPage;
  dashboardPage: DashboardPage;
};

export const test = base.extend<Pages>({
  loginPage: async ({ page }, use) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await use(loginPage);
  },
  dashboardPage: async ({ page }, use) => {
    const dashboardPage = new DashboardPage(page);
    await use(dashboardPage);
  },
});

export { expect };
```

```typescript
// tests/e2e/login.spec.ts
import { test, expect } from '../fixtures';

test('successful login redirects to dashboard', async ({ loginPage, dashboardPage }) => {
  await loginPage.login('user@example.com', 'password');
  await expect(dashboardPage.heading).toBeVisible();
});

test('invalid credentials show error', async ({ loginPage }) => {
  await loginPage.login('user@example.com', 'wrong-password');
  await expect(loginPage.error).toHaveText('Invalid credentials');
});
```

**Benefits:** Tests are clean. POM instantiation and navigation happen in the fixture. Cleanup is guaranteed by `use()`.

## Composing Page Objects

Shared UI components (header, sidebar, footer) should be separate classes composed into page objects:

```typescript
// components/HeaderComponent.ts
export class HeaderComponent {
  constructor(private page: Page) {}

  get searchInput() { return this.page.getByRole('searchbox'); }
  get userMenu() { return this.page.getByRole('button', { name: /profile|avatar/i }); }
  get notifications() { return this.page.getByRole('button', { name: 'Notifications' }); }

  async search(query: string) {
    await this.searchInput.fill(query);
    await this.searchInput.press('Enter');
  }

  async openUserMenu() {
    await this.userMenu.click();
  }
}

// pages/DashboardPage.ts
import { HeaderComponent } from '../components/HeaderComponent';

export class DashboardPage {
  readonly header: HeaderComponent;

  constructor(private page: Page) {
    this.header = new HeaderComponent(page);
  }

  async goto() {
    await this.page.goto('/dashboard');
  }

  get statsCards() { return this.page.getByTestId('stat-card'); }
  get welcomeHeading() { return this.page.getByRole('heading', { level: 1 }); }
}

// Usage in test:
test('search from dashboard', async ({ dashboardPage }) => {
  await dashboardPage.goto();
  await dashboardPage.header.search('revenue');
  await expect(dashboardPage.page).toHaveURL(/search/);
});
```

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| Asserting inside POM methods | Hides what the test is verifying; can't reuse method for different assertion needs | Expose locators, assert in test |
| Deep inheritance (`AdminPage extends UserPage extends BasePage`) | Fragile, hard to understand, changes ripple | Use composition: `this.header = new Header(page)` |
| POM for a page tested in one file | Unnecessary indirection, harder to read | Keep the locators inline in the test file |
| Storing mutable state in POM | Breaks test isolation if POM is shared | POM should be stateless — derive state from the page |
| God page object (200+ lines) | Hard to maintain, too many responsibilities | Split into component objects, compose them |
| Putting test data in POM (`defaultUser = 'admin'`) | Couples POM to specific test scenarios | Pass data as method parameters |
```

- [ ] **Step 2: Verify file is well-formed**
  Run: `wc -l skills/e2e-playwright/references/page-object-model-deep-dive.md`
  Expected: file exists with ~140 lines

- [ ] **Step 3: Commit**
  `git add skills/e2e-playwright/references/page-object-model-deep-dive.md && git commit -m "docs: add page object model deep dive reference"`

---

### Task 5: Update `SKILL.md` — add Visual Regression section + config + reference table

**Files:**
- Modify: `skills/e2e-playwright/SKILL.md`

- [ ] **Step 1: Add Visual Regression section after the Assertions section (after line 231)**

Insert this new section between Assertions and Authentication:

```markdown

---

## Visual Regression

### When to use:

| Scenario | Visual regression? |
|----------|-------------------|
| Component library / design system | **Yes** — catch unintended style side effects |
| Layout after CSS refactor | **Yes** — verify no regressions |
| Pages with live API data | **No** — content changes break screenshots |
| Real-time dashboards | **No** — dynamic content always diffs |

### Quick reference:

```typescript
// Full page baseline
await expect(page).toHaveScreenshot('homepage.png');

// Element-level (smaller, more stable)
await expect(page.getByTestId('nav')).toHaveScreenshot('nav.png');

// Full scrollable page
await expect(page).toHaveScreenshot('pricing.png', { fullPage: true });

// With masking for dynamic content
await expect(page).toHaveScreenshot('profile.png', {
  mask: [page.getByTestId('timestamp'), page.getByTestId('avatar')],
});
```

### Baseline workflow:

```bash
# Generate baselines (first run or after intentional UI change)
npx playwright test --update-snapshots

# Commit baselines — they are the source of truth
git add tests/e2e/*.spec.ts-snapshots/
```

**For thresholds, CI consistency, masking strategies, and anti-patterns, read `references/visual-regression-deep-dive.md`**
```

- [ ] **Step 2: Update the config template (replace the existing `use:` block around line 102)**

Replace the config's `use` block and add `expect` block:

```typescript
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'on',
    video: 'retain-on-failure',
  },

  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,
      animations: 'disabled',
    },
  },
```

- [ ] **Step 3: Update the gitignore section (after the existing gitignore block around line 133)**

Add `screenshots/` to the gitignore list:

```
.env*.local
playwright-report/
playwright/.auth/
test-results/
blob-report/
screenshots/
```

- [ ] **Step 4: Update the Reference Files table at the bottom (replace existing table around line 543)**

Replace with:

```markdown
| File | When to read |
|---|---|
| `locators-deep-dive.md` | Chaining, filtering, nth, scoping within components |
| `authentication-deep-dive.md` | Multi-role, API login, NextAuth, token refresh |
| `fixtures-deep-dive.md` | Worker-scoped, auto fixtures, composing, parameterized |
| `mocking-deep-dive.md` | HAR recording, conditional mocking, request modification |
| `common-pitfalls.md` | All 20 pitfalls with full code examples |
| `nextjs-deep-dive.md` | Middleware, ISR, route handlers, parallel routes |
| `flaky-tests-deep-dive.md` | Isolation strategies, test ordering, CI diagnosis |
| `debugging-deep-dive.md` | Trace viewer, inspector, verbose logging, VS Code |
| `visual-regression-deep-dive.md` | `toHaveScreenshot()`, baselines, thresholds, masking, CI font rendering |
| `screenshots-and-media-deep-dive.md` | Proactive capture, video, traces, per-iteration loop debugging |
| `ci-pipeline-deep-dive.md` | GitHub Actions, GitLab CI, artifacts, sharding, visual regression in CI |
| `page-object-model-deep-dive.md` | POM vs fixtures vs helpers, composition, anti-patterns |
```

- [ ] **Step 5: Commit**
  `git add skills/e2e-playwright/SKILL.md && git commit -m "feat: add visual regression section, update config and references in SKILL.md"`

---

### Task 6: Update `test-automation-loop/SKILL.md` — screenshot-aware loop

**Files:**
- Modify: `skills/test-automation-loop/SKILL.md`

- [ ] **Step 1: Update the Autonomous Loop section (replace existing loop around line 53)**

Replace the loop with the enhanced version:

```
1. Read testing.md
2. Set up the test environment (DB, env vars, services)
3. Ensure screenshot capture is enabled:
   - Verify playwright.config.ts has screenshot: 'on'
   - Verify video: 'retain-on-failure' is set
   - Verify trace: 'on-first-retry' is set
4. Run the relevant test suite
5. If tests fail:
   a. Analyze failure output carefully (Phase 1 of /debug)
   b. Check screenshot/trace artifacts in test-results/:
      - Screenshots: what does the page look like at the failure point?
      - Trace: open with `npx playwright show-trace` for DOM + network + console
      - Diff images (*-diff.png): for visual regression failures, what changed?
   c. Form hypothesis about root cause
   d. Fix the code (using /tdd — failing test → fix → verify)
   e. Run tests again
   f. Repeat until ALL tests pass
6. If tests pass:
   a. Run visual regression suite if project uses toHaveScreenshot():
      npx playwright test --grep @visual --repeat-each=3
   b. Run full suite MULTIPLE TIMES to catch flakiness:
      npx playwright test --repeat-each=3 --reporter=line
   c. Use /verify-done before claiming success
```

- [ ] **Step 2: Add new "Screenshot-Driven Debugging" section before "When To Use This Skill"**

Insert before the "When To Use This Skill" section:

```markdown
## Screenshot-Driven Debugging

When test output alone isn't enough to diagnose a failure, use artifacts:

### Quick diagnosis commands:

```bash
# Re-run failing test with full capture
npx playwright test tests/e2e/failing.spec.ts --trace on --screenshot on --video on

# View the trace (richest artifact — DOM snapshots, network, console)
npx playwright show-trace test-results/failing-chromium/trace.zip

# List all screenshots from last run
ls test-results/*/test-*.png

# List all visual regression diffs
ls test-results/*/*-diff.png
```

### Visual regression failure diagnosis:

When a `toHaveScreenshot()` assertion fails, Playwright generates three images:

| File | Content |
|------|---------|
| `*-expected.png` | Committed baseline |
| `*-actual.png` | Current render |
| `*-diff.png` | Red overlay showing differences |

**Diagnosis steps:**
1. Compare expected vs actual — is this an intentional UI change?
2. If intentional: `npx playwright test --update-snapshots` → commit baselines
3. If unintentional: the diff shows exactly which region changed — fix the CSS/layout
4. Re-run to confirm fix

### When to escalate artifact capture:

| Situation | Action |
|-----------|--------|
| Test fails, error message is clear | No extra capture needed |
| Test fails, unclear why element isn't visible | Check screenshot at failure point |
| Test intermittently fails | Enable trace: 'on', run with --repeat-each=10 |
| Visual regression diff is confusing | Compare trace DOM snapshots at the assertion step |
| Test fails only in CI | Download CI trace artifact, compare with local trace |
```

- [ ] **Step 3: Commit**
  `git add skills/test-automation-loop/SKILL.md && git commit -m "feat: add screenshot-aware loop and artifact debugging to test-automation-loop"`

---

### Task 7: Update `start/SKILL.md` — visual regression in quality gate

**Files:**
- Modify: `skills/start/SKILL.md`

- [ ] **Step 1: Add visual regression checkpoints to the E2E Quality Gate (Step 5, around line 193)**

Add two new checkboxes to the quality gate box, after the existing "Would these tests catch a regression" checkbox:

```
║  □ For UI changes: do visual regression tests capture               ║
║    before/after state with toHaveScreenshot()?                       ║
║                                                                      ║
║  □ Are screenshot baselines committed for new pages/components?      ║
```

- [ ] **Step 2: Commit**
  `git add skills/start/SKILL.md && git commit -m "feat: add visual regression checkpoints to /start quality gate"`

---

## Execution Order

Tasks 1-4 are independent (new files) — can be done in parallel.
Task 5 depends on Tasks 1-4 (references the new files in the table).
Tasks 6-7 are independent of each other but should follow Task 5.

```
Tasks 1, 2, 3, 4  (parallel — new reference files)
       ↓
     Task 5        (update SKILL.md — references new files)
       ↓
  Tasks 6, 7       (parallel — update loop + start skills)
```
