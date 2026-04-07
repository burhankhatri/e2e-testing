# Common Pitfalls — Complete List

The 20 most common Playwright mistakes, ordered by frequency.

## 1. `page.waitForTimeout()` instead of assertions
**Fix:** `await expect(locator).toBeVisible()` — auto-retries until element appears.

## 2. Missing `await` on async operations
**Fix:** `await` every Playwright call. Enable ESLint rule `@typescript-eslint/no-floating-promises`.

## 3. CSS selectors instead of role-based locators
**Fix:** `getByRole()` > `getByLabel()` > `getByText()` > `getByTestId()` > CSS.

## 4. `isVisible()` return value instead of `expect().toBeVisible()`
**Fix:** `expect(locator).toBeVisible()` auto-retries. `isVisible()` checks once.

## 5. `expect(await el.textContent()).toBe(x)` — no retry
**Fix:** `await expect(el).toHaveText(x)` — retries until match or timeout.

## 6. Shared mutable state between tests
**Fix:** Fixtures with cleanup via `use()` callback. Never module-level variables.

## 7. Hardcoded URLs
**Fix:** `baseURL` in config. `page.goto('/path')` instead of `page.goto('http://localhost:3000/path')`.

## 8. Mocking your own application
**Fix:** Only mock third-party APIs (Stripe, analytics). Your API is what you're testing.

## 9. Module-level variables for shared state
**Fix:** `test.extend()` fixtures. Each test gets its own instance.

## 10. No traces in CI
**Fix:** `trace: 'on-first-retry'` in config. View with `npx playwright show-trace`.

## 11. Not waiting for network before asserting
**Fix:** `const resp = page.waitForResponse('**/api/data'); await action; await resp;`

## 12. Clicking during animations
**Fix:** `await expect(page.getByRole('dialog')).toBeVisible()` before clicking inside.

## 13. Testing in one browser only
**Fix:** Add projects for chromium + firefox or mobile. At minimum: chromium + one mobile viewport.

## 14. `page.waitForSelector` instead of locator assertions
**Fix:** Locator-based: `await expect(page.getByRole('button')).toBeVisible()`.

## 15. Not using `exact: true` for ambiguous names
**Fix:** `getByRole('button', { name: 'Log', exact: true })` prevents matching "Log out".

## 16. Testing implementation details (internal state, component props)
**Fix:** Test user-visible behavior. "Button is visible and clickable" not "state.isLoading === false".

## 17. Over-mocking — mocking everything
**Fix:** Only mock external dependencies. Let your full stack run.

## 18. No cleanup in afterEach (when using hooks instead of fixtures)
**Fix:** Use fixtures — cleanup runs even on crash. Or move to `afterEach` with caution.

## 19. Ignoring console errors during tests
**Fix:** Add `page.on('console', msg => { if (msg.type() === 'error') throw new Error(msg.text()); })` for critical paths.

## 20. Giant test files with no organization
**Fix:** `test.describe()` blocks by feature. One behavior per test. Separate spec files per feature area.
