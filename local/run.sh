#!/usr/bin/env bash
set -eo pipefail

log() { echo "[$1] $2"; };
err() { log "error" "$1"; exit 1; }
candidate() {
  [[ -f "$1/config.local.json" ]] && echo "-j $1/config.local.json" && return 0
  [[ -f "$1/config.json" ]] && echo "-j $1/config.json"
}

NAME="$(basename "$(pwd)${1:+/config/libs/$1}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
LIB="${1:-config}"; LOCAL="./local"
CONFIG=$(candidate "${LOCAL}" || candidate "./libs/${LIB:-config}" || true)
LIBS="['/tmp/config','/tmp/config/libs']"

DOCKER_IMAGE="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
DOCKER_FILE="${LOCAL}/Dockerfile"; DOCKER_WAIT="${DOCKER_WAIT:-3}"
DOCKER_CONTAINER="${LIB:-"$NAME"}"

HASH_BASE=$(find "base" -type f -not -path "*/.git/*" -print0 | sort -z | xargs -0 md5sum | md5sum | awk '{print $1}')
HASH_SUM=$(echo "$(md5sum "$DOCKER_FILE" | awk '{print $1}')${HASH_BASE}" | md5sum | awk '{print $1}')
HASH_FILE="${LOCAL}/.local.hash"
HASH_STORED=$(cat "$HASH_FILE" 2>/dev/null || true)

case "$(uname -m)" in
  aarch64|arm64) TARGETARCH="arm64" ;;
  x86_64) TARGETARCH="amd64" ;;
  *) TARGETARCH="unknown" ;;
esac
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/${TARGETARCH}}"

log "" "container"

if [[ -z "$(docker images -q "${DOCKER_IMAGE}")" || "$HASH_STORED" != "$HASH_SUM" ]]; then
    log "container" "build"
    docker build --no-cache --build-arg TARGETARCH="$TARGETARCH" -t "$DOCKER_IMAGE" -f "$DOCKER_FILE" "$(pwd)" || err "image build failed"
    echo "$HASH_SUM" > "$HASH_FILE"
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
    log "container" "clean"
    docker stop "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f -v "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

log "container" "run"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw --add-host=host.docker.internal:host-gateway \
    $( [[ -d "${LOCAL}/share" ]] && echo "-v ${LOCAL}/share:/share:ro " ) \
    $( [[ -n "$1" ]] && echo "-p 80:80 -e HOST=host.docker.internal" || echo "-p 8080:8080 -p 2222:2222" ) \
    --name "$DOCKER_CONTAINER" --platform "linux/${TARGETARCH}" -w /tmp/config "$DOCKER_IMAGE" sleep infinity) || err "failed to start container"
log "container" "started ${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]"

log "container" "configure"

sync() {
  log "configure" "sync"
  docker exec "$CONTAINER_ID" bash -c "rm -rf /tmp/config/*" || log "sync" "cleanup error"
  docker cp "$(pwd)/." "$CONTAINER_ID:/tmp/config/" || err "sync"

  if [[ "${LIB}" != "config" ]]; then
    log "configure" "libraries"
    docker exec "$CONTAINER_ID" bash -c "mkdir -p '/tmp/config/libs/${LIB}/libraries' && \
      cp -a /tmp/config/config/libraries/. '/tmp/config/libs/${LIB}/libraries/'" || err "sync libraries"
  fi
}

run() {
  log "configure" "run"
  sync
  command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID,HOST \
    cinc-client -l info --local-mode --config-option node_path=/tmp/nodes \
      --config-option cookbook_path='"$LIBS"' '"$CONFIG"' -o '"$LIB$1"''
  docker exec "$CONTAINER_ID" bash -c "$command"  || err "failed execution"
}

if [[ "${LIB}" != "config" ]]; then suffixes=("::default"); else suffixes=("::repo"); fi
run ""; while true; do
  log "configure" "$LIB"; read -r
  log "configure" "rerun"
  for s in "${suffixes[@]}"; do run "$s"; done
  log "rerun" "done"
done
