#!/bin/bash

#
# Author: Jim Dunphy / Codex (3/13/2026)
#
# Purpose:
#   Build zm-web-client and produce zimbra.war inside the DockerZimbraRHEL8
#   container. This is intended to be run as the normal user over SSH.
#
# Caveat:
#   --init does not invent its own system dependency model. It delegates to
#   build_zimbra.sh --init when the environment is not already present.
#   That means build_zimbra.sh must be available alongside this script, in the
#   current directory, in ~/mybuild, or under /mnt/zimbra.
#
#   This repository ships a copy of build_zimbra.sh. If someone copies only
#   build_zm_web_client_war.sh by itself, then --init may fail until
#   build_zimbra.sh is also made available.
#
#   Upstream source for build_zimbra.sh:
#   https://github.com/JimDunphy/build_zimbra.sh
#
# Example:
#   ./build_zm_web_client_war.sh --init
#   ./build_zm_web_client_war.sh --version 10.1.16
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQUESTED_VERSION=""
RESOLVED_VERSION=""
WORKDIR="${HOME}/mybuild/zwc-war"
OUTPUT_DIR="/mnt/zimbra"
REMOTE_PREFIX="https://github.com/Zimbra"
ZCS_DEPS_DIR="${HOME}/.zcs-deps"
ANT_CONTRIB_JAR="${ZCS_DEPS_DIR}/ant-contrib-1.0b1.jar"
ANT_CONTRIB_URL="https://files.zimbra.com/repository/ant-contrib/ant-contrib-1.0b1.jar"
COPY_ARTIFACT=1
INIT_ONLY=0

REPOS=(
  "zm-build"
  "zm-zcs"
  "zm-mailbox"
  "zm-taglib"
  "zm-ajax"
  "zm-web-client"
)

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--init] [--version VERSION] [options]

Build zm-web-client and produce zimbra.war for a Zimbra release.

Options:
  --init                Reuse build_zimbra.sh --init if setup is not already present
                        build_zimbra.sh must be available unless the build
                        environment is already prepared
  --version VERSION     Release to build, e.g. 10.1 or 10.1.16
  --workdir DIR         Workspace to clone/build in (default: ${WORKDIR})
  --output-dir DIR      Copy zimbra.war to DIR (default: ${OUTPUT_DIR})
  --no-copy             Do not copy the finished war to the output directory
  --remote-prefix URL   Git prefix (default: ${REMOTE_PREFIX})
  --help                Show this help
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

version_le() {
  printf '%s\n%s\n' "$1" "$2" | sort -C -V
}

series_from_version() {
  local version="$1"
  printf '%s.%s\n' "${version%%.*}" "$(printf '%s' "$version" | cut -d. -f2)"
}

fetch_series_tags() {
  local repo_url="$1"
  local series="$2"
  local escaped_series="${series//./\\.}"

  git ls-remote --tags --refs "$repo_url" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | { grep -E "^${escaped_series}\\.[0-9]+$" || true; } \
    | sort -V
}

