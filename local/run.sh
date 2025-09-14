#!/usr/bin/env bash
set -eo pipefail

log() { echo "[$PROJECT_NAME:$1] $2"; }
fail() { log "error" "$1"; exit 1; }

PROJECT_NAME="$(basename "$(pwd)${1:+/config/libs/$1}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
PROJECT_DIR="$(pwd)"
DEVELOP_DIR="./local"

COOKBOOK_OVERRIDE="$1"
RECIPE="${COOKBOOK_OVERRIDE:-config}"

COOKBOOK_PATH="['/tmp/config','/tmp/config/libs']"

[[ -f "${DEVELOP_DIR}/config.json" ]] && CONFIG_FILE=("-j ${DEVELOP_DIR}/config.json")
[[ -n "${COOKBOOK_OVERRIDE}" ]] && [[ -f "./libs/${COOKBOOK_OVERRIDE}/config.json" ]] && CONFIG_FILE="-j ./libs/${COOKBOOK_OVERRIDE}/config.json"

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')}"
DOCKER_CONTAINER_NAME="${COOKBOOK_OVERRIDE:-"$PROJECT_NAME"}"
DOCKER_WAIT="${DOCKER_WAIT:-3}"
UNAME_ARCH="$(uname -m)"
case "$UNAME_ARCH" in
  aarch64|arm64) TARGETARCH="arm64" ;;
  x86_64) TARGETARCH="amd64" ;;
  *) TARGETARCH="unknown" ;;
esac
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/${TARGETARCH}}"

DOCKERFILE_PATH="${DEVELOP_DIR}/Dockerfile"
BASE=$(find "base" -type f -not -path "*/.git/*" -print0 | sort -z | xargs -0 md5sum | md5sum | awk '{print $1}')
HASH=$(echo "$(md5sum "$DOCKERFILE_PATH" | awk '{print $1}')${BASE}" | md5sum | awk '{print $1}')
STORED_HASH_FILE="${DEVELOP_DIR}/.local.hash"
STORED_HASH=$(cat "$STORED_HASH_FILE" 2>/dev/null || true)

# Container

if [[ -z "$(docker images -q "${DOCKER_IMAGE_NAME}")" || "$STORED_HASH" != "$HASH" ]]; then
    log "image" "build_required"
    docker build --no-cache --build-arg TARGETARCH="$TARGETARCH" -t "$DOCKER_IMAGE_NAME" -f "$DOCKERFILE_PATH" "$PROJECT_DIR" || fail "build_failed"
    echo "$HASH" > "$STORED_HASH_FILE"
    log "image" "build_complete"
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
    log "container" "remove_existing"
    docker stop "$DOCKER_CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f -v "$DOCKER_CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

log "container" "start"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw --add-host=host.docker.internal:host-gateway \
    $( [[ -n "${COOKBOOK_OVERRIDE}" ]] && echo "-p 80:80 -e HOST=host.docker.internal" || echo "-p 8080:8080 -p 2222:2222" ) \
    --name "$DOCKER_CONTAINER_NAME" -w /tmp/config "$DOCKER_IMAGE_NAME" sleep infinity) || fail "container_start_failed"

if [[ -d "${DEVELOP_DIR}/share" ]]; then
  log "sync" "share"
  docker cp "$PROJECT_DIR/local/share" "$CONTAINER_ID:/share" || fail "share_sync_failed"
fi

log "container" "started:${CONTAINER_ID}"

sync() {
  log "sync" "files"
  docker cp "$PROJECT_DIR/." "$CONTAINER_ID:/tmp/config/" || fail "sync_failed"

  if [[ -n "${COOKBOOK_OVERRIDE}" ]]; then
    log "sync" "libraries"
    docker exec "$CONTAINER_ID" bash -c "mkdir -p '/tmp/config/libs/${COOKBOOK_OVERRIDE}/libraries' && cp -a /tmp/config/config/libraries/. '/tmp/config/libs/${COOKBOOK_OVERRIDE}/libraries/'" || fail "libraries_sync_failed"
  fi
}

# Configure

run() {
  sync
  command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID,HOST \
    cinc-client -l info --local-mode --config-option node_path=/tmp/nodes \
      --config-option cookbook_path='"$COOKBOOK_PATH"' '"$CONFIG_FILE"'  -o '"$RECIPE$1"''
  docker exec "$CONTAINER_ID" bash -c "$command"  || log "error" "exec_failed"
}

if [[ -z "${COOKBOOK_OVERRIDE:-}" ]]; then suffixes=(::repo); else suffixes=(::default); fi  # suffixes=(::repo ::task)
run ""; while true; do
  log "rerun" "$RECIPE"; read -r
  for s in "${suffixes[@]}"; do run "$s"; done
done
