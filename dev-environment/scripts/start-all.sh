#!/bin/bash
#
# EchoForge Development Environment - Full Stack Startup
# Starts all services in a tmux session with health verification
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

# Check for tmux
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}Error: tmux is not installed${NC}"
    echo "Install with: brew install tmux"
    exit 1
fi

# Kill existing session if running
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     EchoForge Development Environment - Full Stack          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# =============================================================================
# PHASE 1: Docker Infrastructure
# =============================================================================
echo -e "\n${YELLOW}[1/4] Starting Docker infrastructure...${NC}"

cd "$DEV_ENV_DIR"
docker compose up -d

# Wait for PostgreSQL
echo -n "      Waiting for PostgreSQL..."
for i in {1..30}; do
    if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e " ${RED}failed${NC}"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# Wait for Redis
echo -n "      Waiting for Redis..."
for i in {1..30}; do
    if docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e " ${RED}failed${NC}"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# Enable pgvector
docker exec echoforge_dev_postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1
echo -e "      ${GREEN}✓ pgvector enabled${NC}"

# =============================================================================
# PHASE 2: Database Migrations
# =============================================================================
echo -e "\n${YELLOW}[2/4] Running database migrations...${NC}"

cd "$ECHOFORGE_ROOT/hub/backend"
source .venv/bin/activate
# Re-export env vars (venv activation can interfere with exports)
set -a && source "$DEV_ENV_DIR/.env" && set +a

python manage.py migrate --settings=echoforge_hub.settings.development > /dev/null 2>&1
echo -e "      ${GREEN}✓ Migrations complete${NC}"

# Seed test data (ignore if already exists)
python manage.py setup_test_data --settings=echoforge_hub.settings.development > /dev/null 2>&1 || true
echo -e "      ${GREEN}✓ Test data ready${NC}"

# Ensure admin user exists
python manage.py shell --settings=echoforge_hub.settings.development -c "
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@example.com', 'admin123')
    print('Created admin user')
" 2>/dev/null || true

deactivate

# =============================================================================
# PHASE 3: Create tmux session with services
# =============================================================================
echo -e "\n${YELLOW}[3/4] Starting services in tmux...${NC}"

# Create new tmux session with Hub
# Dynamic .env loading: sources all variables from the central .env file
tmux new-session -d -s "$SESSION_NAME" -n "hub" \
    "cd '$ECHOFORGE_ROOT/hub/backend' && \
     source .venv/bin/activate && \
     set -a && source '$DEV_ENV_DIR/.env' && set +a && \
     echo 'Starting Hub on http://localhost:\$HUB_PORT' && \
     python manage.py runserver \$HUB_PORT; \
     read -p 'Hub stopped. Press enter to close...'"

# Create Agent window
# Dynamic .env loading: sources all variables from the central .env file
tmux new-window -t "$SESSION_NAME" -n "agent" \
    "cd '$ECHOFORGE_ROOT/agent' && \
     source .venv/bin/activate && \
     set -a && source '$DEV_ENV_DIR/.env' && set +a && \
     echo 'Waiting for Hub to be ready...' && \
     for i in {1..30}; do curl -s http://localhost:\$HUB_PORT/ > /dev/null && break; sleep 1; done && \
     echo 'Starting Agent on http://localhost:\$AGENT_PORT' && \
     uvicorn src.main:app --reload --port \$AGENT_PORT; \
     read -p 'Agent stopped. Press enter to close...'"

# Create logs/status window
tmux new-window -t "$SESSION_NAME" -n "status" \
    "watch -n 5 '$SCRIPT_DIR/health-check.sh'"

# Select the hub window
tmux select-window -t "$SESSION_NAME:hub"

# =============================================================================
# PHASE 4: Wait for services to be healthy
# =============================================================================
echo -e "\n${YELLOW}[4/4] Waiting for services to be healthy...${NC}"

# Wait for Hub
echo -n "      Waiting for Hub..."
for i in {1..60}; do
    if curl -s "http://localhost:$HUB_PORT/" > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e " ${YELLOW}timeout (check tmux)${NC}"
    fi
    echo -n "."
    sleep 1
done

# Wait for Agent
echo -n "      Waiting for Agent..."
for i in {1..60}; do
    if curl -s "http://localhost:$AGENT_PORT/" > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e " ${YELLOW}timeout (check tmux)${NC}"
    fi
    echo -n "."
    sleep 1
done

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    ${GREEN}Environment Ready${BLUE}                         ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Services:${NC}                                                  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Hub:    http://localhost:${HUB_PORT}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Agent:  http://localhost:${AGENT_PORT}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Admin:  http://localhost:${HUB_PORT}/admin/                       ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Credentials:${NC}                                               ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Django Admin: admin / admin123                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Hub Login:    testuser / testpass123                     ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    API Key:      ${TEST_API_KEY}  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}tmux session:${NC} ${SESSION_NAME}                                     ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Attach:  tmux attach -t ${SESSION_NAME}                          ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Windows: hub | agent | status                            ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Navigate: Ctrl+B then 0/1/2 or n/p                       ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Detach:  Ctrl+B then d                                   ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Attaching to tmux session...${NC}"
echo -e "${YELLOW}(Press Ctrl+B then d to detach and leave services running)${NC}"
echo ""

# Attach to tmux session
tmux attach -t "$SESSION_NAME"
