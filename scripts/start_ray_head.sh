#!/usr/bin/env bash
# Start Ray head node. Run on the HEAD machine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/.venv/bin/activate"

ray stop 2>/dev/null || true
echo "Starting Ray head node..."
ray start --head --port=6379 --dashboard-host=0.0.0.0
echo "Ray head started. IP: $(hostname -I | awk '{print $1}')"
