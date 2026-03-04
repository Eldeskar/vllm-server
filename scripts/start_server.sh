#!/usr/bin/env bash
# Start vLLM server with tensor parallelism across the Ray cluster.
# Run on the HEAD node after Ray head + worker are up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/.venv/bin/activate"

# Load HF token
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

MODEL="${VLLM_MODEL:-Qwen/Qwen3-VL-32B-Thinking}"
PORT="${VLLM_PORT:-8123}"
TP_SIZE="${VLLM_TP_SIZE:-2}"
MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-16384}"
GPU_UTIL="${VLLM_GPU_UTIL:-0.92}"

echo "Starting vLLM server..."
echo "  Model:           ${MODEL}"
echo "  Tensor parallel:  ${TP_SIZE}"
echo "  Port:            ${PORT}"
echo "  Max context:     ${MAX_MODEL_LEN}"
echo "  GPU utilization:  ${GPU_UTIL}"
echo ""

exec vllm serve "${MODEL}" \
    --tensor-parallel-size "${TP_SIZE}" \
    --port "${PORT}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --gpu-memory-utilization "${GPU_UTIL}" \
    --trust-remote-code \
    --dtype auto
