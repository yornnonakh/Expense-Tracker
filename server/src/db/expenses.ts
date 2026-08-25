/**
 * Expense rows: REST CRUD plus the sync merge.
 *
 * Every query is scoped by `user_id`. That scoping is the entire authorization
 * model for this table — there is no code path that reads an expense without
 * naming whose it is, so one user cannot address another's rows even by
 * guessing a UUID.
 */

import type { DB } from './index.js';
import { now } from './index.js';
import type { ExpenseRecord, MergeOutcome } from '../lib/records.js';
import type { Category } from '../lib/validation.js';

interface ExpenseRow {
  id: string;
  user_id: string;
  amount: number;
  description: string;
  category: string;
  date: number;
  updated_at: number;
  client_updated_at: number;
  deleted_at: number | null;
}

function toRecord(row: ExpenseRow): ExpenseRecord {
  return {
    id: row.id,
    amount: row.amount,
    description: row.description,
    category: row.category as Category,
    date: row.date,
    updatedAt: row.client_updated_at,
    deletedAt: row.deleted_at,
  };
}

/** Live rows only, newest spend first. Backs `GET /expenses`. */
export function listLive(db: DB, userId: string): ExpenseRecord[] {
  const rows = db
    .prepare(
      `SELECT * FROM expenses
       WHERE user_id = ? AND deleted_at IS NULL
       ORDER BY date DESC, id DESC`,
    )
    .all(userId) as ExpenseRow[];
  return rows.map(toRecord);
}

export function findById(db: DB, userId: string, id: string): ExpenseRecord | undefined {
  const row = db
    .prepare('SELECT * FROM expenses WHERE user_id = ? AND id = ?')
    .get(userId, id) as ExpenseRow | undefined;
  return row ? toRecord(row) : undefined;
}

/**
 * Rows changed since `since`, tombstones included.
 *
 * Bounded above by `upTo` so a row written while the response is being built
 * is not skipped: without the bound it could land after the query yet before
 * the client stores `serverTime`, and never appear in any future pull.
 */
export function listChangedSince(
  db: DB,
  userId: string,
  since: number,
  upTo: number,
): ExpenseRecord[] {
  const rows = db
    .prepare(
      `SELECT * FROM expenses
       WHERE user_id = ? AND updated_at > ? AND updated_at <= ?
       ORDER BY updated_at ASC`,
    )
    .all(userId, since, upTo) as ExpenseRow[];
  return rows.map(toRecord);
}

/**
 * Applies one client record, last-write-wins on the client clock.
 *
 * New rows always insert. Existing rows only change when the incoming edit is
 * strictly newer than the stored one; an equal timestamp is treated as the
 * same edit arriving twice, which makes a retried push idempotent rather than
 * a source of flapping.
 */
export function mergeFromClient(
  db: DB,
  userId: string,
  incoming: ExpenseRecord,
): MergeOutcome {
  const existing = db
    .prepare('SELECT * FROM expenses WHERE user_id = ? AND id = ?')
    .get(userId, incoming.id) as ExpenseRow | undefined;

  const serverTime = now();

  if (!existing) {
    db.prepare(
      `INSERT INTO expenses
         (id, user_id, amount, description, category, date,
          updated_at, client_updated_at, deleted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      incoming.id,
      userId,
      incoming.amount,
      incoming.description,
      incoming.category,
      incoming.date,
      serverTime,
      incoming.updatedAt,
      incoming.deletedAt,
    );
    return { status: 'applied', id: incoming.id };
  }

  if (incoming.updatedAt <= existing.client_updated_at) {
    // Server's copy is newer (or identical). Hand back what we hold so the
    // client can settle on it without a second round trip.
    return { status: 'conflict', id: incoming.id, server: toRecord(existing) };
  }

  db.prepare(
    `UPDATE expenses
     SET amount = ?, description = ?, category = ?, date = ?,
         updated_at = ?, client_updated_at = ?, deleted_at = ?
     WHERE user_id = ? AND id = ?`,
  ).run(
    incoming.amount,
    incoming.description,
    incoming.category,
    incoming.date,
    serverTime,
    incoming.updatedAt,
    incoming.deletedAt,
    userId,
    incoming.id,
  );

  return { status: 'applied', id: incoming.id };
}

/** Tombstones a row. Returns false when there was nothing live to delete. */
export function softDelete(db: DB, userId: string, id: string, clientTime: number): boolean {
  const result = db
    .prepare(
      `UPDATE expenses
       SET deleted_at = ?, updated_at = ?, client_updated_at = ?
       WHERE user_id = ? AND id = ? AND deleted_at IS NULL`,
    )
    .run(clientTime, now(), clientTime, userId, id);
  return result.changes > 0;
}

export type { ExpenseRow };
