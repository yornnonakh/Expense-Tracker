/**
 * Sets an existing account's password.
 *
 * The app has no self-service password change, and `POST /auth/password-reset`
 * is deliberately not wired to a mail provider — it logs and returns 202, so no
 * reset link is ever delivered. Without this script an account whose password
 * is forgotten is unreachable, and the only recourse is deleting the row and
 * losing the data hanging off it.
 *
 *   npm run set-password -- <email> <password>
 *
 * Operator tooling, not an endpoint: it needs filesystem access to the
 * database, so it grants nothing to anyone who does not already have the box.
 */

import { loadConfig } from '../src/lib/config.js';
import { openDatabase } from '../src/db/index.js';
import * as users from '../src/db/users.js';
import { hashPassword } from '../src/lib/password.js';
import { emailSchema, passwordSchema } from '../src/lib/validation.js';

const USAGE = 'Usage: npm run set-password -- <email> <password>';

async function main(): Promise<void> {
  const [rawEmail, rawPassword, ...rest] = process.argv.slice(2);

  if (!rawEmail || !rawPassword || rest.length > 0) {
    throw new Error(USAGE);
  }

  // The API's own schemas, so a password this accepts is one sign-in accepts,
  // and the email is normalised the same way the row was written.
  const email = emailSchema.parse(rawEmail);
  const password = passwordSchema.parse(rawPassword);

  const config = loadConfig();
  const db = openDatabase(config.databasePath);

  try {
    const existing = users.findByEmail(db, email);
    if (!existing) {
      // Safe to be specific: this is a local operator tool, not a response
      // that could be used to enumerate registered addresses.
      throw new Error(`No account found for ${email}.`);
    }

    users.setPassword(db, existing.id, await hashPassword(password));
    console.log(`Password updated for ${email}.`);
  } finally {
    db.close();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
