FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build
WORKDIR /app
COPY . /app

RUN apk add --no-cache python3 alpine-sdk git

RUN git config --global --add safe.directory /app || true
RUN (git rev-parse --short HEAD || echo "unknown") > /app/git_commit.txt
RUN (git rev-parse --abbrev-ref HEAD || echo "unknown") > /app/git_branch.txt
RUN (git config --get remote.origin.url || echo "unknown") > /app/git_remote.txt
RUN (node -p "require('./package.json').version" || echo "unknown") > /app/app_version.txt

RUN pnpm install --frozen-lockfile
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

COPY --from=build --chown=node:node /app/git_commit.txt /app/git_commit.txt
COPY --from=build --chown=node:node /app/git_branch.txt /app/git_branch.txt
COPY --from=build --chown=node:node /app/git_remote.txt /app/git_remote.txt
COPY --from=build --chown=node:node /app/app_version.txt /app/app_version.txt
COPY cobalt-cookies.json /app/cobalt-cookies.json

RUN echo $'#!/bin/sh\n\
    export GIT_COMMIT_SHA_SHORT=$(cat /app/git_commit.txt)\n\
    export GIT_BRANCH_NAME=$(cat /app/git_branch.txt)\n\
    export GIT_REMOTE_URL=$(cat /app/git_remote.txt)\n\
    export APP_VERSION=$(cat /app/app_version.txt)\n\
    exec "$@"' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

USER node
EXPOSE 9000

ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD [ "node", "src/cobalt.js" ]