#!/usr/bin/env bash
# Stop the vLLM server.
set -euo pipefail

if systemctl is-active --quiet vllm-server 2>/dev/null; then
    echo "Stopping vllm-server service..."
    sudo systemctl stop vllm-server
else
    echo "Stopping vLLM processes..."
    pkill -f "vllm serve" 2>/dev/null || true
    pkill -f "vllm.entrypoints" 2>/dev/null || true
fi

sleep 2
echo "Stopped."
nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || true
