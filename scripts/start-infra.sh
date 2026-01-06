#!/bin/bash
# Start PostgreSQL and Redis infrastructure

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Starting infrastructure..."
docker compose up -d

echo "Waiting for PostgreSQL..."
until docker exec echoforge_postgres pg_isready -U echoforge > /dev/null 2>&1; do
    sleep 1
done
echo "PostgreSQL ready"

echo "Waiting for Redis..."
until docker exec echoforge_redis redis-cli ping > /dev/null 2>&1; do
    sleep 1
done
echo "Redis ready"

# Enable pgvector extension
docker exec echoforge_postgres psql -U echoforge -d echoforge_hub \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" > /dev/null 2>&1 || true

echo ""
echo "Infrastructure running:"
echo "  PostgreSQL: localhost:5435"
echo "  Redis:      localhost:6382"
