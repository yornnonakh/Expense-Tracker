-- Expense Tracker schema.
--
-- TIME UNITS, stated once because mixing them silently corrupts sync:
--   *_at columns  -> epoch MILLISECONDS (integer). Server-assigned.
--   expenses.date -> epoch SECONDS (real). User-chosen, matches the iOS
--                    on-disk DTO format so the client needs no conversion.
--
-- Every syncable row carries `updated_at` and a nullable `deleted_at`.
-- Deletes are tombstones, never physical removals: a client that was offline
-- during a delete has to learn the row is gone, and a missing row is
-- indistinguishable from a row it has not seen yet.
--
-- TWO CLOCKS, deliberately:
--   updated_at        server clock. The ONLY thing the `?since=` sync cursor
--                     compares against, so a client with a skewed clock can
--                     never make its rows invisible to a pull.
--   client_updated_at originating device's clock. The ONLY thing last-write-
--                     wins compares, because it is the only clock that knows
--                     the order the user actually made the edits in.
-- Collapsing these into one column breaks one of the two properties: a shared
-- server clock loses real edit ordering across devices, and a shared client
-- clock lets a fast device hide rows from every future pull.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id             TEXT PRIMARY KEY,
  name           TEXT    NOT NULL,
  -- Stored lowercased; UNIQUE enforces one account per address.
  email          TEXT    NOT NULL UNIQUE,
  password_hash  TEXT    NOT NULL,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL,
  -- Avatar bytes live in the row rather than on disk: they are small
  -- (downscaled JPEG, capped by the client) and this keeps backup/restore to
  -- a single file with no orphaned-file class of bug.
  avatar_mime    TEXT,
  avatar_data    BLOB
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- SHA-256 of the token, never the token itself: a leaked database must not
  -- hand over usable sessions.
  token_hash  TEXT    NOT NULL UNIQUE,
  expires_at  INTEGER NOT NULL,
  revoked_at  INTEGER,
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);

CREATE TABLE IF NOT EXISTS expenses (
  -- NOT globally unique. Ids are client-generated UUIDs, so a second user
  -- pushing an id that already exists must create their own row rather than
  -- collide: a global primary key turns that into a constraint violation,
  -- which both 500s and confirms to the caller that the id is taken.
  id          TEXT    NOT NULL,
  user_id     TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount      REAL    NOT NULL,
  description TEXT    NOT NULL,
  category    TEXT    NOT NULL,
  date        REAL    NOT NULL,
  updated_at        INTEGER NOT NULL,
  client_updated_at INTEGER NOT NULL,
  deleted_at        INTEGER,
  PRIMARY KEY (user_id, id)
);

-- The sync pull is always "rows for this user changed after T", so the index
-- matches that query exactly.
CREATE INDEX IF NOT EXISTS idx_expenses_user_updated
  ON expenses(user_id, updated_at);

CREATE TABLE IF NOT EXISTS budgets (
  -- Per-user namespace, for the same reason as `expenses.id`.
  id           TEXT    NOT NULL,
  user_id      TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category     TEXT    NOT NULL,
  -- `limit` is a SQL keyword, hence the suffix.
  limit_amount REAL    NOT NULL,
  created_at   REAL    NOT NULL,
  updated_at        INTEGER NOT NULL,
  client_updated_at INTEGER NOT NULL,
  deleted_at        INTEGER,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_budgets_user_updated
  ON budgets(user_id, updated_at);

-- One live budget per category per user. Partial, so a tombstoned budget
-- does not block creating a fresh one for the same category.
CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_user_category_live
  ON budgets(user_id, category) WHERE deleted_at IS NULL;
