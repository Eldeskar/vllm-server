#!/usr/bin/env bash
# Test the vLLM server with a simple chat completion request.
set -euo pipefail

PORT="${VLLM_PORT:-8123}"
HOST="${VLLM_HOST:-localhost}"
MODEL="${VLLM_MODEL:-Qwen/Qwen3-VL-32B-Thinking}"

echo "Testing vLLM server at ${HOST}:${PORT}..."

# Health check
echo -n "Health check: "
curl -sf "http://${HOST}:${PORT}/health" && echo "OK" || { echo "FAILED"; exit 1; }

# Chat completion
echo ""
echo "Chat completion test:"
curl -sf "http://${HOST}:${PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}],
        \"max_tokens\": 64,
        \"temperature\": 0.7
    }" | python3 -m json.tool 2>/dev/null || echo "FAILED"

echo ""
echo "Done."
