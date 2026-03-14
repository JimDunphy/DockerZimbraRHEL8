#!/bin/bash

#
# Author: Jim Dunphy (4/21/2025)
#
# Purpose:
#     Build and run an Oracle Linux 8 Docker image for Zimbra build and test
#     work, including one-shot generation of zimbra.war for Project Z Bridge.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-oracle8/zimbra}"
CONTAINER_NAME="${CONTAINER_NAME:-zimbra}"
USER_NAME="${USER_NAME:-$(id -nu)}"
USER_UID="${USER_UID:-$(id -u)}"
USER_GID="${USER_GID:-$(id -g)}"
SSH_PORT="${SSH_PORT:-717}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa.pub}"
ZIMBRA_DIR="${ZIMBRA_DIR:-$SCRIPT_DIR/Zimbra}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$SCRIPT_DIR}"

ACTION="--help"
WAR_VERSION=""
COPY_SSH_KEYS=0
ALLOW_DIRTY=0

show_help() {
  cat <<EOF
Usage: $0 [action] [options]

Actions:
  --build                 Build the Docker image
  --run                   Run the container attached
  --run-detached          Run the container in the background
  --shell                 Open a root shell in the running container
  --stop                  Stop the running container
  --status                Show container status
  --resume                Start an existing container
  --init                  Set up the mounted workspace with helper scripts
  --build-war VERSION     Build zimbra.war inside the container and print the host path
  --purge                 Run docker system prune --volumes
  --help                  Show this help message

Options:
  --zimbra-dir DIR        Host workspace mounted at /mnt/zimbra
                          Default: ${ZIMBRA_DIR}
                          The returned zimbra.war is copied beside docker.sh
  --copy-ssh-keys         Copy ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub into the workspace
  --allow-dirty           Reuse local edits under ./Zimbra/zwc-war when the
                          existing checkout is already on the resolved tag
EOF
}

log() {
  printf '[docker.sh] %s\n' "$*"
}

fail() {
  printf '[docker.sh] ERROR: %s\n' "$*" >&2
  exit 1
}

fail_workspace_conflict() {
  local existing_mount="$1"
  local container_state="$2"

  cat >&2 <<EOF
[docker.sh] ERROR: Cannot use container ${CONTAINER_NAME} for this one-shot build.
[docker.sh] Requested workspace: ${ZIMBRA_DIR}
[docker.sh] Existing container workspace: ${existing_mount}
[docker.sh] Container state: ${container_state}
[docker.sh] Nothing was changed on the host or in that container.
[docker.sh] Use one of:
[docker.sh]   ./docker.sh --zimbra-dir "${existing_mount}" --build-war ${WAR_VERSION}
[docker.sh]   ./docker.sh --stop
[docker.sh]   CONTAINER_NAME=<other-name> ./docker.sh --build-war ${WAR_VERSION}
EOF
  exit 1
}

