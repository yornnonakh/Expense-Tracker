/**
 * `users.setPassword` — the only way an existing account's password moves.
 *
 * There is no self-service password change in the app, and the reset route is
 * deliberately not wired to a mail provider, so an account whose password is
 * forgotten is otherwise unreachable. `scripts/set-password.ts` is the operator
 * tool built on this; these tests cover the part of it that is real code.
 *
 * The end-to-end assertion is what matters: not "the column changed", but
 * "sign-in now accepts the new password and rejects the old one".
 */

import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { API_PREFIX, makeHarness, signUp, type Harness } from './helpers.js';
import * as users from '../src/db/users.js';
import { hashPassword } from '../src/lib/password.js';

describe('users.setPassword', () => {
  let harness: Harness;

  beforeEach(() => {
    harness = makeHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('makes sign-in accept the new password and reject the old one', async () => {
    const original = 'original-password';
    const replacement = 'replacement-password';
    const session = await signUp(harness.app, { password: original });

    users.setPassword(harness.db, session.userId, await hashPassword(replacement));

    await request(harness.app)
      .post(`${API_PREFIX}/auth/signin`)
      .send({ email: session.email, password: replacement })
      .expect(200);

    // The old password must stop working, or rotating it protects nothing.
    await request(harness.app)
      .post(`${API_PREFIX}/auth/signin`)
      .send({ email: session.email, password: original })
      .expect(401);
  });

  it('stores a hash, never the password itself', async () => {
    const session = await signUp(harness.app);

    await users.setPassword(harness.db, session.userId, await hashPassword('plaintext-secret'));

    const row = users.findByEmail(harness.db, session.email);
    expect(row?.password_hash).toBeTruthy();
    expect(row?.password_hash).not.toContain('plaintext-secret');
    expect(row?.password_hash).toMatch(/^\$2[aby]\$/);
  });

  it('leaves other accounts alone', async () => {
    const target = await signUp(harness.app, { password: 'target-password' });
    const bystander = await signUp(harness.app, { password: 'bystander-password' });

    users.setPassword(harness.db, target.userId, await hashPassword('rotated-password'));

    await request(harness.app)
      .post(`${API_PREFIX}/auth/signin`)
      .send({ email: bystander.email, password: 'bystander-password' })
      .expect(200);
  });

  it('does not disturb the account identity', async () => {
    const session = await signUp(harness.app, { name: 'Yorn Nona' });
    const before = users.findByEmail(harness.db, session.email);

    users.setPassword(harness.db, session.userId, await hashPassword('rotated-password'));

    const after = users.findByEmail(harness.db, session.email);
    expect(after?.id).toBe(before?.id);
    expect(after?.name).toBe('Yorn Nona');
    expect(after?.email).toBe(session.email);
    expect(after?.created_at).toBe(before?.created_at);
  });
});
