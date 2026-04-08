# Test Data Management Deep Dive

## Core principle: every test creates its own data, every test cleans up after itself

```
How should I create test data?
|
+-- Simple value, used once?
|   +-- Inline it. Reader sees exactly what matters.
|
+-- Same shape reused across tests?
|   +-- Factory function with overrides.
|
+-- Need realistic names/addresses/phones?
|   +-- Faker with deterministic seed.
|
+-- Complex object with many optional fields?
|   +-- Builder pattern.
|
+-- Entity must exist before test runs?
|   +-- API exists? --> API seeding via fixture (preferred)
|   +-- No API?    --> DB seeding via fixture (last resort)
```

## Unique IDs for Parallel Safety

Every test runs in parallel. Shared names collide. Always generate unique identifiers.

```typescript
// Cheapest approach -- timestamp + counter
let counter = 0;
function uniqueId(): string {
  return `${Date.now()}-${++counter}-${process.pid}`;
}

// In tests
const email = `user-${uniqueId()}@test.example.com`;
const orgName = `Org-${uniqueId()}`;
```

Use `test.example.com` (RFC 2606 reserved domain) so generated emails never hit real inboxes.

## Factory Pattern

```typescript
// tests/factories/user.factory.ts
export interface UserData {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
}

let counter = 0;

export function createUser(overrides: Partial<UserData> = {}): UserData {
  const id = `${Date.now()}-${++counter}`;
  return {
    firstName: 'Test',
    lastName: `User-${id}`,
    email: `user-${id}@test.example.com`,
    password: 'SecureP@ss123!',
    ...overrides,
  };
}
```

```typescript
// Usage -- override only what the test cares about
test('rejects duplicate email', async ({ page }) => {
  const user = createUser({ email: 'taken@test.example.com' });
  // ...
});
```

## Factory + Faker

```typescript
// tests/factories/faker-user.factory.ts
import { faker } from '@faker-js/faker';

export function createFakerUser(seed?: number) {
  if (seed !== undefined) faker.seed(seed);
  return {
    firstName: faker.person.firstName(),
    lastName: faker.person.lastName(),
    email: faker.internet.email({ provider: 'test.example.com' }),
    phone: faker.phone.number(),
    address: {
      street: faker.location.streetAddress(),
      city: faker.location.city(),
      state: faker.location.state({ abbreviated: true }),
      zip: faker.location.zipCode(),
    },
  };
}
```

```typescript
// Always seed so failures are reproducible
test('checkout with address', async ({ page }, testInfo) => {
  const user = createFakerUser(testInfo.workerIndex);
  // Same workerIndex = same data = reproducible
});
```

## Builder Pattern (5+ optional fields)

```typescript
// tests/builders/product.builder.ts
export class ProductBuilder {
  private product = {
    name: `Product-${Date.now()}`, price: 29.99, currency: 'USD',
    category: 'Electronics', inStock: true, tags: [] as string[],
    variants: [] as { size: string; color: string }[],
  };

  withName(name: string) { this.product.name = name; return this; }
  withPrice(price: number, currency = 'USD') {
    this.product.price = price; this.product.currency = currency; return this;
  }
  outOfStock() { this.product.inStock = false; return this; }
  withVariant(size: string, color: string) {
    this.product.variants.push({ size, color }); return this;
  }
  build() { return { ...this.product }; }
}
```

```typescript
test('out-of-stock badge', async ({ page, request }) => {
  const product = new ProductBuilder().withName('Keyboard').outOfStock().build();
  await request.post('/api/products', { data: product });

  await page.goto('/products');
  await expect(
    page.getByRole('listitem').filter({ hasText: 'Keyboard' }).getByText('Out of Stock')
  ).toBeVisible();
});
```

## API Seeding via Fixture (preferred)

```typescript
// tests/fixtures/api-data.fixture.ts
import { test as base } from '@playwright/test';
import { createUser, UserData } from '../factories/user.factory';

type Fixtures = { apiUser: UserData & { id: string } };

export const test = base.extend<Fixtures>({
  apiUser: async ({ request }, use) => {
    const data = createUser();
    const resp = await request.post('/api/users', { data });
    const created = await resp.json();

    await use({ ...data, id: created.id });

    // Cleanup runs even if test fails
    await request.delete(`/api/users/${created.id}`);
  },
});
export { expect } from '@playwright/test';
```

```typescript
// Compose fixtures for multi-entity seeding
export const test = base.extend({
  apiOrder: async ({ request, apiUser }, use) => {
    const resp = await request.post('/api/orders', {
      data: { userId: apiUser.id, items: [{ sku: 'W-001', qty: 2 }] },
    });
    const order = await resp.json();
    await use(order);
    await request.delete(`/api/orders/${order.id}`);
  },
});
```

## DB Seeding (last resort)

```typescript
// tests/fixtures/db.fixture.ts
import { test as base } from '@playwright/test';
import { Pool } from 'pg';

export const test = base.extend<{ db: Pool; seededOrg: { id: string; name: string } }>({
  db: async ({}, use) => {
    const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
    await use(pool);
    await pool.end();
  },
  seededOrg: async ({ db }, use) => {
    const name = `Org-${Date.now()}`;
    const { rows } = await db.query(
      'INSERT INTO organizations (name) VALUES ($1) RETURNING id', [name]
    );
    await use({ id: rows[0].id, name });
    await db.query('DELETE FROM organizations WHERE id = $1', [rows[0].id]);
  },
});
```

## Decision Table

| Data need | Strategy | Why |
|---|---|---|
| Form input values | Inline in test | Self-documenting, no imports |
| Reused shape (user, product) | Factory function | Single source of truth for shape |
| Realistic random data | Faker + seed | Reproducible, catches edge cases |
| Many optional fields | Builder | Readable fluent API |
| Entity must pre-exist | API fixture | Fast, exercises real app logic |
| Complex relational data, no API | DB fixture | Direct but couples to schema |

## Anti-Patterns

| Don't | Problem | Do |
|---|---|---|
| Share data between tests | Parallel tests collide, order-dependent failures | Each test creates its own data |
| Use hardcoded IDs (`user-1`) | Collides when tests run in parallel | Generate unique IDs per test |
| Seed via UI clicks | 10-100x slower than API seeding | Use `request.post()` in fixture |
| Skip cleanup | Test data accumulates, slows DB, causes false failures | Always clean up in fixture teardown |
| Use Faker without a seed | Failures are non-reproducible | Seed with `testInfo.workerIndex` |
| DB seed without API fallback plan | Couples tests to schema migrations | Prefer API seeding; DB is last resort |
| Create data in `beforeAll` for parallel tests | `beforeAll` runs per worker, not per test | Use per-test fixtures |
