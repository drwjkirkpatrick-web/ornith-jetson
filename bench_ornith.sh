#!/usr/bin/env bash
# bench_ornith.sh — Benchmark Ornith-1.0-9B IQ3_M
#
# Two phases:
#   1. llama-bench: raw speed metrics (pp512, tg128) at multiple context sizes
#   2. Quality prompts: 12-prompt eval suite from jetson-model-zoo
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${MODEL:-$HOME/models/Ornith-1.0-9B-MTP-IQ3_M.gguf}"
LLAMA_BENCH="${LLAMA_BENCH:-$HOME/llama.cpp/build/bin/llama-bench}"
LLAMA_CLI="${LLAMA_CLI:-$HOME/llama.cpp/build/bin/llama-cli}"
RESULTS_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

if [[ ! -f "$MODEL" ]]; then
  echo "Error: model not found at $MODEL" >&2
  exit 1
fi

echo "================================================"
echo "  Ornith-1.0-9B IQ3_M Benchmark"
echo "  $(date)"
echo "================================================"
echo ""

# --- Phase 1: llama-bench raw speed ---
echo "--- Phase 1: llama-bench (raw speed) ---"
echo ""

BENCH_FILE="$RESULTS_DIR/bench_${TIMESTAMP}.txt"

"$LLAMA_BENCH" \
  -m "$MODEL" \
  -ngl 99 \
  -fa 1 \
  -ctk q4_0 \
  -ctv q4_0 \
  -p 512 \
  -n 128 \
  -t 6 \
  2>&1 | tee "$BENCH_FILE"

echo ""
echo "Raw speed results saved to: $BENCH_FILE"
echo ""

# --- Phase 2: Context scaling (1K, 8K, 32K, 65K) ---
echo "--- Phase 1b: Context scaling ---"
echo ""

CTX_FILE="$RESULTS_DIR/ctx_scaling_${TIMESTAMP}.txt"

for CTX in 1024 8192 32768 65536; do
  echo "Testing context=${CTX} ($(( CTX / 1024 ))K)..."
  "$LLAMA_BENCH" \
    -m "$MODEL" \
    -ngl 99 \
    -fa 1 \
    -ctk q4_0 \
    -ctv q4_0 \
    -c "$CTX" \
    -p 512 \
    -n 128 \
    -t 6 \
    2>&1 | tee -a "$CTX_FILE"
  echo "" >> "$CTX_FILE"
done

echo "Context scaling saved to: $CTX_FILE"
echo ""

# --- Phase 3: Quality prompts ---
echo "--- Phase 2: Quality prompt evaluation ---"
echo ""

PROMPTS_FILE="${SCRIPT_DIR}/test_prompts.json"
QUALITY_FILE="$RESULTS_DIR/quality_${TIMESTAMP}.jsonl"

if [[ ! -f "$PROMPTS_FILE" ]]; then
  echo "Warning: $PROMPTS_FILE not found, skipping quality eval."
  exit 0
fi

# Run each prompt through llama-cli and capture output
python3 "$SCRIPT_DIR/bench_quality.py" \
  --model "$MODEL" \
  --cli "$LLAMA_CLI" \
  --prompts "$PROMPTS_FILE" \
  --output "$QUALITY_FILE" \
  --max-tokens 4096 \
  --context 8192 \
  --temp 0.3

echo ""
echo "Quality results saved to: $QUALITY_FILE"
echo ""
echo "================================================"
echo "  Benchmark complete!"
echo "  Results in: $RESULTS_DIR/"
echo "================================================"