/**
 * Structured logging.
 *
 * One JSON object per line, so `jq` works and a log shipper can index fields
 * without regex parsing. Silent under NODE_ENV=test to keep test output
 * readable — the assertions are the signal there, not the logs.
 */

type Level = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

function activeLevel(): Level {
  const configured = process.env.LOG_LEVEL as Level | undefined;
  if (configured && configured in LEVEL_ORDER) return configured;
  return process.env.NODE_ENV === 'production' ? 'info' : 'debug';
}

/**
 * Fields that must never reach a log line, even if a caller passes them.
 *
 * Logs get copied into tickets, pasted into chats and shipped to third-party
 * indexes; a password that lands in one is effectively public and cannot be
 * unpublished. Redacting at the sink means no individual call site has to
 * remember.
 */
const REDACTED_KEYS = new Set([
  'password',
  'passwordhash',
  'password_hash',
  'token',
  'accesstoken',
  'refreshtoken',
  'authorization',
  'imagebase64',
  'avatar_data',
]);

function redact(context: Record<string, unknown>): Record<string, unknown> {
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    output[key] = REDACTED_KEYS.has(key.toLowerCase()) ? '[redacted]' : value;
  }
  return output;
}

function emit(level: Level, message: string, context?: Record<string, unknown>): void {
  if (process.env.NODE_ENV === 'test' && process.env.LOG_LEVEL === undefined) return;
  if (LEVEL_ORDER[level] < LEVEL_ORDER[activeLevel()]) return;

  const line = {
    level,
    time: new Date().toISOString(),
    message,
    ...(context ? redact(context) : {}),
  };

  const stream = level === 'error' || level === 'warn' ? process.stderr : process.stdout;
  stream.write(`${JSON.stringify(line)}\n`);
}

export const logger = {
  debug: (message: string, context?: Record<string, unknown>) => emit('debug', message, context),
  info: (message: string, context?: Record<string, unknown>) => emit('info', message, context),
  warn: (message: string, context?: Record<string, unknown>) => emit('warn', message, context),
  error: (message: string, context?: Record<string, unknown>) => emit('error', message, context),
};
