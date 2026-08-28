/**
 * Small request helpers.
 */

import type { Request } from 'express';
import { ApiError } from './errors.js';

/**
 * Reads a path parameter as a definite string.
 *
 * Express types params as possibly-undefined under
 * `noUncheckedIndexedAccess`, which is honest: a route mounted with a
 * different path pattern really would produce undefined here. Throwing turns
 * that wiring mistake into a clear 404 instead of an `undefined` reaching a
 * SQL bind, where it would silently match nothing.
 */
export function requireParam(req: Request, name: string): string {
  const value = req.params[name];
  if (typeof value !== 'string' || value.length === 0) {
    throw ApiError.notFound(`Missing "${name}" in path.`);
  }
  return value;
}
