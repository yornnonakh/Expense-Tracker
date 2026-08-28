/**
 * Wraps an async handler so a rejected promise reaches Express's error
 * middleware.
 *
 * Express 4 only catches synchronous throws; an unhandled rejection inside a
 * handler otherwise hangs the request until the client times out. Every async
 * route in this server goes through here.
 */

import type { NextFunction, Request, RequestHandler, Response } from 'express';

export function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    handler(req, res, next).catch(next);
  };
}
