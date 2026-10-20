# Railway image for apps/ui: build the Vite SPA, then serve it with the repo's own
# nginx template (which also proxies /v1/, /.well-known/oauth-*, etc. to the API).
FROM node:24-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl && rm -rf /var/lib/apt/lists/*
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
# Call vite directly rather than through `pnpm run` / turbo: pnpm re-verifies and reinstalls
# dependencies before each script, and the parallel reinstalls collide inside this build.
# Workspace packages export TypeScript source, so nothing else needs building first.
WORKDIR /app/apps/ui
RUN ./node_modules/.bin/vite build

FROM nginx:alpine
COPY apps/ui/nginx.conf.template /etc/nginx/templates/default.conf.template
# The template resolves API_UPSTREAM once at startup, so after every api redeploy (new private
# IP) the proxy keeps dialing the dead address and /v1/* hangs. Route it through a variable
# with a resolver instead, so nginx re-resolves the name; the image's local-resolvers
# entrypoint fills NGINX_LOCAL_RESOLVERS from /etc/resolv.conf.
RUN sed -i \
      -e 's|proxy_pass http://${API_UPSTREAM};|proxy_pass http://$api_upstream;|' \
      -e 's|^\(\s*listen 3000;\)|\1\n    listen [::]:3000;\n    resolver ${NGINX_LOCAL_RESOLVERS} valid=10s;\n    set $api_upstream ${API_UPSTREAM};|' \
      /etc/nginx/templates/default.conf.template
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
COPY --from=build /app/apps/ui/dist/ /usr/share/nginx/html/
EXPOSE 3000
# API_UPSTREAM (host:port of the API on Railway's private network) is substituted
# into the template at container start.
ENV NGINX_ENVSUBST_FILTER=API_UPSTREAM|NGINX_LOCAL_RESOLVERS
