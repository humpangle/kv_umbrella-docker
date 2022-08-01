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

function _is_prod {
  [[ "$MIX_ENV" == "prod" ]] && echo 1
}

function _iex {
  : "        Run iex shell. Example:"
  : "                  bash run.sh shell"
  clear

  local node_name
  node_name="kv_iex_$(_timestamp)@d"

  PORT=4001 iex --sname "$node_name" --remsh kv_dev@d -S mix
}

function _test {
  : "        test watch. Example:"
  : "                  bash run.sh test"
  clear

  local node_name
  node_name="kv_test_$(_timestamp)@d"

  PORT=4002 \
    elixir --sname "$node_name" -S \
    mix test.interactive
}

function _test.a {
  : "        test all. Example:"
  : "                  bash run.sh test.a"
  clear

  local node_a
  local node_b
  local now

  now="$(date +'%s')"
  node_a="a_test_$now@d"
  node_b="b_test_$now@d"

  NO_START_SERVER=1 \
    elixir --sname "$node_a" --no-halt -S \
    mix &

  PORT=4003 \
    NODE1=$node_a \
    NODE2=$node_b \
    elixir --sname "$node_b" -S \
    mix test --include distributed

  wait
}

function test {
  : "Run non excluded tests inside docker. Example:"
  : "          run.sh test"
  docker compose exec d bash run.sh _test
}

function test.a {
  : "Run all tests inside docker. Example:"
  : "          run.sh test.a"
  docker compose exec d bash run.sh _test.a
}

function diex {
  : "Run iex shell in docker. Example:"
  : "          run.sh d.iex"

  if [[ "$(_is_prod)" ]]; then
    docker compose exec p bin/run remote
  else
    docker compose exec d bash run.sh _iex
  fi
}

function sh {
  : "Run sh/bash inside docker. Example:"
  : "          run.sh sh"

  if [[ "$(_is_prod)" ]]; then
    docker compose exec p sh
  else
    docker compose exec d bash
  fi
}

function dev {
  : "Run development commands. Example:"
  : "                  bash run.sh dev"
  if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
    mix deps.get
    mix compile
  fi

  elixir --sname kv_dev@d --no-halt -S mix
}

function tel {
  : "Run telnet. Example:"
  : "                  bash run telnet.r [.env.file]"

  _env "$1"

  clear

  local cmd
  cmd="telnet 127.0.0.1 $DOCKER_HOST_PORT"

  _printf "$cmd"

  eval "$cmd"
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
