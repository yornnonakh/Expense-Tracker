/**
 * Budget rows. Same shape and merge rules as expenses, with one extra
 * constraint: at most one live budget per category per user.
 */

import type { DB } from './index.js';
import { now } from './index.js';
import type { BudgetRecord, MergeOutcome } from '../lib/records.js';
import type { Category } from '../lib/validation.js';

interface BudgetRow {
  id: string;
  user_id: string;
  category: string;
  limit_amount: number;
  created_at: number;
  updated_at: number;
  client_updated_at: number;
  deleted_at: number | null;
}

function toRecord(row: BudgetRow): BudgetRecord {
  return {
    id: row.id,
    category: row.category as Category,
    limit: row.limit_amount,
    createdAt: row.created_at,
    updatedAt: row.client_updated_at,
    deletedAt: row.deleted_at,
  };
}

export function listLive(db: DB, userId: string): BudgetRecord[] {
  const rows = db
    .prepare(
      `SELECT * FROM budgets
       WHERE user_id = ? AND deleted_at IS NULL
       ORDER BY created_at ASC`,
    )
    .all(userId) as BudgetRow[];
  return rows.map(toRecord);
}

export function findById(db: DB, userId: string, id: string): BudgetRecord | undefined {
  const row = db
    .prepare('SELECT * FROM budgets WHERE user_id = ? AND id = ?')
    .get(userId, id) as BudgetRow | undefined;
  return row ? toRecord(row) : undefined;
}

export function findLiveByCategory(
  db: DB,
  userId: string,
  category: string,
): BudgetRecord | undefined {
  const row = db
    .prepare(
      'SELECT * FROM budgets WHERE user_id = ? AND category = ? AND deleted_at IS NULL',
    )
    .get(userId, category) as BudgetRow | undefined;
  return row ? toRecord(row) : undefined;
}

export function listChangedSince(
  db: DB,
  userId: string,
  since: number,
  upTo: number,
): BudgetRecord[] {
  const rows = db
    .prepare(
      `SELECT * FROM budgets
       WHERE user_id = ? AND updated_at > ? AND updated_at <= ?
       ORDER BY updated_at ASC`,
    )
    .all(userId, since, upTo) as BudgetRow[];
  return rows.map(toRecord);
}

/**
 * Same last-write-wins rule as expenses, plus the one-per-category invariant.
 *
 * Two devices can each create a budget for the same category while offline.
 * Both arrive with different ids and neither is "an edit of" the other, so LWW
 * has nothing to compare. The newer one wins and the older is tombstoned,
 * which keeps the unique index satisfiable and leaves the user with the budget
 * they set most recently — the one they are more likely to have meant.
 */
export function mergeFromClient(db: DB, userId: string, incoming: BudgetRecord): MergeOutcome {
  const existing = db
    .prepare('SELECT * FROM budgets WHERE user_id = ? AND id = ?')
    .get(userId, incoming.id) as BudgetRow | undefined;

  const serverTime = now();

  if (existing && incoming.updatedAt <= existing.client_updated_at) {
    return { status: 'conflict', id: incoming.id, server: toRecord(existing) };
  }

  // Only a live incoming row can collide; a tombstone frees the slot.
  if (incoming.deletedAt === null) {
    const rival = db
      .prepare(
        `SELECT * FROM budgets
         WHERE user_id = ? AND category = ? AND deleted_at IS NULL AND id != ?`,
      )
      .get(userId, incoming.category, incoming.id) as BudgetRow | undefined;

    if (rival) {
      if (rival.client_updated_at > incoming.updatedAt) {
        return { status: 'conflict', id: incoming.id, server: toRecord(rival) };
      }
      db.prepare(
        `UPDATE budgets SET deleted_at = ?, updated_at = ?, client_updated_at = ?
         WHERE id = ?`,
      ).run(incoming.updatedAt, serverTime, incoming.updatedAt, rival.id);
    }
  }

  if (!existing) {
    db.prepare(
      `INSERT INTO budgets
         (id, user_id, category, limit_amount, created_at,
          updated_at, client_updated_at, deleted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      incoming.id,
      userId,
      incoming.category,
      incoming.limit,
      incoming.createdAt,
      serverTime,
      incoming.updatedAt,
      incoming.deletedAt,
    );
  } else {
    db.prepare(
      `UPDATE budgets
       SET category = ?, limit_amount = ?, created_at = ?,
           updated_at = ?, client_updated_at = ?, deleted_at = ?
       WHERE user_id = ? AND id = ?`,
    ).run(
      incoming.category,
      incoming.limit,
      incoming.createdAt,
      serverTime,
      incoming.updatedAt,
      incoming.deletedAt,
      userId,
      incoming.id,
    );
  }

  return { status: 'applied', id: incoming.id };
}

export function softDelete(db: DB, userId: string, id: string, clientTime: number): boolean {
  const result = db
    .prepare(
      `UPDATE budgets
       SET deleted_at = ?, updated_at = ?, client_updated_at = ?
       WHERE user_id = ? AND id = ? AND deleted_at IS NULL`,
    )
    .run(clientTime, now(), clientTime, userId, id);
  return result.changes > 0;
}

export type { BudgetRow };
