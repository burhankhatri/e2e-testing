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

## Sharding Strategy

### When to shard:

| Suite size | Shards | Why |
|-----------|--------|-----|
| < 20 tests | 1 (no sharding) | Overhead of merge job not worth it |
| 20-100 tests | 2-4 | Good balance of speed vs complexity |
| 100+ tests | 4-8 | Diminishing returns beyond 8 |

### Shard configuration:

```bash
# Split into 4 shards
npx playwright test --shard=1/4
npx playwright test --shard=2/4
npx playwright test --shard=3/4
npx playwright test --shard=4/4
```

Playwright distributes tests across shards automatically. Each shard gets a roughly equal portion.

### Merging sharded reports:

```bash
# Each shard produces blob-report/ directory
# Merge all fragments into one HTML report:
npx playwright merge-reports --reporter html ./all-blob-reports
```

The merged report contains all tests from all shards, with full screenshots, traces, and video.

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
  tests/e2e/*.spec.ts-snapshots/   # Committed baselines (source of truth)

feature branch:
  UI change → visual test fails → expected
  Developer reviews diff images in CI artifact
  npx playwright test --update-snapshots (locally or in CI)
  Commits updated baselines with the PR
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

## Test Coverage

### V8 coverage with Playwright:

```typescript
// playwright.config.ts — enable V8 coverage collection
export default defineConfig({
  use: {
    // V8 coverage is collected via Chrome DevTools Protocol
    contextOptions: {
      // No special config needed — coverage is collected via test code
    },
  },
});
```

### Coverage fixture:

```typescript
// fixtures.ts — collect coverage per test
import { test as base } from '@playwright/test';
import fs from 'fs';
import path from 'path';

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.coverage.startJSCoverage();
    await use(page);
    const coverage = await page.coverage.stopJSCoverage();

    // Write coverage data for merging
    const coverageDir = path.join('coverage', 'tmp');
    fs.mkdirSync(coverageDir, { recursive: true });
    fs.writeFileSync(
      path.join(coverageDir, `coverage-${Date.now()}.json`),
      JSON.stringify(coverage),
    );
  },
});
```

### Merging coverage from sharded runs:

```yaml
# In GitHub Actions merge-reports job:
- name: Download coverage data
  uses: actions/download-artifact@v4
  with:
    path: all-coverage
    pattern: coverage-*
    merge-multiple: true

- name: Merge and report coverage
  run: npx nyc report --reporter=text --reporter=lcov --temp-dir=all-coverage
```

### Coverage thresholds in CI:

```json
// .nycrc or package.json
{
  "check-coverage": true,
  "lines": 80,
  "branches": 70,
  "functions": 75,
  "statements": 80
}
```

## Docker Compose for Full-Stack Testing

When your app needs a database and services, use Docker Compose to run the full stack:

```yaml
# docker-compose.test.yml
services:
  app:
    build: .
    ports:
      - '3000:3000'
    environment:
      - DATABASE_URL=postgresql://test:test@db:5432/testdb
      - NODE_ENV=test
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: testdb
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U test']
      interval: 5s
      timeout: 5s
      retries: 5

  e2e:
    image: mcr.microsoft.com/playwright:v1.50.0-noble
    depends_on:
      - app
    working_dir: /work
    volumes:
      - .:/work
    command: npx playwright test
    environment:
      - BASE_URL=http://app:3000
```

```bash
# Run full stack + tests
docker compose -f docker-compose.test.yml up --abort-on-container-exit --exit-code-from e2e

# Extract reports after run
docker compose -f docker-compose.test.yml cp e2e:/work/playwright-report ./playwright-report
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
