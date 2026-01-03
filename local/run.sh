#!/usr/bin/env bash
set -eo pipefail

log() { echo "[$1] $2"; };
err() { log "error" "$1"; exit 1; }
cfg() {
  [[ -f "$1/config.local.json" ]] && echo "-j $1/config.local.json" && return 0
  [[ -f "$1/config.json" ]] && echo "-j $1/config.json"
}
arg() {
  LIB="config"
  LOG_LEVEL="info"
  REBOOT="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        echo "\t-l, --log-level LEVEL\n\t-d, --debug\n\t-r, --reboot"; exit 0;;
      -l|--log-level)
        [[ $# -gt 1 ]] && LOG_LEVEL="$2" && shift;;
      -d|--debug)
        LOG_LEVEL="debug";;
      -r|--reboot)
        REBOOT="true";;
      -*)
        err "unknown option: $1";;
      *)
        [[ -z "$LIB" || "$LIB" == "config" ]] && LIB="$1" ;;
    esac
    shift
  done
}

arg "$@"

NAME="$(basename "$(pwd)${LIB:+/config/libs/$LIB}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
LIB="${LIB:-config}"; LOCAL="./local"
CONFIG=$(cfg "${LOCAL}" || cfg "./libs/${LIB:-config}" || true)
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

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
    log "container" "clean"
    docker stop "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f -v "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

if [[ -z "$(docker images -q "${DOCKER_IMAGE}")" || "$HASH_STORED" != "$HASH_SUM" ]]; then
    log "container" "build"
    docker build --no-cache --build-arg TARGETARCH="$TARGETARCH" -t "$DOCKER_IMAGE" -f "$DOCKER_FILE" "$(pwd)" || err "image build failed"
    echo "$HASH_SUM" > "$HASH_FILE"
fi

log "container" "run"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw --add-host=host.docker.internal:host-gateway \
    $( [[ -d "${LOCAL}/share" ]] && echo "-v ${LOCAL}/share:/share:ro " ) \
    $( [[ "$LIB" != "config" ]] && echo "-p 80:80 -e HOST=host.docker.internal" || echo "-p 8080:8080 -p 2222:2222" ) \
    --name "$DOCKER_CONTAINER" --platform "linux/${TARGETARCH}" -w /tmp/config "$DOCKER_IMAGE" sleep infinity) || err "failed to start container"
log "container" "${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]"

log "" "configuration"

sync() {
  docker exec "$CONTAINER_ID" bash -c "rm -rf /tmp/config/*" || err "cleanup error"
  docker cp "$(pwd)/." "$CONTAINER_ID:/tmp/config/" || err "remote error"

  if [[ "${LIB}" != "config" ]]; then
    log "configuration" "sync libraries (${LIB})"
    docker exec "$CONTAINER_ID" bash -c "mkdir -p '/tmp/config/libs/${LIB}/libraries' && \
      cp -a /tmp/config/config/libraries/. '/tmp/config/libs/${LIB}/libraries/'" || err "copy error"
  fi
}

configuration() {
  local suffix="${1:-}"
  log "configuration" "sync" && sync
  log "configuration" "execute ($LIB$1)"
  command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID,HOST \
    cinc-client -l '"$LOG_LEVEL"' --local-mode --config-option node_path=/tmp/nodes \
      --config-option cookbook_path='"$LIBS"' '"$CONFIG"' -o '"$LIB$1"''
  docker exec "$CONTAINER_ID" bash -c "$command"  || err "execution error"
  log "configuration" "executed ($LIB$1)"
}

if [[ "${LIB}" != "config" ]]; then suffixes=("::default"); else suffixes=("::repo"); fi
configuration ""; while true; do
  log "configuration" "$LIB${suffixes[@]}"; read -r
  for s in "${suffixes[@]}"; do configuration "$s"; done

  if [[ "${REBOOT}" == "true" ]]; then
    log "configuration" "restart [${CONTAINER_ID:0:6}]"
    sleep "$DOCKER_WAIT" && docker restart $CONTAINER_ID
  fi
done
