#!/usr/bin/env bash
# stop_ornith.sh — Stop the Ornith llama-server
set -euo pipefail

PID=$(pgrep -f "llama-server.*Ornith" 2>/dev/null || true)

if [[ -z "$PID" ]]; then
  echo "Ornith server is not running."
  exit 0
fi

echo "Stopping Ornith server (PID: $PID)..."
kill "$PID" 2>/dev/null || true

# Wait for clean shutdown
for i in $(seq 1 10); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Stopped."
    exit 0
  fi
  sleep 1
done

# Force if needed
echo "Server did not exit gracefully, sending SIGKILL..."
kill -9 "$PID" 2>/dev/null || true
echo "Killed."