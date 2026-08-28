/**
 * Express app assembly.
 *
 * Split from `server.ts` so tests can build an app against an in-memory
 * database and drive it with supertest, without binding a port or racing
 * another test for one.
 */

import express, { type Express } from 'express';
import cors from 'cors';
import type { DB } from './db/index.js';
import type { Config } from './lib/config.js';
import { authRoutes } from './routes/auth.js';
import { expenseRoutes } from './routes/expenses.js';
import { budgetRoutes } from './routes/budgets.js';
import { syncRoutes } from './routes/sync.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

export const API_PREFIX = '/api/v1';

export function createApp(db: DB, config: Config): Express {
  const app = express();

  // Express advertises itself by default; there is no reason to tell the
  // internet which framework and version to look up exploits for.
  app.disable('x-powered-by');

  // Trust the first proxy hop so `req.ip` is the real client behind a load
  // balancer — the rate limiter buckets on it, and without this every request
  // would share the proxy's address and one bucket.
  app.set('trust proxy', 1);

  app.use(cors({ origin: config.corsOrigin }));

  // 5 MB ceiling: large enough for a base64 avatar plus a full sync batch,
  // small enough that an unauthenticated caller cannot exhaust memory.
  app.use(express.json({ limit: '5mb' }));

  app.use((_req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'no-referrer');
    next();
  });

  // Unauthenticated, and deliberately free of database access, so a health
  // probe stays meaningful when the database is the thing that is unwell.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', time: new Date().toISOString() });
  });

  app.get(`${API_PREFIX}/health`, (_req, res) => {
    let database: 'ok' | 'unavailable' = 'ok';
    try {
      db.prepare('SELECT 1').get();
    } catch {
      database = 'unavailable';
    }
    res.status(database === 'ok' ? 200 : 503).json({
      status: database === 'ok' ? 'ok' : 'degraded',
      database,
      time: new Date().toISOString(),
    });
  });

  app.use(`${API_PREFIX}/auth`, authRoutes(db, config));
  app.use(`${API_PREFIX}/expenses`, expenseRoutes(db, config));
  app.use(`${API_PREFIX}/budgets`, budgetRoutes(db, config));
  app.use(`${API_PREFIX}/sync`, syncRoutes(db, config));

  app.use(notFoundHandler);
  app.use(errorHandler(config.nodeEnv === 'production'));

  return app;
}
