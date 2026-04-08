# Locators Deep Dive

## Locator Priority (use the first that works)

```typescript
page.getByRole('button', { name: 'Submit' })        // 1. Role (default for everything)
page.getByLabel('Email address')                     // 2. Label (form fields)
page.getByText('Welcome back')                       // 3. Text (non-interactive content)
page.getByPlaceholder('Search...')                    // 4. Placeholder (inputs without labels)
page.getByAltText('Company logo')                    // 5. Alt text (images)
page.getByTitle('Close dialog')                      // 6. Title attribute
page.getByTestId('checkout-summary')                 // 7. Test ID (last semantic option)
page.locator('.legacy-widget')                       // 8. CSS/XPath (last resort — legacy only)
```

## Decision Flowchart

```
Element to locate
  |
  +-- Has a semantic role? (button, link, heading, textbox, checkbox, combobox, dialog, row...)
  |     YES --> getByRole('role', { name: 'accessible name' })
  |               +-- Multiple matches? --> Scope within parent: getByRole('navigation').getByRole(...)
  |               +-- Substring collision? --> Add { exact: true }
  |
  +-- Form field with <label>?
  |     YES --> getByLabel('label text')
  |
  +-- Non-interactive text? (paragraph, span, status message, badge)
  |     YES --> getByText('content') — use { exact: true } when text is short
  |
  +-- Has placeholder?
  |     YES --> getByPlaceholder('...') — treat as yellow flag, file ticket for proper label
  |
  +-- Has alt text or title?
  |     YES --> getByAltText('...') or getByTitle('...')
  |
  +-- None of the above?
        --> Add data-testid to markup, use getByTestId('...')
        --> NEVER fall back to CSS/XPath. Fix the markup instead.
```

## Element Type Decision Matrix

| Element Type | Recommended Locator | Fallback | Example |
|---|---|---|---|
| Button | `getByRole('button', { name })` | `getByLabel()` for icon-only | `getByRole('button', { name: 'Save' })` |
| Link | `getByRole('link', { name })` | `getByText()` if role missing | `getByRole('link', { name: 'Sign up' })` |
| Text input | `getByRole('textbox', { name })` | `getByLabel()` | `getByLabel('Email address')` |
| Password | `getByLabel()` | `getByPlaceholder()` | `getByLabel('Password')` |
| Search input | `getByRole('searchbox', { name })` | `getByPlaceholder('Search...')` | `getByRole('searchbox', { name: 'Search' })` |
| Checkbox | `getByRole('checkbox', { name })` | `getByLabel()` | `getByRole('checkbox', { name: 'Remember me' })` |
| Radio | `getByRole('radio', { name })` | `getByLabel()` | `getByRole('radio', { name: 'Express' })` |
| Native select | `getByRole('combobox', { name })` | `getByLabel()` | `getByLabel('Country')` |
| Custom dropdown | `getByRole('combobox')` then `getByRole('option')` | `getByRole('listbox')` chain | Click trigger, then `getByRole('option', { name })` |
| Heading | `getByRole('heading', { name, level })` | `getByText()` | `getByRole('heading', { name: 'Dashboard', level: 1 })` |
| Navigation | `getByRole('navigation', { name })` | `locator('nav')` | `getByRole('navigation', { name: 'Main' })` |
| Table | `getByRole('table', { name })` | `locator('table')` | `getByRole('table', { name: 'Users' })` |
| Table row | `getByRole('row').filter({ has })` | `.filter({ hasText })` | `.filter({ has: getByRole('cell', { name: 'Jane' }) })` |
| Table header | `getByRole('columnheader', { name })` | `locator('th')` | `getByRole('columnheader', { name: 'Status' })` |
| Image | `getByRole('img', { name })` | `getByAltText()` | `getByRole('img', { name: 'Logo' })` |
| Dialog / Modal | `getByRole('dialog', { name })` | `locator('[role="dialog"]')` | `getByRole('dialog', { name: 'Confirm' })` |
| Tab | `getByRole('tab', { name })` | — | `getByRole('tab', { name: 'Settings' })` |
| List item | `getByRole('listitem').filter()` | `.nth()` as last resort | `.filter({ hasText: 'Milk' })` |
| Iframe content | `frameLocator()` then any locator | — | `frameLocator('#payment').getByLabel('Card')` |
| Shadow DOM | `getByRole()` / `locator()` | — | Automatic piercing of open shadow roots |
| Custom widget | `getByTestId()` | Add `role` + `aria-label` first | `getByTestId('color-picker')` |

