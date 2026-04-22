#!/usr/bin/env bash

log() { echo "[$1] $2"; };

err() { log "error" "$1"; exit 1; }

cfg() { local lib="${1:-}"
  [[ -f "$lib/config.local.json" ]] && echo "-j $lib/config.local.json" && return 0
  [[ -f "$lib/config.json" ]]       && echo "-j $lib/config.json"; }

pre() { set -eo pipefail
  command -v docker >/dev/null || err "missing docker"
  command -v md5sum >/dev/null || function md5sum() { md5 -q "$1"; } || err "missing md5";
  if [[ "$(basename "$(pwd)")" == "local" ]]; then cd ..; fi
}; pre

arg() { while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help)
    echo -e "\n./$SCRIPT [OPTIONS] [lib] [-h|--help]"
    echo -e "  -l, --log-level <level>\n  -p, --port <port>\n  -s, --suffixes <list>"
    echo -e "  -d, --debug\n  -r, --restart"
    echo -e "\nExamples:"
    echo -e "  ./$SCRIPT --debug --restart broker\n  ./$SCRIPT -s \"customize\" -l error\n"
    exit 0 ;;
  -l|--log-level)
    [[ $# -gt 1 ]] && LOG_LEVEL="$2" && shift ;;
  -p|--port)
    [[ $# -gt 1 ]] && PORT="$2" && shift ;;
  -s|--suffixes)
    [[ $# -gt 1 ]] && SUFFIXES="$2" && shift ;;
  -d|--debug)   LOG_LEVEL="debug" ;;
  -r|--restart) RESTART="true" ;;
  sync) . ./container.env || . ../container.env || true ;;
  -*) ;;
  *) [[ -z "$LIB" || "$LIB" == "config" ]] && LIB="$1" ;;
  esac; shift; done
}; LIB="config"; LOG_LEVEL="info"; PORT=""; RESTART="false"; SCRIPT="$(basename "$0")";

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
esac; export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/${TARGETARCH}}"

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
    log "container" "clean"
    docker stop "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
    docker rm -f -v "$DOCKER_CONTAINER" >/dev/null || true
    sleep "$DOCKER_WAIT"
fi

if [[ -z "$(docker images -q "${DOCKER_IMAGE}")" || "$HASH_STORED" != "$HASH_SUM" ]]; then
    log "container" "image"
    docker build --no-cache --build-arg TARGETARCH="$TARGETARCH" -t "$DOCKER_IMAGE" -f "$DOCKER_FILE" "$(pwd)" || err "image build failed"
    echo "$HASH_SUM" > "$HASH_FILE"
fi

log "container" "start"
CONTAINER_ID=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw --add-host=host.docker.internal:host-gateway \
    $( [[ -d "${LOCAL}/share" ]] && echo "-v ${LOCAL}/share:/share:ro " ) \
    $( [[ "$LIB" != "config" ]] && echo "-p ${PORT:-80}:${PORT:-80} -e HOST=host.docker.internal" || echo "-p ${PORT:-8080}:8080 -p 2222:2222" ) \
    --name "$DOCKER_CONTAINER" --platform "linux/${TARGETARCH}" -w /tmp/config "$DOCKER_IMAGE" sleep infinity) || err "failed to start container"

files() {
  log "${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]" "files"

  docker exec "$CONTAINER_ID" bash -c "rm -rf /tmp/config/*" || err "cleanup error"
  docker cp "$(pwd)/." "$CONTAINER_ID:/tmp/config/" || err "remote error"

  if [[ "${LIB}" != "config" ]]; then
    log "${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]" "libraries"
    docker exec "$CONTAINER_ID" bash -c "mkdir -p '/tmp/config/libs/${LIB}/libraries' && \
      cp -a /tmp/config/config/libraries/. '/tmp/config/libs/${LIB}/libraries/'" || err "copy error"
  fi
}; files

arg "$@"
if [[ -n "${IP}" && -n "${ID}" ]]; then # if sync sourced container.env
  docker exec "$CONTAINER_ID" bash -c "tar -cz -C /tmp config | \
    ssh -o StrictHostKeyChecking=no -i \"/share/.keys/${ID}\" \"config@${IP}\" '\
        sudo rm -rf /tmp/config && sudo tar -xz -C /tmp \

        sudo -E IP=\"${IP}\" ID=\"${ID}\" PWD=/tmp/config cinc-client --local-mode -j \"/tmp/config/local/config\$( [ -f /tmp/config/local/config.local.json ] && echo \".local\" ).json\" --config-option cookbook_path=\"/tmp/config\" -o \"config::repo\" \
      '" || err "sync error"
  exit 0
fi

configuration() {
  log "${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]" "$LIB::$1"
  command='sudo $(sudo -u config env) PWD=/tmp/config --preserve-env=ID,HOST \
    cinc-client -l '"$LOG_LEVEL"' --local-mode --config-option node_path=/tmp/nodes \
      --config-option cookbook_path='"$LIBS"' '"$CONFIG"' -o '"$LIB::$1"''
  docker exec "$CONTAINER_ID" bash -c "$command"  || err "execution error"
}; configuration

if [[ -z "${SUFFIXES+x}" ]]; then if [[ "${LIB}" != "config" ]]; then SUFFIXES=("default"); else SUFFIXES=("repo"); fi; fi
while true; do
  echo -n "$LIB::${SUFFIXES[*]} or $LIB::"; read -r input; [[ -n "$input" ]] && SUFFIXES=($input)
  for s in "${SUFFIXES[@]}"; do configuration "$s"; done

  if [[ "${RESTART}" == "true" ]]; then
    log "${DOCKER_CONTAINER} [${CONTAINER_ID:0:6}]" "restart"
    sleep "$DOCKER_WAIT" && docker restart $CONTAINER_ID
  fi
done
