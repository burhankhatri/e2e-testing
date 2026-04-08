# Iframes and Shadow DOM Deep Dive

## Rule: `frameLocator()` for iframes, standard locators for Shadow DOM (auto-pierced)

```
What are you interacting with?
|
+-- Content inside an <iframe>?
|   +-- Use page.frameLocator('selector').getByRole(...)
|   +-- Cross-origin? Same API -- Playwright handles it.
|   +-- Nested iframes? Chain: frameLocator().frameLocator()
|
+-- Web Component with Shadow DOM?
|   +-- Open shadow root? Standard locators auto-pierce.
|   +-- Closed shadow root? addInitScript to force open.
|
+-- Need frame URL or evaluate()?
|   +-- Use page.frame({ url }) -- the Frame API, not FrameLocator.
```

## frameLocator() Basics

`frameLocator()` returns a scoped locator for the iframe's document. All standard locator methods work inside it.

```typescript
test('payment inside Stripe iframe', async ({ page }) => {
  await page.goto('/checkout');

  const paymentFrame = page.frameLocator('iframe[title="Secure payment"]');

  await paymentFrame.getByLabel('Card number').fill('4242424242424242');
  await paymentFrame.getByLabel('Expiry').fill('12/28');
  await paymentFrame.getByLabel('CVC').fill('123');
  await paymentFrame.getByRole('button', { name: 'Pay' }).click();

  // Assert inside iframe
  await expect(paymentFrame.getByText('Payment successful')).toBeVisible();
  // Assert on parent page
  await expect(page.getByRole('heading', { name: 'Order confirmed' })).toBeVisible();
});
```

## Selecting the Right iframe

Prefer `title`, `name`, or `src` attributes. Fall back to `nth()` only when nothing else works.

```typescript
test('target specific iframe', async ({ page }) => {
  await page.goto('/dashboard');

  // By title (best -- accessible and stable)
  const chatFrame = page.frameLocator('iframe[title="Live chat"]');

  // By name attribute
  const reportFrame = page.frameLocator('iframe[name="analytics-report"]');

  // By src pattern
  const adFrame = page.frameLocator('iframe[src*="ads.example.com"]');

  // By parent container -- scope first
  const sidebar = page.getByRole('complementary');
  const sidebarFrame = sidebar.frameLocator('iframe');

  // Last resort -- index (fragile)
  const thirdFrame = page.frameLocator('iframe').nth(2);
});
```

## Cross-Origin Iframes

Playwright handles cross-origin transparently. No special config needed.

```typescript
test('cross-origin Stripe widget', async ({ page }) => {
  await page.goto('/checkout');

  // Works exactly like same-origin iframes
  const stripeFrame = page.frameLocator('iframe[src*="js.stripe.com"]');
  await stripeFrame.getByLabel('Card number').fill('4242424242424242');
  await stripeFrame.getByLabel('MM / YY').fill('12 / 28');
  await stripeFrame.getByLabel('CVC').fill('123');
});
```

## Nested Iframes

Chain `frameLocator()` calls -- one per level of nesting.

```typescript
test('nested iframe interaction', async ({ page }) => {
  await page.goto('/embed-page');

  const outerFrame = page.frameLocator('#widget-container');
  const innerFrame = outerFrame.frameLocator('#payment-form');
  await innerFrame.getByLabel('Amount').fill('99.99');
  await innerFrame.getByRole('button', { name: 'Confirm' }).click();

  // Three levels deep
  const deepFrame = page
    .frameLocator('#level-1')
    .frameLocator('#level-2')
    .frameLocator('#level-3');
  await expect(deepFrame.getByText('Success')).toBeVisible();
});
```

## Frame API (advanced -- URL checks, evaluate)

Use `page.frame()` when you need the frame's URL or need to run JS inside it. Prefer `frameLocator()` for routine interactions.

```typescript
test('frame URL and evaluate', async ({ page }) => {
  await page.goto('/dashboard');

  const frame = page.frame({ url: /analytics\.example\.com/ });
  expect(frame).not.toBeNull();
  expect(frame!.url()).toContain('analytics.example.com');

  const title = await frame!.evaluate(() => document.title);
  expect(title).toBe('Analytics Dashboard');

  // Wait for frame navigation
  const navPromise = page.waitForEvent('framenavigated', {
    predicate: (f) => f.url().includes('/reports'),
  });
  await page.frameLocator('iframe[name="analytics"]')
    .getByRole('link', { name: 'Reports' }).click();
  await navPromise;
});
```

## Shadow DOM -- Auto-Piercing

