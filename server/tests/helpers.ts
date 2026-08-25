/**
 * Test fixtures.
 *
 * Every test gets its own `:memory:` database, so tests share no state, can
 * run in parallel, and never leave a file behind. Nothing here touches the
 * real data directory.
 */

import type { Express } from 'express';
import request from 'supertest';
import { createApp, API_PREFIX } from '../src/app.js';
import { openDatabase, type DB } from '../src/db/index.js';
import type { Config } from '../src/lib/config.js';

export const testConfig: Config = {
  port: 0,
  nodeEnv: 'test',
  accessSecret: 'test-access-secret-value-for-unit-tests',
  refreshSecret: 'test-refresh-secret-value-for-unit-tests',
  accessTokenTtl: 900,
  refreshTokenTtl: 2592000,
  databasePath: ':memory:',
  corsOrigin: '*',
};

export interface Harness {
  app: Express;
  db: DB;
  close(): void;
}

export function makeHarness(overrides: Partial<Config> = {}): Harness {
  const config = { ...testConfig, ...overrides };
  const db = openDatabase(':memory:');
  const app = createApp(db, config);
  return { app, db, close: () => db.close() };
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  userId: string;
  email: string;
}

let emailCounter = 0;

/** Unique per call, so rate-limit buckets (keyed on IP+email) never collide. */
export function uniqueEmail(): string {
  emailCounter += 1;
  return `user${emailCounter}.${Date.now()}@example.com`;
}

export async function signUp(
  app: Express,
  overrides: { name?: string; email?: string; password?: string } = {},
): Promise<Session> {
  const email = overrides.email ?? uniqueEmail();
  const response = await request(app)
    .post(`${API_PREFIX}/auth/signup`)
    .send({
      name: overrides.name ?? 'Test User',
      email,
      password: overrides.password ?? 'correct-horse-battery',
    })
    .expect(201);

  return {
    accessToken: response.body.accessToken,
    refreshToken: response.body.refreshToken,
    userId: response.body.user.id,
    email,
  };
}

export function auth(session: Session): [string, string] {
  return ['Authorization', `Bearer ${session.accessToken}`];
}

/** A valid v4 UUID, since the schemas reject anything else. */
export function uuid(): string {
  return crypto.randomUUID();
}

export function makeExpense(overrides: Record<string, unknown> = {}) {
  return {
    id: uuid(),
    amount: 12.5,
    description: 'Lunch',
    category: 'food',
    date: 1_700_000_000,
    updatedAt: Date.now(),
    deletedAt: null,
    ...overrides,
  };
}

export function makeBudget(overrides: Record<string, unknown> = {}) {
  return {
    id: uuid(),
    category: 'food',
    limit: 300,
    createdAt: 1_700_000_000,
    updatedAt: Date.now(),
    deletedAt: null,
    ...overrides,
  };
}

export { API_PREFIX };
