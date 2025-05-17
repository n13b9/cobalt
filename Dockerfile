FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
# Assuming Railway checks out the repo at /app, this includes .git if Railway provides it
COPY . /app

RUN corepack enable
# git is needed if the app or any build script tries to run git commands
RUN apk add --no-cache python3 alpine-sdk git

# PNPM install without Docker-level caching (this got us past build errors)
RUN pnpm install --prod --frozen-lockfile

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

# --- Attempt to copy .git again ---
# If Railway's checkout for the 'build' stage *does* have a .git folder after COPY . /app,
# this will bring it into the final image.
# We must ensure .dockerignore is NOT excluding .git
COPY --from=build --chown=node:node /app/.git /app/.git

USER node

EXPOSE 9000
CMD [ "node", "src/cobalt" ]