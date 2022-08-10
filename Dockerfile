#=============================================================================
# Development image
#=============================================================================
FROM hexpm/elixir:1.13.4-erlang-25.0.2-debian-bullseye-20210902-slim AS dev

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
FROM hexpm/elixir:1.13.4-erlang-25.0.2-debian-bullseye-20210902-slim AS prod

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
