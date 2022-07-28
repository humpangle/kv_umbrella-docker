#!/bin/bash
# shellcheck disable=1090

function _timestamp {
  date +'%s'
}

function _raise_on_no_env_file {
  if [[ -z "$1" ]] || [[ ! -e "$1" ]]; then
    printf "\nenv filename has not been provided or invalid\n\n"
    exit 1
  fi
}

function _env {
  local env

  if [[ -n "$1" ]]; then
    env="$1"
  else
    env=".env"
  fi

  set -a
  . $env
  set +a

  splitenvs "$env" --lines
}

function build {
  : "Build docker image. Usage:"
  : "    run build .env.file"

  _raise_on_no_env_file "$1"

  _env "$1"
  clear

  local build_arg_release
  build_arg_release=""

  if [[ -n "$RELEASE_NAME" ]]; then
    build_arg_release="--build-arg RELEASE_NAME=${RELEASE_NAME}"
  fi

  local cmd

  cmd="docker build \
    -t $DOCKER_IMAGE_NAME \
    $build_arg_release \
    --target ${MIX_ENV:-dev} \
    ."

  printf "%s\n\n" "$cmd"
  eval "$cmd"
}

function docker.run {
  : "Run docker image"
  : "    docker.run .env.file"

  _raise_on_no_env_file "$1"

  _env "$1"
  clear

  local cmd

  cmd="docker run \
    --name kv-$(_timestamp) \
    -p 4000:4000 \
    $DOCKER_IMAGE_NAME"

  printf "%s\n\n" "$cmd"
  eval "$cmd"
}

function shell {
  : "Run iex shell. Example:"
  : "    run shell .env.dev."
  _env "$1"
  clear
  eval "$(_env "$1") iex -S mix"
}

function test {
  : "test watch. Example:"
  : "    run test .env.test"
  clear
  eval "$(_env "$1") mix test.interactive"
}

function test.a {
  : "test all. Example:"
  : "    run test.a .env.test"

  _raise_on_no_env_file "$1"
  _env "$1"
  clear

  local node_a
  local node_b
  local now

  now="$(date +'%s')"
  node_a="a$now@127.0.0.1"
  node_b="b$now@127.0.0.1"

  eval "$(_env "$1") \
      NO_START_SERVER=1 \
    elixir --name $node_a --no-halt -S \
      mix &"

  eval "$(_env "$1") \
      NODE1=$node_a \
      NODE2=$node_b \
    elixir --name $node_b -S \
      mix test --include distributed"

  wait
}

function help {
  : "List tasks"

  clear

  compgen -A function | grep -v "^_" | while read -r name; do
    paste <(printf '%s' "$name") <(type "$name" | sed -nEe 's/^[[:space:]]*: ?"(.*)";/    \1/p')
  done

  printf "\n"
}

TIMEFORMAT="Task completed in %3lR"
time "${@:-help}"
