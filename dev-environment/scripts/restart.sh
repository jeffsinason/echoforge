#!/bin/bash
#
# EchoForge Development Environment - Quick Restart
# Restarts Hub and Agent without touching Docker infrastructure
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"
SESSION_NAME="echoforge"

# Load environment
set -a
source "$DEV_ENV_DIR/.env"
set +a

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         EchoForge Quick Restart (Services Only)              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# =============================================================================
# STEP 1: Kill ALL existing processes (thorough cleanup)
# =============================================================================
echo -e "\n${YELLOW}[1/5] Stopping existing services...${NC}"

# Kill tmux session if exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
    echo -e "      ${GREEN}✓ Killed tmux session${NC}"
fi

# Kill any processes on Hub port
if lsof -i :${HUB_PORT:-8003} -t > /dev/null 2>&1; then
    lsof -i :${HUB_PORT:-8003} -t | xargs kill -9 2>/dev/null || true
    sleep 1
    echo -e "      ${GREEN}✓ Killed processes on port ${HUB_PORT:-8003}${NC}"
fi

# Kill any processes on Agent port
if lsof -i :${AGENT_PORT:-8004} -t > /dev/null 2>&1; then
    lsof -i :${AGENT_PORT:-8004} -t | xargs kill -9 2>/dev/null || true
    sleep 1
    echo -e "      ${GREEN}✓ Killed processes on port ${AGENT_PORT:-8004}${NC}"
fi

# Kill any stray Python processes running our services
pkill -f "manage.py runserver" 2>/dev/null || true
pkill -f "uvicorn src.main:app" 2>/dev/null || true
sleep 1

echo -e "      ${GREEN}✓ All services stopped${NC}"

# =============================================================================
# STEP 2: Verify Docker infrastructure is running
# =============================================================================
echo -e "\n${YELLOW}[2/5] Checking Docker infrastructure...${NC}"

cd "$DEV_ENV_DIR"

# Check PostgreSQL
if ! docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
    echo -e "      ${YELLOW}Starting Docker infrastructure...${NC}"
    docker compose up -d

    # Wait for PostgreSQL
    for i in {1..30}; do
        if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi
echo -e "      ${GREEN}✓ PostgreSQL ready${NC}"

# Check Redis
if ! docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; then
    echo -e "      ${RED}Redis not responding, restarting Docker...${NC}"
    docker compose restart redis
    sleep 3
fi
echo -e "      ${GREEN}✓ Redis ready${NC}"

# =============================================================================
# STEP 3: Run pending migrations (if any)
# =============================================================================
echo -e "\n${YELLOW}[3/5] Checking for pending migrations...${NC}"

cd "$ECHOFORGE_ROOT/hub/backend"
source .venv/bin/activate
# Re-export env vars (venv activation can interfere with exports)
set -a && source "$DEV_ENV_DIR/.env" && set +a

# Check for pending migrations (must use settings flag and have env vars loaded)
PENDING=$(python manage.py showmigrations --plan --settings=echoforge_hub.settings.development 2>&1 | grep "\[ \]" || true)
if [ -n "$PENDING" ]; then
    echo -e "      ${YELLOW}Applying pending migrations...${NC}"
    if python manage.py migrate --settings=echoforge_hub.settings.development 2>&1; then
        echo -e "      ${GREEN}✓ Migrations applied${NC}"
    else
        echo -e "      ${RED}✗ Migration failed - check database connection${NC}"
    fi
else
    # Verify we can actually connect (showmigrations might have silently failed)
    if python manage.py showmigrations --settings=echoforge_hub.settings.development > /dev/null 2>&1; then
        echo -e "      ${GREEN}✓ No pending migrations${NC}"
    else
        echo -e "      ${YELLOW}⚠ Could not check migrations (database may not be ready)${NC}"
        echo -e "      ${YELLOW}  Run manually: cd backend && python manage.py migrate${NC}"
    fi
fi

deactivate

# =============================================================================
# STEP 4: Start services in tmux
# =============================================================================
echo -e "\n${YELLOW}[4/5] Starting services...${NC}"

# Create new tmux session with Hub
# Dynamic .env loading: sources all variables from the central .env file
tmux new-session -d -s "$SESSION_NAME" -n "hub" \
    "cd '$ECHOFORGE_ROOT/hub/backend' && \
     source .venv/bin/activate && \
     set -a && source '$DEV_ENV_DIR/.env' && set +a && \
     python manage.py runserver \${HUB_PORT:-8003}; \
     echo 'Hub stopped. Press enter...'; read"

# Create Agent window
# Dynamic .env loading: sources all variables from the central .env file
tmux new-window -t "$SESSION_NAME" -n "agent" \
    "cd '$ECHOFORGE_ROOT/agent' && \
     source .venv/bin/activate && \
     set -a && source '$DEV_ENV_DIR/.env' && set +a && \
     sleep 3 && \
     uvicorn src.main:app --reload --port \${AGENT_PORT:-8004}; \
     echo 'Agent stopped. Press enter...'; read"

# Create status window
tmux new-window -t "$SESSION_NAME" -n "status" \
    "watch -n 5 '$SCRIPT_DIR/health-check.sh'"

tmux select-window -t "$SESSION_NAME:hub"

# =============================================================================
# STEP 5: Wait for services to be healthy
# =============================================================================
echo -e "\n${YELLOW}[5/5] Waiting for services...${NC}"

# Wait for Hub
echo -n "      Hub..."
for i in {1..30}; do
    if curl -s "http://localhost:${HUB_PORT:-8003}/" > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    [ $i -eq 30 ] && echo -e " ${YELLOW}timeout${NC}"
    sleep 1
done

# Wait for Agent
echo -n "      Agent..."
for i in {1..30}; do
    if curl -s "http://localhost:${AGENT_PORT:-8004}/" > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    [ $i -eq 30 ] && echo -e " ${YELLOW}timeout${NC}"
    sleep 1
done

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Services Restarted                         ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Hub:    http://localhost:${HUB_PORT:-8003}                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Agent:  http://localhost:${AGENT_PORT:-8004}                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Test UI: http://localhost:8080                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  tmux attach -t echoforge                                  ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Option to attach
if [[ "$1" != "--no-attach" ]]; then
    echo -e "${YELLOW}Attaching to tmux (Ctrl+B then d to detach)...${NC}"
    sleep 1
    tmux attach -t "$SESSION_NAME"
fi
