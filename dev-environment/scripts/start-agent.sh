#!/bin/bash
# Start EchoForge Agent server
# Run this in its own terminal (after Hub is running)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"

# Load unified environment
set -a
source "$DEV_ENV_DIR/.env"
set +a

cd "$ECHOFORGE_ROOT/agent"

# Activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "Error: Virtual environment not found at .venv"
    echo "Run: python3 -m venv .venv && pip install -r requirements/development.txt"
    exit 1
fi

echo "Starting EchoForge Agent on http://localhost:${AGENT_PORT:-8004}"
echo ""
echo "Test with:"
echo "  curl -X POST http://localhost:${AGENT_PORT:-8004}/v1/chat \\"
echo "    -H 'Authorization: Bearer ${TEST_API_KEY}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
echo ""
echo "Press Ctrl+C to stop"
echo ""

uvicorn src.main:app --reload --port ${AGENT_PORT:-8004}