Playwright's `locator()`, `getByRole()`, `getByText()`, and all semantic locators pierce open Shadow DOM automatically. No config needed.

```typescript
test('web components with shadow DOM', async ({ page }) => {
  await page.goto('/design-system-demo');

  // All of these auto-pierce shadow roots
  await page.getByRole('button', { name: 'Open menu' }).click();
  await page.locator('my-dropdown').getByRole('option', { name: 'Settings' }).click();

  // Nested web components -- each shadow root pierced
  await page.locator('my-app').locator('my-sidebar')
    .getByRole('link', { name: 'Dashboard' }).click();

  // Assertions pierce too
  await expect(page.locator('my-card').getByText('Welcome back')).toBeVisible();
  await expect(page.getByTestId('user-avatar')).toBeVisible();
});
```

## Closed Shadow DOM Workaround

Override `attachShadow` before the page loads to force open mode.

```typescript
test('closed shadow DOM forced open', async ({ page }) => {
  await page.addInitScript(() => {
    const original = Element.prototype.attachShadow;
    Element.prototype.attachShadow = function (init: ShadowRootInit) {
      return original.call(this, { ...init, mode: 'open' });
    };
  });

  await page.goto('/third-party-widget');

  // Previously closed shadow root is now accessible
  await page.locator('closed-component').getByRole('button', { name: 'Action' }).click();
  await expect(page.locator('closed-component').getByText('Done')).toBeVisible();
});
```

## Slots and Custom Events

```typescript
// Slotted content is light DOM -- locate through parent element
const card = page.locator('my-card');
await expect(card.getByRole('heading', { name: 'Product Title' })).toBeVisible();

// Custom events -- set up listener before triggering
const eventPromise = page.evaluate(() =>
  new Promise<{ detail: unknown }>((resolve) => {
    document.querySelector('my-color-picker')!.addEventListener(
      'color-change', (e: Event) => resolve({ detail: (e as CustomEvent).detail }), { once: true }
    );
  })
);
await page.locator('my-color-picker').getByRole('button', { name: 'Red' }).click();
expect((await eventPromise).detail).toEqual({ color: '#ff0000' });
```

## Payment Widget Patterns (Stripe, PayPal)

```typescript
// Stripe Elements -- separate iframe per field
const cardFrame = page.frameLocator('iframe[title="Secure card number input"]');
const expiryFrame = page.frameLocator('iframe[title="Secure expiration date input"]');
const cvcFrame = page.frameLocator('iframe[title="Secure CVC input"]');
await cardFrame.getByLabel('Card number').fill('4242424242424242');
await expiryFrame.getByLabel('Expiry').fill('12/28');
await cvcFrame.getByLabel('CVC').fill('123');

// PayPal -- button lives in an iframe
const paypalFrame = page.frameLocator('iframe[title*="PayPal"]');
await expect(paypalFrame.getByRole('button', { name: /paypal/i })).toBeVisible();
```

## Decision Table

| Scenario | Approach | Why |
|---|---|---|
| Content in `<iframe>` | `frameLocator('selector')` | Scoped locator for iframe document |
| Multiple iframes | Use `title`, `name`, `src` selectors | Stable; avoids fragile index |
| Nested iframes | Chain `frameLocator().frameLocator()` | One call per nesting level |
| Cross-origin iframe | Same `frameLocator()` API | Playwright handles transparently |
| URL/evaluate in frame | `page.frame({ url })` | FrameLocator has no URL/evaluate |
| Open Shadow DOM | Standard locators | Auto-piercing by default |
| Closed Shadow DOM | `addInitScript` to override `attachShadow` | Forces open before page loads |
| Slotted content | Locate within custom element tag | Light DOM, accessible normally |

## Anti-Patterns

| Don't | Problem | Do |
|---|---|---|
| `page.locator('#inside-iframe')` | Locators don't cross iframe boundaries | `page.frameLocator('iframe').locator('#inside-iframe')` |
| `page.$('>>> .shadow-el')` | `>>>` piercing is not Playwright API | Use `page.locator('host').getByRole(...)` |
| `page.evaluate` to query shadow DOM | Bypasses auto-waiting and retry | Use `page.locator()` -- auto-pierces |
| `frameLocator('iframe').nth(0)` when attrs exist | Index changes when iframes added/removed | Use `title`, `name`, or `src` pattern |
| `contentFrame()` for routine interactions | More complex than necessary | Use `frameLocator()` -- simpler, auto-waits |
| Unscoped locator in multi-shadow-root page | Matches wrong element from wrong component | Scope: `page.locator('my-component').getByRole(...)` |
