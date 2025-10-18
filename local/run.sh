#!/usr/bin/env bash
set -eo pipefail

PROJECT_NAME="$(basename "$(pwd)${1:+/config/libs/$1}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
IMAGE_NAME="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
LIB_NAME="${1:-config}"
CONTAINER_NAME="${LIB_NAME:-"$PROJECT_NAME"}"

LOCAL_DIR="./local"
[[ -f "${LOCAL_DIR}/config.json" ]] && CONFIG_FILE=("-j ${LOCAL_DIR}/config.json")
[[ -n "${LIB_NAME}" ]] && [[ -f "./libs/${LIB_NAME}/config.json" ]] && CONFIG_FILE="-j ./libs/${LIB_NAME}/config.json"

COOKBOOK_PATH="['/tmp/config','/tmp/config/libs']"

DOCKER_WAIT="${DOCKER_WAIT:-3}"

DOCKERFILE_PATH="${LOCAL_DIR}/Dockerfile"
BASE=$(find "base" -type f -not -path "*/.git/*" -print0 | sort -z | xargs -0 md5sum | md5sum | awk '{print $1}')
HASH=$(echo "$(md5sum "$DOCKERFILE_PATH" | awk '{print $1}')${BASE}" | md5sum | awk '{print $1}')
STORED_HASH_FILE="${LOCAL_DIR}/.local.hash"
STORED_HASH=$(cat "$STORED_HASH_FILE" 2>/dev/null || true)

log() { echo "[$PROJECT_NAME:$1] $2"; }
err() { log "error" "$1"; exit 1; }

case "$(uname -m)" in
  aarch64|arm64) TARGETARCH="arm64" ;;
  x86_64) TARGETARCH="amd64" ;;
  *) TARGETARCH="unknown" ;;
esac
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/${TARGETARCH}}"

# Container

if [[ -z "$(docker images -q "${IMAGE_NAME}")" || "$STORED_HASH" != "$HASH" ]]; then
    log "image" "build required"
    docker build --no-cache --build-arg TARGETARCH="$TARGETARCH" -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$(pwd)" || err "image build failed"
    echo "$HASH" > "$STORED_HASH_FILE"
    log "image" "build complete"
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "container" "remove existing"
    docker stop "$CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f -v "$CONTAINER_NAME" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

log "container" "start container"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw --add-host=host.docker.internal:host-gateway \
    $( [[ -d "${LOCAL_DIR}/share" ]] && echo "-v ${LOCAL_DIR}/share:/share:ro " ) \
    $( [[ -n "$1" ]] && echo "-p 80:80 -e HOST=host.docker.internal" || echo "-p 8080:8080 -p 2222:2222" ) \
    --name "$CONTAINER_NAME" --platform "linux/${TARGETARCH}" -w /tmp/config "$IMAGE_NAME" sleep infinity) || err "failed to start container"
log "container" "started [${CONTAINER_ID}]"

sync() {
  log "sync" "files"
  docker exec "$CONTAINER_ID" bash -c "rm -rf /tmp/config/*" || log "sync" "cleanup error"
  docker cp "$(pwd)/." "$CONTAINER_ID:/tmp/config/" || err "sync"

  if [[ "${LIB_NAME}" != "config" ]]; then
    log "sync" "libraries"
    docker exec "$CONTAINER_ID" bash -c "mkdir -p '/tmp/config/libs/${LIB_NAME}/libraries' && \
      cp -a /tmp/config/config/libraries/. '/tmp/config/libs/${LIB_NAME}/libraries/'" || err "sync libraries"
  fi
}

# Configure

run() {
  log "run" "start"
  sync
  command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID,HOST \
    cinc-client -l info --local-mode --config-option node_path=/tmp/nodes \
      --config-option cookbook_path='"$COOKBOOK_PATH"' '"$CONFIG_FILE"'  -o '"$LIB_NAME$1"''
  docker exec "$CONTAINER_ID" bash -c "$command"  || err "failed execution"
}

if [[ "${LIB_NAME}" != "config" ]]; then suffixes=("::repo"); else suffixes=("::default"); fi
run ""; while true; do
  log "rerun" "$LIB_NAME"; read -r
  log "rerun" "start"
  for s in "${suffixes[@]}"; do run "$s"; done
  log "rerun" "done"
done
