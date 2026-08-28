/**
 * Seeds the demo account the sign-in screen advertises.
 *
 * `SignInViewModel.fillDemoCredentials()` fills the form with
 * demo@expensetracker.app / demo1234, but nothing ever created that account —
 * the shortcut 401'd on every fresh database. This closes that gap in a way
 * that survives `rm -rf data/`, rather than a one-off INSERT nobody can repeat.
 *
 * Idempotent: re-running resets the demo password rather than failing on the
 * UNIQUE constraint, so it is safe to wire into a setup step.
 *
 *   npm run seed
 */

import { loadConfig } from '../src/lib/config.js';
import { openDatabase } from '../src/db/index.js';
import * as users from '../src/db/users.js';
import { hashPassword } from '../src/lib/password.js';
import { emailSchema, passwordSchema } from '../src/lib/validation.js';

/** Kept in step with `SignInViewModel.fillDemoCredentials()`. */
const DEMO_NAME = 'Demo User';
const DEMO_EMAIL = 'demo@expensetracker.app';
const DEMO_PASSWORD = 'demo1234';

async function main(): Promise<void> {
  // Through the same schemas the API uses, so the row cannot be stored in a
  // shape sign-in would then normalise differently and fail to find.
  const email = emailSchema.parse(DEMO_EMAIL);
  const password = passwordSchema.parse(DEMO_PASSWORD);

  const config = loadConfig();
  const db = openDatabase(config.databasePath);

  try {
    const passwordHash = await hashPassword(password);
    const existing = users.findByEmail(db, email);

    if (existing) {
      users.setPassword(db, existing.id, passwordHash);
      console.log(`Demo account already present; password reset. (${email})`);
    } else {
      users.createUser(db, { name: DEMO_NAME, email, passwordHash });
      console.log(`Demo account created. (${email})`);
    }

    console.log(`Sign in with ${email} / ${DEMO_PASSWORD}`);
  } finally {
    db.close();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
