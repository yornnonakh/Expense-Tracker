/**
 * Request validation.
 *
 * These rules are the authority. The iOS client validates the same fields for
 * fast inline feedback, but a client is only a convenience — anything that
 * reaches the database has to pass through here first.
 *
 * Limits are kept numerically identical to the client's (`ExpenseValidator`,
 * `AuthValidator`) so a value the form accepts is never rejected by the server.
 */

import { z } from 'zod';
import { ApiError } from './errors.js';
import { MAX_PASSWORD_BYTES, MIN_PASSWORD_LENGTH } from './password.js';

/** Mirrors `ExpenseCategory` in the iOS domain layer. */
export const CATEGORIES = [
  'food',
  'transport',
  'entertainment',
  'utilities',
  'shopping',
  'health',
  'other',
] as const;

export type Category = (typeof CATEGORIES)[number];

export const DESCRIPTION_LIMIT = 120;
export const MAX_AMOUNT = 1_000_000_000;

/** Downscaled JPEG from the client; anything larger is a misuse of the field. */
export const MAX_AVATAR_BYTES = 2 * 1024 * 1024;

const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  // Same permissive shape as the client: something@something.tld, no spaces.
  .regex(/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/, 'Enter a valid email address.')
  .max(254, 'Email address is too long.');

const passwordSchema = z
  .string()
  .min(MIN_PASSWORD_LENGTH, `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`)
  .refine(
    (value) => Buffer.byteLength(value, 'utf8') <= MAX_PASSWORD_BYTES,
    `Password must be at most ${MAX_PASSWORD_BYTES} bytes.`,
  );

const amountSchema = z
  .number()
  .finite('Amount must be a number.')
  .positive('Enter an amount greater than 0.')
  .max(MAX_AMOUNT, 'That amount is too large to record.');

/** Epoch seconds, as a float. Matches the iOS on-disk representation. */
const epochSecondsSchema = z.number().finite();

/** Epoch milliseconds, as an integer. */
const epochMillisSchema = z.number().int().nonnegative();

export const signUpSchema = z.object({
  name: z.string().trim().min(1, 'Enter your name.').max(100, 'Name is too long.'),
  email: emailSchema,
  password: passwordSchema,
});

export const signInSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, 'Enter your password.'),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1, 'Missing refresh token.'),
});

export const passwordResetSchema = z.object({
  email: emailSchema,
});

export const avatarSchema = z.object({
  /** Base64-encoded JPEG bytes. */
  imageBase64: z.string().min(1, 'Missing image data.'),
  mimeType: z.enum(['image/jpeg', 'image/png']).default('image/jpeg'),
});

/** A syncable expense as the client sends it. */
export const expenseInputSchema = z.object({
  id: z.string().uuid('Expense id must be a UUID.'),
  amount: amountSchema,
  description: z
    .string()
    .trim()
    .min(1, 'Add a short description.')
    .max(DESCRIPTION_LIMIT, `Keep the description under ${DESCRIPTION_LIMIT} characters.`),
  category: z.enum(CATEGORIES),
  date: epochSecondsSchema,
  /**
   * Client's clock when it made the change. Advisory only — the server stamps
   * its own `updatedAt` on write, because trusting a client clock lets a
   * device with a fast clock win every conflict forever.
   */
  updatedAt: epochMillisSchema.optional(),
  /** Present and non-null means "this row is deleted". */
  deletedAt: epochMillisSchema.nullable().optional(),
});

export const budgetInputSchema = z.object({
  id: z.string().uuid('Budget id must be a UUID.'),
  category: z.enum(CATEGORIES),
  limit: amountSchema,
  createdAt: epochSecondsSchema,
  updatedAt: epochMillisSchema.optional(),
  deletedAt: epochMillisSchema.nullable().optional(),
});

export const syncPushSchema = z.object({
  expenses: z.array(expenseInputSchema).max(1000, 'Too many expenses in one batch.').default([]),
  budgets: z.array(budgetInputSchema).max(200, 'Too many budgets in one batch.').default([]),
});

export const syncPullQuerySchema = z.object({
  /** Epoch millis. Omitted or 0 means "send me everything". */
  since: z.coerce.number().int().nonnegative().default(0),
});

/**
 * Runs a schema and converts a Zod failure into the API's error shape.
 *
 * Returns the parsed value with its inferred type, so callers get full type
 * safety downstream without re-checking anything.
 */
export function parse<T extends z.ZodTypeAny>(schema: T, input: unknown): z.infer<T> {
  const result = schema.safeParse(input);
  if (result.success) return result.data;

  const issues = result.error.issues.map((issue) => ({
    field: issue.path.join('.') || '(root)',
    message: issue.message,
  }));

  // The first issue is the user-facing message; the rest ride along in
  // `details` for debugging without making the toast unreadable.
  throw ApiError.validation(issues[0]?.message ?? 'Invalid request.', issues);
}
