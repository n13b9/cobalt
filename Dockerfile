FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build
WORKDIR /app
COPY . /app

RUN apk add --no-cache python3 alpine-sdk git

RUN pnpm install --frozen-lockfile
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

USER node
EXPOSE 9000
# CMD should align with the "start" script in the package.json at /app/package.json
# which is "node src/cobalt"
CMD [ "node", "src/cobalt.js" ] 
# Using .js extension for explicitness, Node.js will also often resolve "src/cobalt" if it's a JS file.