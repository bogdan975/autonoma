# Railway image for apps/api. Builds from the repo root (unlike apps/api/Dockerfile,
# which expects a prebuilt dist/ from CI) and runs the source with tsx, the same way
# the workers run in production - workspace packages export TypeScript source.
FROM node:24-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY . .

# postinstall in @autonoma/db generates the Prisma client.
RUN pnpm install --frozen-lockfile

ENV NODE_ENV=production
WORKDIR /app/apps/api
EXPOSE 4000
CMD ["/app/node_modules/.bin/tsx", "src/index.ts"]
