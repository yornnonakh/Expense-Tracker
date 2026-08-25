/**
 * Bearer-token authentication.
 *
 * Attaches `req.userId` on success. Everything downstream reads that and
 * nothing else — no route ever takes a user id from the body or the path, so
 * there is no way to spell a request that acts on someone else's data.
 */

import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../lib/errors.js';
import { verifyAccessToken } from '../lib/tokens.js';
import type { Config } from '../lib/config.js';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      userId?: string;
      userEmail?: string;
    }
  }
}

export function authenticate(config: Config) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const header = req.get('authorization');

    if (!header?.startsWith('Bearer ')) {
      next(ApiError.unauthorized('Missing bearer token.'));
      return;
    }

    const token = header.slice('Bearer '.length).trim();
    if (!token) {
      next(ApiError.unauthorized('Missing bearer token.'));
      return;
    }

    try {
      const claims = verifyAccessToken(token, config.accessSecret);
      req.userId = claims.sub;
      req.userEmail = claims.email;
      next();
    } catch (error) {
      next(error);
    }
  };
}

/** Narrowing helper so handlers get a `string` without a non-null assertion. */
export function requireUserId(req: Request): string {
  if (!req.userId) {
    // Unreachable behind `authenticate`; throwing beats asserting because a
    // future route mounted without the middleware fails loudly here.
    throw ApiError.unauthorized();
  }
  return req.userId;
}
