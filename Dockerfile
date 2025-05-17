FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build
WORKDIR /app
# This copies everything from your repo root (including cobalt-cookies.json)
# into /app inside this 'build' stage.
COPY . /app

RUN apk add --no-cache python3 alpine-sdk git
RUN pnpm install --frozen-lockfile
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

# After COPY . /app, cobalt-cookies.json from your repo root is now at /app/cobalt-cookies.json
# within this 'build' stage.

FROM base AS api
WORKDIR /app

# Copy the deployed API package from /prod-api-deploy in 'build' stage to /app in this 'api' stage
COPY --from=build --chown=node:node /prod-api-deploy /app

# Copy cobalt-cookies.json from /app/cobalt-cookies.json in the 'build' stage
# (where it landed after 'COPY . /app') to /app/cobalt-cookies.json in this final 'api' stage.
COPY --from=build --chown=node:node /app/cobalt-cookies.json /app/cobalt-cookies.json

USER node
EXPOSE 9000
CMD [ "node", "src/cobalt.js" ]