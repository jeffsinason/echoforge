#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"

if [ -f "$DEV_ENV_DIR/.env" ]; then
    set -a
    source "$DEV_ENV_DIR/.env"
    set +a
fi

echo -e "${YELLOW}Seeding test data for EchoForge Hub...${NC}"

# Check PostgreSQL is running
if ! docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
    echo -e "${RED}Error: PostgreSQL is not running${NC}"
    echo "Run ./scripts/start.sh first"
    exit 1
fi

cd "$ECHOFORGE_ROOT/hub/backend"

# Activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo -e "${RED}Error: Virtual environment not found${NC}"
    echo "Run ./scripts/start.sh first to set up the environment"
    exit 1
fi

# Export database settings
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export POSTGRES_HOST="${POSTGRES_HOST}"
export POSTGRES_PORT="${POSTGRES_PORT}"
export POSTGRES_DB="${POSTGRES_DB}"
export POSTGRES_USER="${POSTGRES_USER}"
export REDIS_URL="${REDIS_URL}"

# Run migrations first (in case they haven't been run)
echo -e "${YELLOW}Running migrations...${NC}"
python manage.py migrate --settings=echoforge_hub.settings.development

# Seed test data
echo -e "${YELLOW}Seeding test data...${NC}"
python manage.py setup_test_data --settings=echoforge_hub.settings.development

echo -e "${GREEN}✓ Test data seeded successfully${NC}"
echo ""
echo "Created:"
echo "  - Test User: ${TEST_USERNAME} / ${TEST_PASSWORD}"
echo "  - Test Customer: ${TEST_CUSTOMER_EMAIL}"
echo "  - Test Agent with API Key: ${TEST_API_KEY}"
