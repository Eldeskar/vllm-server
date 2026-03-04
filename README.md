# vLLM Multi-Node Inference Server

Serves `Qwen/Qwen3-VL-32B-Thinking` across two GPU machines using vLLM + Ray tensor parallelism. Exposes an OpenAI-compatible API for scoring, error analysis, and prompt optimization.

## Architecture

```
Head node (10.0.3.209)              Worker node (10.0.0.115)
┌───────────────────────┐           ┌───────────────────────┐
│  Ray head             │           │  Ray worker           │
│  vLLM shard 0 (GPU)   │◄────────►│  vLLM shard 1 (GPU)   │
│  API :8123            │           │                       │
└───────────────────────┘           └───────────────────────┘
```

Both GPUs serve one model. The API is always available at `http://10.0.3.209:8123`.

## Setup

### Step 1: Get this repo on BOTH machines

```bash
# On head node (10.0.3.209):
cd ~/vllm-server

# Copy to worker:
scp -r ~/vllm-server ubuntu@10.0.0.115:~/vllm-server
```

### Step 2: Run install script on BOTH machines

```bash
cd ~/vllm-server
bash scripts/install.sh
```

### Step 3: Configure HuggingFace token on BOTH machines

```bash
cp .env.template .env
nano .env   # add your HF_TOKEN
```

### Step 4: (Optional) Pre-download model on BOTH machines

```bash
source .venv/bin/activate
huggingface-cli download Qwen/Qwen3-VL-32B-Thinking
```

### Step 5: Set up SSH keys (head → worker)

```bash
# On head node:
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id ubuntu@10.0.0.115
ssh ubuntu@10.0.0.115 "echo OK"   # verify
```

### Step 6: Install systemd services

**On worker (10.0.0.115):**
```bash
sudo bash scripts/install_service.sh worker 10.0.3.209
```

**On head (10.0.3.209):**
```bash
sudo bash scripts/install_service.sh head
```

### Step 7: Start everything

The worker service is started automatically by Step 6. Only the head node needs manual startup:

```bash
# On head node:
sudo systemctl start ray-head

# Verify worker joined (wait a few seconds):
source .venv/bin/activate
ray status   # should show 2 nodes, 2 GPUs

# Start vLLM:
sudo systemctl start vllm-server
```

### Step 8: Test

```bash
# Wait for model to load (~1-2 min if cached), then:
curl http://localhost:8123/health

# Full test:
bash scripts/test_server.sh
```

## API Usage

```bash
curl http://10.0.3.209:8123/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-VL-32B-Thinking",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 256,
    "temperature": 0.8
  }'
```

For vision (images as base64):
```bash
curl http://10.0.3.209:8123/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-VL-32B-Thinking",
    "messages": [{"role": "user", "content": [
      {"type": "text", "text": "What is in this image?"},
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
    ]}],
    "max_tokens": 256
  }'
```

## Configuration

Set in `.env` or export before running:

| Variable | Default | Description |
|---|---|---|
| `HF_TOKEN` | (required) | HuggingFace access token |
| `VLLM_MODEL` | `Qwen/Qwen3-VL-32B-Thinking` | Model to serve |
| `VLLM_PORT` | `8123` | API port |
| `VLLM_TP_SIZE` | `2` | Tensor parallel size (GPUs) |
| `VLLM_MAX_MODEL_LEN` | `16384` | Maximum context length |
| `VLLM_GPU_UTIL` | `0.92` | GPU memory utilization |

## Management

```bash
# Status
sudo systemctl status ray-head      # head node
sudo systemctl status ray-worker    # worker node
sudo systemctl status vllm-server   # vLLM (head only)

# Logs
sudo journalctl -u vllm-server -f

# Restart
sudo systemctl restart vllm-server

# Stop everything (head node)
sudo systemctl stop vllm-server ray-head

# Stop worker
# On worker: sudo systemctl stop ray-worker
```

## Troubleshooting

**`ray status` shows only 1 node:**
- Check worker: `sudo systemctl status ray-worker`
- Check firewall: ports 6379, 8265, 10001-10100 must be open between machines
- Check connectivity: `ping 10.0.3.209` from worker

**vLLM OOM:**
- Reduce `VLLM_GPU_UTIL` (e.g., `0.85`)
- Reduce `VLLM_MAX_MODEL_LEN` (e.g., `8192`)

**NCCL errors:**
- `export NCCL_SOCKET_IFNAME=eth0` (or your network interface name)
- Ensure both machines can reach each other on all ports

**Model download slow:**
- Pre-download on both machines (Step 4)
