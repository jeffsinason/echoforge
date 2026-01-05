#!/bin/bash
#
# EchoForge Development Environment - Stop All Services
#
# Usage:
#   ./stop-all.sh          # Stop Hub and Agent only
#   ./stop-all.sh --all    # Stop everything including Docker
#   ./stop-all.sh --force  # Force kill all processes on ports
#

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
SESSION_NAME="echoforge"

# Load environment for port numbers
if [ -f "$DEV_ENV_DIR/.env" ]; then
    set -a
    source "$DEV_ENV_DIR/.env"
    set +a
fi

HUB_PORT=${HUB_PORT:-8003}
AGENT_PORT=${AGENT_PORT:-8004}

echo -e "${YELLOW}Stopping EchoForge development environment...${NC}"

# Kill tmux session (stops Hub and Agent)
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
    echo -e "${GREEN}✓ Killed tmux session${NC}"
else
    echo "  No tmux session found"
fi

# Force kill any remaining processes on the ports
echo -e "${YELLOW}Cleaning up stale processes...${NC}"

# Kill Hub port
if lsof -i :$HUB_PORT -t > /dev/null 2>&1; then
    lsof -i :$HUB_PORT -t | xargs kill -9 2>/dev/null || true
    echo -e "${GREEN}✓ Killed processes on port $HUB_PORT${NC}"
else
    echo "  Port $HUB_PORT already free"
fi

# Kill Agent port
if lsof -i :$AGENT_PORT -t > /dev/null 2>&1; then
    lsof -i :$AGENT_PORT -t | xargs kill -9 2>/dev/null || true
    echo -e "${GREEN}✓ Killed processes on port $AGENT_PORT${NC}"
else
    echo "  Port $AGENT_PORT already free"
fi

# Kill any stray Django/uvicorn processes
pkill -f "manage.py runserver" 2>/dev/null && echo -e "${GREEN}✓ Killed Django processes${NC}" || true
pkill -f "uvicorn src.main:app" 2>/dev/null && echo -e "${GREEN}✓ Killed uvicorn processes${NC}" || true

# Check for --all flag to also stop Docker
if [[ "$1" == "--all" ]]; then
    echo -e "${YELLOW}Stopping Docker infrastructure...${NC}"
    cd "$DEV_ENV_DIR"
    docker compose down
    echo -e "${GREEN}✓ Docker infrastructure stopped${NC}"
else
    echo ""
    echo "Docker infrastructure is still running (use --all to stop)"
fi

# Verify ports are free
echo ""
if lsof -i :$HUB_PORT -t > /dev/null 2>&1 || lsof -i :$AGENT_PORT -t > /dev/null 2>&1; then
    echo -e "${RED}Warning: Some ports still in use. Try: ./stop-all.sh --all${NC}"
else
    echo -e "${GREEN}✓ All ports free${NC}"
fi

echo ""
echo -e "${GREEN}Done. To restart: ./restart.sh${NC}"
