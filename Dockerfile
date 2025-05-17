FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk git

RUN pnpm install --frozen-lockfile

# We remove this because the log said "None of the selected packages has a 'build' script"
# RUN pnpm --filter=@imput/cobalt-api build 

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

# For debugging - to see what pnpm deploy actually created
RUN echo "---- Contents of /prod-api-deploy ----"
RUN ls -R /prod-api-deploy

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

# For debugging - to see the final /app structure
RUN echo "---- Contents of /app (final stage) ----"
RUN ls -R /app

USER node
EXPOSE 9000
# Adjust this CMD based on the output of "ls -R /app" from the build log
# If the package @imput/cobalt-api has its main file as src/index.js or src/cobalt.js
# this needs to match.
# Let's assume the structure deployed by `pnpm deploy` places the package's own `src`
# directory directly into `/app`.
CMD [ "node", "src/index.js" ] 
# OR try: CMD [ "node", "src/cobalt.js" ]
# OR check the package.json within /app for its "main" or "start" script.