# Railway image for apps/api. Builds from the repo root (unlike apps/api/Dockerfile,
# which expects a prebuilt dist/ from CI) and runs the source with tsx, the same way
# the workers run in production - workspace packages export TypeScript source.
FROM node:24-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl && rm -rf /var/lib/apt/lists/*
RUN corepack enable
# pnpm re-verifies dependencies before every `pnpm run`; inside a turbo build that makes
# each package task reinstall in parallel, and the concurrent Prisma generates collide.
ENV pnpm_config_verify_deps_before_run=false npm_config_verify_deps_before_run=false

WORKDIR /app
COPY . .

# postinstall in @autonoma/db generates the Prisma client.
RUN pnpm install --frozen-lockfile

ENV NODE_ENV=production
WORKDIR /app/apps/api
EXPOSE 4000
CMD ["/app/node_modules/.bin/tsx", "src/index.ts"]
