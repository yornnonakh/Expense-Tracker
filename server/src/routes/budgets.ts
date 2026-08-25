/**
 * Budget REST routes. One live budget per category is enforced in the data
 * layer's merge, so these handlers only translate that into HTTP.
 */

import { Router } from 'express';
import type { DB } from '../db/index.js';
import { now } from '../db/index.js';
import * as budgets from '../db/budgets.js';
import type { Config } from '../lib/config.js';
import { ApiError } from '../lib/errors.js';
import { requireParam } from '../lib/http.js';
import { asyncHandler } from '../lib/asyncHandler.js';
import { authenticate, requireUserId } from '../middleware/authenticate.js';
import { budgetInputSchema, parse } from '../lib/validation.js';

export function budgetRoutes(db: DB, config: Config): Router {
  const router = Router();
  router.use(authenticate(config));

  router.get(
    '/',
    asyncHandler(async (req, res) => {
      res.json({ budgets: budgets.listLive(db, requireUserId(req)) });
    }),
  );

  router.put(
    '/:id',
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const id = requireParam(req, 'id');
      const input = parse(budgetInputSchema, { ...req.body, id });

      const existing = budgets.findLiveByCategory(db, userId, input.category);
      if (existing && existing.id !== id) {
        throw new ApiError(
          'conflict',
          `A budget for ${input.category} already exists. Edit it instead.`,
        );
      }

      const outcome = budgets.mergeFromClient(db, userId, {
        ...input,
        updatedAt: input.updatedAt ?? now(),
        deletedAt: input.deletedAt ?? null,
      });

      if (outcome.status === 'conflict') {
        res.status(409).json({
          error: { code: 'conflict', message: 'A newer version of that budget exists.' },
          budget: outcome.server,
        });
        return;
      }

      res.json({ budget: budgets.findById(db, userId, id) });
    }),
  );

  router.delete(
    '/:id',
    asyncHandler(async (req, res) => {
      const deleted = budgets.softDelete(db, requireUserId(req), requireParam(req, 'id'), now());
      if (!deleted) throw ApiError.notFound('That budget no longer exists.');
      res.status(204).send();
    }),
  );

  return router;
}
