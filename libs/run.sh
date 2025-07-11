#!/usr/bin/env bash
set -eo pipefail

COOKBOOK="$1"
PROJECT_DIR="$PWD"

DOCKER_IMAGE_NAME="proxmoxgitops"
DOCKER_CONTAINER_NAME="${COOKBOOK}"
DOCKER_INIT_WAIT="${DOCKER_INIT_WAIT:-5}"

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
    log "remove" "wait"
    docker stop "${DOCKER_CONTAINER_NAME}" >/dev/null
    sleep 1
    docker rm -f "${DOCKER_CONTAINER_NAME}" >/dev/null
    sleep "${DOCKER_INIT_WAIT}"
fi

CONTAINER_ID=$(docker ps -aq --filter "name=$DOCKER_CONTAINER_NAME")
if [[ -z "$CONTAINER_ID" ]]; then
  CONTAINER_ID=$(docker run -d --privileged \
    --tmpfs /share \
    -w "/tmp" \
    -v "$PROJECT_DIR:/tmp:ro" \
    -v "$PROJECT_DIR/../config/libraries/":"/tmp/$COOKBOOK/libraries/:ro" \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --cgroupns=host \
    --name "$DOCKER_CONTAINER_NAME" \
    "$DOCKER_IMAGE_NAME")
  sleep "$DOCKER_INIT_WAIT"
fi

docker exec "$CONTAINER_ID" cinc-client -l debug --local-mode --config-option cookbook_path=/tmp --chef-license accept $( [ -f /tmp/$COOKBOOK/config.json ] && echo "-j /tmp/$COOKBOOK/config.json" ) -o "$COOKBOOK"
