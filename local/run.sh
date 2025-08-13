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

[[ -f "${DEVELOP_DIR}/config.json" ]] && CONFIG_FILE=("${DEVELOP_DIR}/config.json")
[[ -n "${COOKBOOK_OVERRIDE}" ]] && [[ -f "./libs/${COOKBOOK_OVERRIDE}/config.json" ]] && CONFIG_FILE="./libs/${COOKBOOK_OVERRIDE}/config.json"

CONFIG_FILE="-j $CONFIG_FILE"

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')}"
DOCKER_CONTAINER_NAME="${DOCKER_CONTAINER_NAME:-"$PROJECT_NAME"}"
DOCKER_WAIT="${DOCKER_WAIT:-3}"
UNAME_ARCH="$(uname -m)"
case "$UNAME_ARCH" in
  aarch64|arm64) TARGETARCH="arm64" ;;
  x86_64) TARGETARCH="amd64" ;;
  *) TARGETARCH="unknown" ;;
esac
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/${TARGETARCH}}"

DOCKERFILE_PATH="${DEVELOP_DIR}/Dockerfile"
[[ -f "${DOCKERFILE_PATH}" ]] || fail "dockerfile_missing:${DOCKERFILE_PATH}"
DOCKERFILE_HASH=$(md5sum "${DOCKERFILE_PATH}" | awk '{print $1}')
STORED_HASH_FILE="${DEVELOP_DIR}/.${DOCKER_IMAGE_NAME}.hash"
STORED_HASH=$(cat "${STORED_HASH_FILE}" 2>/dev/null || true)

BUILD_NEEDED=false
if [[ -z "$(docker images -q "${DOCKER_IMAGE_NAME}")" || "${STORED_HASH}" != "${DOCKERFILE_HASH}" ]]; then
    BUILD_NEEDED=true
    log "image" "build_required"
    docker build --build-arg TARGETARCH="$TARGETARCH" -t "$DOCKER_IMAGE_NAME" -f "$DOCKERFILE_PATH" "$PROJECT_DIR" || fail "build_failed"
    echo "$DOCKERFILE_HASH" > "$STORED_HASH_FILE"
    log "image" "build_complete"
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
    log "container" "remove_existing"
    docker stop "$DOCKER_CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f "$DOCKER_CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

log "container" "start"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host --tmpfs /tmp  \
    -v "$PROJECT_DIR:/tmp/config:ro" --tmpfs "/tmp/config/.git" \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw -w /tmp/config \
    $( [[ -n "${COOKBOOK_OVERRIDE}" ]] && echo "-e RUBYLIB=/tmp/config/config/libraries -e RUBYOPT=-r/tmp/config/config/libraries/env.rb") \
    $( [[ -n "${COOKBOOK_OVERRIDE}" ]] && echo "-p :80 -p :8080 -p :8123" || echo "-p 80:80 -p 8080:8080 -p 2222:2222" ) \
    --name "$DOCKER_CONTAINER_NAME" "$DOCKER_IMAGE_NAME") || fail "container_start_failed"
log "container" "started:${CONTAINER_ID}"
sleep "$DOCKER_WAIT"

command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID \
  cinc-client -l info --local-mode --chef-license accept --config-option node_path=/tmp/nodes \
    --config-option cookbook_path='"$COOKBOOK_PATH"' '"$CONFIG_FILE"'  -o '"$RECIPE"''
docker exec "$CONTAINER_ID" bash -c "$command"  || log "error" "exec_failed"

[[ -z "${COOKBOOK_OVERRIDE}" ]] && command+="::repo"
while true; do
    log "rerun" "$RECIPE" && read -r
    docker exec "$CONTAINER_ID" bash -c "$command" || log "error" "exec_failed"
done
