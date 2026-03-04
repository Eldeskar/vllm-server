# vLLM Multi-Node Inference Server

Serves `Qwen/Qwen3-VL-32B-Thinking-FP8` across two GPU machines using vLLM + Ray tensor parallelism. Exposes an OpenAI-compatible API for scoring, error analysis, and prompt optimization.

## Architecture

```
Head node (10.0.3.209)              Worker node (10.0.0.115)
┌───────────────────────┐           ┌───────────────────────┐
│  Ray head             │           │  Ray worker           │
│  vLLM shard 0 (GPU)   │◄────────►│  vLLM shard 1 (GPU)   │
│  API :8123            │           │                       │
└───────────────────────┘           └───────────────────────┘
```

Each node has one NVIDIA L4 GPU (23 GB). The FP8-quantized model splits evenly (~17 GB per shard), leaving room for KV cache. The API is always available at `http://10.0.3.209:8123`.

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
huggingface-cli download Qwen/Qwen3-VL-32B-Thinking-FP8
```

### Step 5: Set up SSH keys (head → worker)

Ray needs passwordless SSH from head to worker for distributed execution.

```bash
# On head node:
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id ubuntu@10.0.0.115
ssh ubuntu@10.0.0.115 "echo OK"   # verify

# If ssh-copy-id fails, manually append the pubkey on the worker:
# cat ~/.ssh/id_ed25519.pub | ssh ubuntu@10.0.0.115 'cat >> ~/.ssh/authorized_keys'
# Then restart ssh on the worker: sudo systemctl restart ssh
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
    "model": "Qwen/Qwen3-VL-32B-Thinking-FP8",
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
    "model": "Qwen/Qwen3-VL-32B-Thinking-FP8",
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
| `VLLM_MODEL` | `Qwen/Qwen3-VL-32B-Thinking-FP8` | Model to serve |
| `VLLM_PORT` | `8123` | API port |
| `VLLM_TP_SIZE` | `2` | Tensor parallel size (GPUs across nodes) |
| `VLLM_MAX_MODEL_LEN` | `12288` | Maximum context length (input + output) |
| `VLLM_GPU_UTIL` | `0.95` | GPU memory utilization fraction |

### Important notes on configuration

- **`max_model_len`** is the total context window (input + output tokens combined), not just output. With FP8 on 2x L4 GPUs, 12288 is the practical maximum — higher values cause KV cache OOM.
- **`max_tokens`** (per-request) controls how many tokens a single request can generate. Must be ≤ `max_model_len`.
- **`--enforce-eager`** is used to skip CUDA graph capture, freeing ~1 GB of GPU memory for KV cache. This is required to fit the 12288 context length.
- The FP8 model loads ~17 GB per GPU shard. With `gpu_memory_utilization=0.95`, this leaves ~4.5 GB per GPU for KV cache.

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

**`ray status` shows 3+ nodes (stale entries):**
- Restart Ray head: `sudo systemctl restart ray-head`
- Then restart worker: `ssh ubuntu@10.0.0.115 'sudo systemctl restart ray-worker'`
- Verify: `ray status` should show exactly 2 nodes, 2 GPUs

**vLLM OOM / KV cache too small:**
- Reduce `VLLM_MAX_MODEL_LEN` (e.g., `8192`)
- Ensure `--enforce-eager` is set (saves ~1 GB by skipping CUDA graphs)
- Check for stale GPU processes: `nvidia-smi` — kill any leftover `RayWorkerWrapper` processes
- Do NOT increase `VLLM_GPU_UTIL` above 0.95 — CUDA graph capture OOMs at 0.98

**Why FP8 instead of bf16?**
- The bf16 model needs ~64 GB total (~32 GB per shard) which exceeds L4's 23 GB
- FP8 reduces to ~34 GB total (~17 GB per shard), fits comfortably
- bitsandbytes runtime quantization also OOMs because it loads full bf16 weights before quantizing

**NVIDIA driver/library version mismatch (nvidia-smi fails):**
- Reboot the affected node — this resolves driver/library version mismatches after kernel updates

**NCCL errors:**
- `export NCCL_SOCKET_IFNAME=eth0` (or your network interface name)
- Ensure both machines can reach each other on all ports

**Model download slow:**
- Pre-download on both machines (Step 4)
