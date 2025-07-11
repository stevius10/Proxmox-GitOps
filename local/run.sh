#!/usr/bin/env bash
set -eo pipefail

log() { echo "[$PROJECT_NAME:$1] $2"; }
fail() { log "error" "$1"; exit 1; }

PROJECT_NAME="$(basename "${PWD}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
PROJECT_DIR="$(pwd)"
DEVELOP_DIR="./local"
CONFIG_FILE="${DEVELOP_DIR}/config.json"
COOKBOOK_PATH="['.', './libs']"
CINC_ARGS=()

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-"$PROJECT_NAME"}"
DOCKER_CONTAINER_NAME="${DOCKER_CONTAINER_NAME:-"$PROJECT_NAME"}"
DOCKER_INIT_WAIT="${DOCKER_INIT_WAIT:-3}"
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/arm64}"

DOCKERFILE_PATH="${DEVELOP_DIR}/Dockerfile"
[[ -f "${DOCKERFILE_PATH}" ]] || fail "dockerfile_missing:${DOCKERFILE_PATH}"
DOCKERFILE_HASH=$(md5sum "${DOCKERFILE_PATH}" | awk '{print $1}')

STORED_HASH_FILE="${DEVELOP_DIR}/.${DOCKER_IMAGE_NAME}.hash"
STORED_HASH=$(cat "${STORED_HASH_FILE}" 2>/dev/null || true)

if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
    log "remove" "wait"
    docker stop "${DOCKER_CONTAINER_NAME}" >/dev/null
    sleep 1
    docker rm -f "${DOCKER_CONTAINER_NAME}" >/dev/null
    sleep "${DOCKER_INIT_WAIT}"
fi

BUILD_NEEDED=false
if [[ -z "$(docker images -q "${DOCKER_IMAGE_NAME}")" || "${STORED_HASH}" != "${DOCKERFILE_HASH}" ]]; then
    BUILD_NEEDED=true
    log "image" "build_required"
    docker build -t "${DOCKER_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${PROJECT_DIR}" || fail "build_failed"
    echo "${DOCKERFILE_HASH}" > "${STORED_HASH_FILE}"
    log "image" "build_complete"
fi

CONTAINER_ID=$(docker ps -aq --filter "name=^/${DOCKER_CONTAINER_NAME}$")
if [[ -n "${CONTAINER_ID}" ]]; then
    if [[ "${BUILD_NEEDED}" == "true" || -z "$(docker ps -q --filter "id=${CONTAINER_ID}")" ]]; then
        log "container" "recreate_required"
        docker rm -f "${CONTAINER_ID}" >/dev/null || fail "container_rm_failed"
        log "container" "removed:${CONTAINER_ID}"
        CONTAINER_ID=""
    fi
fi

if [[ -z "${CONTAINER_ID}" ]]; then
    log "container" "start"
    CONTAINER_ID=$(docker run -d --privileged --cgroupns=host \
        --tmpfs /tmp --tmpfs /run \
        -p 8080:8080 -p 80:80 -p 2222:2222 \
        -w "/${PROJECT_NAME}" \
        -v "${PROJECT_DIR}:/${PROJECT_NAME}:ro" -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        --name "${DOCKER_CONTAINER_NAME}" "${DOCKER_IMAGE_NAME}") || fail "container_start_failed"
    log "container" "started:${CONTAINER_ID}"
    log "container" "init_wait:${DOCKER_INIT_WAIT}s"
    sleep "${DOCKER_INIT_WAIT}"
fi

[[ -f "${CONFIG_FILE}" ]] && CINC_ARGS+=("-j" "${CONFIG_FILE}")

log "exec" "start"
docker exec "${CONTAINER_ID}" bash -c '
    set -e
    env MOUNT=share cinc-client -l debug --local-mode --config-option node_path=/tmp --config-option cookbook_path="$1" "${@:2}" --chef-license accept -o share
    cinc-client -l debug --local-mode --config-option node_path=/tmp --config-option cookbook_path="$1" "${@:2}" --chef-license accept -o config
' _ "${COOKBOOK_PATH}" "${CINC_ARGS[@]}" || fail "exec_failed"

log "exec" "complete"
