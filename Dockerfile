#=============================================================================
# Development image
#=============================================================================
FROM hexpm/elixir:1.13.4-erlang-25.0.2-alpine-3.16.0 AS dev

ENV \
  PORT=4000

RUN \
  addgroup -S kv \
  && adduser -S kv -G kv \
  && mkdir -p /app/_build \
  && mkdir -p /app/apps/kv \
  && mkdir -p /app/apps/kv_s \
  && chown -R kv:kv /app \
  && apk add --no-cache \
  openssl \
  git \
  ca-certificates \
  curl \
  bash \
  inotify-tools \
  iputils

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

EXPOSE 4000 4001 4002 4003

CMD ["/bin/sh"]

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
  && mix release ${RELEASE_NAME} \
  && rm -rf deps

#=============================================================================
# PRODUCTION IMAGE
#=============================================================================
FROM hexpm/elixir:1.13.4-erlang-25.0.2-alpine-3.16.0 AS prod

ARG RELEASE_NAME

ENV \
  PORT=4000 \
  LANG=C.UTF-8 \
  MIX_ENV=prod \
  RELEASE_NAME=${RELEASE_NAME}

RUN \
  addgroup -S kv \
  && adduser -S kv -G kv \
  && apk add --no-cache \
  openssl

USER kv

WORKDIR /app

COPY \
  --from=build \
  --chown=kv:kv \
  /app/_build/prod/rel/${RELEASE_NAME} \
  ./

RUN mv bin/${RELEASE_NAME} bin/run

EXPOSE 4000

ENTRYPOINT ["bin/run"]

CMD ["start"]
# CMD ["/bin/sh"]