## Locators by Element Type

### Buttons and Links

```typescript
// Button — matches <button>, <input type="submit">, role="button"
await page.getByRole('button', { name: 'Save changes' }).click();

// Icon-only button (relies on aria-label)
await page.getByRole('button', { name: 'Close' }).click();

// Exact match — prevents 'Log' from matching 'Log out'
await page.getByRole('button', { name: 'Log', exact: true }).click();

// Button scoped within a section
await page.getByRole('region', { name: 'Billing' })
  .getByRole('button', { name: 'Update' }).click();

// Links
await page.getByRole('link', { name: 'Sign up' }).click();

// Link scoped within navigation
await page.getByRole('navigation', { name: 'Main menu' })
  .getByRole('link', { name: 'Pricing' }).click();
```

### Inputs, Checkboxes, Radios, and Selects

```typescript
// Text input by label (preferred)
await page.getByLabel('Email address').fill('user@example.com');

// By role when label is ambiguous
await page.getByRole('textbox', { name: 'Email address' }).fill('user@example.com');

// Password — no distinct role, use label
await page.getByLabel('Password', { exact: true }).fill('s3cure!Pass');

// Search input (role = searchbox)
await page.getByRole('searchbox', { name: 'Search' }).fill('playwright');

// Checkbox — use .check()/.uncheck(), not .click()
await page.getByRole('checkbox', { name: 'Accept terms' }).check();
await expect(page.getByRole('checkbox', { name: 'Accept terms' })).toBeChecked();

// Radio within a fieldset group
await page.getByRole('group', { name: 'Shipping method' })
  .getByRole('radio', { name: 'Express' }).check();

// Native <select>
await page.getByLabel('Country').selectOption('Canada');

// Custom ARIA combobox
await page.getByRole('combobox', { name: 'Country' }).click();
await page.getByRole('option', { name: 'Canada' }).click();
```

### Headings, Tables, Images, and Lists

```typescript
// Heading with specific level
await expect(page.getByRole('heading', { name: 'Dashboard', level: 1 })).toBeVisible();

// Table — chain with row, cell, columnheader
const table = page.getByRole('table', { name: 'Recent orders' });
await expect(table.getByRole('row')).toHaveCount(5);
await expect(page.getByRole('columnheader', { name: 'Status' })).toBeVisible();

// Row filtered by cell content
const row = page.getByRole('row').filter({
  has: page.getByRole('cell', { name: 'Premium Plan' }),
});
await row.getByRole('button', { name: 'Upgrade' }).click();

// Image
await expect(page.getByRole('img', { name: 'Company logo' })).toBeVisible();
await expect(page.getByAltText('Company logo')).toBeVisible(); // alternative

// List items — filter, count, iterate
const item = page.getByRole('listitem').filter({ hasText: 'Milk' });
await item.getByRole('button', { name: 'Remove' }).click();
await expect(page.getByRole('listitem')).toHaveCount(5);
```

### Dialogs and Modals

```typescript
// Scope ALL interactions inside the dialog
const dialog = page.getByRole('dialog', { name: 'Confirm deletion' });
await expect(dialog).toBeVisible();
await dialog.getByRole('button', { name: 'Delete' }).click();
await expect(dialog).toBeHidden();

// Form inside a modal
const modal = page.getByRole('dialog', { name: 'Edit profile' });
await modal.getByLabel('Display name').fill('Jane');
await modal.getByRole('button', { name: 'Save' }).click();
```

## Chaining, Filtering, and Scoping

### Chaining (scope within a parent)

```typescript
const nav = page.getByRole('navigation', { name: 'Main' });
await nav.getByRole('link', { name: 'Settings' }).click();
```

### Filtering by text and by child locator

```typescript
// Filter by text
await page.getByRole('listitem')
  .filter({ hasText: 'Product A' })
  .getByRole('button', { name: 'Buy' }).click();

// Filter by child locator (more precise than hasText)
await page.getByRole('listitem')
  .filter({ has: page.getByRole('heading', { name: 'Premium' }) })
  .getByRole('button', { name: 'Subscribe' }).click();

// Negative filter — exclude by child
await page.getByRole('listitem')
  .filter({ hasNot: page.getByText('Sold out') })
  .first()
  .click();

// Negative filter — exclude by text
const nonFeatured = page.getByRole('listitem').filter({ hasNotText: 'Featured' });

// Combine multiple filters
const activeAdminRow = page
  .getByRole('row')
  .filter({ has: page.getByRole('cell', { name: 'Admin' }) })
  .filter({ has: page.getByText('Active') });
await expect(activeAdminRow).toHaveCount(1);
```

