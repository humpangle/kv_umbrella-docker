#!/bin/bash

function _env {
  local env

  if [[ -n "$1" ]]; then
    env="$1"
  else
    env=".env"
  fi

  splitenvs "$env" --lines
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

  local node_a
  local node_b
  local now

  now="$(date +'%s')"
  node_a="a$now@127.0.0.1"
  node_b="b$now@127.0.0.1"

  clear

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
