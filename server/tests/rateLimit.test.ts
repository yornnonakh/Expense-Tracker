import { describe, expect, it, afterEach, beforeEach } from 'vitest';
import request from 'supertest';
import { API_PREFIX, makeHarness, uniqueEmail, type Harness } from './helpers.js';

describe('rate limiting', () => {
  let harness: Harness;

  beforeEach(() => {
    harness = makeHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('locks out repeated failed sign-ins for one email', async () => {
    const email = uniqueEmail();

    // The limiter allows 10 attempts per window.
    for (let attempt = 0; attempt < 10; attempt += 1) {
      await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .send({ email, password: 'wrong-password-guess' })
        .expect(401);
    }

    const blocked = await request(harness.app)
      .post(`${API_PREFIX}/auth/signin`)
      .send({ email, password: 'wrong-password-guess' })
      .expect(429);

    expect(blocked.body.error.code).toBe('rate_limited');
    expect(blocked.headers['retry-after']).toBeTruthy();
  });

  it('does not let one email exhaust the budget for another', async () => {
    const victim = uniqueEmail();
    const other = uniqueEmail();

    for (let attempt = 0; attempt < 11; attempt += 1) {
      await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .send({ email: victim, password: 'wrong-password-guess' });
    }

    // Bucketing on IP alone would have locked this out too, which is how a
    // shared NAT turns one attacker into an outage for everyone behind it.
    await request(harness.app)
      .post(`${API_PREFIX}/auth/signin`)
      .send({ email: other, password: 'wrong-password-guess' })
      .expect(401);
  });
});
