#!/usr/bin/env bash
# Join Ray cluster as a worker. Run on the WORKER machine.
# Usage: bash scripts/start_ray_worker.sh <HEAD_IP>
set -euo pipefail

HEAD_IP="${1:?Usage: bash scripts/start_ray_worker.sh <HEAD_IP>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/.venv/bin/activate"

ray stop 2>/dev/null || true
echo "Joining Ray cluster at ${HEAD_IP}:6379..."
ray start --address="${HEAD_IP}:6379"
echo "Worker joined."
