/**
 * Wire shapes for syncable records — what the client sends and receives.
 *
 * `updatedAt` on the wire is always the ORIGINATING DEVICE's clock, never the
 * server's. A client that pulls a record and pushes it back unchanged sends
 * back the same value, which compares as "not strictly newer" and correctly
 * no-ops. The server's own clock is exposed once per response as `serverTime`
 * and is what the client stores as its next `since` cursor.
 */

import type { Category } from './validation.js';

export interface ExpenseRecord {
  id: string;
  amount: number;
  description: string;
  category: Category;
  /** Epoch seconds — when the money was spent. */
  date: number;
  /** Epoch millis, originating device's clock. */
  updatedAt: number;
  /** Epoch millis when deleted, or null for a live row. */
  deletedAt: number | null;
}

export interface BudgetRecord {
  id: string;
  category: Category;
  limit: number;
  /** Epoch seconds. */
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
}

/** What happened to one pushed record. */
export type MergeOutcome =
  | { status: 'applied'; id: string }
  /** The server's copy was newer; the client should adopt `server`. */
  | { status: 'conflict'; id: string; server: ExpenseRecord | BudgetRecord };

export interface SyncPullResponse {
  /** Epoch millis. The client stores this as its next `since`. */
  serverTime: number;
  expenses: ExpenseRecord[];
  budgets: BudgetRecord[];
}

export interface SyncPushResponse {
  serverTime: number;
  applied: number;
  conflicts: MergeOutcome[];
}
