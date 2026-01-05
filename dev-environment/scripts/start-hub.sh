#!/bin/bash
# Start EchoForge Hub server
# Run this in its own terminal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"

# Load unified environment
set -a
source "$DEV_ENV_DIR/.env"
set +a

cd "$ECHOFORGE_ROOT/hub/backend"

# Activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "Error: Virtual environment not found at .venv"
    echo "Run: python3 -m venv .venv && pip install -r requirements/development.txt"
    exit 1
fi

echo "Starting EchoForge Hub on http://localhost:${HUB_PORT:-8003}"
echo "Django Admin: http://localhost:${HUB_PORT:-8003}/admin/"
echo "Credentials: admin / admin123"
echo ""
echo "Press Ctrl+C to stop"
echo ""

python manage.py runserver ${HUB_PORT:-8003}
