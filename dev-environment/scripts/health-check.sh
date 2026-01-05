#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$DEV_ENV_DIR/.env" ]; then
    set -a
    source "$DEV_ENV_DIR/.env"
    set +a
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     EchoForge Development Environment Health Check          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

ALL_HEALTHY=true

# PostgreSQL
echo -n "PostgreSQL (port ${POSTGRES_PORT}): "
if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
    echo -e "${GREEN}HEALTHY${NC}"
else
    echo -e "${RED}UNHEALTHY${NC}"
    ALL_HEALTHY=false
fi

# Redis
echo -n "Redis (port ${REDIS_PORT}):       "
if docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}HEALTHY${NC}"
else
    echo -e "${RED}UNHEALTHY${NC}"
    ALL_HEALTHY=false
fi

# Hub
echo -n "Hub (port ${HUB_PORT}):           "
if curl -s "http://localhost:${HUB_PORT}/health/" > /dev/null 2>&1; then
    echo -e "${GREEN}RUNNING${NC}"
elif curl -s "http://localhost:${HUB_PORT}/" > /dev/null 2>&1; then
    echo -e "${GREEN}RUNNING${NC} (no /health/ endpoint)"
else
    echo -e "${YELLOW}NOT RUNNING${NC}"
fi

# Agent
echo -n "Agent (port ${AGENT_PORT}):         "
if curl -s "http://localhost:${AGENT_PORT}/v1/health" > /dev/null 2>&1; then
    echo -e "${GREEN}RUNNING${NC}"
elif curl -s "http://localhost:${AGENT_PORT}/" > /dev/null 2>&1; then
    echo -e "${GREEN}RUNNING${NC} (no /v1/health endpoint)"
else
    echo -e "${YELLOW}NOT RUNNING${NC}"
fi

echo ""
echo -e "${BLUE}─────────────────────────────────────────────────────────────────${NC}"
echo ""

# Docker containers
echo "Docker Containers:"
docker ps --format "  {{.Names}}: {{.Status}}" | grep echoforge || echo "  (none running)"

echo ""
echo -e "${BLUE}─────────────────────────────────────────────────────────────────${NC}"
echo ""

# Credentials reminder
echo "Test Credentials:"
echo "  API Key:   ${TEST_API_KEY}"
echo "  Hub Login: ${TEST_USERNAME} / ${TEST_PASSWORD}"

echo ""

if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}✓ Infrastructure is healthy${NC}"
else
    echo -e "${RED}✗ Some services are unhealthy${NC}"
    echo -e "${YELLOW}Run ./scripts/start.sh to fix${NC}"
fi
