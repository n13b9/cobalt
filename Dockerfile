FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build
WORKDIR /app
COPY . /app

RUN apk add --no-cache python3 alpine-sdk git

RUN pnpm install --frozen-lockfile

# We know "pnpm --filter=@imput/cobalt-api build" found no build script, so it's removed/commented.
# RUN pnpm --filter=@imput/cobalt-api build

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod-api-deploy

# Optional: You can remove the ls commands now if you're confident, or keep for one more check
# RUN echo "---- CONTENTS OF /prod-api-deploy ----"
# RUN ls -R /prod-api-deploy
# RUN echo "---- END OF /prod-api-deploy LISTING ----"

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod-api-deploy /app

# Optional: You can remove the ls commands now if you're confident
# RUN echo "---- CONTENTS OF /app (FINAL STAGE) ----"
# RUN ls -R /app
# RUN echo "---- END OF /app LISTING (FINAL STAGE) ----"

USER node
EXPOSE 9000
CMD [ "node", "index.js" ]