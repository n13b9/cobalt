FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk git

# Install ALL dependencies (including devDependencies needed for building the workspace package)
# Remove --prod flag here temporarily to ensure build tools for the package are present
RUN pnpm install --frozen-lockfile 

# Build the specific API package (compiles TS to JS in its 'lib' folder)
RUN pnpm --filter=@imput/cobalt-api build

# Now deploy the built package (this will copy from its 'lib' folder and prod dependencies)
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

USER node
EXPOSE 9000
CMD [ "node", "lib/index.js" ]