/**
 * Refresh token storage.
 *
 * Rows hold a SHA-256 of the token, never the token itself, so a database
 * dump cannot be replayed as a set of live sessions.
 */

import { randomUUID } from 'node:crypto';
import type { DB } from './index.js';
import { now } from './index.js';

interface RefreshTokenRow {
  id: string;
  user_id: string;
  token_hash: string;
  expires_at: number;
  revoked_at: number | null;
  created_at: number;
}

export function store(
  db: DB,
  input: { userId: string; tokenHash: string; expiresAt: number },
): void {
  db.prepare(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, revoked_at, created_at)
     VALUES (?, ?, ?, ?, NULL, ?)`,
  ).run(randomUUID(), input.userId, input.tokenHash, input.expiresAt, now());
}

/**
 * Looks up a token that is still usable: it exists, has not been revoked, and
 * has not expired. Anything else returns undefined and reads as "invalid".
 */
export function findUsable(db: DB, tokenHash: string): RefreshTokenRow | undefined {
  return db
    .prepare(
      `SELECT * FROM refresh_tokens
       WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
    )
    .get(tokenHash, now()) as RefreshTokenRow | undefined;
}

export function revoke(db: DB, tokenHash: string): void {
  db.prepare('UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL')
    .run(now(), tokenHash);
}

/**
 * Kills every session for a user.
 *
 * Used on sign-out-everywhere and on detected refresh-token reuse, where the
 * safe assumption is that the token leaked and both parties must re-auth.
 */
export function revokeAllForUser(db: DB, userId: string): void {
  db.prepare('UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL')
    .run(now(), userId);
}

/** Housekeeping: drop rows that can no longer authenticate anything. */
export function purgeExpired(db: DB): number {
  const result = db.prepare('DELETE FROM refresh_tokens WHERE expires_at < ?').run(now());
  return result.changes;
}

export type { RefreshTokenRow };
