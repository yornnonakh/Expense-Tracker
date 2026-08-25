/**
 * Runtime configuration, read once at boot.
 *
 * Every value has a development default so `npm run dev` works with no setup,
 * but the secrets are validated in production: shipping the dev JWT secret
 * would let anyone mint a token for any account, so the server refuses to
 * start rather than come up quietly insecure.
 */

export interface Config {
  port: number;
  nodeEnv: 'development' | 'test' | 'production';
  accessSecret: string;
  refreshSecret: string;
  /** Seconds. Short by design — the refresh token carries the long tail. */
  accessTokenTtl: number;
  /** Seconds. */
  refreshTokenTtl: number;
  databasePath: string;
  corsOrigin: string;
}

const DEV_ACCESS_SECRET = 'dev-access-secret-change-me';
const DEV_REFRESH_SECRET = 'dev-refresh-secret-change-me';

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer, got "${raw}"`);
  }
  return parsed;
}

export function loadConfig(): Config {
  const nodeEnv = (process.env.NODE_ENV ?? 'development') as Config['nodeEnv'];

  const accessSecret = process.env.JWT_ACCESS_SECRET ?? DEV_ACCESS_SECRET;
  const refreshSecret = process.env.JWT_REFRESH_SECRET ?? DEV_REFRESH_SECRET;

  if (nodeEnv === 'production') {
    if (accessSecret === DEV_ACCESS_SECRET || refreshSecret === DEV_REFRESH_SECRET) {
      throw new Error(
        'Refusing to start: JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be ' +
          'set to real values when NODE_ENV=production.',
      );
    }
    if (accessSecret.length < 32 || refreshSecret.length < 32) {
      throw new Error('Refusing to start: JWT secrets must be at least 32 characters.');
    }
    if (accessSecret === refreshSecret) {
      throw new Error(
        'Refusing to start: access and refresh secrets must differ, otherwise a ' +
          'refresh token is accepted as an access token.',
      );
    }
  }

  return {
    port: intFromEnv('PORT', 8787),
    nodeEnv,
    accessSecret,
    refreshSecret,
    accessTokenTtl: intFromEnv('ACCESS_TOKEN_TTL', 15 * 60),
    refreshTokenTtl: intFromEnv('REFRESH_TOKEN_TTL', 30 * 24 * 60 * 60),
    databasePath: process.env.DATABASE_PATH ?? './data/expense-tracker.db',
    corsOrigin: process.env.CORS_ORIGIN ?? '*',
  };
}
