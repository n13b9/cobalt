FROM node:23-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk git # Add git here to use git commands

# Extract git info and save to files
RUN git config --global --add safe.directory /app # Needed if git complains about ownership
RUN GIT_COMMIT_SHA=$(git rev-parse --short HEAD) && echo $GIT_COMMIT_SHA > /app/git_commit.txt
RUN GIT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD) && echo $GIT_BRANCH_NAME > /app/git_branch.txt
# You might also want the remote URL if the app uses it
# RUN GIT_REMOTE_URL=$(git config --get remote.origin.url) && echo $GIT_REMOTE_URL > /app/git_remote.txt

# (Keep your existing pnpm install and deploy commands)
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --prod --frozen-lockfile # Or without id=pnpm if that was causing cache key issues, or without cache at all if that was the only way to build
RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app
# COPY --from=build --chown=node:node /app/.git /app/.git # Keep this commented out

# Copy the git info files instead of the whole .git directory
COPY --from=build --chown=node:node /app/git_commit.txt /app/git_commit.txt
COPY --from=build --chown=node:node /app/git_branch.txt /app/git_branch.txt
# COPY --from=build --chown=node:node /app/git_remote.txt /app/git_remote.txt # If you created it

USER node
EXPOSE 9000
CMD [ "node", "src/cobalt" ]