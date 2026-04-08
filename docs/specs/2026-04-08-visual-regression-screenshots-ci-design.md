# Visual Regression, Screenshots & CI Pipeline — Design Spec

**Goal:** Incorporate missing TestDino Playwright Skill patterns into the e2e-playwright skill, focused on visual regression testing, screenshot/media capture for loop debugging, CI/CD pipeline guidance, and Page Object Model patterns.

**Motivation:** The current skill writes strong functional/behavioral Playwright tests but underutilizes screenshots (only `'only-on-failure'`), has no visual regression testing, no CI pipeline guidance, and no POM patterns. For the autonomous loop testing workflow, the agent needs to both **capture visual state for debugging between iterations** and **use screenshot comparison as a testing assertion** to catch unintended visual changes.

**Scope:** Approach A (Surgical Integration) — 4 new reference files + updates to 3 existing files. Niche topics (i18n, security, canvas/WebGL, service workers, browser extensions, Playwright CLI, migrations) are explicitly out of scope.

---

## Architecture

All new content follows the existing skill structure:
- **SKILL.md** — quick-reference sections agents read on every invocation
- **references/*.md** — deep-dive guides agents read when working on the specific topic

No new skill directories. No new dependencies. Pure documentation that shapes agent behavior.

### File Map

| Action | File | Purpose |
|--------|------|---------|
| **Create** | `references/visual-regression-deep-dive.md` | `toHaveScreenshot()`, baselines, thresholds, masking, CI consistency |
| **Create** | `references/screenshots-and-media-deep-dive.md` | Proactive capture, video, traces, per-iteration screenshots for agent loop debugging |
| **Create** | `references/ci-pipeline-deep-dive.md` | GitHub Actions, GitLab CI, artifact management, sharding, visual regression in CI |
| **Create** | `references/page-object-model-deep-dive.md` | POM vs fixtures vs helpers decision guide, patterns, anti-patterns |
| **Update** | `skills/e2e-playwright/SKILL.md` | New Visual Regression section, updated config template, updated reference table |
| **Update** | `skills/test-automation-loop/SKILL.md` | Screenshot-aware autonomous loop, visual diff step, artifact inspection |
| **Update** | `skills/start/SKILL.md` | Visual regression checkpoints in E2E quality gate |

---

## Component Design

### 1. Visual Regression Deep Dive

**When to use:** Layout stability, component libraries, redesigns, catching unintended CSS side effects.

**When NOT to use:** Pages with heavy dynamic content (live feeds, real-time data), pages where content changes every load.

**Core API — `toHaveScreenshot()`:**
- Named screenshots: `await expect(page).toHaveScreenshot('homepage.png')`
- Element-level: `await expect(locator).toHaveScreenshot('button-hover.png')`
- Full-page: `await expect(page).toHaveScreenshot('full-page.png', { fullPage: true })`
- With options: `maxDiffPixelRatio`, `maxDiffPixels`, `threshold`, `animations`, `mask`

**Baseline workflow:**
1. First run generates baselines in `tests/e2e/*.spec.ts-snapshots/`
2. Commit baselines to git (they ARE the source of truth)
3. Intentional changes: `npx playwright test --update-snapshots`
4. Review diff, commit updated baselines

**Masking dynamic content:**
- `mask: [page.getByTestId('timestamp'), page.getByTestId('avatar')]`
- Masks render as colored boxes in the screenshot, excluding those regions from comparison
- Critical for pages with dates, random avatars, ad slots

**CI consistency:**
- Linux renders fonts differently than macOS — baselines generated on macOS will fail on Linux CI
- Solution: generate baselines per-platform OR use Docker for consistent rendering
- `expect.toHaveScreenshot.maxDiffPixelRatio: 0.01` as default tolerance
- `animations: 'disabled'` prevents animation-frame timing differences

**Anti-patterns:**
- Screenshotting entire pages with live API data (always flaky)
- Tight thresholds (`maxDiffPixelRatio: 0`) on pages with sub-pixel rendering
- Not committing baselines (breaks CI for other developers)
- Updating baselines without reviewing the diff

### 2. Screenshots & Media Deep Dive

**Capture modes in config:**

| Mode | `screenshot` | `video` | `trace` | Use case |
|------|-------------|---------|---------|----------|
| **Loop debugging** | `'on'` | `'retain-on-failure'` | `'on-first-retry'` | Agent iterating — needs screenshots every test for diagnosis |
| **CI default** | `'on'` | `'retain-on-failure'` | `'on-first-retry'` | Balance of artifacts vs speed |
| **Local dev** | `'off'` | `'off'` | `'off'` | Speed, no artifact noise |
| **Full audit** | `'on'` | `'on'` | `'on'` | Investigating a stubborn flaky test |

**Manual capture at workflow steps:**
```typescript
await page.screenshot({ path: `screenshots/step-1-before-login.png` });
// ... perform action ...
await page.screenshot({ path: `screenshots/step-2-after-login.png` });
```

**Per-iteration naming for loop debugging:**
```typescript
await page.screenshot({
  path: `test-results/iteration-${n}/step-${step}-${description}.png`,
  fullPage: true,
});
```

**Video recording:**
- `video: 'on'` — records every test (large files, slow)
- `video: 'retain-on-failure'` — records but only keeps failures (recommended for CI)
- Videos saved to `test-results/<test-name>/video.webm`
- When to use: complex multi-step flows where screenshots miss the transition

**Traces vs video vs screenshots:**

| Artifact | Size | Interactivity | Best for |
|----------|------|--------------|----------|
| Screenshot | Small | None | Quick state check, visual regression |
| Video | Large | Playback only | Animation bugs, multi-step flows |
| Trace | Medium | Full (DOM, network, console) | Root cause analysis, CI failures |

**Agent debugging pattern:** When the loop agent can't diagnose a failure from test output alone, it should:
1. Enable `screenshot: 'on'` temporarily
2. Re-run the failing test
3. Inspect screenshots at each action step
4. Correlate visual state with the assertion failure
5. Restore original capture mode after diagnosis

### 3. CI Pipeline Deep Dive

**GitHub Actions — complete workflow with artifacts:**
- Install with browser caching (`~/.cache/ms-playwright`)
- Run tests with sharding: `--shard=${{ matrix.shard }}`
- Upload artifacts: screenshots, traces, HTML report
- Merge sharded reports: `npx playwright merge-reports`
- Retention: 30 days for reports, 7 days for traces/screenshots

**GitLab CI — equivalent config:**
- Uses `mcr.microsoft.com/playwright` Docker image for consistent rendering
- Artifacts in `artifacts:paths` with `expire_in`

**Sharding strategy:**
- `--shard=1/4` through `--shard=4/4` via matrix
- Each shard uploads its `blob-report/` fragment
- Merge job combines fragments into final HTML report
- Visual regression baselines work normally with sharding (each shard reads the same committed baselines)

**Visual regression in CI:**
- Baselines committed to repo — CI reads them like any other test fixture
- CI failures on visual diff: upload the `test-results/` directory as artifact
- Diff images (`*-diff.png`, `*-actual.png`, `*-expected.png`) are auto-generated
- PR workflow: developer downloads artifact, reviews diff, updates baselines if intentional

**Artifact management:**
- `test-results/` — screenshots, videos, traces (per-test)
- `playwright-report/` — HTML report
- `blob-report/` — sharded report fragments (temporary)
- All three should be uploaded; only `playwright-report/` needs long retention

### 4. Page Object Model Deep Dive

**Decision guide:**

| Pattern | Use when | Avoid when |
|---------|----------|------------|
| **POM** | Page has 5+ interactions reused across 3+ test files | Simple pages, one-off tests |
| **Fixtures** | Setup/teardown with guaranteed cleanup | No cleanup needed |
| **Helpers** | One-off utility (generate test data, format date) | Reused across many files (promote to fixture/POM) |

**Basic POM:**
- Class per page/component
- Constructor takes `Page`
- Methods for actions (`login()`, `addToCart()`)
- Methods for assertions (`expectLoggedIn()`, `expectCartCount()`)
- Navigation methods (`goto()`)

**POM + fixtures:**
- Wire POM into `test.extend()` so tests receive page objects as fixture parameters
- Fixture handles instantiation + navigation
- Tests stay clean: `test('adds item', async ({ productPage }) => { ... })`

**Composing page objects:**
- Shared components (header, sidebar, footer) as separate POM classes
- Page POM composes them: `this.header = new HeaderComponent(page)`
- Avoids god objects

**Anti-patterns:**
- Asserting inside POM methods (assertions belong in tests)
- Inheritance hierarchies (`AdminPage extends UserPage extends BasePage` — use composition)
- POM for pages tested in only one file (overhead > benefit)
- Storing state in POM instances between tests (breaks isolation)

### 5. SKILL.md Updates

**New section — "Visual Regression"** (after Assertions):
- Quick `toHaveScreenshot()` reference (3-4 patterns)
- When to use / when to avoid (compact decision table)
- Config additions for the config template
- Pointer to deep dive

**Updated config template:**
- `screenshot: 'on'` (was `'only-on-failure'`)
- Add `video: 'retain-on-failure'`
- Add `expect.toHaveScreenshot` block with `maxDiffPixelRatio` and `animations: 'disabled'`

**Updated reference table:**
- Add all 4 new deep-dive files with "when to read" descriptions

### 6. test-automation-loop/SKILL.md Updates

**Enhanced loop:**
- Step 3 now includes "capture mode" — ensure screenshots are enabled for the iteration
- Step 4b becomes: "Check screenshot/trace artifacts for visual clues"
- Step 4c (new): "For visual regression failures: compare actual vs expected screenshots, identify what changed"
- Step 5a (new): "Run visual regression suite if project uses `toHaveScreenshot()`"

**New section — "Screenshot-Driven Debugging":**
- Commands to enable full capture temporarily
- How to inspect artifacts between iterations
- When to switch from screenshots to traces to video

### 7. start/SKILL.md Updates

**E2E Quality Gate additions (Step 5):**
- `□ For UI changes: do visual regression tests capture before/after state?`
- `□ Are screenshot baselines committed for new pages/components?`

---

## What's Explicitly Out of Scope

| Topic | Reason |
|-------|--------|
| i18n/localization testing | Niche — applies to <10% of projects |
| Security testing (XSS, CSRF) | Better served by dedicated security tools |
| Performance testing / Core Web Vitals | Separate concern from E2E functional testing |
| Service workers / PWA | Niche |
| Browser extensions | Niche |
| Canvas / WebGL | Niche |
| Playwright CLI snapshot automation | Different paradigm, not test-file based |
| Cypress / Selenium migration | Not relevant to improving test quality |

These can be added later as separate skill packs if needed.

---

## Success Criteria

1. Agent can write visual regression tests with `toHaveScreenshot()` using proper thresholds and masking
2. Agent captures screenshots proactively during loop iterations for debugging
3. Agent can set up a GitHub Actions workflow with proper artifact management
4. Agent uses POM when appropriate (5+ interactions, 3+ test files) and fixtures otherwise
5. The autonomous loop includes visual regression as a step, not an afterthought
6. All new content follows existing reference file structure (when to use, avoid when, quick reference, full patterns)
