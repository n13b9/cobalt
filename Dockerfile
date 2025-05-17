FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk git

# Install ALL dependencies (including devDependencies needed for building the workspace package)
RUN pnpm install --frozen-lockfile 

# Build the specific API package (compiles TS to JS in its 'lib' folder)
RUN echo "---- BUILDING @imput/cobalt-api ----"
RUN pnpm --filter=@imput/cobalt-api build
RUN echo "---- LISTING files in @imput/cobalt-api after build (expected to see a lib folder) ----"
# Assuming @imput/cobalt-api is at packages/api or a similar path known from the monorepo structure
# Adjust 'packages/api' if the actual path to @imput/cobalt-api within the monorepo is different
RUN ls -R /app/packages/api/ 

# Now deploy the built package
RUN echo "---- DEPLOYING @imput/cobalt-api to /prod/api ----"
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api
RUN echo "---- LISTING files in /prod/api after pnpm deploy ----"
RUN ls -R /prod/api/

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

RUN echo "---- LISTING files in /app in FINAL API STAGE ----"
RUN ls -R /app/

USER node
EXPOSE 9000
CMD [ "node", "lib/index.js" ]