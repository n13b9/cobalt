FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build
WORKDIR /app
COPY . /app

RUN apk add --no-cache python3 alpine-sdk git

RUN pnpm install --frozen-lockfile

# We know this next line says "None of the selected packages has a 'build' script",
# so it does nothing, but we'll keep it for now to match the structure that led to this point.
# If the build takes too long, this can be commented out.
RUN pnpm --filter=@imput/cobalt-api build

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

RUN echo "---- CONTENTS OF /prod-api-deploy ----"
RUN ls -R /prod-api-deploy
RUN echo "---- END OF /prod-api-deploy LISTING ----"

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

RUN echo "---- CONTENTS OF /app (FINAL STAGE) ----"
RUN ls -R /app
RUN echo "---- END OF /app LISTING (FINAL STAGE) ----"

USER node
EXPOSE 9000
# We will determine this CMD after seeing the 'ls -R /app' output
# For now, let's use a command that won't immediately try to run a specific file
# and will just keep the container alive for a moment if possible, or just exit.
# A more robust way is to just use a known file like package.json if it exists.
# If package.json is copied to /app, then "node package.json" (if it has a start/main)
# or just "node -e \"console.log('Container started, check file structure for CMD')\""
CMD [ "node", "-e", "console.log('Container started. Examine build logs for ls -R /app output to determine correct CMD.')" ]