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

describe('REST endpoints', () => {
  let harness: Harness;
  let session: Session;

  beforeEach(async () => {
    harness = makeHarness();
    session = await signUp(harness.app);
  });

  afterEach(() => {
    harness.close();
  });

  describe('expenses', () => {
    it('creates, reads, updates and deletes', async () => {
      const expense = makeExpense({ amount: 30, description: 'Taxi', category: 'transport' });

      const created = await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(expense)
        .expect(201);
      expect(created.body.expense.amount).toBe(30);

      const read = await request(harness.app)
        .get(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .expect(200);
      expect(read.body.expense.description).toBe('Taxi');

      const updated = await request(harness.app)
        .put(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .send({ ...expense, amount: 45, updatedAt: Date.now() + 1000 })
        .expect(200);
      expect(updated.body.expense.amount).toBe(45);

      await request(harness.app)
        .delete(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .expect(204);

      await request(harness.app)
        .get(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .expect(404);
    });

    it('rejects creating the same id twice', async () => {
      const expense = makeExpense();
      await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(expense)
        .expect(201);

      const duplicate = await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(expense)
        .expect(409);
      expect(duplicate.body.error.code).toBe('conflict');
    });

    it('404s updating an expense that does not exist', async () => {
      await request(harness.app)
        .put(`${API_PREFIX}/expenses/${uuid()}`)
        .set(...auth(session))
        .send(makeExpense())
        .expect(404);
    });

    it('404s deleting twice', async () => {
      const expense = makeExpense();
      await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(expense)
        .expect(201);

      await request(harness.app)
        .delete(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .expect(204);
      await request(harness.app)
        .delete(`${API_PREFIX}/expenses/${expense.id}`)
        .set(...auth(session))
        .expect(404);
    });

    it('returns expenses newest first', async () => {
      await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(makeExpense({ date: 1_000, description: 'Older' }))
        .expect(201);
      await request(harness.app)
        .post(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .send(makeExpense({ date: 9_000, description: 'Newer' }))
        .expect(201);

      const list = await request(harness.app)
        .get(`${API_PREFIX}/expenses`)
        .set(...auth(session))
        .expect(200);

      expect(list.body.expenses.map((e: { description: string }) => e.description)).toEqual([
        'Newer',
        'Older',
      ]);
    });
  });

  describe('budgets', () => {
    it('creates and lists a budget', async () => {
      const budget = makeBudget({ category: 'health', limit: 250 });
      await request(harness.app)
        .put(`${API_PREFIX}/budgets/${budget.id}`)
        .set(...auth(session))
        .send(budget)
        .expect(200);

      const list = await request(harness.app)
        .get(`${API_PREFIX}/budgets`)
        .set(...auth(session))
        .expect(200);

      expect(list.body.budgets).toHaveLength(1);
      expect(list.body.budgets[0].limit).toBe(250);
    });

    it('refuses a second live budget for the same category', async () => {
      await request(harness.app)
        .put(`${API_PREFIX}/budgets/${makeBudget({ category: 'food' }).id}`)
        .set(...auth(session))
        .send(makeBudget({ category: 'food' }))
        .expect(200);

      const second = makeBudget({ category: 'food' });
      const response = await request(harness.app)
        .put(`${API_PREFIX}/budgets/${second.id}`)
        .set(...auth(session))
        .send(second)
        .expect(409);

      expect(response.body.error.code).toBe('conflict');
    });
  });

  describe('profile', () => {
    const tinyJpeg =
      '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB' +
      'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAA' +
      'AAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==';

    it('uploads, serves and removes an avatar', async () => {
      const uploaded = await request(harness.app)
        .put(`${API_PREFIX}/auth/me/avatar`)
        .set(...auth(session))
        .send({ imageBase64: tinyJpeg, mimeType: 'image/jpeg' })
        .expect(200);
      expect(uploaded.body.user.hasAvatar).toBe(true);

      const served = await request(harness.app)
        .get(`${API_PREFIX}/auth/me/avatar`)
        .set(...auth(session))
        .expect(200);
      expect(served.headers['content-type']).toContain('image/jpeg');
      expect(served.body.length).toBeGreaterThan(0);

      const removed = await request(harness.app)
        .delete(`${API_PREFIX}/auth/me/avatar`)
        .set(...auth(session))
        .expect(200);
      expect(removed.body.user.hasAvatar).toBe(false);

      await request(harness.app)
        .get(`${API_PREFIX}/auth/me/avatar`)
        .set(...auth(session))
        .expect(404);
    });

    it('rejects an oversized avatar', async () => {
      // 3 MB of base64 decodes to over the 2 MB ceiling.
      const oversized = Buffer.alloc(3 * 1024 * 1024, 1).toString('base64');
      const response = await request(harness.app)
        .put(`${API_PREFIX}/auth/me/avatar`)
        .set(...auth(session))
        .send({ imageBase64: oversized, mimeType: 'image/jpeg' })
        .expect(413);

      expect(response.body.error.code).toBe('payload_too_large');
    });
  });

  describe('infrastructure', () => {
    it('serves an unauthenticated health check', async () => {
      const response = await request(harness.app).get('/health').expect(200);
      expect(response.body.status).toBe('ok');
    });

    it('reports database health on the versioned endpoint', async () => {
      const response = await request(harness.app).get(`${API_PREFIX}/health`).expect(200);
      expect(response.body.database).toBe('ok');
    });

    it('404s an unknown route in the API error shape', async () => {
      const response = await request(harness.app).get(`${API_PREFIX}/nope`).expect(404);
      expect(response.body.error.code).toBe('not_found');
    });

    it('rejects malformed JSON with 400, not 500', async () => {
      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .set('Content-Type', 'application/json')
        .send('{"email": ')
        .expect(400);

      expect(response.body.error.code).toBe('validation_failed');
    });

    it('does not advertise the framework', async () => {
      const response = await request(harness.app).get('/health').expect(200);
      expect(response.headers['x-powered-by']).toBeUndefined();
    });

    it('sets nosniff', async () => {
      const response = await request(harness.app).get('/health').expect(200);
      expect(response.headers['x-content-type-options']).toBe('nosniff');
    });
  });
});
