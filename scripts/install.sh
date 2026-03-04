#!/usr/bin/env bash
# Full installation script for vLLM inference server.
# Run this on BOTH machines (head and worker).
set -euo pipefail

echo "=== vLLM Server Setup ==="

# ---- 1. System dependencies ----
echo "[1/6] Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev curl git \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev

# ---- 2. pyenv ----
if [ ! -d "$HOME/.pyenv" ]; then
    echo "[2/6] Installing pyenv..."
    curl -fsSL https://pyenv.run | bash

    if ! grep -q 'PYENV_ROOT' ~/.bashrc; then
        cat >> ~/.bashrc << 'BASHRC'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
BASHRC
    fi
else
    echo "[2/6] pyenv already installed, skipping."
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"

# ---- 3. Python 3.12 ----
PYTHON_VERSION="3.12.9"
if ! pyenv versions --bare | grep -q "^${PYTHON_VERSION}$"; then
    echo "[3/6] Installing Python ${PYTHON_VERSION}..."
    pyenv install "${PYTHON_VERSION}"
else
    echo "[3/6] Python ${PYTHON_VERSION} already installed."
fi
pyenv local "${PYTHON_VERSION}"

# ---- 4. Virtual environment ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"

if [ ! -d "${VENV_DIR}" ]; then
    echo "[4/6] Creating virtual environment..."
    python -m venv "${VENV_DIR}"
else
    echo "[4/6] Virtual environment already exists."
fi
source "${VENV_DIR}/bin/activate"

# ---- 5. Install dependencies ----
echo "[5/6] Installing Python dependencies (vLLM + Ray)..."
pip install --upgrade pip -q
pip install -r "${SCRIPT_DIR}/requirements.txt"

# ---- 6. Verify ----
echo "[6/6] Verifying installation..."
python -c "import vllm; print(f'vLLM {vllm.__version__}')"
python -c "import ray; print(f'Ray {ray.__version__}')"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

echo ""
echo "=== Installation complete ==="
echo "Next steps:"
echo "  1. Copy .env.template to .env and add your HF_TOKEN"
echo "  2. On HEAD node:   sudo bash scripts/install_service.sh head"
echo "  3. On WORKER node: sudo bash scripts/install_service.sh worker <HEAD_IP>"
