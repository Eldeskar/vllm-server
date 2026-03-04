#!/usr/bin/env bash
# Install systemd services for Ray + vLLM.
#
# Usage:
#   Head node:   sudo bash scripts/install_service.sh head
#   Worker node: sudo bash scripts/install_service.sh worker <HEAD_IP>
set -euo pipefail

ROLE="${1:?Usage: sudo bash scripts/install_service.sh head|worker [HEAD_IP]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_USER="${SUDO_USER:-ubuntu}"

if [ "${ROLE}" = "head" ]; then
    # ---- Ray head service ----
    cat > /etc/systemd/system/ray-head.service << EOF
[Unit]
Description=Ray Head Node
After=network.target

[Service]
Type=forking
User=${SERVICE_USER}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/scripts/start_ray_head.sh
ExecStop=${SCRIPT_DIR}/.venv/bin/ray stop
Restart=on-failure
RestartSec=10
Environment=HOME=/home/${SERVICE_USER}

[Install]
WantedBy=multi-user.target
EOF

    # ---- vLLM server service (depends on Ray head) ----
    cat > /etc/systemd/system/vllm-server.service << EOF
[Unit]
Description=vLLM Inference Server
After=ray-head.service
Requires=ray-head.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/scripts/start_server.sh
Restart=on-failure
RestartSec=15
Environment=HOME=/home/${SERVICE_USER}
# Give time for model loading before systemd considers it failed
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ray-head vllm-server
    echo ""
    echo "Head node services installed."
    echo "  Start Ray first, wait for worker to join, then start vLLM:"
    echo "    sudo systemctl start ray-head"
    echo "    # (start worker on remote machine)"
    echo "    # (verify: source .venv/bin/activate && ray status → 2 nodes)"
    echo "    sudo systemctl start vllm-server"
    echo ""
    echo "  Logs:"
    echo "    sudo journalctl -u ray-head -f"
    echo "    sudo journalctl -u vllm-server -f"

elif [ "${ROLE}" = "worker" ]; then
    HEAD_IP="${2:?Worker needs HEAD_IP: sudo bash scripts/install_service.sh worker <HEAD_IP>}"

    cat > /etc/systemd/system/ray-worker.service << EOF
[Unit]
Description=Ray Worker Node
After=network.target

[Service]
Type=forking
User=${SERVICE_USER}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/scripts/start_ray_worker.sh ${HEAD_IP}
ExecStop=${SCRIPT_DIR}/.venv/bin/ray stop
Restart=on-failure
RestartSec=10
Environment=HOME=/home/${SERVICE_USER}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ray-worker
    systemctl start ray-worker
    echo ""
    echo "Worker service installed and started."
    echo "  Status: sudo systemctl status ray-worker"
    echo "  Logs:   sudo journalctl -u ray-worker -f"
else
    echo "Unknown role: ${ROLE}. Use 'head' or 'worker'."
    exit 1
fi
