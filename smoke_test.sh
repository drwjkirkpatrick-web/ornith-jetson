#!/usr/bin/env bash
# smoke_test.sh — Quick load + inference test for Ornith-1.0-9B
set -euo pipefail

MODEL="$HOME/models/Ornith-1.0-9B-MTP-IQ3_M.gguf"
SERVER="$HOME/llama.cpp/build/bin/llama-server"
PORT=8099

echo "=== Ornith-1.0-9B IQ3_M Smoke Test ==="
echo "Model: $(ls -lh "$MODEL" | awk '{print $5}')"
echo "Free RAM before: $(free -h | grep Mem | awk '{print $7}')"
echo ""

# Start server in background
"$SERVER" \
  -m "$MODEL" \
  --host 127.0.0.1 --port "$PORT" \
  -c 8192 -ngl 99 -t 6 -fa on \
  -ctk q4_0 -ctv q4_0 -ub 128 -b 512 -np 1 --jinja \
  > /tmp/ornith-smoke.log 2>&1 &

SMOKE_PID=$!
echo "Server PID: $SMOKE_PID"

# Wait for ready
echo -n "Waiting for server..."
for i in $(seq 1 60); do
  if curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q "ok"; then
    echo " ready!"
    break
  fi
  echo -n "."
  sleep 2
  if [[ $i -eq 60 ]]; then
    echo " TIMEOUT"
    echo "=== Server log ==="
    tail -30 /tmp/ornith-smoke.log
    kill "$SMOKE_PID" 2>/dev/null || true
    exit 1
  fi
done

echo ""
echo "=== Server log (first 25 lines) ==="
head -25 /tmp/ornith-smoke.log
echo ""

# Send test prompt
echo "=== Test prompt ==="
RESPONSE=$(curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"ornith","messages":[{"role":"user","content":"Write a one-sentence greeting."}],"temperature":0.3,"max_tokens":100,"stream":false}')

echo "$RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
msg = r['choices'][0]['message']
print('Response:', msg.get('content', '(empty)'))
if msg.get('reasoning_content'):
    print('Reasoning:', msg['reasoning_content'][:200])
print('Usage:', r.get('usage', {}))
" 2>/dev/null || echo "Response: $RESPONSE"

echo ""
echo "Free RAM after load: $(free -h | grep Mem | awk '{print $7}')"
echo ""

echo "=== Stopping smoke test ==="
kill "$SMOKE_PID" 2>/dev/null || true
sleep 2
echo "Done."