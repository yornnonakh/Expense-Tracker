import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { API_PREFIX, makeHarness, signUp, uniqueEmail, type Harness } from './helpers.js';

describe('auth', () => {
  let harness: Harness;

  beforeEach(() => {
    harness = makeHarness();
  });

  afterEach(() => {
    harness.close();
  });

  describe('signup', () => {
    it('creates an account and returns a usable session', async () => {
      const email = uniqueEmail();
      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signup`)
        .send({ name: 'Yorn Nona', email, password: 'correct-horse-battery' })
        .expect(201);

      expect(response.body.user).toMatchObject({ name: 'Yorn Nona', email, hasAvatar: false });
      expect(response.body.accessToken).toBeTruthy();
      expect(response.body.refreshToken).toBeTruthy();
      expect(response.body.expiresIn).toBe(900);

      // The access token must actually authenticate, not merely exist.
      await request(harness.app)
        .get(`${API_PREFIX}/auth/me`)
        .set('Authorization', `Bearer ${response.body.accessToken}`)
        .expect(200);
    });

    it('never returns the password hash', async () => {
      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signup`)
        .send({ name: 'A', email: uniqueEmail(), password: 'correct-horse-battery' })
        .expect(201);

      const serialized = JSON.stringify(response.body);
      expect(serialized).not.toContain('password');
      expect(serialized).not.toContain('$2a$');
    });

    it('normalizes the email to lowercase', async () => {
      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signup`)
        .send({ name: 'A', email: 'MiXeD.CaSe@Example.COM', password: 'correct-horse-battery' })
        .expect(201);

      expect(response.body.user.email).toBe('mixed.case@example.com');
    });

    it('rejects a duplicate email regardless of casing', async () => {
      const email = uniqueEmail();
      await signUp(harness.app, { email });

      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signup`)
        .send({ name: 'B', email: email.toUpperCase(), password: 'correct-horse-battery' })
        .expect(409);

      expect(response.body.error.code).toBe('email_already_registered');
    });

    it.each([
      ['missing name', { name: '', email: uniqueEmail(), password: 'correct-horse-battery' }],
      ['bad email', { name: 'A', email: 'not-an-email', password: 'correct-horse-battery' }],
      ['short password', { name: 'A', email: uniqueEmail(), password: 'short' }],
    ])('rejects %s', async (_label, body) => {
      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signup`)
        .send(body)
        .expect(422);
      expect(response.body.error.code).toBe('validation_failed');
    });
  });

  describe('signin', () => {
    it('returns a session for correct credentials', async () => {
      const email = uniqueEmail();
      await signUp(harness.app, { email, password: 'correct-horse-battery' });

      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .send({ email, password: 'correct-horse-battery' })
        .expect(200);

      expect(response.body.accessToken).toBeTruthy();
    });

    it('gives the same error for a wrong password and an unknown account', async () => {
      const email = uniqueEmail();
      await signUp(harness.app, { email, password: 'correct-horse-battery' });

      const wrongPassword = await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .send({ email, password: 'wrong-password-entirely' })
        .expect(401);

      const noAccount = await request(harness.app)
        .post(`${API_PREFIX}/auth/signin`)
        .send({ email: uniqueEmail(), password: 'correct-horse-battery' })
        .expect(401);

      // Identical code AND identical copy: a difference in either one
      // enumerates which addresses are registered.
      expect(wrongPassword.body.error.code).toBe('invalid_credentials');
      expect(noAccount.body.error.code).toBe('invalid_credentials');
      expect(noAccount.body.error.message).toBe(wrongPassword.body.error.message);
    });
  });

  describe('refresh', () => {
    it('exchanges a refresh token for a new session', async () => {
      const session = await signUp(harness.app);

      const response = await request(harness.app)
        .post(`${API_PREFIX}/auth/refresh`)
        .send({ refreshToken: session.refreshToken })
        .expect(200);

      expect(response.body.accessToken).toBeTruthy();
      expect(response.body.refreshToken).not.toBe(session.refreshToken);
      expect(response.body.user.id).toBe(session.userId);
    });

    it('refuses to reuse a rotated refresh token', async () => {
      const session = await signUp(harness.app);

      await request(harness.app)
        .post(`${API_PREFIX}/auth/refresh`)
        .send({ refreshToken: session.refreshToken })
        .expect(200);

      // Second use of the same token must fail — this is what makes a stolen
      // refresh token a detectable event rather than permanent access.
      const replay = await request(harness.app)
        .post(`${API_PREFIX}/auth/refresh`)
        .send({ refreshToken: session.refreshToken })
        .expect(401);

      expect(replay.body.error.code).toBe('unauthorized');
    });

    it('rejects a garbage refresh token', async () => {
      await request(harness.app)
        .post(`${API_PREFIX}/auth/refresh`)
        .send({ refreshToken: 'not-a-real-token' })
        .expect(401);
    });
  });

  describe('signout', () => {
    it('invalidates the refresh token', async () => {
      const session = await signUp(harness.app);

      await request(harness.app)
        .post(`${API_PREFIX}/auth/signout`)
        .send({ refreshToken: session.refreshToken })
        .expect(204);

      await request(harness.app)
        .post(`${API_PREFIX}/auth/refresh`)
        .send({ refreshToken: session.refreshToken })
        .expect(401);
    });
  });

  describe('password reset', () => {
    it('responds identically whether or not the account exists', async () => {
      const email = uniqueEmail();
      await signUp(harness.app, { email });

      const known = await request(harness.app)
        .post(`${API_PREFIX}/auth/password-reset`)
        .send({ email })
        .expect(202);

      const unknown = await request(harness.app)
        .post(`${API_PREFIX}/auth/password-reset`)
        .send({ email: uniqueEmail() })
        .expect(202);

      expect(known.body).toEqual(unknown.body);
    });
  });

  describe('token enforcement', () => {
    it('rejects a request with no token', async () => {
      const response = await request(harness.app).get(`${API_PREFIX}/auth/me`).expect(401);
      expect(response.body.error.code).toBe('unauthorized');
    });

    it('rejects a token signed with the wrong secret', async () => {
      const attacker = makeHarness({ accessSecret: 'a-completely-different-secret-value' });
      const session = await signUp(attacker.app);

      await request(harness.app)
        .get(`${API_PREFIX}/auth/me`)
        .set('Authorization', `Bearer ${session.accessToken}`)
        .expect(401);

      attacker.close();
    });

    it('reports an expired access token distinctly so the client refreshes', async () => {
      const shortLived = makeHarness({ accessTokenTtl: 1 });
      const session = await signUp(shortLived.app);

      await new Promise((resolve) => setTimeout(resolve, 1500));

      const response = await request(shortLived.app)
        .get(`${API_PREFIX}/auth/me`)
        .set('Authorization', `Bearer ${session.accessToken}`)
        .expect(401);

      // Distinct from `unauthorized`: the client should refresh, not sign out.
      expect(response.body.error.code).toBe('token_expired');
      shortLived.close();
    });
  });
});
