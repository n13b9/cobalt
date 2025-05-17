FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# Enable corepack in the base image so all stages inherit it and pnpm is available
RUN corepack enable

FROM base AS build
WORKDIR /app
COPY . /app

# corepack already enabled from base
RUN apk add --no-cache python3 alpine-sdk git

RUN pnpm install --frozen-lockfile
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

USER node
EXPOSE 9000
# pnpm should be available on PATH due to corepack enable in base stage
CMD [ "pnpm", "start" ]