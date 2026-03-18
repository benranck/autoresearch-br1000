#!/usr/bin/env bash
set -euo pipefail

TRAIN_ENV_VARS="${TRAIN_ENV_VARS:-AR_TINY_VRAM_PRESET=1 AR_DISABLE_COMPILE=1 AR_MAX_SEQ_LEN=256 AR_EVAL_TOKENS=524288}"
PREP_ARGS="${PREP_ARGS:---num-shards 1}"
PYTHON_BIN="${PYTHON_BIN:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v uv >/dev/null 2>&1; then
  echo "[error] uv is not installed or not on PATH"
  exit 1
fi

if [[ -z "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(command -v python3 || true)"
fi

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "[error] python3 is not installed or not on PATH"
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "[error] nvidia-smi is not available; GPU setup is incomplete"
  exit 1
fi

echo "[1/4] Verifying NVIDIA GPU access..."
nvidia-smi -L

echo "[2/4] Syncing dependencies..."
(cd "${ROOT_DIR}" && uv sync --python "${PYTHON_BIN}")

echo "[3/4] Running prepare.py ${PREP_ARGS}..."
read -r -a prep_args <<<"${PREP_ARGS}"
(cd "${ROOT_DIR}" && uv run --python "${PYTHON_BIN}" prepare.py "${prep_args[@]}")

echo "[4/4] Starting training with env: ${TRAIN_ENV_VARS}"
read -r -a train_env_array <<<"${TRAIN_ENV_VARS}"
(cd "${ROOT_DIR}" && env "${train_env_array[@]}" uv run --python "${PYTHON_BIN}" train.py)
