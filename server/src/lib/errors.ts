/**
 * One error type for everything the API can reject, so route handlers throw
 * and a single middleware decides status codes and response shape.
 *
 * `code` is a stable machine-readable string the iOS client switches on;
 * `message` is human copy that may be reworded without breaking the client.
 */

export type ApiErrorCode =
  | 'validation_failed'
  | 'invalid_credentials'
  | 'email_already_registered'
  | 'unauthorized'
  | 'token_expired'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'payload_too_large'
  | 'rate_limited'
  | 'internal_error';

const STATUS_BY_CODE: Record<ApiErrorCode, number> = {
  validation_failed: 422,
  invalid_credentials: 401,
  email_already_registered: 409,
  unauthorized: 401,
  token_expired: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  payload_too_large: 413,
  rate_limited: 429,
  internal_error: 500,
};

export class ApiError extends Error {
  readonly code: ApiErrorCode;
  readonly status: number;
  readonly details?: unknown;

  constructor(code: ApiErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = STATUS_BY_CODE[code];
    this.details = details;
  }

  static validation(message: string, details?: unknown): ApiError {
    return new ApiError('validation_failed', message, details);
  }

  static unauthorized(message = 'Authentication required.'): ApiError {
    return new ApiError('unauthorized', message);
  }

  static notFound(message = 'Not found.'): ApiError {
    return new ApiError('not_found', message);
  }
}
