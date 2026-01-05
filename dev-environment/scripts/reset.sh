#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║        FULL DEVELOPMENT ENVIRONMENT RESET                    ║${NC}"
echo -e "${RED}║        This will destroy all local data!                     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

# Check for --force flag
if [[ "$1" != "--force" ]]; then
    read -p "Are you sure you want to reset everything? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

cd "$DEV_ENV_DIR"

echo -e "\n${YELLOW}[1/5] Stopping unified infrastructure...${NC}"
docker compose down 2>/dev/null || true

echo -e "${YELLOW}[2/5] Removing Docker volumes...${NC}"
docker volume rm echoforge_dev_postgres_data echoforge_dev_redis_data 2>/dev/null || true

echo -e "${YELLOW}[3/5] Cleaning up old Hub infrastructure (if exists)...${NC}"
# Stop any old containers from individual projects
docker stop echoforge_hub_postgres echoforge_hub_redis 2>/dev/null || true
docker rm echoforge_hub_postgres echoforge_hub_redis 2>/dev/null || true
docker volume rm docker_postgres_data docker_redis_data 2>/dev/null || true

echo -e "${YELLOW}[4/5] Cleaning up old testing infrastructure (if exists)...${NC}"
docker stop echoforge_agent echoforge_test_ui 2>/dev/null || true
docker rm echoforge_agent echoforge_test_ui 2>/dev/null || true

echo -e "${YELLOW}[5/5] Starting fresh environment...${NC}"
"$SCRIPT_DIR/start.sh"

echo -e "\n${GREEN}✓ Reset complete!${NC}"
