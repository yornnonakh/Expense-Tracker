# Build stage. better-sqlite3 is a native module, so the toolchain has to be
# present to compile it — but it has no business in the shipped image.
FROM node:22-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy manifests alone first: this layer is cached and only reinvalidated when
# dependencies actually change, not on every source edit.
COPY package.json package-lock.json* ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Re-resolve to production dependencies only, so devDependencies (tsx,
# typescript, vitest) never reach the runtime image.
RUN npm ci --omit=dev

# ---

FROM node:22-slim AS runtime

# tini reaps zombies and forwards signals, so the SIGTERM handling in
# server.ts actually runs and the database is checkpointed on deploy.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./

# The database lives on a mounted volume, not in the image layer: a container
# filesystem is recreated on every deploy and would take every account with it.
ENV DATABASE_PATH=/data/expense-tracker.db
RUN mkdir -p /data && chown -R node:node /data /app

USER node
EXPOSE 8787

# Hits the database-free probe, so a restart loop is not triggered by a
# transient database problem the app is already reporting as degraded.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/server.js"]
