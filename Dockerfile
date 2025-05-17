FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
# This COPY command assumes the Docker build context is the root of your monorepo.
COPY . /app

RUN corepack enable
# Ensure git is available in the build stage
RUN apk add --no-cache python3 alpine-sdk git

# --- Create Git information files ---
# This tells git to trust the directory, sometimes needed in CI/Docker
RUN git config --global --add safe.directory /app
# Extract current commit SHA (short) and save to a file
RUN git rev-parse --short HEAD > /app/git_commit.txt || echo "unknown_commit" > /app/git_commit.txt
# Extract current branch name and save to a file
RUN git rev-parse --abbrev-ref HEAD > /app/git_branch.txt || echo "unknown_branch" > /app/git_branch.txt
# You can add more if needed, e.g., git describe --tags
# The `|| echo "unknown_..."` part provides a fallback if git commands fail for any reason (e.g. shallow clone without enough info)

# PNPM install without Docker-level caching
RUN pnpm install --prod --frozen-lockfile

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

# --- Copy the generated Git information files ---
COPY --from=build --chown=node:node /app/git_commit.txt /app/git_commit.txt
COPY --from=build --chown=node:node /app/git_branch.txt /app/git_branch.txt

# Keep the original .git copy line commented out or remove it
# COPY --from=build --chown=node:node /app/.git /app/.git

USER node

EXPOSE 9000
CMD [ "node", "src/cobalt" ]