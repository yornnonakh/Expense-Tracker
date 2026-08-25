import { describe, expect, it, afterEach } from 'vitest';
import { loadConfig } from '../src/lib/config.js';

/**
 * The production guards are the difference between "insecure by default" and
 * "refuses to be insecure". Worth testing precisely because nothing exercises
 * them until a real deploy, when a silent failure is most expensive.
 */
describe('config', () => {
  const original = { ...process.env };

  afterEach(() => {
    process.env = { ...original };
  });

  it('supplies working development defaults', () => {
    process.env.NODE_ENV = 'development';
    delete process.env.JWT_ACCESS_SECRET;
    delete process.env.JWT_REFRESH_SECRET;

    const config = loadConfig();
    expect(config.port).toBe(8787);
    expect(config.accessTokenTtl).toBe(900);
  });

  it('refuses to boot in production with the development secrets', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.JWT_ACCESS_SECRET;
    delete process.env.JWT_REFRESH_SECRET;

    expect(() => loadConfig()).toThrow(/must be set to real values/);
  });

  it('refuses short secrets in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_ACCESS_SECRET = 'too-short';
    process.env.JWT_REFRESH_SECRET = 'also-too-short';

    expect(() => loadConfig()).toThrow(/at least 32 characters/);
  });

  it('refuses identical access and refresh secrets in production', () => {
    // Sharing one secret would make a refresh token verify as an access
    // token, silently defeating the short access-token lifetime.
    const shared = 'x'.repeat(40);
    process.env.NODE_ENV = 'production';
    process.env.JWT_ACCESS_SECRET = shared;
    process.env.JWT_REFRESH_SECRET = shared;

    expect(() => loadConfig()).toThrow(/must differ/);
  });

  it('accepts well-formed production secrets', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_ACCESS_SECRET = 'a'.repeat(40);
    process.env.JWT_REFRESH_SECRET = 'b'.repeat(40);

    expect(() => loadConfig()).not.toThrow();
  });

  it('rejects a non-numeric port', () => {
    process.env.PORT = 'eighty-eighty';
    expect(() => loadConfig()).toThrow(/positive integer/);
  });
});
