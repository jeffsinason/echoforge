#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$DEV_ENV_DIR/.env" ]; then
    set -a
    source "$DEV_ENV_DIR/.env"
    set +a
fi

echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║           Database Password Recovery                         ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}This script fixes PostgreSQL password authentication issues.${NC}"
echo -e "${YELLOW}The issue occurs when Docker volumes persist old credentials.${NC}"
echo ""
echo "Choose an option:"
echo ""
echo "  1) Full reset - delete volume and recreate (DESTROYS DATA)"
echo "  2) Try to update password in existing database (may not work)"
echo ""
read -p "Enter choice [1/2]: " choice

case $choice in
    1)
        echo -e "\n${RED}WARNING: This will delete all database data!${NC}"
        read -p "Are you sure? [y/N]: " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cd "$DEV_ENV_DIR"

            echo -e "${YELLOW}Stopping containers...${NC}"
            docker compose down 2>/dev/null || true

            echo -e "${YELLOW}Removing postgres volume...${NC}"
            docker volume rm echoforge_dev_postgres_data 2>/dev/null || true

            echo -e "${YELLOW}Starting fresh...${NC}"
            docker compose up -d postgres

            echo -e "${YELLOW}Waiting for PostgreSQL to initialize...${NC}"
            for i in {1..30}; do
                if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓ PostgreSQL ready with new password${NC}"
                    break
                fi
                sleep 1
            done

            # Start redis too
            docker compose up -d redis

            echo -e "${GREEN}✓ Database reset complete${NC}"
            echo -e "${YELLOW}Run ./scripts/start.sh to run migrations and seed data${NC}"
        else
            echo "Cancelled."
        fi
        ;;

    2)
        echo -e "\n${YELLOW}Attempting to update password in running database...${NC}"

        # First check if container is running
        if ! docker ps | grep -q echoforge_dev_postgres; then
            echo -e "${YELLOW}PostgreSQL container not running. Starting it...${NC}"
            cd "$DEV_ENV_DIR"
            docker compose up -d postgres
            sleep 5
        fi

        # Try to connect via local socket (no password needed) and change password
        if docker exec echoforge_dev_postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" 2>/dev/null; then
            echo -e "${GREEN}✓ Password updated successfully${NC}"
            echo -e "${YELLOW}Restarting PostgreSQL to apply changes...${NC}"
            cd "$DEV_ENV_DIR"
            docker compose restart postgres
            sleep 3
            echo -e "${GREEN}✓ PostgreSQL restarted${NC}"
        else
            echo -e "${RED}✗ Could not update password${NC}"
            echo -e "${YELLOW}Try option 1 (full reset) instead.${NC}"
            exit 1
        fi
        ;;

    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
