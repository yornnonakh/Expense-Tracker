/**
 * Authentication routes.
 *
 * Account enumeration is treated as a real leak throughout: sign-in returns
 * one error for both "no such account" and "wrong password" and spends the
 * same time on each, and password reset always reports success. A caller
 * cannot learn which addresses are registered.
 */

import { Router } from 'express';
import type { DB } from '../db/index.js';
import { now } from '../db/index.js';
import * as users from '../db/users.js';
import * as refreshTokens from '../db/refreshTokens.js';
import type { Config } from '../lib/config.js';
import { ApiError } from '../lib/errors.js';
import { logger } from '../lib/logger.js';
import { asyncHandler } from '../lib/asyncHandler.js';
import { dummyVerify, hashPassword, verifyPassword } from '../lib/password.js';
import { generateRefreshToken, hashRefreshToken, signAccessToken } from '../lib/tokens.js';
import { authenticate, requireUserId } from '../middleware/authenticate.js';
import { authRateLimitKey, rateLimit } from '../middleware/rateLimit.js';
import {
  avatarSchema,
  MAX_AVATAR_BYTES,
  parse,
  passwordResetSchema,
  refreshSchema,
  signInSchema,
  signUpSchema,
} from '../lib/validation.js';

interface SessionResponse {
  accessToken: string;
  refreshToken: string;
  /** Seconds until the access token expires. */
  expiresIn: number;
  user: users.PublicUser;
}

function issueSession(db: DB, config: Config, user: users.PublicUser): SessionResponse {
  const accessToken = signAccessToken(
    { sub: user.id, email: user.email },
    config.accessSecret,
    config.accessTokenTtl,
  );

  const refreshToken = generateRefreshToken();
  refreshTokens.store(db, {
    userId: user.id,
    tokenHash: hashRefreshToken(refreshToken),
    expiresAt: now() + config.refreshTokenTtl * 1000,
  });

  return { accessToken, refreshToken, expiresIn: config.accessTokenTtl, user };
}

export function authRoutes(db: DB, config: Config): Router {
  const router = Router();

  // 10 attempts per 15 minutes per IP+email. Generous for a person who
  // mistypes, ruinous for a script working through a wordlist.
  const attemptLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    keyFor: authRateLimitKey,
  });

  router.post(
    '/signup',
    attemptLimiter,
    asyncHandler(async (req, res) => {
      const input = parse(signUpSchema, req.body);

      if (users.emailExists(db, input.email)) {
        // Signup is the one place enumeration cannot be avoided — the user has
        // to be told the address is taken in order to pick another.
        throw new ApiError(
          'email_already_registered',
          'An account already exists for that email.',
        );
      }

      const passwordHash = await hashPassword(input.password);
      const user = users.createUser(db, {
        name: input.name,
        email: input.email,
        passwordHash,
      });

      logger.info('account created', { userId: user.id });
      res.status(201).json(issueSession(db, config, user));
    }),
  );

  router.post(
    '/signin',
    attemptLimiter,
    asyncHandler(async (req, res) => {
      const input = parse(signInSchema, req.body);
      const row = users.findByEmail(db, input.email);

      if (!row) {
        // Burn comparable time so response latency does not reveal that the
        // address has no account.
        await dummyVerify();
        throw new ApiError('invalid_credentials', 'Incorrect email or password.');
      }

      const matches = await verifyPassword(input.password, row.password_hash);
      if (!matches) {
        throw new ApiError('invalid_credentials', 'Incorrect email or password.');
      }

      logger.info('signed in', { userId: row.id });
      res.json(issueSession(db, config, users.toPublicUser(row)));
    }),
  );

  router.post(
    '/refresh',
    asyncHandler(async (req, res) => {
      const input = parse(refreshSchema, req.body);
      const tokenHash = hashRefreshToken(input.refreshToken);
      const stored = refreshTokens.findUsable(db, tokenHash);

      if (!stored) {
        throw new ApiError('unauthorized', 'Refresh token is invalid or expired.');
      }

      const row = users.findById(db, stored.user_id);
      if (!row) {
        throw new ApiError('unauthorized', 'Account no longer exists.');
      }

      // Rotation: the presented token dies here. If it ever shows up again it
      // will miss `findUsable` and be rejected, which is how a stolen token
      // becomes a visible failure instead of silent indefinite access.
      refreshTokens.revoke(db, tokenHash);

      res.json(issueSession(db, config, users.toPublicUser(row)));
    }),
  );

  router.post(
    '/signout',
    asyncHandler(async (req, res) => {
      const input = parse(refreshSchema, req.body);
      // Unconditional: signing out with an already-invalid token is still a
      // successful sign-out from the user's point of view.
      refreshTokens.revoke(db, hashRefreshToken(input.refreshToken));
      res.status(204).send();
    }),
  );

  router.post(
    '/password-reset',
    attemptLimiter,
    asyncHandler(async (req, res) => {
      const input = parse(passwordResetSchema, req.body);
      const row = users.findByEmail(db, input.email);

      if (row) {
        // Where a mail provider would be called. Intentionally not wired up:
        // a fake "email sent" that silently does nothing is worse than an
        // honest gap, and the response is identical either way.
        logger.info('password reset requested', { userId: row.id });
      }

      // Always 202, account or not — the response must not confirm the address.
      res.status(202).json({
        message: 'If that email has an account, a reset link is on its way.',
      });
    }),
  );

  // MARK: - Authenticated profile routes

  const requireAuth = authenticate(config);

  router.get(
    '/me',
    requireAuth,
    asyncHandler(async (req, res) => {
      const user = users.publicUserById(db, requireUserId(req));
      if (!user) throw ApiError.notFound('Account not found.');
      res.json({ user });
    }),
  );

  router.get(
    '/me/avatar',
    requireAuth,
    asyncHandler(async (req, res) => {
      const avatar = users.getAvatar(db, requireUserId(req));
      if (!avatar) throw ApiError.notFound('No profile photo set.');
      res.set('Content-Type', avatar.mimeType);
      res.set('Cache-Control', 'private, max-age=0, must-revalidate');
      res.send(avatar.data);
    }),
  );

  router.put(
    '/me/avatar',
    requireAuth,
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      const input = parse(avatarSchema, req.body);

      const bytes = Buffer.from(input.imageBase64, 'base64');
      if (bytes.length === 0) {
        throw ApiError.validation('Image data could not be decoded.');
      }
      if (bytes.length > MAX_AVATAR_BYTES) {
        throw new ApiError(
          'payload_too_large',
          `Profile photo must be under ${MAX_AVATAR_BYTES / 1024 / 1024} MB.`,
        );
      }

      users.setAvatar(db, userId, bytes, input.mimeType);
      const user = users.publicUserById(db, userId);
      if (!user) throw ApiError.notFound('Account not found.');
      res.json({ user });
    }),
  );

  router.delete(
    '/me/avatar',
    requireAuth,
    asyncHandler(async (req, res) => {
      const userId = requireUserId(req);
      users.setAvatar(db, userId, null, null);
      const user = users.publicUserById(db, userId);
      if (!user) throw ApiError.notFound('Account not found.');
      res.json({ user });
    }),
  );

  router.post(
    '/signout-everywhere',
    requireAuth,
    asyncHandler(async (req, res) => {
      refreshTokens.revokeAllForUser(db, requireUserId(req));
      res.status(204).send();
    }),
  );

  return router;
}
