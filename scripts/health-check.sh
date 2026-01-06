#!/bin/bash
# Check status of all EchoForge services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a && source "$PROJECT_ROOT/.env" && set +a
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "EchoForge Health Check"
echo "======================"
echo ""

# PostgreSQL
if docker exec echoforge_postgres pg_isready -U echoforge > /dev/null 2>&1; then
    echo -e "PostgreSQL (${POSTGRES_PORT:-5435}):  ${GREEN}RUNNING${NC}"
else
    echo -e "PostgreSQL (${POSTGRES_PORT:-5435}):  ${RED}STOPPED${NC}"
fi

# Redis
if docker exec echoforge_redis redis-cli ping > /dev/null 2>&1; then
    echo -e "Redis (${REDIS_PORT:-6382}):       ${GREEN}RUNNING${NC}"
else
    echo -e "Redis (${REDIS_PORT:-6382}):       ${RED}STOPPED${NC}"
fi

# Hub
if curl -s "http://localhost:${HUB_PORT:-8003}/" > /dev/null 2>&1; then
    echo -e "Hub (${HUB_PORT:-8003}):          ${GREEN}RUNNING${NC}"
else
    echo -e "Hub (${HUB_PORT:-8003}):          ${YELLOW}STOPPED${NC}"
fi

# Agent
if curl -s "http://localhost:${AGENT_PORT:-8004}/" > /dev/null 2>&1; then
    echo -e "Agent (${AGENT_PORT:-8004}):        ${GREEN}RUNNING${NC}"
else
    echo -e "Agent (${AGENT_PORT:-8004}):        ${YELLOW}STOPPED${NC}"
fi

# Test UI
if curl -s "http://localhost:${TEST_UI_PORT:-8080}/" > /dev/null 2>&1; then
    echo -e "Test UI (${TEST_UI_PORT:-8080}):      ${GREEN}RUNNING${NC}"
else
    echo -e "Test UI (${TEST_UI_PORT:-8080}):      ${YELLOW}STOPPED${NC}"
fi

echo ""
