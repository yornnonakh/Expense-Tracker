/**
 * The one place a thrown error becomes an HTTP response.
 *
 * Route handlers throw `ApiError` and never touch `res.status`, which keeps
 * status-code policy in a single file instead of scattered across handlers.
 */

import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../lib/errors.js';
import { logger } from '../lib/logger.js';

export interface ErrorBody {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    error: { code: 'not_found', message: `No route for ${req.method} ${req.path}` },
  } satisfies ErrorBody);
}

export function errorHandler(isProduction: boolean) {
  return (error: unknown, req: Request, res: Response, next: NextFunction): void => {
    if (res.headersSent) {
      next(error);
      return;
    }

    if (error instanceof ApiError) {
      // Expected rejections (bad input, wrong password) are not incidents;
      // logging them at error level would bury the ones that are.
      logger.debug('request rejected', {
        code: error.code,
        status: error.status,
        path: req.path,
      });

      res.status(error.status).json({
        error: { code: error.code, message: error.message, details: error.details },
      } satisfies ErrorBody);
      return;
    }

    // A body-parser failure is the client's fault, not ours.
    if (error instanceof SyntaxError && 'body' in error) {
      res.status(400).json({
        error: { code: 'validation_failed', message: 'Request body is not valid JSON.' },
      } satisfies ErrorBody);
      return;
    }

    if (typeof error === 'object' && error !== null && 'type' in error) {
      if ((error as { type: string }).type === 'entity.too.large') {
        res.status(413).json({
          error: { code: 'payload_too_large', message: 'Request body is too large.' },
        } satisfies ErrorBody);
        return;
      }
    }

    logger.error('unhandled error', {
      path: req.path,
      method: req.method,
      error: error instanceof Error ? error.stack : String(error),
    });

    res.status(500).json({
      error: {
        code: 'internal_error',
        // A stack trace in a response is a gift to an attacker; it stays in
        // the logs, where it is equally useful and not publicly readable.
        message: 'Something went wrong.',
        details: isProduction ? undefined : String(error),
      },
    } satisfies ErrorBody);
  };
}