resolve_path() {
  local input="$1"

  case "$input" in
    /*)
      printf '%s\n' "$input"
      ;;
    *)
      printf '%s/%s\n' "$(pwd -P)" "$input"
      ;;
  esac
}

container_exists() {
  docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = "true" ]
}

container_mount_source() {
  docker inspect -f '{{range .Mounts}}{{if eq .Destination "/mnt/zimbra"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null
}

build_image() {
  local status=0
  local ssh_pubkey=""

  if [ -f "$SSH_KEY" ]; then
    ssh_pubkey="$(tr -d '\r\n' < "$SSH_KEY")"
    log "Building Docker image as user '${USER_NAME}' with container SSH key support"
  else
    log "Building Docker image as user '${USER_NAME}' without container SSH key support"
  fi

  if docker build \
    --build-arg USER_NAME="$USER_NAME" \
    --build-arg USER_UID="$USER_UID" \
    --build-arg USER_GID="$USER_GID" \
    --build-arg SSH_PUBKEY="$ssh_pubkey" \
    -t "$IMAGE_NAME" \
    "$SCRIPT_DIR"
  then
    status=0
  else
    status=$?
  fi

  [ "$status" -eq 0 ] || exit "$status"

  log "Build complete"
}

run_container() {
  local skip_dns="${1:-${ZIMBRA_SKIP_DNS_SETUP:-0}}"
  local publish_ssh="${2:-1}"
  local skip_ssh_setup="${3:-0}"
  local docker_args=()

  log "Running container attached"
  docker_args=(
    -it
    --hostname mail.example.com
    --name "$CONTAINER_NAME"
    -e "ZIMBRA_SKIP_DNS_SETUP=${skip_dns}"
    -e "ZIMBRA_SKIP_SSH_SETUP=${skip_ssh_setup}"
    -v "${ZIMBRA_DIR}":/mnt/zimbra
  )
  if [ "$publish_ssh" -eq 1 ]; then
    docker_args+=(-p "${SSH_PORT}:22")
  fi
  docker run "${docker_args[@]}" "$IMAGE_NAME"
}

run_container_detached() {
  local skip_dns="${1:-${ZIMBRA_SKIP_DNS_SETUP:-0}}"
  local publish_ssh="${2:-1}"
  local skip_ssh_setup="${3:-0}"
  local docker_args=()

  log "Running container in the background"
  docker_args=(
    -dit
    --hostname mail.example.com
    --name "$CONTAINER_NAME"
    -e "ZIMBRA_SKIP_DNS_SETUP=${skip_dns}"
    -e "ZIMBRA_SKIP_SSH_SETUP=${skip_ssh_setup}"
    -v "${ZIMBRA_DIR}":/mnt/zimbra
  )
  if [ "$publish_ssh" -eq 1 ]; then
    docker_args+=(-p "${SSH_PORT}:22")
  fi
  docker run "${docker_args[@]}" "$IMAGE_NAME"
}

shell_container() {
  container_running || fail "Container ${CONTAINER_NAME} is not running"
  log "Opening a root shell in ${CONTAINER_NAME}"
  docker exec -it "$CONTAINER_NAME" /bin/bash
}

stop_container() {
  if container_running; then
    log "Stopping ${CONTAINER_NAME}"
    docker stop "$CONTAINER_NAME"
  else
    log "Container ${CONTAINER_NAME} is not running"
  fi
}

status_container() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

resume_container() {
  if container_running; then
    log "Container ${CONTAINER_NAME} is already running"
    return
  fi

  container_exists || fail "Container ${CONTAINER_NAME} does not exist"
  log "Starting ${CONTAINER_NAME}"
  docker start "$CONTAINER_NAME"
}

init_zimbra_dir() {
  log "Initializing host workspace ${ZIMBRA_DIR}"
  mkdir -p "$ZIMBRA_DIR"

  cp "${SCRIPT_DIR}/setup_env.sh" "${ZIMBRA_DIR}/setup_env.sh"
  cp "${SCRIPT_DIR}/build_zimbra.sh" "${ZIMBRA_DIR}/build_zimbra.sh"
  cp "${SCRIPT_DIR}/build_zm_web_client_war.sh" "${ZIMBRA_DIR}/build_zm_web_client_war.sh"
  chmod +x \
    "${ZIMBRA_DIR}/setup_env.sh" \
    "${ZIMBRA_DIR}/build_zimbra.sh" \
    "${ZIMBRA_DIR}/build_zm_web_client_war.sh"

  if [ "$COPY_SSH_KEYS" -eq 1 ]; then
    if [ -f "$HOME/.ssh/id_rsa" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
      log "Copying SSH keys into ${ZIMBRA_DIR}"
      cp "$HOME/.ssh/id_rsa" "${ZIMBRA_DIR}/"
      cp "$HOME/.ssh/id_rsa.pub" "${ZIMBRA_DIR}/"
      chmod 600 "${ZIMBRA_DIR}/id_rsa"
    else
      fail "--copy-ssh-keys was requested, but ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub were not found"
    fi
  else
    log "SSH keys were not copied; use --copy-ssh-keys or stage them manually if needed"
  fi

  cat > "${ZIMBRA_DIR}/.gitignore" <<EOF
# Never commit private keys
id_rsa
id_rsa.pub
ssh-keys.tar
EOF

  log "Initialization complete"
}

wait_for_exec() {
  local attempt

  for attempt in $(seq 1 60); do
    if docker exec -u "$USER_NAME" "$CONTAINER_NAME" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  fail "Container ${CONTAINER_NAME} did not become ready for docker exec as ${USER_NAME}"
}

run_war_build_in_container() {
  local version="$1"
  local dirty_flag=""

  if [ "$ALLOW_DIRTY" -eq 1 ]; then
    dirty_flag="--allow-dirty"
  fi

  docker exec -i -u "$USER_NAME" "$CONTAINER_NAME" bash -s -- "$version" "$dirty_flag" <<'EOF'
set -euo pipefail

version="$1"
dirty_flag="$2"

cd /mnt/zimbra
./build_zm_web_client_war.sh --init
./build_zm_web_client_war.sh --version "$version" --workdir /mnt/zimbra/zwc-war --output-dir /mnt/zimbra ${dirty_flag}
EOF
}

latest_war_after() {
  local after_epoch="$1"
  local artifact=""
  local artifact_epoch=""

  artifact="$(
    find "$ZIMBRA_DIR" -maxdepth 1 -type f -name 'zimbra-*.war' -printf '%T@\t%p\n' \
      | sort -nr -k1,1 \
      | head -n1 \
      | cut -f2-
  )"

  [ -n "$artifact" ] || return 1

  artifact_epoch="$(stat -c %Y "$artifact")"
  [ "$artifact_epoch" -ge "$after_epoch" ] || return 1

  printf '%s\n' "$artifact"
}

build_war() {
  local before_epoch=""
  local artifact=""
  local final_artifact=""
  local stop_after=0
  local existing_mount=""
  local existing_state="stopped"

  [ -n "$WAR_VERSION" ] || fail "--build-war requires a version"

  if container_exists; then
    existing_mount="$(container_mount_source)"
    if [ -n "$existing_mount" ] && [ "$existing_mount" != "$ZIMBRA_DIR" ]; then
      if container_running; then
        existing_state="running"
      fi
      fail_workspace_conflict "$existing_mount" "$existing_state"
    fi
  fi

  log "Host changes for this command are limited to ${ZIMBRA_DIR} and ${ARTIFACT_DIR}/zimbra-*.war"
  log "Package installation and compilation happen inside the container"
  log "Container source workspace for this command: /mnt/zimbra/zwc-war"
  init_zimbra_dir

  if container_running; then
    log "Using running container ${CONTAINER_NAME}"
  elif container_exists; then
    log "Starting existing container ${CONTAINER_NAME}"
    docker start "$CONTAINER_NAME" >/dev/null
    stop_after=1
  else
    build_image

    run_container_detached 1 0 1 >/dev/null
    stop_after=1
  fi

  wait_for_exec

  before_epoch="$(date +%s)"
  log "Building zimbra.war for ${WAR_VERSION}"
  run_war_build_in_container "$WAR_VERSION"

  artifact="$(latest_war_after "$before_epoch")" || fail "zimbra.war was not copied back to ${ZIMBRA_DIR}"
  final_artifact="${ARTIFACT_DIR}/$(basename "$artifact")"
  if [ "$artifact" != "$final_artifact" ]; then
    cp "$artifact" "$final_artifact"
  fi
  log "Artifact ready on host: ${final_artifact}"
  printf '%s\n' "$final_artifact"

  if [ "$stop_after" -eq 1 ]; then
    log "Stopping container started for this one-shot build"
    docker stop "$CONTAINER_NAME" >/dev/null
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --build|--run|--run-detached|--shell|--stop|--status|--resume|--init|--purge|--help)
        [ "$ACTION" = "--help" ] || fail "Only one primary action may be specified"
        ACTION="$1"
        shift
        ;;
      --build-war)
        [ "$ACTION" = "--help" ] || fail "Only one primary action may be specified"
        [ "$#" -ge 2 ] || fail "--build-war requires a version"
        ACTION="--build-war"
        WAR_VERSION="$2"
        shift 2
        ;;
      --zimbra-dir)
        [ "$#" -ge 2 ] || fail "--zimbra-dir requires a directory"
        ZIMBRA_DIR="$(resolve_path "$2")"
        shift 2
        ;;
      --copy-ssh-keys)
        COPY_SSH_KEYS=1
        shift
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        shift
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  case "$ACTION" in
    --build)
      build_image
      ;;
    --run)
      run_container
      ;;
    --run-detached)
      run_container_detached
      ;;
    --shell)
      shell_container
      ;;
    --stop)
      stop_container
      ;;
    --status)
      status_container
      ;;
    --resume)
      resume_container
      ;;
    --init)
      init_zimbra_dir
      ;;
    --build-war)
      build_war
      ;;
    --purge)
      docker system prune --volumes
      ;;
    --help)
      show_help
      ;;
  esac
}

main "$@"
exit 0
