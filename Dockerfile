FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk git # Keep git in case pnpm scripts or app build needs it

# PNPM install without Docker-level caching
RUN pnpm install --prod --frozen-lockfile

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

# CRITICAL: The .git copy line is removed (or commented out)
# COPY --from=build --chown=node:node /app/.git /app/.git

USER node

EXPOSE 9000
# This CMD should match the actual entry point. If this is still an issue, it's a separate problem.
CMD [ "node", "src/cobalt" ]