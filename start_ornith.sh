#!/usr/bin/env bash
# start_ornith.sh — Start Ornith-1.0-9B IQ3_M on Jetson Orin Nano 8GB
#
# Champion config from jimenezcarrero/jetson-llm-benchmarks:
#   Undefeated across all 4 agent arenas, 11/11 marathon, 9.2K peak ctx.
#
# Optimized flags (each has a measured reason — see README.md):
#   -ngl 99         All layers on GPU (tensor cores for all matmul)
#   -fa on          Flash attention (6-50x prompt eval speedup on sm_87)
#   -ctk q4_0       Q4 KV cache — free on Qwen3.5 family (hybrid-SSM, ~8 attn layers)
#   -ctv q4_0       Q4 V-cache — same, no quality/speed cost vs f16
#   -c 65536        65K context — champion deployment window
#   -ub 128         Small compute buffer — the alloc that OOMs first on 8GB
#   -b 512          Batch size for prompt processing
#   -np 1           Single slot — all RAM for one model
#   --jinja         Chat template engine (required for thinking/reasoning models)
#   -t 6            6 CPU threads (6-core Cortex-A78AE)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${MODEL:-$HOME/models/Ornith-1.0-9B-MTP-IQ3_M.gguf}"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/llama.cpp/build/bin/llama-server}"
PORT="${PORT:-8080}"
CONTEXT="${CONTEXT:-65536}"

# --- Check prerequisites ---
if [[ ! -f "$MODEL" ]]; then
  echo "Error: model not found at $MODEL" >&2
  echo "  Download from: https://huggingface.co/protoLabsAI/Ornith-1.0-9B-MTP-GGUF" >&2
  exit 1
fi
if [[ ! -x "$LLAMA_SERVER" ]]; then
  echo "Error: llama-server not found at $LLAMA_SERVER" >&2
  exit 1
fi

# --- Stop any existing instance ---
pkill -f "llama-server.*Ornith" 2>/dev/null || true
sleep 1

# --- Optional: free RAM by stopping GUI ---
if systemctl is-active --quiet gdm 2>/dev/null || systemctl is-active --quiet gdm3 2>/dev/null; then
  echo "GDM is running — consider 'sudo systemctl stop gdm' to free ~600MB for larger context"
fi

# --- Start llama-server ---
echo "Starting Ornith-1.0-9B IQ3_M on :${PORT}..."
echo "  Model:   $MODEL"
echo "  Context: ${CONTEXT} ($(( CONTEXT / 1024 ))K)"
echo "  KV:      q4_0 / q4_0 (free on Qwen3.5 hybrid-SSM family)"
echo "  Flags:   -ngl 99 -fa on -ub 128 -b 512 -np 1 --jinja"

"$LLAMA_SERVER" \
  -m "$MODEL" \
  --host 0.0.0.0 \
  --port "$PORT" \
  -c "$CONTEXT" \
  -ngl 99 \
  -t 6 \
  -fa on \
  -ctk q4_0 \
  -ctv q4_0 \
  -ub 128 \
  -b 512 \
  -np 1 \
  --jinja \
  --metrics \
  > /tmp/ornith-server.log 2>&1 &

PID=$!
echo "  PID:     $PID"
echo "  Log:     /tmp/ornith-server.log"

# --- Wait for server to be ready ---
echo -n "  Waiting for server..."
for i in $(seq 1 60); do
  if curl -s "http://localhost:$PORT/health" 2>/dev/null | grep -q "ok"; then
    echo " ready!"
    echo ""
    echo "Ornith is serving at http://localhost:$PORT"
    echo "  Chat:    http://localhost:$PORT/v1/chat/completions"
    echo "  Completions: http://localhost:$PORT/v1/completions"
    echo "  Health:  http://localhost:$PORT/health"
    echo ""
    echo "Stop with: ./stop_ornith.sh"
    exit 0
  fi
  echo -n "."
  sleep 2
  if [[ $i -eq 60 ]]; then
    echo " TIMEOUT (120s)"
    echo "Check /tmp/ornith-server.log for errors"
    exit 1
  fi
done