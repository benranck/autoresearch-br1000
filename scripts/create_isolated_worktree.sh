#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_ROOT="${WORKTREE_ROOT:-${ROOT_DIR}/worktrees}"
BASE_REF="${BASE_REF:-HEAD}"
RUN_TAG="${RUN_TAG:-}"
PRINT_PATH_ONLY="${PRINT_PATH_ONLY:-0}"

if [[ -z "${RUN_TAG}" ]]; then
  RUN_TAG="$(date +%b%d | tr '[:upper:]' '[:lower:]')"
fi

BRANCH_NAME="autoresearch/${RUN_TAG}"
DEFAULT_WORKTREE_DIR="${WORKTREE_ROOT}/${RUN_TAG}"

cd "${ROOT_DIR}"

existing_worktree_dir="$(
  git worktree list --porcelain | awk -v branch="refs/heads/${BRANCH_NAME}" '
    $1 == "worktree" { wt = $2 }
    $1 == "branch" && $2 == branch { print wt }
  '
)"

if [[ -n "${existing_worktree_dir}" ]]; then
  WORKTREE_DIR="${existing_worktree_dir}"
elif [[ -e "${DEFAULT_WORKTREE_DIR}" ]]; then
  echo "[error] ${DEFAULT_WORKTREE_DIR} already exists but is not registered for ${BRANCH_NAME}" >&2
  exit 1
elif git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  git worktree add "${DEFAULT_WORKTREE_DIR}" "${BRANCH_NAME}"
  WORKTREE_DIR="${DEFAULT_WORKTREE_DIR}"
else
  mkdir -p "${WORKTREE_ROOT}"
  git worktree add -b "${BRANCH_NAME}" "${DEFAULT_WORKTREE_DIR}" "${BASE_REF}"
  WORKTREE_DIR="${DEFAULT_WORKTREE_DIR}"
fi

RESULTS_TSV="${WORKTREE_DIR}/results.tsv"
if [[ ! -f "${RESULTS_TSV}" ]]; then
  printf "commit\tval_bpb\tmemory_gb\tstatus\tdescription\n" > "${RESULTS_TSV}"
fi

if [[ "${PRINT_PATH_ONLY}" == "1" ]]; then
  printf "%s\n" "${WORKTREE_DIR}"
  exit 0
fi

printf "[ok] Isolated worktree ready\n"
printf "  branch: %s\n" "${BRANCH_NAME}"
printf "  path:   %s\n" "${WORKTREE_DIR}"
printf "  base:   %s\n" "${BASE_REF}"
printf "  tsv:    %s\n" "${RESULTS_TSV}"
