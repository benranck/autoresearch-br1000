#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-autoresearch:cuda118}"
WORKTREE_ROOT="${WORKTREE_ROOT:-${ROOT_DIR}/worktrees}"
BASE_REF="${BASE_REF:-HEAD}"
RUN_TAG="${RUN_TAG:-}"
WORKTREE_DIR="${WORKTREE_DIR:-}"
CACHE_ROOT="${CACHE_ROOT:-${HOME}/.cache/autoresearch}"
LOG_ROOT="${LOG_ROOT:-${HOME}/.cache/autoresearch/logs}"
AGENT_HOME_ROOT="${AGENT_HOME_ROOT:-${HOME}/.cache/autoresearch/agent-home}"
NETWORK_MODE="${NETWORK_MODE:-bridge}"
READ_ONLY_ROOTFS="${READ_ONLY_ROOTFS:-1}"
SHM_SIZE="${SHM_SIZE:-8g}"
DROP_CAPS="${DROP_CAPS:-1}"
AGENT_CMD="${AGENT_CMD:-}"
GIT_USER_NAME="${GIT_USER_NAME:-$(git -C "${ROOT_DIR}" config --get user.name || true)}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git -C "${ROOT_DIR}" config --get user.email || true)}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[error] docker is not installed or not on PATH" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[error] docker daemon is not reachable" >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "[error] nvidia-smi is not available in WSL" >&2
  exit 1
fi

if [[ -z "${WORKTREE_DIR}" ]]; then
  WORKTREE_DIR="$(
    RUN_TAG="${RUN_TAG}" \
    BASE_REF="${BASE_REF}" \
    WORKTREE_ROOT="${WORKTREE_ROOT}" \
    PRINT_PATH_ONLY=1 \
    bash "${ROOT_DIR}/scripts/create_isolated_worktree.sh"
  )"
fi

if [[ -z "${RUN_TAG}" ]]; then
  RUN_TAG="$(basename "${WORKTREE_DIR}")"
fi

CONTAINER_NAME="${CONTAINER_NAME:-autoresearch-agent-${RUN_TAG//[^a-zA-Z0-9_.-]/-}}"
CONTAINER_HOME="${AGENT_HOME_ROOT}/${RUN_TAG}"
RUN_LOG_DIR="${LOG_ROOT}/${RUN_TAG}"

mkdir -p "${CACHE_ROOT}" "${CONTAINER_HOME}" "${RUN_LOG_DIR}"

tty_args=()
if [[ -t 0 && -t 1 ]]; then
  tty_args=(-it)
fi

runtime_args=(
  --rm
  "${tty_args[@]}"
  --gpus all
  --shm-size "${SHM_SIZE}"
  --security-opt no-new-privileges
  --name "${CONTAINER_NAME}"
  --network "${NETWORK_MODE}"
  -v "${WORKTREE_DIR}:/workspace/run"
  -v "${CONTAINER_HOME}:/home/app"
  -v "${CACHE_ROOT}:/home/app/.cache/autoresearch"
  -v "${RUN_LOG_DIR}:/workspace/logs"
  -w /workspace/run
  -e HOME=/home/app
  -e XDG_CACHE_HOME=/home/app/.cache/autoresearch
  -e HF_HOME=/home/app/.cache/autoresearch/huggingface
  -e TORCH_HOME=/home/app/.cache/autoresearch/torch
  -e MPLCONFIGDIR=/tmp/matplotlib
  -e GIT_USER_NAME="${GIT_USER_NAME}"
  -e GIT_USER_EMAIL="${GIT_USER_EMAIL}"
)

if [[ "${DROP_CAPS}" == "1" ]]; then
  runtime_args+=(--cap-drop ALL)
fi

if [[ "${READ_ONLY_ROOTFS}" == "1" ]]; then
  runtime_args+=(
    --read-only
    --tmpfs /tmp:exec,mode=1777,size=4g
    --tmpfs /run:mode=755,size=64m
  )
fi

cmd=(bash)
if [[ $# -gt 0 ]]; then
  cmd=("$@")
elif [[ -n "${AGENT_CMD}" ]]; then
  cmd=(bash -lc "${AGENT_CMD}")
fi

echo "[1/3] Verifying Docker GPU support..."
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi >/dev/null

echo "[2/3] Building image ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" "${ROOT_DIR}"

echo "[3/3] Launching isolated workspace container"
echo "  worktree: ${WORKTREE_DIR}"
echo "  branch:   $(git -C "${WORKTREE_DIR}" rev-parse --abbrev-ref HEAD)"
echo "  logs:     ${RUN_LOG_DIR}"
echo "  network:  ${NETWORK_MODE}"

docker run "${runtime_args[@]}" \
  "${IMAGE_NAME}" \
  bash -lc '
    git config --global --add safe.directory /workspace/run
    if [[ -n "${GIT_USER_NAME:-}" ]]; then
      git config --global user.name "${GIT_USER_NAME}"
    fi
    if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
      git config --global user.email "${GIT_USER_EMAIL}"
    fi
    exec "$@"
  ' bash "${cmd[@]}"