### Positional selectors (use sparingly -- only when order is stable)

```typescript
await page.getByRole('listitem').nth(2).click();   // 0-indexed
await page.getByRole('listitem').first().click();
await page.getByRole('listitem').last().click();
```

### Scoping within a component

```typescript
const productCard = page.locator('[data-testid="product-card"]')
  .filter({ hasText: 'Headphones' });
await productCard.getByRole('button', { name: 'Add to cart' }).click();
await expect(productCard.getByText('Added')).toBeVisible();
```

### Scoping strategy: scope first, never nth first

```typescript
// BAD: fragile index
page.getByRole('button', { name: 'Edit' }).nth(0);

// GOOD: scope to a parent section
page.getByRole('region', { name: 'Billing' })
  .getByRole('button', { name: 'Edit' });

// GOOD: scope to a table row
page.getByRole('row', { name: /Order #1234/ })
  .getByRole('button', { name: 'Edit' });
```

## Regex Matching Patterns

```typescript
// Dynamic text — order numbers, IDs, timestamps
await expect(page.getByText(/Order #\d+/)).toBeVisible();
await expect(page.getByRole('heading', { name: /Welcome, .+/ })).toBeVisible();

// Case-insensitive matching
await page.getByRole('button', { name: /submit/i }).click();

// Anchored currency pattern
await expect(page.getByText(/^\$[\d,]+\.\d{2}$/)).toBeVisible();

// Multi-locale text
await page.getByRole('button', { name: /accept|aceptar|akzeptieren/i }).click();

// Row containing a date pattern
const row = page.getByRole('row').filter({ hasText: /\d{4}-\d{2}-\d{2}/ });

// Substring match is default for getByText
await expect(page.getByText('items in cart')).toBeVisible(); // matches "3 items in cart"

// Exact match when needed (string, not regex)
await page.getByRole('button', { name: 'Log', exact: true }); // won't match "Log out"
```

## Frame Locators

**When to use**: Content inside `<iframe>` -- payment widgets, embedded editors, third-party widgets.

```typescript
// Locate the iframe, then use normal locators inside it
const paymentFrame = page.frameLocator('iframe[title="Payment"]');
await paymentFrame.getByLabel('Card number').fill('4242424242424242');
await paymentFrame.getByLabel('Expiration').fill('12/28');
await paymentFrame.getByLabel('CVC').fill('123');
await paymentFrame.getByRole('button', { name: 'Pay' }).click();

// Nested iframes — chain frameLocator calls
const nestedFrame = page
  .frameLocator('#outer-frame')
  .frameLocator('#inner-frame');
await expect(nestedFrame.getByText('Payment confirmed')).toBeVisible();

// Frame by index — when no better selector exists
const secondFrame = page.frameLocator('iframe').nth(1);
await expect(secondFrame.getByRole('heading')).toBeVisible();
```

## Shadow DOM Piercing

**When to use**: Web components with Shadow DOM (custom elements, design system components).

Playwright pierces open Shadow DOM automatically. Both `getByRole()` and `locator()` work through shadow roots by default.

```typescript
// getByRole pierces automatically — just use it
await page.getByRole('button', { name: 'Toggle menu' }).click();

// locator() with CSS also pierces shadow roots
await page.locator('my-dropdown').getByRole('option', { name: 'Settings' }).click();

// Chain into nested shadow DOMs
await page
  .locator('my-app')
  .locator('my-sidebar')
  .getByRole('link', { name: 'Profile' })
  .click();

// Non-piercing behavior (rare) — use css:light
// await page.locator('css:light=.outer-only').click();
```

## Anti-Patterns

