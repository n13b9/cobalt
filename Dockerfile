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

RUN echo "---- CONTENTS OF /app (FINAL STAGE) - THIS IS CRITICAL ----"
RUN ls -R -A /app 
RUN echo "---- END OF /app LISTING (FINAL STAGE) ----"
RUN echo "---- PACKAGE.JSON IN /app (FINAL STAGE) ----"
RUN cat /app/package.json || echo "No package.json found at /app/package.json"
RUN echo "---- END OF PACKAGE.JSON ----"


USER node
EXPOSE 9000
CMD [ "node", "-e", "console.log('Build successful. Container started with placeholder CMD. Check build logs for ls -R /app output to determine correct final CMD.')" ]