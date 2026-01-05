#!/bin/bash
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

# Load environment
if [ -f "$DEV_ENV_DIR/.env" ]; then
    set -a
    source "$DEV_ENV_DIR/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found at $DEV_ENV_DIR/.env${NC}"
    echo "Copy .env.example to .env and configure it."
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        EchoForge Development Environment                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Check for --infra-only flag
INFRA_ONLY=false
RUN_MIGRATIONS=true
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --infra-only) INFRA_ONLY=true ;;
        --no-migrate) RUN_MIGRATIONS=false ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --infra-only   Only start Docker infrastructure"
            echo "  --no-migrate   Skip database migrations"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
    esac
    shift
done

# Step 1: Start Docker infrastructure
echo -e "\n${YELLOW}[1/3] Starting Docker infrastructure...${NC}"
cd "$DEV_ENV_DIR"
docker compose up -d

# Wait for PostgreSQL
echo -e "${YELLOW}      Waiting for PostgreSQL...${NC}"
for i in {1..30}; do
    if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
        echo -e "${GREEN}      ✓ PostgreSQL ready${NC}"
        break
    fi
    [ $i -eq 30 ] && { echo -e "${RED}      ✗ PostgreSQL failed${NC}"; exit 1; }
    sleep 1
done

# Wait for Redis
echo -e "${YELLOW}      Waiting for Redis...${NC}"
for i in {1..30}; do
    if docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; then
        echo -e "${GREEN}      ✓ Redis ready${NC}"
        break
    fi
    [ $i -eq 30 ] && { echo -e "${RED}      ✗ Redis failed${NC}"; exit 1; }
    sleep 1
done

# Enable pgvector
docker exec echoforge_dev_postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1
echo -e "${GREEN}      ✓ pgvector enabled${NC}"

if [ "$INFRA_ONLY" = true ]; then
    echo -e "\n${GREEN}Infrastructure ready!${NC}"
    exit 0
fi

# Step 2: Run migrations
if [ "$RUN_MIGRATIONS" = true ]; then
    echo -e "\n${YELLOW}[2/3] Running database migrations...${NC}"
    cd "$ECHOFORGE_ROOT/hub/backend"
    source .venv/bin/activate 2>/dev/null || { echo -e "${RED}Hub venv not found${NC}"; exit 1; }
    python manage.py migrate --settings=echoforge_hub.settings.development > /dev/null 2>&1
    echo -e "${GREEN}      ✓ Migrations complete${NC}"

    # Seed test data
    python manage.py setup_test_data --settings=echoforge_hub.settings.development > /dev/null 2>&1 || true
    echo -e "${GREEN}      ✓ Test data seeded${NC}"
else
    echo -e "\n${YELLOW}[2/3] Skipping migrations${NC}"
fi

# Step 3: Instructions
echo -e "\n${YELLOW}[3/3] Start the servers${NC}"
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Infrastructure is ready! Start servers in separate terminals:║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Terminal 1 - Hub:${NC}                                         ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    $SCRIPT_DIR/start-hub.sh                                  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Terminal 2 - Agent:${NC}                                       ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    $SCRIPT_DIR/start-agent.sh                                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${YELLOW}Credentials:${NC}                                               ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Django Admin: admin / admin123                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Hub Login:    testuser / testpass123                     ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Test API Key: efh_test_key_for_integration_testing_only  ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  ${YELLOW}URLs:${NC}                                                      ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Hub:    http://localhost:${HUB_PORT}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Agent:  http://localhost:${AGENT_PORT}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    Admin:  http://localhost:${HUB_PORT}/admin/                       ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