| Don't | Problem | Do Instead |
|---|---|---|
| `page.locator('.btn-primary')` | CSS classes change (renames, modules, Tailwind) | `page.getByRole('button', { name: 'Save' })` |
| `page.locator('#submit-btn')` | IDs are implementation details, often auto-generated | `page.getByRole('button', { name: 'Submit' })` |
| `page.locator('div > span:nth-child(3)')` | Breaks on any DOM restructure | `page.getByText('...')` or `getByTestId()` |
| `page.locator('xpath=//div[@class="form"]//input[2]')` | Fragile, unreadable, position-dependent | `page.getByLabel('Last name')` |
| `page.getByText('Submit')` for a button | Doesn't assert the element is interactive | `page.getByRole('button', { name: 'Submit' })` |
| `page.locator('.item').nth(0)` on dynamic lists | Index changes when items reorder | `.filter({ hasText: 'Specific item' })` |
| `page.getByText('Aceptar')` hardcoded i18n | Fails when locale changes | `getByRole('button', { name: /accept/i })` or `getByTestId()` |
| `await page.waitForTimeout(3000)` | Arbitrary delay, flaky in CI | `await expect(locator).toBeVisible()` |
| `page.$('selector')` (ElementHandle) | Snapshot, no auto-waiting, deprecated | `page.locator('selector')` — lazy and auto-waits |
| `page.locator('text=Click here')` | Legacy text selector syntax | `page.getByText('Click here')` or `getByRole` with name |
| `page.locator('[data-testid="submit"]')` | Raw CSS for test IDs | `page.getByTestId('submit')` — built-in method |
| Repeated locator calls for same element | Each call restarts the search | Store as variable: `const btn = page.getByRole(...)` |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `strict mode violation` | Locator too broad, matches multiple | Add `{ name }`, scope within parent, or `{ exact: true }` |
| Element exists but times out | Inside an iframe or hidden | `frameLocator()` for iframes; `toBeAttached()` for hidden |
| `getByRole` finds nothing | Element has no implicit ARIA role | Inspect a11y tree; add `role` + `aria-label` or use `getByTestId()` |
| Locator finds wrong element | Substring match hits parent/sibling | Add `{ exact: true }` or scope with `.filter()` |
| Flaky in CI, passes locally | Timing or animation issue | Web-first assertions (`toBeVisible()`), never `waitForTimeout()` |
| `getByLabel` doesn't match | Label not associated (`for` missing) | Fix HTML: add `for="id"` or wrap input in `<label>` |
| Matches hidden element | Duplicate text, one copy hidden | Scope to visible parent: `getByRole('main').getByText('...')` |

### Debugging strict mode violations

```typescript
// See how many elements matched
const count = await page.getByRole('button', { name: 'Submit' }).count();
console.log(`Found ${count} matching buttons`);

// Fix 1: Add a name
await page.getByRole('button', { name: 'Save' }).click();
// Fix 2: Scope within a parent
await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
// Fix 3: Exact matching
await page.getByRole('button', { name: 'Save', exact: true }).click();
// Fix 4: Filter
await page.getByRole('button').filter({ hasText: 'Save draft' }).click();
```

### Debugging missing elements

```typescript
// Check if in an iframe
const frame = page.frameLocator('iframe');
await frame.getByRole('button', { name: 'Submit' }).click();

// Check visibility vs DOM presence
await expect(page.getByRole('button', { name: 'Submit' })).toBeAttached(); // in DOM
await expect(page.getByRole('button', { name: 'Submit' })).toBeVisible();  // on screen

// Inspect the accessibility tree
const snapshot = await page.accessibility.snapshot();
console.log(JSON.stringify(snapshot, null, 2));
```

## Debugging Locators in Playwright Inspector

```bash
# Launch Inspector — pick locators interactively
PWDEBUG=1 npx playwright test
# Playwright prioritizes: role > label > text > testid automatically
```

## When CSS/XPath Is Unavoidable

Only when no semantic locator works (legacy apps, third-party widgets without ARIA):

```typescript
// Combine CSS with role scoping
page.locator('.legacy-datepicker').getByRole('button', { name: 'Today' });

// data-testid as last semantic option before CSS
page.getByTestId('color-picker-swatch');
// Configure: playwright.config.ts -> use: { testIdAttribute: 'data-cy' }

// CSS — prefer short structural selectors over fragile class chains
await page.locator('table.report-grid td:has-text("Overdue")').first().click();

// XPath — only when CSS cannot express the query (text + ancestor traversal)
await page.locator('xpath=//td[contains(text(),"Overdue")]/ancestor::tr//button').click();
```
