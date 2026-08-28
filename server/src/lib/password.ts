/**
 * Password hashing.
 *
 * bcrypt with a work factor of 12: deliberately slow, so an attacker holding
 * a dumped `users` table cannot test candidate passwords at speed. bcryptjs is
 * the pure-JS build, chosen so `npm install` never needs a native toolchain.
 */

import bcrypt from 'bcryptjs';

const WORK_FACTOR = 12;

/**
 * bcrypt silently truncates at 72 bytes, so a longer password would have its
 * tail ignored. Rejecting is honest; truncating is a security surprise.
 */
export const MAX_PASSWORD_BYTES = 72;
export const MIN_PASSWORD_LENGTH = 8;

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, WORK_FACTOR);
}

/**
 * Verifies a password. bcrypt's compare is constant-time with respect to the
 * digest, so it does not leak how much of a guess was correct.
 */
export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  try {
    return await bcrypt.compare(plain, hash);
  } catch {
    // A malformed hash in the database must read as "wrong password", never
    // as a crash that reveals the row exists.
    return false;
  }
}

/**
 * Burns roughly the same time as a real verification.
 *
 * Called on the "no such account" path so sign-in takes the same wall-clock
 * time whether or not the email is registered — otherwise response latency
 * alone enumerates which addresses have accounts.
 */
export async function dummyVerify(): Promise<void> {
  await bcrypt.compare(
    'dummy-password-for-timing',
    '$2a$12$C6UzMDM.H6dfI/f/IKcEe.aX3fJ0dHOHYnyBMEBLQvQnl8YZq6uJK',
  );
}
