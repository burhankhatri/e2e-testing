# Clock and Time Mocking Deep Dive

## Rule: if the assertion depends on what time it is, mock the clock

`page.clock.install()` replaces `Date`, `setTimeout`, `setInterval`, and `requestAnimationFrame` in the page. Call it BEFORE `page.goto()` -- the page must load with mocked time from the start.

## Quick Decision

```
What are you testing?
|
+-- Static display at a specific date/time?
|   +-- clock.install() + setFixedTime() -- time frozen
|
+-- Countdown, timer, debounce, auto-save?
|   +-- clock.install() + fastForward() -- fires pending timers
|
+-- Long idle period (session timeout)?
|   +-- clock.install() + fastForward('30:00') -- instant
|
+-- Need real rAF/timers after setup?
|   +-- clock.install() + resume() -- mocked then real
|
+-- Different timezone rendering?
|   +-- browser.newContext({ timezoneId }) -- affects Date display
|
+-- Timezone + mocked time?
|   +-- newContext({ timezoneId }) + clock.install() -- both controlled
```

## Frozen Time (install + setFixedTime)

**When to use**: UI that varies by date/time -- greetings, holiday banners, expiration status.
**Avoid when**: Feature depends on timers ticking.

```typescript
test('greeting changes by time of day', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-06-15T08:30:00') });
  await page.goto('/dashboard');
  await expect(page.getByText('Good morning')).toBeVisible();

  await page.clock.setFixedTime(new Date('2025-06-15T14:00:00'));
  await page.reload();
  await expect(page.getByText('Good afternoon')).toBeVisible();
});

test('holiday banner on Christmas', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-12-25T10:00:00') });
  await page.goto('/');
  await expect(page.getByTestId('holiday-banner')).toBeVisible();
});
```

## Fast-Forwarding (install + fastForward)

**When to use**: Countdowns, auto-save, session timeouts, debounced actions.
**Avoid when**: Static date display -- use `setFixedTime` instead.

```typescript
test('countdown reaches zero', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-03-15T10:00:00Z') });
  await page.goto('/sale');

  await expect(page.getByTestId('countdown')).toContainText('2:00:00');

  await page.clock.fastForward('01:00:00');
  await expect(page.getByTestId('countdown')).toContainText('1:00:00');

  await page.clock.fastForward('01:00:00');
  await expect(page.getByText('Sale ended')).toBeVisible();
});

test('session timeout warning at 25 minutes', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-03-15T10:00:00Z') });
  await page.goto('/dashboard');

  await page.clock.fastForward('24:59');
  await expect(page.getByRole('dialog', { name: 'Session timeout' })).not.toBeVisible();

  await page.clock.fastForward('00:01');
  await expect(page.getByRole('dialog', { name: 'Session timeout' })).toBeVisible();
});

test('auto-save fires after 30s inactivity', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-03-15T10:00:00Z') });
  await page.goto('/editor');

  await page.getByRole('textbox', { name: 'Content' }).fill('Draft');
  await page.clock.fastForward('00:30');
  await expect(page.getByText('Saved')).toBeVisible();
});
```

## Resuming Real Time (install + resume)

**When to use**: Start at a known time, then let real timers fire for interaction-dependent behavior.
**Avoid when**: The entire test should stay in mocked time.

```typescript
test('scheduled notification fires in real time', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-03-15T09:59:55Z') });
  await page.goto('/dashboard');

  await page.clock.resume(); // real time ticks from 09:59:55

  await expect(page.getByTestId('notification-bell')).toHaveAttribute('data-count', '1', {
    timeout: 10000,
  });
});
```

## Trial Period / Expiration Testing

```typescript
test('trial banner lifecycle', async ({ page }) => {
  // Day 1 of 14-day trial
  await page.clock.install({ time: new Date('2025-03-01T12:00:00Z') });
  await page.goto('/dashboard');
  await expect(page.getByTestId('trial-banner')).toContainText('13 days remaining');

  // Day 12 -- warning
  await page.clock.setFixedTime(new Date('2025-03-12T12:00:00Z'));
  await page.reload();
  await expect(page.getByTestId('trial-banner')).toContainText('2 days remaining');

  // Day 15 -- expired
  await page.clock.setFixedTime(new Date('2025-03-15T12:00:00Z'));
  await page.reload();
  await expect(page.getByText('Your trial has expired')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Upgrade now' })).toBeVisible();
});
```

## Timezone Handling

Always set `timezoneId` on the browser context. Never rely on the machine's local timezone.

```typescript
test('business hours open/closed by timezone', async ({ browser }) => {
  const ctx = await browser.newContext({ timezoneId: 'America/New_York' });
  const page = await ctx.newPage();

  // 10 AM Eastern -- open
  await page.clock.install({ time: new Date('2025-03-15T14:00:00Z') });
  await page.goto('/contact');
  await expect(page.getByTestId('business-hours')).toContainText('Open');

  // 6 PM Eastern -- closed
  await page.clock.setFixedTime(new Date('2025-03-15T22:00:00Z'));
  await page.reload();
  await expect(page.getByTestId('business-hours')).toContainText('Closed');

  await ctx.close();
});

test('event time renders in user timezone', async ({ browser }) => {
  // Event at 18:00 UTC
  const tokyoCtx = await browser.newContext({ timezoneId: 'Asia/Tokyo' });
  const tokyoPage = await tokyoCtx.newPage();
  await tokyoPage.clock.install({ time: new Date('2025-03-20T10:00:00Z') });
  await tokyoPage.goto('/events/upcoming');
  await expect(tokyoPage.getByTestId('event-time')).toContainText('3:00 AM');
  await tokyoCtx.close();
});
```

## Date Picker Defaults

```typescript
test('date picker opens to mocked today', async ({ page }) => {
  await page.clock.install({ time: new Date('2025-07-04T12:00:00') });
  await page.goto('/booking');
  await page.getByLabel('Check-in date').click();

  await expect(page.getByText('July 2025')).toBeVisible();
  await expect(page.locator('[aria-current="date"]')).toHaveText('4');
});
```

## Decision Table

| Scenario | API | Why |
|---|---|---|
| UI at specific date/time | `install()` + `setFixedTime()` | Frozen, no ticking |
| Countdown/timer behavior | `install()` + `fastForward()` | Fires timers instantly |
| Long idle simulation | `install()` + `fastForward('30:00')` | No real waiting |
| Mocked start, then real ticking | `install()` + `resume()` | rAF works after resume |
| Timezone display | `newContext({ timezoneId })` | Affects Date rendering |
| Timezone + frozen time | `newContext({ timezoneId })` + `install()` | Both controlled |
| DST edge cases | `timezoneId` + `install` at DST boundary | Catches timezone bugs |

## Anti-Patterns

| Don't | Problem | Do |
|---|---|---|
| Call `clock.install()` after `page.goto()` | Page loaded with real Date; timers already fired | Install BEFORE navigation |
| `page.waitForTimeout(30000)` for timer test | Wastes 30 real seconds | `clock.fastForward('00:30')` |
| `setFixedTime` when timers need to fire | `setTimeout`/`setInterval` won't trigger | Use `fastForward` |
| Mock only `Date.now()` via `page.evaluate` | Doesn't affect setTimeout/setInterval/rAF | Use `page.clock.install()` |
| Test dates without setting `timezoneId` | Passes locally, fails in CI (different TZ) | Always set timezoneId explicitly |
| Advance in tiny increments | Slow, many unnecessary timer firings | Jump to the exact time of interest |
| Skip `resume()` before real-time assertions | Mocked timers won't fire naturally | Call `resume()` first |
