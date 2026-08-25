import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import {
  API_PREFIX,
  auth,
  makeBudget,
  makeExpense,
  makeHarness,
  signUp,
  type Harness,
  type Session,
} from './helpers.js';

/**
 * Cross-tenant isolation.
 *
 * Every query in the data layer is scoped by user_id; these tests are what
 * hold that property in place. A regression here is the most damaging bug this
 * service could ship, so the cases assert on "not found" rather than merely
 * "not equal" — leaking existence is itself a failure.
 */
describe('authorization', () => {
  let harness: Harness;
  let alice: Session;
  let bob: Session;

  beforeEach(async () => {
    harness = makeHarness();
    alice = await signUp(harness.app, { name: 'Alice' });
    bob = await signUp(harness.app, { name: 'Bob' });
  });

  afterEach(() => {
    harness.close();
  });

  it("keeps one user's expenses out of another's sync pull", async () => {
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ expenses: [makeExpense({ description: "Alice's lunch" })] })
      .expect(200);

    const bobsPull = await request(harness.app)
      .get(`${API_PREFIX}/sync`)
      .query({ since: 0 })
      .set(...auth(bob))
      .expect(200);

    expect(bobsPull.body.expenses).toHaveLength(0);
  });

  it("keeps one user's expenses out of another's REST list", async () => {
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ expenses: [makeExpense()] })
      .expect(200);

    const bobsList = await request(harness.app)
      .get(`${API_PREFIX}/expenses`)
      .set(...auth(bob))
      .expect(200);

    expect(bobsList.body.expenses).toHaveLength(0);
  });

  it("404s when reading another user's expense by id", async () => {
    const expense = makeExpense();
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ expenses: [expense] })
      .expect(200);

    // Bob knows the exact id and still cannot read it.
    await request(harness.app)
      .get(`${API_PREFIX}/expenses/${expense.id}`)
      .set(...auth(bob))
      .expect(404);
  });

  it("404s when deleting another user's expense, and leaves it intact", async () => {
    const expense = makeExpense();
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ expenses: [expense] })
      .expect(200);

    await request(harness.app)
      .delete(`${API_PREFIX}/expenses/${expense.id}`)
      .set(...auth(bob))
      .expect(404);

    const alicesList = await request(harness.app)
      .get(`${API_PREFIX}/expenses`)
      .set(...auth(alice))
      .expect(200);

    expect(alicesList.body.expenses).toHaveLength(1);
  });

  it("cannot overwrite another user's expense by pushing the same id", async () => {
    const expense = makeExpense({ amount: 10, updatedAt: 1000 });
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ expenses: [expense] })
      .expect(200);

    // Bob pushes the same id with a much newer timestamp. Because rows are
    // keyed on (user_id, id), this creates Bob's own row rather than
    // hijacking Alice's.
    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(bob))
      .send({ expenses: [{ ...expense, amount: 999, updatedAt: 9_999_999 }] })
      .expect(200);

    const alicesPull = await request(harness.app)
      .get(`${API_PREFIX}/sync`)
      .query({ since: 0 })
      .set(...auth(alice))
      .expect(200);

    expect(alicesPull.body.expenses).toHaveLength(1);
    expect(alicesPull.body.expenses[0].amount).toBe(10);
  });

  it('scopes the one-budget-per-category rule per user', async () => {
    const alicesBudget = makeBudget({ category: 'food', limit: 100 });
    const bobsBudget = makeBudget({ category: 'food', limit: 200 });

    await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(alice))
      .send({ budgets: [alicesBudget] })
      .expect(200);

    // Bob having a food budget must not collide with Alice's.
    const response = await request(harness.app)
      .post(`${API_PREFIX}/sync`)
      .set(...auth(bob))
      .send({ budgets: [bobsBudget] })
      .expect(200);

    expect(response.body.applied).toBe(1);
    expect(response.body.conflicts).toHaveLength(0);
  });

  it("keeps one user's avatar private", async () => {
    const oneByOneJpeg = Buffer.from(
      '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB' +
        'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAA' +
        'AAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==',
      'base64',
    );

    await request(harness.app)
      .put(`${API_PREFIX}/auth/me/avatar`)
      .set(...auth(alice))
      .send({ imageBase64: oneByOneJpeg.toString('base64'), mimeType: 'image/jpeg' })
      .expect(200);

    // Bob's avatar endpoint reflects Bob, who has none.
    await request(harness.app)
      .get(`${API_PREFIX}/auth/me/avatar`)
      .set(...auth(bob))
      .expect(404);

    const bobsProfile = await request(harness.app)
      .get(`${API_PREFIX}/auth/me`)
      .set(...auth(bob))
      .expect(200);

    expect(bobsProfile.body.user.hasAvatar).toBe(false);
  });

  it.each([
    ['GET', `${API_PREFIX}/expenses`],
    ['GET', `${API_PREFIX}/budgets`],
    ['GET', `${API_PREFIX}/sync`],
    ['POST', `${API_PREFIX}/sync`],
    ['GET', `${API_PREFIX}/auth/me`],
  ])('requires authentication for %s %s', async (method, path) => {
    const agent = request(harness.app);
    const response =
      method === 'GET' ? await agent.get(path).send() : await agent.post(path).send({});
    expect(response.status).toBe(401);
  });
});
