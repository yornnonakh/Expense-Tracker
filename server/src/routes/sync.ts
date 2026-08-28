/**
 * The sync protocol.
 *
 *   GET  /sync?since=<epochMillis>   pull changes (tombstones included)
 *   POST /sync                       push a batch, and optionally pull in the
 *                                    same round trip by passing `since`
 *
 * PULL CONTRACT
 * `since` is a server-clock watermark, never a client clock. The client stores
 * whatever `serverTime` the previous response carried and sends it back
 * verbatim; it never computes a watermark itself. A device with a wrong clock
 * therefore still receives every change exactly once.
 *
 * Deleted rows come back as tombstones rather than being omitted. An omitted
 * row is ambiguous — "deleted" and "never existed" look identical — and a
 * client that guessed wrong would resurrect deleted expenses on every sync.
 *
 * PUSH CONTRACT
 * The batch is applied in a single transaction: a partially applied push would
 * leave the client's outbox unable to tell which records it still owes.
 * Records the server holds a newer copy of come back under `conflicts`, with
 * the server's version attached so the client can settle without a second
 * round trip.
 */

import { Router } from 'express';
import type { DB } from '../db/index.js';
import { now } from '../db/index.js';
import * as expenses from '../db/expenses.js';
import * as budgets from '../db/budgets.js';
import type { Config } from '../lib/config.js';
import { asyncHandler } from '../lib/asyncHandler.js';
import { logger } from '../lib/logger.js';
import { authenticate, requireUserId } from '../middleware/authenticate.js';
import { parse, syncPullQuerySchema, syncPushSchema } from '../lib/validation.js';
import type { MergeOutcome } from '../lib/records.js';

export function syncRoutes(db: DB, config: Config): Router {
  const router = Router();
  router.use(authenticate(config));

  router.get(
    '/',
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const { since } = parse(syncPullQuerySchema, req.query);

      // Fix the upper bound before querying. Rows written between the two
      // table reads would otherwise fall in a gap: after the expense query ran
      // but before the client adopts `serverTime`, making them invisible to
      // this pull and to every later one.
      const serverTime = now();

      res.json({
        serverTime,
        expenses: expenses.listChangedSince(db, userId, since, serverTime),
        budgets: budgets.listChangedSince(db, userId, since, serverTime),
      });
    }),
  );

  router.post(
    '/',
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const body = parse(syncPushSchema, req.body);

      // `since` is optional on push. Present means "and give me everything I
      // have not seen", which collapses a sync cycle into one request.
      const since =
        typeof req.body?.since === 'number'
          ? parse(syncPullQuerySchema, { since: req.body.since }).since
          : null;

      const conflicts: MergeOutcome[] = [];
      let applied = 0;

      // better-sqlite3 transactions are synchronous, so the whole batch either
      // lands or none of it does — no await can interleave inside.
      const applyBatch = db.transaction(() => {
        for (const record of body.expenses) {
          const outcome = expenses.mergeFromClient(db, userId, {
            ...record,
            updatedAt: record.updatedAt ?? now(),
            deletedAt: record.deletedAt ?? null,
          });
          if (outcome.status === 'applied') applied += 1;
          else conflicts.push(outcome);
        }

        for (const record of body.budgets) {
          const outcome = budgets.mergeFromClient(db, userId, {
            ...record,
            updatedAt: record.updatedAt ?? now(),
            deletedAt: record.deletedAt ?? null,
          });
          if (outcome.status === 'applied') applied += 1;
          else conflicts.push(outcome);
        }
      });

      applyBatch();

      const serverTime = now();

      logger.info('sync push', {
        userId,
        expenses: body.expenses.length,
        budgets: body.budgets.length,
        applied,
        conflicts: conflicts.length,
      });

      const response: Record<string, unknown> = { serverTime, applied, conflicts };

      if (since !== null) {
        response.expenses = expenses.listChangedSince(db, userId, since, serverTime);
        response.budgets = budgets.listChangedSince(db, userId, since, serverTime);
      }

      res.json(response);
    }),
  );

  return router;
}
