# Railway image for apps/ui: build the Vite SPA, then serve it with the repo's own
# nginx template (which also proxies /v1/, /.well-known/oauth-*, etc. to the API).
FROM node:24-slim AS build
RUN corepack enable
WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile

# Vite inlines these at build time. Railway passes service variables to the build
# only when they are declared as ARGs.
ARG VITE_API_URL
ARG VITE_INTERNAL_DOMAIN
ARG VITE_TEMPORAL_URL
ARG VITE_SENTRY_DSN
ARG VITE_SENTRY_URL
ARG VITE_POSTHOG_KEY
RUN pnpm turbo run build --filter=@autonoma/ui

FROM nginx:alpine
COPY apps/ui/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/apps/ui/dist/ /usr/share/nginx/html/
EXPOSE 3000
# API_UPSTREAM (host:port of the API on Railway's private network) is substituted
# into the template at container start.
ENV NGINX_ENVSUBST_FILTER=API_UPSTREAM
