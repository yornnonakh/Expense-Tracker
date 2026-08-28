import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],

    // Sign-in spends a full bcrypt cost-12 comparison on every attempt --
    // including the miss path, which burns a dummy hash so response latency
    // cannot be used to enumerate registered addresses. That is ~450ms each,
    // by design, and the rate-limit tests must exhaust a 10-attempt window to
    // reach the 429. Eleven attempts alone overruns the 5s default, so the
    // suite needs a budget that reflects what deliberately-slow hashing costs.
    testTimeout: 30_000,
  },
});
