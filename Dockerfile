FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
# This COPY command assumes the Docker build context is the root of your monorepo.
# Ensure your .dockerignore file does NOT exclude the .git directory.
COPY . /app

RUN corepack enable
# Added git here to ensure git commands can run if needed for versioning during build,
# and python3/alpine-sdk were already there from your original file.
RUN apk add --no-cache python3 alpine-sdk git

# Extract git info if your app needs it, as an alternative to copying the whole .git dir later (optional but good practice)
# RUN git config --global --add safe.directory /app # May be needed
# RUN GIT_COMMIT_SHA=$(git rev-parse --short HEAD) && echo $GIT_COMMIT_SHA > /app/git_commit.txt
# RUN GIT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD) && echo $GIT_BRANCH_NAME > /app/git_branch.txt

# PNPM install without the --mount=type=cache to avoid Railway-specific cache errors
RUN pnpm install --prod --frozen-lockfile

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app
# This line copies the .git directory from the build stage to the final image.
# This is to address the "no git repository root found" runtime error.
# Ensure .git was actually copied into the 'build' stage (check .dockerignore).
COPY --from=build --chown=node:node /app/.git /app/.git

# If you used the git info extraction method above, copy those files instead:
# COPY --from=build --chown=node:node /app/git_commit.txt /app/git_commit.txt
# COPY --from=build --chown=node:node /app/git_branch.txt /app/git_branch.txt

USER node

EXPOSE 9000
# This CMD should match the actual entry point of the deployed @imput/cobalt-api package.
# If it's lib/index.js after pnpm deploy, change src/cobalt to lib/index.js
CMD [ "node", "src/cobalt" ]