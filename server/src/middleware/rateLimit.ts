/**
 * Fixed-window rate limiter, in memory.
 *
 * Scoped to the auth routes, where the thing being protected is password
 * guessing rather than general load. In-memory state means the limit is
 * per-process: correct for the single-instance deployment this targets, and
 * the seam to swap in Redis is this file alone.
 */

import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../lib/errors.js';

interface Window {
  count: number;
  resetAt: number;
}

export interface RateLimitOptions {
  windowMs: number;
  max: number;
  /** Defaults to client IP. Auth routes add the email so one attacker cannot
   *  lock out every user behind a shared NAT by exhausting the IP bucket. */
  keyFor?: (req: Request) => string;
}

export function rateLimit(options: RateLimitOptions) {
  const windows = new Map<string, Window>();

  // Bound memory: without this, every distinct key from a scan is retained
  // until the process restarts.
  const sweep = setInterval(() => {
    const currentTime = Date.now();
    for (const [key, window] of windows) {
      if (window.resetAt <= currentTime) windows.delete(key);
    }
  }, 60_000);
  sweep.unref();

  return (req: Request, res: Response, next: NextFunction): void => {
    const key = options.keyFor?.(req) ?? req.ip ?? 'unknown';
    const currentTime = Date.now();
    const existing = windows.get(key);

    if (!existing || existing.resetAt <= currentTime) {
      windows.set(key, { count: 1, resetAt: currentTime + options.windowMs });
      next();
      return;
    }

    existing.count += 1;

    if (existing.count > options.max) {
      const retryAfter = Math.ceil((existing.resetAt - currentTime) / 1000);
      res.set('Retry-After', String(retryAfter));
      next(
        new ApiError('rate_limited', `Too many attempts. Try again in ${retryAfter}s.`),
      );
      return;
    }

    next();
  };
}

/** Buckets auth attempts by IP *and* email. */
export function authRateLimitKey(req: Request): string {
  const email =
    typeof req.body === 'object' && req.body !== null && 'email' in req.body
      ? String((req.body as { email: unknown }).email).toLowerCase()
      : '';
  return `${req.ip ?? 'unknown'}|${email}`;
}
