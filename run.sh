#!/bin/bash
# shellcheck disable=1090

temp_node_name='kv_temp'

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

  printf "%s" "$splitted_envs"
}

function _printf {
  printf "\n%s\n\n" "$1"
}

function _timestamp {
  date +'%s'
}

function _raise_on_no_env_file {
  if [[ -n "$ENV_FILE" ]]; then
    if [[ "$ENV_FILE" =~ .env.example ]]; then
      printf "\nERROR: env filename can not be .env.example.\n\n"
      exit 1
    fi

    return 0
  fi

  if [[ -z "$1" ]] || [[ ! -e "$1" ]]; then
    printf "\nERROR:env filename has not been provided or invalid.\n"
    printf "You may also source your environment file.\n\n"
    exit 1
  fi
}

function _is_prod {
  [[ "$MIX_ENV" == "prod" ]] && echo 1
}

function _has_internet {
  if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
    printf 0
  fi

  printf 1
}

function _test {
  clear

  PORT=4001 \
    NO_START_SERVER='' \
    elixir \
    -S \
    mix test.interactive
}

function _test.a {
  local node

  node="${temp_node_name}_test"

  # Dev node already started by docker. We start a test node here. Inside
  # kv_test.ex (the test node), we connect to the dev node.

  PORT=4001 \
    NO_START_SERVER='' \
    DEV_NODE="$(_dev_node_name)" \
    elixir \
    --sname "$node" \
    -S \
    mix test --include distributed
}

function _maybe_start_container {
  if docker ps | grep -P "$COMPOSE_PROJECT_NAME" >/dev/null; then
    return
  fi

  _raise_on_no_env_file "$@"

  if _has_internet; then
    mix deps.get
  fi

  mix compile

  clear

  docker compose up -d "$RELEASE_NAME"
}

function _d {
  if _has_internet; then
    mix deps.get
  fi

  mix compile

  elixir \
    --no-halt \
    --name "$(_dev_node_name)" \
    -S \
    mix
}

function _dev_node_name {
  printf "dev@%s" "$RELEASE_NAME"
}

function _iex {
  local node
  node="${temp_node_name}_$(_timestamp)"

  PORT=5000 \
    iex \
    --sname "$node" \
    --remsh "$(_dev_node_name)" \
    -S \
    mix
}

function _get-containers {
  printf "%s" "$(
    docker ps --all --filter "ancestor=$DOCKER_IMAGE_NAME" 2>/dev/null |
      awk 'NR !=1 {print $NF}'
  )"
}

function _get-container-name {
  local the_container_name

  if [ -n "$CONTAINER_NAME" ]; then
    the_container_name="$CONTAINER_NAME"
  else
    the_container_name="$(
      docker compose ps |
        grep "$COMPOSE_PROJECT_NAME" |
        awk '{print $1}'
    )"
  fi

  printf '%s' "$the_container_name"
}

function _maybe-install-chokidar {
  if ! command -v chokidar; then
    npm install --global chokidar
  fi
}

# -----------------------------------------------------------------------------
# END HELPER FUNCTIONS
# -----------------------------------------------------------------------------

function t {
  : "Run non excluded tests inside docker. Example:"
  : "  run.sh t"

  _maybe_start_container "$@"

  docker compose exec "$RELEASE_NAME" \
    bash run.sh _test
}

function t.a {
  : "Run all tests including distributed tests. Example:"
  : "  run.sh t.a"

  _maybe-install-chokidar

  _maybe_start_container "$@"

  chokidar \
    "apps/**/*.ex*" \
    -i "**/mix.exs" \
    -i "**/priv/**" \
    -i "**/config/**" \
    --initial \
    -c "clear && docker compose exec t bash run.sh _test.a"
}

function diex {
  : "Run iex shell in docker. Example:"
  : "  run.sh diex"

  _raise_on_no_env_file "$@"

  if _is_prod; then
    docker compose exec p \
      bin/run remote
  else
    docker compose exec "$RELEASE_NAME" bash run.sh _iex
  fi
}

function d {
  : "Start dev/tests server: Example:"
  : "  r d"

  _maybe_start_container "$@"

  docker compose logs -f
}

function tel {
  : "Run telnet. Example:"
  : "  run.sh teln [.env.file]"

  _env "$1"

  clear

  local cmd
  cmd="telnet 127.0.0.1 $DOCKER_HOST_PORT"

  _printf "$cmd"

  eval "$cmd"
}

function rmc {
  : "Docker remove container: Example:"
  : "  run.sh rmc"

  _raise_on_no_env_file "$@"

  local the_container_name
  the_container_name="$(docker compose ps | grep "$COMPOSE_PROJECT_NAME" | awk '{print $1}')"

  if [ -n "$the_container_name" ]; then
    docker compose kill
    docker rm "$the_container_name"
  fi
}

function rmi {
  : "Docker remove image and associated containers and volumes. Example:"
  : "  run.sh rmi"

  _raise_on_no_env_file "$@"

  docker compose down -v &>/dev/null

  # container name = $COMPOSE_PROJECT_NAME-(docker compose service name)-(current count of containers started with that service)

  local image_id
  local containers
  local volumes_prefixes
  local volumes_prefixes_str

  mapfile -t containers < <(_get-containers)

  local containers_as_str="${containers[*]}"

  if [ -n "$containers_as_str" ]; then
    local cmd="docker rm --force --volumes $containers_as_str"
    eval "$cmd"
  fi

  for the_container_name in "${containers[@]}"; do
    mapfile -t volumes_prefixes < <(
      echo -n "$the_container_name" |
        awk 'BEGIN { FS = "-"; }
      { for(i=1; i < (NF - 1) ; i++ ) print $i }'
    )

    volumes_prefixes_str=$(
      IFS=-
      echo "${volumes_prefixes[*]}"
    )

    docker volume ls |
      grep "$volumes_prefixes_str" |
      awk '{print $2}' |
      xargs docker volume rm
  done

  image_id="$(
    docker images --filter "reference=$DOCKER_IMAGE_NAME" 2>/dev/null |
      awk 'NR !=1 {print $3}'
  )"

  if [ -n "$image_id" ]; then
    docker rmi "$image_id"
  fi
}

function remote {
  : "Connect to remote"

  _raise_on_no_env_file

  local remote_ip
  local node
  local the_container_name

  node="${temp_node_name}_$(_timestamp)@127.0.0.1"

  the_container_name="$(_get-container-name)"

  remote_ip="$(
    docker inspect \
      --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
      "$the_container_name"
  )"

  iex \
    --name "${node}" \
    --cookie "${RELEASE_COOKIE}" \
    --remsh "kv@${remote_ip}"
}

function help {
  : "List available tasks."
  compgen -A function | grep -v "^_" | while read -r name; do
    paste <(printf '%s' "$name") <(type "$name" | sed -nEe 's/^[[:space:]]*: ?"(.*)";/    \1/p')
    printf "\n"
  done

  printf "\n"
}

TIMEFORMAT="Task completed in %3lR"
time "${@:-help}"
