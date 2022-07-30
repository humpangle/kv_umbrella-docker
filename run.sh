#!/bin/bash
# shellcheck disable=1090

function _printf {
  printf "\n%s\n\n" "$1"
}

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
  local splitted_envs=""

  if [[ -n "$1" ]]; then
    env="$1"
  elif [[ -e .env ]]; then
    env=".env"
  fi

  if [[ -n "$env" ]]; then
    set -a
    . $env
    set +a

    splitted_envs=$(splitenvs "$env" --lines)
  fi

  "$splitted_envs"
}

function telnet.r {
  : "Run telnet. Example:"
  : "                  bash run telnet.r [.env.file]"

  _env "$1"
  clear

  local cmd
  cmd="telnet 127.0.0.1 $DOCKER_HOST_PORT"

  _printf "$cmd"

  eval "$cmd"
}

function shell {
  : "        Run iex shell. Example:"
  : "                  bash run.sh shell"
  clear
  PORT=4001 iex -S mix
}

function test {
  : "        test watch. Example:"
  : "                  bash run.sh test"
  clear
  PORT=4002 mix test.interactive
}

function test.a {
  : "        test all. Example:"
  : "                  bash run.sh test.a"
  clear

  local node_a
  local node_b
  local now

  now="$(date +'%s')"
  node_a="a$now@127.0.0.1"
  node_b="b$now@127.0.0.1"

  NO_START_SERVER=1 \
    elixir --name "$node_a" --no-halt -S \
    mix &

  PORT=4003 \
    NODE1=$node_a \
    NODE2=$node_b \
    elixir --name "$node_b" -S \
    mix test --include distributed

  wait
}

function docker.r {
  : "Run production docker image."

  _env "$1"
  clear

  local cmd
  local container_name

  container_name="kv-$(_timestamp)"

  cmd="docker run -d --name $container_name $DOCKER_IMAGE_NAME"

  _printf "$cmd"

  echo "$@"

  eval "$cmd"
}

function dev {
  : "        Run development commands. Example:"
  : "                  bash run.sh dev"
  if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
    mix deps.get
    mix compile
  fi

  elixir --no-halt -S mix
}

function help {
  : "        List tasks"

  clear

  compgen -A function | grep -v "^_" | while read -r name; do
    paste <(printf '%s' "$name") <(type "$name" | sed -nEe 's/^[[:space:]]*: ?"(.*)";/ \1/p')
    printf "\n"
  done

  printf "\n"
}

TIMEFORMAT="Task completed in %3lR"
time "${@:-help}"
