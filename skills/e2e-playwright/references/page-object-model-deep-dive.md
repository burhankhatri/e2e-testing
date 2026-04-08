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

- **1 test file uses it** — inline code or helper function
- **2-3 test files use it** — fixture
- **4+ test files use it + complex page** — POM class + fixture to instantiate it
- **Needs cleanup** — always a fixture (POM alone has no cleanup mechanism)

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
import { type Page } from '@playwright/test';

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
```

```typescript
// pages/DashboardPage.ts
import { type Page } from '@playwright/test';
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
  get heading() { return this.page.getByRole('heading', { level: 1 }); }
}
```

```typescript
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
| Asserting inside POM methods | Hides what the test verifies; can't reuse for different assertions | Expose locators, assert in test |
| Deep inheritance (`AdminPage extends UserPage extends BasePage`) | Fragile, hard to understand, changes ripple | Use composition: `this.header = new Header(page)` |
| POM for a page tested in one file | Unnecessary indirection, harder to read | Keep locators inline in the test file |
| Storing mutable state in POM | Breaks test isolation if POM is shared | POM should be stateless — derive state from the page |
| God page object (200+ lines) | Hard to maintain, too many responsibilities | Split into component objects, compose them |
| Putting test data in POM (`defaultUser = 'admin'`) | Couples POM to specific test scenarios | Pass data as method parameters |
