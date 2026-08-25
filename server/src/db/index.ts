/**
 * Database handle and schema bootstrap.
 *
 * better-sqlite3 is synchronous by design. That is a good fit here: SQLite
 * calls are microseconds against a local file, and synchronous access removes
 * a whole class of interleaving bug from the sync endpoint, where a pull and
 * a push must not observe each other half-applied.
 */

import Database from 'better-sqlite3';
import { readFileSync } from 'node:fs';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export type DB = Database.Database;

const HERE = dirname(fileURLToPath(import.meta.url));

/**
 * Opens (or creates) the database and applies the schema.
 *
 * @param path filesystem path, or ':memory:' for an isolated test database.
 */
export function openDatabase(path: string): DB {
  if (path !== ':memory:') {
    // A fresh checkout has no data/ directory; creating it here means the
    // server starts with no manual setup step.
    mkdirSync(dirname(path), { recursive: true });
  }

  const db = new Database(path);

  // WAL lets reads proceed during a write. Not supported for :memory:, where
  // there is a single connection anyway.
  if (path !== ':memory:') {
    db.pragma('journal_mode = WAL');
  }
  db.pragma('foreign_keys = ON');

  // Fail a busy write after 5s rather than hanging the request forever.
  db.pragma('busy_timeout = 5000');

  applySchema(db);
  return db;
}

function applySchema(db: DB): void {
  // Resolved relative to this module so it works from src/ under tsx and
  // from dist/ after a build (the file is copied by the build script).
  const schemaPath = join(HERE, 'schema.sql');
  const sql = readFileSync(schemaPath, 'utf8');
  db.exec(sql);
}

/** Epoch milliseconds. Every server-assigned timestamp goes through here. */
export function now(): number {
  return Date.now();
}
