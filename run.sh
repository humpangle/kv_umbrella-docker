#!/usr/bin/env bash
# shellcheck disable=1090,2207

temp_node_name='kv_temp'

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
    return 0
  fi

  return 1
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

  docker compose up -d d
}

function _d {
  if _has_internet; then
    mix deps.get
  fi

  mix compile

  elixir \
    --no-halt \
    --name "$(_dev_node_name)" \
    --cookie "${RELEASE_COOKIE}" \
    -S \
    mix
}

function _dev_node_name {
  local hostname_=

  if [ -e "/.dockerenv" ]; then
    # Inside container
    hostname_="$(hostname -i)"
  else
    # On container host
    hostname_="$(exec-cmd hostname -i)"
  fi

  printf "%s@%s" "$COMPOSE_PROJECT_NAME" "$hostname_"
}

function _iex {
  local temp_node_name

  temp_node_name="${temp_node_name}_$(_timestamp)@$(hostname -i)"

  PORT=5000 \
    AUTO_JOIN_NODES=false \
    iex \
    --name "$temp_node_name" \
    --remsh "$(_dev_node_name)" \
    --werl \
    --hidden \
    --cookie "${RELEASE_COOKIE}" \
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

  the_container_name="$(
    docker compose ps |
      grep "$COMPOSE_PROJECT_NAME" |
      awk '{print $1}'
  )"

  printf '%s' "$the_container_name"
}

_clear() {
  clear && printf '\e[3J'
}

# -----------------------------------------------------------------------------
# END HELPER FUNCTIONS
# -----------------------------------------------------------------------------

___t_help() {
  : "___help___ ___t_help"
  read -r -d '' var <<'eof' || true
Run tests. Usage:
  rum.sh t [OPTIONS]

By default, we will run non distributed tests.

Options:
  -h
    Print this help text and quit.
  -a
    Run all tests including distributed tests.

Examples:
  # Get help.
  rum.sh t --help
  rum.sh t -h

  # Exclude distributed tests from run.
  rum.sh t

  # Run all tests including distributed tests.
  run.sh t -a
eof

  echo -e "${var}"
}

function t {
  : "___help___ ___t_help"

  _maybe_start_container "$@"

  local all_=
  local parsed_=

  while getopts 'ha' parsed_; do
    case "$parsed_" in
    h)
      ___t_help
      exit
      ;;

    a)
      all_=1
      shift
      ;;
    *)
      echo "Unknown argument: $parsed_"
      ___t_help
      exit 1
      ;;
    esac
  done

  local envs_="-e START_SERVER=true \
    -e AUTO_JOIN_NODES=false \
    -e DEBUG_LIB_CLUSTER=true \
    -e PORT=4001 \
    -e MIX_ENV=test"

  local mix_cmd_="'\
    __other_args__ \
    -S mix'"

  local mix_cmd_other_args_=''

  local test_args_=''

  if [ -n "$all_" ]; then
    envs_+=" -e DEV_NODE=$(_dev_node_name)"

    # Dev node already started by docker.
    # We start a test node (temp_node_name_) here. Inside kv_test.ex (the test node), we connect to the dev node
    # ($DEV_NODE).

    local temp_node_name_=
    temp_node_name_="${temp_node_name}_test_$(date +'%s')@$(exec-cmd hostname -i)"

    mix_cmd_other_args_="\
      --name $temp_node_name_ \
      --cookie ${RELEASE_COOKIE}"

    test_args_="--include distributed"
  fi

  mix_cmd_="${mix_cmd_//__other_args__/$mix_cmd_other_args_}"

  envs_+=" -e MIX_TEST_INTERACTIVE_COMMAND_CONFIG=${mix_cmd_}"

  local cmd_string_="docker compose exec \
    $envs_ d mix test.interactive $test_args_"

  eval "$cmd_string_"
}

exec-cmd() {
  local envs_="-e START_SERVER=false \
    -e AUTO_JOIN_NODES=false \
    -e DEBUG_LIB_CLUSTER=false \
    -e PORT=4001"

  local cmd_string_="docker compose exec $envs_ d $*"
  eval "$cmd_string_"
}

function diex {
  : "Run iex shell in docker. Example:"
  : "  run.sh diex"

  _raise_on_no_env_file "$@"

  if _is_prod; then
    docker compose exec p \
      bin/run remote
  else
    docker compose exec d bash run.sh _iex
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

  local image_id
  local containers
  local volumes_prefixes
  local volumes_prefixes_str

  mapfile -t containers < <(_get-containers)

  for the_container_name in "${containers[@]}"; do
    docker kill --signal SIGTERM "$the_container_name"
    docker rm --force --volumes "$the_container_name"

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

function ls-ports {
  : "List ports in use"

  local line_regex="^[^#]+PORT.*=[^$]+"

  local ports=()

  local old_ifs="$IFS"

  for filename in ./.env*; do
    if [[ "$filename" == "./.env.example" ]]; then
      continue
    fi

    while read -r line; do
      if [[ "$line" =~ $line_regex ]]; then
        ports+=("$(echo "$line" | cut -d'=' -f 2-)")
      fi
    done <<<"$(cat "$filename")"
  done

  # shellcheck disable=2207
  IFS=$'\n' ports=($(sort -u <<<"${ports[*]}"))

  IFS="$old_ifs"

  echo "${ports[*]}"
}

function p {
  : "Start production app. Example:"
  : "  run.sh p"

  _raise_on_no_env_file

  docker compose up p
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
