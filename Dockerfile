#=============================================================================
# Development image
#=============================================================================

ARG CONTAINER_BUILDER_IMAGE="${CONTAINER_BUILDER_IMAGE:-hexpm/elixir:1.17.2-erlang-27.0.1-debian-bookworm-20240722-slim}"
ARG RUNNER_IMAGE="${RUNNER_IMAGE:-debian:bookworm-20240722-slim}"

FROM ${CONTAINER_BUILDER_IMAGE} AS dev

ENV \
  PORT=4000

RUN \
  groupadd kv \
  && useradd -m -g kv kv \
  && mkdir -p /app/apps/kv \
  && mkdir -p /app/apps/kv_s \
  && mkdir -p /app/_build \
  && chown -R kv:kv /app \
  && apt update  \
  && apt-get install -y --no-install-recommends \
  openssl \
  git \
  ca-certificates \
  curl \
  inotify-tools \
  iputils-ping \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc  /usr/share/man \
  && apt-get clean

USER kv

WORKDIR /app

COPY \
  --chown=kv:kv \
  ./mix.exs \
  ./mix.lock \
  ./

COPY \
  --chown=kv:kv \
  ./apps/kv_s/mix.exs \
  ./apps/kv_s

COPY \
  --chown=kv:kv \
  ./apps/kv/mix.exs \
  ./apps/kv

COPY \
  --chown=kv:kv \
  --chmod=755 \
  ./run.sh \
  /usr/local/bin/run

COPY \
  --chown=kv:kv \
  . .

RUN \
  mix local.hex --force \
  && mix local.rebar --force \
  && mix deps.get

EXPOSE 4000

CMD ["/bin/bash"]

#=============================================================================
# BUILD IMAGE
#=============================================================================

FROM dev AS build

ARG RELEASE_NAME

ENV \
  MIX_ENV=prod \
  RELEASE_NAME=${RELEASE_NAME}

RUN \
  mix do deps.get --only prod, compile \
  && mix release ${RELEASE_NAME}

#=============================================================================
# PRODUCTION IMAGE
#=============================================================================

FROM ${RUNNER_IMAGE} AS prod

ARG RELEASE_NAME

ENV \
  PORT=4000 \
  LANG=C.UTF-8 \
  MIX_ENV=prod \
  RELEASE_NAME=${RELEASE_NAME}

RUN \
  groupadd kv \
  && useradd -m -g kv kv \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  openssl \
  libtinfo5 \
  curl \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc  /usr/share/man \
  && apt-get clean


USER kv

WORKDIR /app

COPY \
  --from=build \
  --chown=kv:kv \
  /app/_build/prod/rel/${RELEASE_NAME} \
  ./

COPY \
  --from=build \
  --chown=kv:kv \
  --chmod=755 \
  /usr/local/bin/run \
  /usr/local/bin/run

RUN mv bin/${RELEASE_NAME} bin/run

EXPOSE 4000

CMD ["/app/bin/run", "start"]
