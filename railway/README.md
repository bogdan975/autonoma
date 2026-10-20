# Deploying Autonoma on Railway

This deploys the core platform plus test execution:

| Railway service   | Source                                     | Config file                    | Public domain |
|-------------------|--------------------------------------------|--------------------------------|---------------|
| `Postgres`        | Railway Postgres template                  | -                              | no            |
| `Redis`           | Railway Redis template                     | -                              | no            |
| `temporal`        | Docker image `temporalio/auto-setup:1.25.2`| -                              | no            |
| `api`             | this repo                                  | `railway/api.json`             | yes (webhooks, MCP) |
| `ui`              | this repo                                  | `railway/ui.json`              | yes (the app) |
| `worker-general`  | this repo                                  | `railway/worker-general.json`  | no            |
| `worker-web`      | this repo                                  | `railway/worker-web.json`      | no            |

Not deployed: `previewkit` and `cronjobs` (they drive Kubernetes), `worker-mobile` (needs
Appium devices), `worker-diffs` (PR analysis - add it later the same way as
`worker-general`, using `apps/workers/diffs/Dockerfile`).

Service names matter: the variable references below (`${{api.RAILWAY_PRIVATE_DOMAIN}}` etc.)
assume exactly these names.

## 1. Create the project

1. Fork `Autonoma-AI/autonoma` on GitHub and push the `railway/` folder to the fork.
2. In Railway: **New Project → Deploy PostgreSQL**, then **+ Create → Database → Redis**.
3. **+ Create → Docker Image** → `temporalio/auto-setup:1.25.2`, rename it `temporal`.
4. For each of `api`, `ui`, `worker-general`, `worker-web`: **+ Create → GitHub Repo** →
   your fork, rename the service, then in **Settings**:
   - **Root Directory**: leave empty (repo root - every image builds from the whole monorepo)
   - **Config-as-code → Railway Config File**: `/railway/<service>.json` (from the table)
5. For `api` and `ui`: **Settings → Networking → Generate Domain** (target ports 4000 and 3000).

## 2. Variables

Generate secrets with `openssl rand -hex 32`.

### Shared variables (Project Settings → Shared Variables), then share with api, worker-general, worker-web

```
NODE_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
REDIS_URL=${{Redis.REDIS_URL}}
TEMPORAL_ADDRESS=${{temporal.RAILWAY_PRIVATE_DOMAIN}}:7233
TEMPORAL_NAMESPACE=default
NAMESPACE=railway
SCENARIO_ENCRYPTION_KEY=<openssl rand -hex 32>

# AI - all three are required by packages/ai
GEMINI_API_KEY=
GROQ_KEY=
OPENROUTER_API_KEY=

# Storage (screenshots, videos). An AWS S3 bucket is the tested path.
S3_BUCKET=
S3_REGION=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
# Untested: an S3-compatible store (Railway Bucket, Cloudflare R2) via the AWS SDK's
# standard endpoint override:
# AWS_ENDPOINT_URL_S3=

# GitHub App - required: api and worker-general refuse to boot without it
GITHUB_APP_ID=
GITHUB_APP_PRIVATE_KEY=        # base64 of the PEM: base64 -i private-key.pem
GITHUB_APP_WEBHOOK_SECRET=
GITHUB_APP_SLUG=
```

### `temporal`

```
DB=postgres12
DB_PORT=${{Postgres.PGPORT}}
POSTGRES_USER=${{Postgres.PGUSER}}
POSTGRES_PWD=${{Postgres.PGPASSWORD}}
POSTGRES_SEEDS=${{Postgres.PGHOST}}
BIND_ON_IP=0.0.0.0
TEMPORAL_BROADCAST_ADDRESS=127.0.0.1
```

auto-setup creates its own `temporal` and `temporal_visibility` databases on the same
Postgres server, next to the app's `railway` database.

### `api`

The UI is the single public entry point: its nginx proxies `/v1/*`, `/.well-known/oauth-*`
and friends to the API over the private network. So the browser, cookies and OAuth callbacks
all live on the UI's domain - `*.up.railway.app` is a public suffix, so cross-domain cookies
between two Railway subdomains would not work.

```
API_PORT=4000
PORT=4000
APP_URL=https://${{ui.RAILWAY_PUBLIC_DOMAIN}}
BETTER_AUTH_URL=https://${{ui.RAILWAY_PUBLIC_DOMAIN}}
ALLOWED_ORIGINS=https://${{ui.RAILWAY_PUBLIC_DOMAIN}}
MCP_RESOURCE_URL=https://${{api.RAILWAY_PUBLIC_DOMAIN}}
BETTER_AUTH_SECRET=<openssl rand -hex 32>
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
STRIPE_ENABLED=false
```

Optional: `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` (GitHub sign-in), `RESEND_API_KEY`,
`RESEND_FROM_EMAIL`, `SENTRY_DSN`, `POSTHOG_KEY`. See `.env.example` and `apps/api/src/env.ts`.

### `ui`

```
PORT=3000
VITE_API_URL=https://${{ui.RAILWAY_PUBLIC_DOMAIN}}
API_UPSTREAM=${{api.RAILWAY_PRIVATE_DOMAIN}}:4000
```

`VITE_*` values are baked in at build time, so redeploy `ui` after changing them.

### `worker-general`, `worker-web`

Only the shared variables. Optional: `SENTRY_DSN_WORKER_GENERAL`, `SENTRY_DSN_WORKER_WEB`.

## 3. External setup

- **Google OAuth**: authorized redirect URI
  `https://<ui domain>/v1/auth/callback/google`, JavaScript origin `https://<ui domain>`.
- **GitHub App**: webhook URL `https://<api domain>/v1/github/webhook`, callback/setup URLs
  on the UI domain.

## 4. Deploy order

1. Postgres, Redis, then `temporal` (wait until its logs show the frontend is serving).
2. `api` - its pre-deploy step runs `prisma migrate deploy`.
3. `ui`, `worker-general`, `worker-web`.

## How the web worker behaves here

`worker-web` is built to be a one-shot Kubernetes Job: it takes one test run, then exits;
if nothing arrives in 2 minutes it exits too. On Railway, `restartPolicyType: ALWAYS`
turns that into a loop, so one replica runs one test at a time and restarts between runs.
Scale replicas in **Settings → Deploy → Replicas** for parallel runs. Expect restart
entries in its logs - that is normal.

## Troubleshooting

- **ui returns 502 on `/v1/...`**: check `API_UPSTREAM` and that the api is healthy. Railway's
  private network must reach it over IPv4 (the API binds `0.0.0.0`); environments created
  before Railway's dual-stack private networking are IPv6-only and need a new environment.
- **Sign-in loops / cookie errors**: `APP_URL`, `BETTER_AUTH_URL` and `VITE_API_URL` must all
  be the UI's `https://` domain.
- **Workers can't reach Temporal**: `TEMPORAL_ADDRESS` must include `:7233`.
- **ui crashes with `host not found in upstream`**: nginx resolves `API_UPSTREAM` at startup,
  so the ui can't start until the api service exists and has deployed once. It restarts on
  its own; deploy the api first.
