#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Stopping EchoForge development infrastructure...${NC}"

cd "$DEV_ENV_DIR"
docker compose down

echo -e "${GREEN}✓ Infrastructure stopped${NC}"
echo ""
echo "Note: Hub and Agent servers must be stopped manually (Ctrl+C in their terminals)"