find_best_tag() {
  local repo_url="$1"
  local request="$2"
  local series
  local tags
  local tag

  series="$(series_from_version "$request")"
  tags="$(fetch_series_tags "$repo_url" "$series")"
  [ -n "$tags" ] || fail "No matching tags found in ${repo_url} for ${series}.x"

  if [[ "$request" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$tags" | tail -n 1
    return
  fi

  while IFS= read -r tag; do
    if version_le "$tag" "$request"; then
      printf '%s\n' "$tag"
      return
    fi
  done < <(printf '%s\n' "$tags" | tac)

  fail "No tag in ${repo_url} is <= ${request}"
}

ensure_commands() {
  local cmd
  for cmd in git ant java sort awk sed grep; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
  done
}

find_ant_contrib_jar() {
  local candidate

  for candidate in \
    "${ANT_CONTRIB_JAR}" \
    "/usr/share/java/ant-contrib/ant-contrib.jar" \
    "/usr/share/ant/lib/ant-contrib.jar" \
    "/usr/share/java/ant-contrib.jar"
  do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

bootstrap_ant_contrib_jar() {
  local tmp_file="${ANT_CONTRIB_JAR}.tmp"

  mkdir -p "${ZCS_DEPS_DIR}"

  if [ -f "${ANT_CONTRIB_JAR}" ]; then
    return
  fi

  log "Bootstrapping ant-contrib from ${ANT_CONTRIB_URL}"

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "${tmp_file}" "${ANT_CONTRIB_URL}"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "${ANT_CONTRIB_URL}" -o "${tmp_file}"
  else
    fail "wget or curl is required to fetch ${ANT_CONTRIB_URL}"
  fi

  mv "${tmp_file}" "${ANT_CONTRIB_JAR}"
}

find_build_zimbra_script() {
  local candidate

  for candidate in \
    "${SCRIPT_DIR}/build_zimbra.sh" \
    "${PWD}/build_zimbra.sh" \
    "${HOME}/mybuild/build_zimbra.sh" \
    "/mnt/zimbra/build_zimbra.sh"
  do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || fail "sudo is required to install prerequisites"
    sudo "$@"
  fi
}

delegate_build_zimbra_init() {
  local init_script=""

  init_script="$(find_build_zimbra_script)" || fail "build_zimbra.sh not found; cannot delegate --init"
  log "Delegating environment setup to ${init_script} --init"
  "$init_script" --init
}

ensure_prereqs() {
  local ant_contrib_jar=""

  if [ "$INIT_ONLY" -eq 1 ]; then
    if command -v ant >/dev/null 2>&1 && command -v java >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
      if ant_contrib_jar="$(find_ant_contrib_jar)"; then
        log "Build environment already present"
        log "Using ant-contrib jar: ${ant_contrib_jar}"
        return
      fi
    fi

    delegate_build_zimbra_init
    if ! ant_contrib_jar="$(find_ant_contrib_jar)"; then
      bootstrap_ant_contrib_jar
      ant_contrib_jar="$(find_ant_contrib_jar)" || fail "build_zimbra.sh --init completed, but ant-contrib jar is still missing"
    fi
    log "Using ant-contrib jar: ${ant_contrib_jar}"
    return
  fi

  ensure_commands

  if ant_contrib_jar="$(find_ant_contrib_jar)"; then
    log "Using ant-contrib jar: ${ant_contrib_jar}"
    return
  fi

  bootstrap_ant_contrib_jar
  ant_contrib_jar="$(find_ant_contrib_jar)" || fail "ant-contrib jar not found after bootstrap"
  log "Using ant-contrib jar: ${ant_contrib_jar}"
}

resolve_version() {
  if [[ ! "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    fail "Version must look like 10.1 or 10.1.16"
  fi

  RESOLVED_VERSION="$(find_best_tag "${REMOTE_PREFIX}/zm-build.git" "$REQUESTED_VERSION")"

  log "Requested version: ${REQUESTED_VERSION}"
  log "Resolved version: ${RESOLVED_VERSION}"
}

assert_clean_repo() {
  local repo_dir="$1"
  local status

  status="$(git -C "$repo_dir" status --porcelain)"
  [ -z "$status" ] || fail "Repository ${repo_dir} has local changes; use a clean workdir"
}

clone_or_checkout_repo() {
  local repo="$1"
  local tag="$2"
  local repo_url="${REMOTE_PREFIX}/${repo}.git"
  local repo_dir="${WORKDIR}/${repo}"
  local current_tag=""

  if [ ! -d "$repo_dir" ]; then
    log "Cloning ${repo} at ${tag}"
    git clone --depth 1 --branch "$tag" "$repo_url" "$repo_dir"
    return
  fi

  [ -d "${repo_dir}/.git" ] || fail "${repo_dir} exists but is not a git repository"
  assert_clean_repo "$repo_dir"

  current_tag="$(git -C "$repo_dir" describe --tags --exact-match 2>/dev/null || true)"
  if [ "$current_tag" = "$tag" ]; then
    log "Using existing ${repo} checkout at ${tag}"
    return
  fi

  log "Updating ${repo} to ${tag}"
  git -C "$repo_dir" fetch --depth 1 origin "refs/tags/${tag}:refs/tags/${tag}"
  git -C "$repo_dir" checkout --detach "$tag"
}

write_release_files() {
  local major minor micro

  IFS='.' read -r major minor micro <<<"$RESOLVED_VERSION"
  mkdir -p "${WORKDIR}/zm-build/RE"
  printf '%s\n' "$major" > "${WORKDIR}/zm-build/RE/MAJOR"
  printf '%s\n' "$minor" > "${WORKDIR}/zm-build/RE/MINOR"
  printf '%s_GA\n' "$micro" > "${WORKDIR}/zm-build/RE/MICRO"
}

build_mailbox_artifacts() {
  log "Publishing zm-mailbox artifacts"
  (
    cd "${WORKDIR}/zm-mailbox"
    ant -Dzimbra.buildinfo.version="${RESOLVED_VERSION}_GA_1001" publish-local-all
  )
}

build_taglib_artifacts() {
  log "Publishing zm-taglib artifacts"
  (
    cd "${WORKDIR}/zm-taglib"
    ant publish-local
  )
}

build_ajax_artifacts() {
  log "Publishing zm-ajax artifacts"
  (
    cd "${WORKDIR}/zm-ajax"
    ant publish-local
  )
}

build_web_client_war() {
  log "Building zm-web-client zimbra.war"
  (
    cd "${WORKDIR}/zm-web-client"
    ant clean-pkg prod-war
  )
}

copy_artifact() {
  local artifact="${WORKDIR}/zm-web-client/build/dist/jetty/webapps/zimbra.war"
  local output_file="${OUTPUT_DIR}/zimbra-${RESOLVED_VERSION}.war"

  [ -f "$artifact" ] || fail "Expected artifact not found: ${artifact}"

  log "Built artifact: ${artifact}"
  if [ "$COPY_ARTIFACT" -ne 1 ]; then
    return
  fi

  if [ -d "$OUTPUT_DIR" ]; then
    cp "$artifact" "$output_file"
    log "Copied artifact to ${output_file}"
  else
    log "Output directory ${OUTPUT_DIR} not present; skipping copy"
  fi
}

resolve_repo_tags() {
  local repo
  local tag

  for repo in "${REPOS[@]}"; do
    tag="$(find_best_tag "${REMOTE_PREFIX}/${repo}.git" "$RESOLVED_VERSION")"
    log "${repo} tag: ${tag}"
    clone_or_checkout_repo "$repo" "$tag"
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --init)
        INIT_ONLY=1
        shift
        ;;
      --version)
        [ "$#" -ge 2 ] || fail "--version requires an argument"
        REQUESTED_VERSION="$2"
        shift 2
        ;;
      --workdir)
        [ "$#" -ge 2 ] || fail "--workdir requires an argument"
        WORKDIR="$2"
        shift 2
        ;;
      --output-dir)
        [ "$#" -ge 2 ] || fail "--output-dir requires an argument"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --no-copy)
        COPY_ARTIFACT=0
        shift
        ;;
      --remote-prefix)
        [ "$#" -ge 2 ] || fail "--remote-prefix requires an argument"
        REMOTE_PREFIX="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  ensure_prereqs

  if [ "$INIT_ONLY" -eq 1 ]; then
    log "Initialization complete"
    exit 0
  fi

  resolve_version
  mkdir -p "$WORKDIR"
  resolve_repo_tags
  write_release_files
  build_mailbox_artifacts
  build_taglib_artifacts
  build_ajax_artifacts
  build_web_client_war
  copy_artifact
}

main "$@"
