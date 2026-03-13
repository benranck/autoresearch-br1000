#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-autoresearch:cuda128}"
CONTAINER_NAME="${CONTAINER_NAME:-autoresearch-wsl2}"
CACHE_ROOT="${CACHE_ROOT:-${HOME}/.cache/autoresearch}"
TRAIN_ENV_VARS="${TRAIN_ENV_VARS:-AR_LOW_VRAM_PRESET=1 AR_DISABLE_COMPILE=1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "[error] docker is not installed or not on PATH"
  exit 1
fi

mkdir -p "${CACHE_ROOT}/data" "${CACHE_ROOT}/tokenizer"

echo "[1/5] Verifying Docker GPU support..."
if ! docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
  cat <<MSG
[error] Docker GPU support check failed.
Make sure:
  - NVIDIA drivers are installed on Windows host
  - WSL2 GPU support is enabled
  - Docker Desktop has WSL integration enabled
  - NVIDIA Container Toolkit is available to Docker
MSG
  exit 1
fi

echo "[2/5] Building image ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" "${ROOT_DIR}"

echo "[3/5] Syncing dependencies inside container..."
docker run --rm --gpus all \
  -v "${ROOT_DIR}:/workspace/autoresearch" \
  -v "${CACHE_ROOT}:/root/.cache/autoresearch" \
  -w /workspace/autoresearch \
  "${IMAGE_NAME}" \
  bash -lc 'uv sync --frozen'

echo "[4/5] Running prepare.py (downloads data/tokenizer if needed)..."
docker run --rm --gpus all \
  -v "${ROOT_DIR}:/workspace/autoresearch" \
  -v "${CACHE_ROOT}:/root/.cache/autoresearch" \
  -w /workspace/autoresearch \
  "${IMAGE_NAME}" \
  bash -lc 'uv run prepare.py'

read -r -a train_env_array <<<"${TRAIN_ENV_VARS}"
train_env_args=()
for kv in "${train_env_array[@]}"; do
  train_env_args+=("-e" "$kv")
done

echo "[5/5] Starting training with env: ${TRAIN_ENV_VARS}"
docker run --rm --gpus all --shm-size=8g \
  --name "${CONTAINER_NAME}" \
  "${train_env_args[@]}" \
  -v "${ROOT_DIR}:/workspace/autoresearch" \
  -v "${CACHE_ROOT}:/root/.cache/autoresearch" \
  -w /workspace/autoresearch \
  "${IMAGE_NAME}" \
  bash -lc 'uv run train.py'
