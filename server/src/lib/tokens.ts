/**
 * Token minting and verification.
 *
 * Two-token scheme:
 *   access token  — JWT, short-lived (15 min), sent on every request. Never
 *                   stored server-side; it is verified by signature alone.
 *   refresh token — opaque random string, long-lived (30 days), stored as a
 *                   SHA-256 hash and exchangeable exactly once (rotation).
 *
 * Rotation matters: if a refresh token leaks, the attacker and the real client
 * both try to use it, the second use fails, and the account owner is logged
 * out — a visible symptom rather than silent indefinite access.
 */

import jwt from 'jsonwebtoken';
import { createHash, randomBytes } from 'node:crypto';
import { ApiError } from './errors.js';

export interface AccessTokenClaims {
  /** User id. */
  sub: string;
  email: string;
}

export function signAccessToken(
  claims: AccessTokenClaims,
  secret: string,
  ttlSeconds: number,
): string {
  return jwt.sign({ email: claims.email }, secret, {
    subject: claims.sub,
    expiresIn: ttlSeconds,
    algorithm: 'HS256',
  });
}

export function verifyAccessToken(token: string, secret: string): AccessTokenClaims {
  try {
    // Pinning the algorithm blocks the "alg: none" and HS/RS confusion attacks
    // that come from letting the token pick its own verification scheme.
    const payload = jwt.verify(token, secret, { algorithms: ['HS256'] });

    if (typeof payload === 'string' || !payload.sub) {
      throw ApiError.unauthorized('Malformed token.');
    }
    return { sub: payload.sub, email: String((payload as jwt.JwtPayload).email ?? '') };
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      // Distinct from a bad token: the client should refresh, not sign out.
      throw new ApiError('token_expired', 'Access token expired.');
    }
    if (error instanceof ApiError) throw error;
    throw ApiError.unauthorized('Invalid token.');
  }
}

/** 32 bytes of entropy, base64url. Opaque — it carries no claims. */
export function generateRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

/**
 * What gets written to the database. Plain SHA-256 with no salt is correct
 * here (unlike for passwords): the input is already 256 bits of uniform
 * randomness, so there is no dictionary to precompute.
 */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
