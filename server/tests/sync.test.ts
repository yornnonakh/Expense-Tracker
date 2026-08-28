import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import {
  API_PREFIX,
  auth,
  makeBudget,
  makeExpense,
  makeHarness,
  signUp,
  uuid,
  type Harness,
  type Session,
} from './helpers.js';

describe('sync', () => {
  let harness: Harness;
  let session: Session;

  beforeEach(async () => {
    harness = makeHarness();
    session = await signUp(harness.app);
  });

  afterEach(() => {
    harness.close();
  });

  const push = (body: unknown) =>
    request(harness.app).post(`${API_PREFIX}/sync`).set(...auth(session)).send(body);

  const pull = (since = 0) =>
    request(harness.app).get(`${API_PREFIX}/sync`).query({ since }).set(...auth(session));

  describe('push then pull', () => {
    it('round-trips an expense', async () => {
      const expense = makeExpense({ amount: 42.75, description: 'Groceries' });

      const pushed = await push({ expenses: [expense] }).expect(200);
      expect(pushed.body.applied).toBe(1);
      expect(pushed.body.conflicts).toEqual([]);

      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses).toHaveLength(1);
      expect(pulled.body.expenses[0]).toMatchObject({
        id: expense.id,
        amount: 42.75,
        description: 'Groceries',
        category: 'food',
        deletedAt: null,
      });
    });

    it('round-trips a budget', async () => {
      const budget = makeBudget({ limit: 500, category: 'transport' });
      await push({ budgets: [budget] }).expect(200);

      const pulled = await pull(0).expect(200);
      expect(pulled.body.budgets).toHaveLength(1);
      expect(pulled.body.budgets[0]).toMatchObject({ id: budget.id, limit: 500 });
    });

    it('applies a mixed batch in one request', async () => {
      const response = await push({
        expenses: [makeExpense(), makeExpense()],
        budgets: [makeBudget({ category: 'health' })],
      }).expect(200);

      expect(response.body.applied).toBe(3);
    });
  });

  describe('the since watermark', () => {
    it('returns only what changed after the watermark', async () => {
      await push({ expenses: [makeExpense({ description: 'First' })] }).expect(200);

      const first = await pull(0).expect(200);
      expect(first.body.expenses).toHaveLength(1);
      const watermark = first.body.serverTime;

      // Nothing has changed since, so a pull at the watermark is empty.
      const empty = await pull(watermark).expect(200);
      expect(empty.body.expenses).toHaveLength(0);

      await push({ expenses: [makeExpense({ description: 'Second' })] }).expect(200);

      const second = await pull(watermark).expect(200);
      expect(second.body.expenses).toHaveLength(1);
      expect(second.body.expenses[0].description).toBe('Second');
    });

    it('advances serverTime monotonically', async () => {
      const first = await pull(0).expect(200);
      await push({ expenses: [makeExpense()] }).expect(200);
      const second = await pull(0).expect(200);

      expect(second.body.serverTime).toBeGreaterThanOrEqual(first.body.serverTime);
    });

    it('pushes and pulls in one round trip when since is supplied', async () => {
      const first = await pull(0).expect(200);

      const response = await push({
        since: first.body.serverTime,
        expenses: [makeExpense({ description: 'Combined' })],
      }).expect(200);

      expect(response.body.applied).toBe(1);
      expect(response.body.expenses).toHaveLength(1);
      expect(response.body.expenses[0].description).toBe('Combined');
    });
  });

  describe('tombstones', () => {
    it('sends deletes as tombstones rather than omitting the row', async () => {
      const expense = makeExpense();
      await push({ expenses: [expense] }).expect(200);

      const afterCreate = await pull(0).expect(200);
      const watermark = afterCreate.body.serverTime;

      await push({
        expenses: [{ ...expense, deletedAt: Date.now(), updatedAt: Date.now() + 1 }],
      }).expect(200);

      const afterDelete = await pull(watermark).expect(200);

      // The row must still arrive. An omitted row is indistinguishable from
      // one the client has never seen, and it would be resurrected.
      expect(afterDelete.body.expenses).toHaveLength(1);
      expect(afterDelete.body.expenses[0].id).toBe(expense.id);
      expect(afterDelete.body.expenses[0].deletedAt).toBeGreaterThan(0);
    });

    it('hides tombstoned rows from the REST list', async () => {
      const expense = makeExpense();
      await push({ expenses: [expense] }).expect(200);
      await push({
        expenses: [{ ...expense, deletedAt: Date.now(), updatedAt: Date.now() + 1 }],
      }).expect(200);

      const listed = await request(harness.app)
        .get(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .expect(200);

      expect(listed.body.expenses).toHaveLength(0);
    });
  });

  describe('last-write-wins', () => {
    it('accepts a strictly newer edit', async () => {
      const expense = makeExpense({ amount: 10, updatedAt: 1000 });
      await push({ expenses: [expense] }).expect(200);

      const response = await push({
        expenses: [{ ...expense, amount: 20, updatedAt: 2000 }],
      }).expect(200);

      expect(response.body.applied).toBe(1);
      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses[0].amount).toBe(20);
    });

    it('rejects a stale edit and returns the server copy', async () => {
      const expense = makeExpense({ amount: 10, updatedAt: 2000 });
      await push({ expenses: [expense] }).expect(200);

      const response = await push({
        expenses: [{ ...expense, amount: 999, updatedAt: 1000 }],
      }).expect(200);

      expect(response.body.applied).toBe(0);
      expect(response.body.conflicts).toHaveLength(1);
      expect(response.body.conflicts[0]).toMatchObject({
        status: 'conflict',
        id: expense.id,
      });
      // The server hands back what it holds so the client can settle without
      // another round trip.
      expect(response.body.conflicts[0].server.amount).toBe(10);

      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses[0].amount).toBe(10);
    });

    it('treats an identical re-push as a no-op, making retries idempotent', async () => {
      const expense = makeExpense({ amount: 10, updatedAt: 5000 });
      await push({ expenses: [expense] }).expect(200);

      // A client that retries after a dropped response sends the same bytes.
      const retry = await push({ expenses: [expense] }).expect(200);

      expect(retry.body.applied).toBe(0);
      expect(retry.body.conflicts).toHaveLength(1);

      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses).toHaveLength(1);
      expect(pulled.body.expenses[0].amount).toBe(10);
    });

    it('lets a newer delete beat an older edit', async () => {
      const expense = makeExpense({ updatedAt: 1000 });
      await push({ expenses: [expense] }).expect(200);

      await push({ expenses: [{ ...expense, deletedAt: 3000, updatedAt: 3000 }] }).expect(200);

      const stale = await push({
        expenses: [{ ...expense, description: 'Resurrected', updatedAt: 2000 }],
      }).expect(200);

      expect(stale.body.applied).toBe(0);

      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses[0].deletedAt).toBe(3000);
    });
  });

  describe('budget one-per-category', () => {
    it('tombstones the older rival when two devices create the same category', async () => {
      const older = makeBudget({ category: 'food', limit: 100, updatedAt: 1000 });
      const newer = makeBudget({ category: 'food', limit: 200, updatedAt: 2000 });

      await push({ budgets: [older] }).expect(200);
      const response = await push({ budgets: [newer] }).expect(200);

      expect(response.body.applied).toBe(1);

      const pulled = await pull(0).expect(200);
      const live = pulled.body.budgets.filter((b: { deletedAt: number | null }) => b.deletedAt === null);

      // Exactly one survives, and it is the one set most recently.
      expect(live).toHaveLength(1);
      expect(live[0].id).toBe(newer.id);
      expect(live[0].limit).toBe(200);
    });

    it('keeps the incumbent when the arriving budget is older', async () => {
      const incumbent = makeBudget({ category: 'shopping', limit: 100, updatedAt: 5000 });
      const arriving = makeBudget({ category: 'shopping', limit: 200, updatedAt: 1000 });

      await push({ budgets: [incumbent] }).expect(200);
      const response = await push({ budgets: [arriving] }).expect(200);

      expect(response.body.conflicts).toHaveLength(1);

      const pulled = await pull(0).expect(200);
      const live = pulled.body.budgets.filter((b: { deletedAt: number | null }) => b.deletedAt === null);
      expect(live).toHaveLength(1);
      expect(live[0].id).toBe(incumbent.id);
    });

    it('frees the category once the live budget is tombstoned', async () => {
      const first = makeBudget({ category: 'utilities', updatedAt: 1000 });
      await push({ budgets: [first] }).expect(200);
      await push({ budgets: [{ ...first, deletedAt: 2000, updatedAt: 2000 }] }).expect(200);

      const replacement = makeBudget({ category: 'utilities', limit: 999, updatedAt: 3000 });
      const response = await push({ budgets: [replacement] }).expect(200);

      expect(response.body.applied).toBe(1);
    });
  });

  describe('validation', () => {
    it.each([
      ['a negative amount', makeExpense({ amount: -5 })],
      ['a zero amount', makeExpense({ amount: 0 })],
      ['an absurd amount', makeExpense({ amount: 2_000_000_000 })],
      ['an empty description', makeExpense({ description: '   ' })],
      ['an unknown category', makeExpense({ category: 'crypto' })],
      ['a non-UUID id', makeExpense({ id: 'not-a-uuid' })],
    ])('rejects %s', async (_label, expense) => {
      const response = await push({ expenses: [expense] }).expect(422);
      expect(response.body.error.code).toBe('validation_failed');
    });

    it('rejects the whole batch when one record is invalid', async () => {
      const good = makeExpense({ description: 'Valid' });
      await push({ expenses: [good, makeExpense({ amount: -1 })] }).expect(422);

      // Nothing from the batch may land — a partially applied push leaves the
      // client's outbox unable to tell what it still owes.
      const pulled = await pull(0).expect(200);
      expect(pulled.body.expenses).toHaveLength(0);
    });

    it('caps batch size', async () => {
      const huge = Array.from({ length: 1001 }, () => makeExpense());
      await push({ expenses: huge }).expect(422);
    });
  });
});
