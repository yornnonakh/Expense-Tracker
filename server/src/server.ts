/**
 * Process entry point: load config, open the database, listen, and shut down
 * cleanly.
 */

import { createApp } from './app.js';
import { openDatabase } from './db/index.js';
import { loadConfig } from './lib/config.js';
import { logger } from './lib/logger.js';
import { purgeExpired } from './db/refreshTokens.js';

const config = loadConfig();
const db = openDatabase(config.databasePath);

// Expired refresh tokens can never authenticate anything; clearing them at
// boot keeps the table from growing without bound in a long-lived deployment.
const purged = purgeExpired(db);
if (purged > 0) logger.info('purged expired refresh tokens', { count: purged });

const app = createApp(db, config);

const server = app.listen(config.port, () => {
  logger.info('server listening', {
    port: config.port,
    env: config.nodeEnv,
    database: config.databasePath,
  });
});

/**
 * Finish in-flight requests before exiting, then close the database so WAL
 * state is checkpointed rather than left for recovery on next boot.
 */
function shutdown(signal: string): void {
  logger.info('shutting down', { signal });

  server.close(() => {
    db.close();
    process.exit(0);
  });

  // A stuck connection must not hold the process open forever.
  setTimeout(() => {
    logger.warn('forced shutdown after timeout');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  logger.error('unhandled rejection', { reason: String(reason) });
});
