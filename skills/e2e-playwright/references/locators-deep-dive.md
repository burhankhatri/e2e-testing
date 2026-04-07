# Locators Deep Dive

## Chaining and Filtering

```typescript
// Scope within a section
const nav = page.getByRole('navigation', { name: 'Main' });
await nav.getByRole('link', { name: 'Settings' }).click();

// Filter by text within role matches
await page.getByRole('listitem').filter({ hasText: 'Product A' }).getByRole('button', { name: 'Buy' }).click();

// Filter by child locator
await page.getByRole('listitem')
  .filter({ has: page.getByRole('heading', { name: 'Premium' }) })
  .getByRole('button', { name: 'Subscribe' }).click();

// Negative filter — exclude
await page.getByRole('listitem')
  .filter({ hasNot: page.getByText('Sold out') })
  .first()
  .click();

// nth — when you must pick by index (avoid if possible)
await page.getByRole('listitem').nth(2).click();
await page.getByRole('listitem').first().click();
await page.getByRole('listitem').last().click();
```

## Scoping Within Components

```typescript
// Scope to a specific card/section
const productCard = page.locator('[data-testid="product-card"]').filter({ hasText: 'Headphones' });
await productCard.getByRole('button', { name: 'Add to cart' }).click();
await expect(productCard.getByText('Added')).toBeVisible();

// Scope to a table row
const row = page.getByRole('row').filter({ hasText: 'jane@example.com' });
await row.getByRole('button', { name: 'Edit' }).click();
```

## Dynamic Content and Regex

```typescript
// Regex for dynamic text
await expect(page.getByText(/Order #\d+/)).toBeVisible();
await expect(page.getByRole('heading', { name: /Welcome, .+/ })).toBeVisible();

// Partial text match (default for getByText)
await expect(page.getByText('items in cart')).toBeVisible(); // matches "3 items in cart"

// Exact match when needed
await page.getByRole('button', { name: 'Log', exact: true }); // won't match "Log out"
```

## When CSS/XPath Is Unavoidable

Only use when no semantic locator works (custom canvas widgets, third-party iframes):

```typescript
// Combine CSS with role scoping
page.locator('.legacy-datepicker').getByRole('button', { name: 'Today' });

// data-testid as last semantic option before CSS
page.getByTestId('color-picker-swatch');

// Configure testIdAttribute to match your codebase
// playwright.config.ts: use: { testIdAttribute: 'data-cy' }
```

## Debugging Locators

```bash
# Pick a locator interactively
PWDEBUG=1 npx playwright test

# In the Inspector, hover elements to see suggested locators
# Playwright prioritizes role > label > text > testid automatically
```

```typescript
// Count matches to debug "strict mode" violations
const count = await page.getByRole('button', { name: 'Submit' }).count();
console.log(`Found ${count} matching buttons`);
// If > 1, add more specificity (scope to parent, use exact: true, filter)
```
