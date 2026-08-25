/**
 * User row access.
 *
 * Everything the rest of the server needs to know about a user, with the
 * password hash and avatar blob kept out of the public shape so they cannot be
 * serialised into a response by accident.
 */

import { randomUUID } from 'node:crypto';
import type { DB } from './index.js';
import { now } from './index.js';

/** Safe to send to a client. */
export interface PublicUser {
  id: string;
  name: string;
  email: string;
  /** Epoch millis. */
  createdAt: number;
  hasAvatar: boolean;
}

interface UserRow {
  id: string;
  name: string;
  email: string;
  password_hash: string;
  created_at: number;
  updated_at: number;
  avatar_mime: string | null;
  avatar_data: Buffer | null;
}

function toPublic(row: UserRow): PublicUser {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    createdAt: row.created_at,
    hasAvatar: row.avatar_data !== null,
  };
}

export function createUser(
  db: DB,
  input: { name: string; email: string; passwordHash: string },
): PublicUser {
  const timestamp = now();
  const id = randomUUID();

  db.prepare(
    `INSERT INTO users (id, name, email, password_hash, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(id, input.name, input.email, input.passwordHash, timestamp, timestamp);

  return {
    id,
    name: input.name,
    email: input.email,
    createdAt: timestamp,
    hasAvatar: false,
  };
}

export function findByEmail(db: DB, email: string): UserRow | undefined {
  return db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRow | undefined;
}

export function findById(db: DB, id: string): UserRow | undefined {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id) as UserRow | undefined;
}

export function publicUserById(db: DB, id: string): PublicUser | undefined {
  const row = findById(db, id);
  return row ? toPublic(row) : undefined;
}

export function emailExists(db: DB, email: string): boolean {
  const row = db.prepare('SELECT 1 AS present FROM users WHERE email = ?').get(email);
  return row !== undefined;
}

export function setAvatar(
  db: DB,
  userId: string,
  data: Buffer | null,
  mimeType: string | null,
): void {
  db.prepare('UPDATE users SET avatar_mime = ?, avatar_data = ?, updated_at = ? WHERE id = ?').run(
    data ? mimeType : null,
    data,
    now(),
    userId,
  );
}

export function getAvatar(
  db: DB,
  userId: string,
): { data: Buffer; mimeType: string } | undefined {
  const row = db
    .prepare('SELECT avatar_mime, avatar_data FROM users WHERE id = ?')
    .get(userId) as { avatar_mime: string | null; avatar_data: Buffer | null } | undefined;

  if (!row?.avatar_data) return undefined;
  return { data: row.avatar_data, mimeType: row.avatar_mime ?? 'image/jpeg' };
}

export { toPublic as toPublicUser };
export type { UserRow };
