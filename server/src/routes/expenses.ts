/**
 * Expense REST routes.
 *
 * The iOS client drives most traffic through `/sync`, but these exist so the
 * API is usable on its own terms — by a web client, a script, or curl during
 * debugging — without having to understand the sync protocol.
 */

import { Router } from 'express';
import type { DB } from '../db/index.js';
import { now } from '../db/index.js';
import * as expenses from '../db/expenses.js';
import type { Config } from '../lib/config.js';
import { ApiError } from '../lib/errors.js';
import { requireParam } from '../lib/http.js';
import { asyncHandler } from '../lib/asyncHandler.js';
import { authenticate, requireUserId } from '../middleware/authenticate.js';
import { expenseInputSchema, parse } from '../lib/validation.js';

export function expenseRoutes(db: DB, config: Config): Router {
  const router = Router();
  router.use(authenticate(config));

  router.get(
    '/',
    asyncHandler(async (req, res) => {
      res.json({ expenses: expenses.listLive(db, requireUserId(req)) });
    }),
  );

  router.get(
    '/:id',
    asyncHandler(async (req, res) => {
      const record = expenses.findById(db, requireUserId(req), requireParam(req, 'id'));
      // A tombstone is "gone" to a REST caller; only sync needs to see it.
      if (!record || record.deletedAt !== null) {
        throw ApiError.notFound('That expense no longer exists.');
      }
      res.json({ expense: record });
    }),
  );

  router.post(
    '/',
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const input = parse(expenseInputSchema, req.body);

      if (expenses.findById(db, userId, input.id)) {
        throw new ApiError('conflict', 'An expense with that id already exists.');
      }

      const outcome = expenses.mergeFromClient(db, userId, {
        ...input,
        updatedAt: input.updatedAt ?? now(),
        deletedAt: input.deletedAt ?? null,
      });

      if (outcome.status === 'conflict') {
        throw new ApiError('conflict', 'A newer version of that expense exists.');
      }

      const created = expenses.findById(db, userId, input.id);
      res.status(201).json({ expense: created });
    }),
  );

  router.put(
    '/:id',
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const id = requireParam(req, 'id');

      // The path is authoritative; a mismatched body id is a client bug worth
      // surfacing rather than silently resolving one way or the other.
      const input = parse(expenseInputSchema, { ...req.body, id });

      if (!expenses.findById(db, userId, id)) {
        throw ApiError.notFound('That expense no longer exists.');
      }

      const outcome = expenses.mergeFromClient(db, userId, {
        ...input,
        updatedAt: input.updatedAt ?? now(),
        deletedAt: input.deletedAt ?? null,
      });

      if (outcome.status === 'conflict') {
        res.status(409).json({
          error: { code: 'conflict', message: 'A newer version of that expense exists.' },
          expense: outcome.server,
        });
        return;
      }

      res.json({ expense: expenses.findById(db, userId, id) });
    }),
  );

  router.delete(
    '/:id',
    asyncHandler(async (req, res) => {
      const deleted = expenses.softDelete(db, requireUserId(req), requireParam(req, 'id'), now());
      if (!deleted) throw ApiError.notFound('That expense no longer exists.');
      res.status(204).send();
    }),
  );

  return router;
}
