# Feature Specification: Unified Development Environment

**Status:** Draft
**Created:** 2025-12-31
**Author:** System Architect Session

---

## 1. Problem Statement

The EchoForge ecosystem consists of multiple interdependent services (Hub, Agent, Testing UI) that currently suffer from configuration synchronization issues:

### Current Issues

| Issue | Symptom | Root Cause |
|-------|---------|------------|
| Service Secret Mismatch | Agent authentication fails | Hub uses 38-char secret, Testing uses 26-char |
| Database Password Persistence | PostgreSQL login fails | Docker volume persists old credentials; `.env` changes ignored |
| Redis Port Ambiguity | Connection failures | Multiple Redis instances (6382, 6383) cause confusion |
| No Unified Startup | Manual multi-step process | Each service has separate startup; no dependency management |
| Missing Test Data | API calls return 404s | Database has no seeded agents/customers |

### Impact

Developers cannot run integration tests without manually debugging configuration mismatches, slowing development and onboarding.

---

## 2. Proposed Solution

Create a **centralized development environment orchestration system** at `/EchoForgeX/dev-environment/` that:

1. Provides a single source of truth for all credentials
2. Manages Docker infrastructure (Postgres, Redis)
3. Supports hybrid workflow (native Hub/Agent + Docker infrastructure)
4. Auto-seeds test data on startup
5. Includes database recovery procedures

### Architecture Overview

```
EchoForgeX/
├── dev-environment/           # NEW: Centralized orchestration
│   ├── .env                   # Single source of truth for credentials
│   ├── .env.example           # Template for new developers
│   ├── docker-compose.yml     # Unified infrastructure (Postgres + Redis)
│   ├── scripts/
│   │   ├── start.sh           # Main startup orchestrator
│   │   ├── stop.sh            # Graceful shutdown
│   │   ├── reset.sh           # Full reset (volumes + data)
│   │   ├── seed-data.sh       # Manual test data seeding
│   │   ├── fix-db-password.sh # Database password recovery
│   │   └── health-check.sh    # Service health verification
│   └── README.md              # Setup documentation
├── echoforge-hub/             # Symlinks to dev-environment/.env
├── echoforge-agent/           # Symlinks to dev-environment/.env
└── testing/                   # Uses dev-environment infrastructure
```

---

## 3. Unified Configuration

### 3.1 Shared Environment Variables

**File:** `/dev-environment/.env`

```bash
# =============================================================================
# ECHOFORGE UNIFIED DEVELOPMENT ENVIRONMENT
# =============================================================================
# This file is the single source of truth for all development credentials.
# Individual projects symlink to this file.
# =============================================================================

# -----------------------------------------------------------------------------
# PostgreSQL Database (Hub)
# -----------------------------------------------------------------------------
POSTGRES_HOST=localhost
POSTGRES_PORT=5435
POSTGRES_DB=echoforge_hub
POSTGRES_USER=echoforge
POSTGRES_PASSWORD=echoforge_dev_2025

# Full connection URL for services that need it
DATABASE_URL=postgresql://echoforge:echoforge_dev_2025@localhost:5435/echoforge_hub

# -----------------------------------------------------------------------------
# Redis Cache/Queue
# -----------------------------------------------------------------------------
REDIS_HOST=localhost
REDIS_PORT=6382
REDIS_URL=redis://localhost:6382

# Database indices (0-15 available)
# 0 = Hub Celery broker
# 1 = Hub cache
# 2 = Agent cache

# -----------------------------------------------------------------------------
# Inter-Service Authentication
# -----------------------------------------------------------------------------
# Agent <-> Hub authentication (minimum 32 characters)
HUB_SERVICE_SECRET=echoforge-dev-service-secret-2025-min32chars

# -----------------------------------------------------------------------------
# External APIs (Development/Test Keys)
# -----------------------------------------------------------------------------
ANTHROPIC_API_KEY=sk-ant-your-api-key-here
OPENAI_API_KEY=sk-test-fake
STRIPE_SECRET_KEY=sk_test_fake
STRIPE_PUBLISHABLE_KEY=pk_test_fake
STRIPE_WEBHOOK_SECRET=whsec_test_fake

# -----------------------------------------------------------------------------
# Django (Hub)
# -----------------------------------------------------------------------------
DJANGO_SECRET_KEY=dev-secret-key-not-for-production-use-only
DJANGO_ENV=development
DJANGO_DEBUG=True

# -----------------------------------------------------------------------------
# Service Ports
# -----------------------------------------------------------------------------
HUB_PORT=8003
AGENT_PORT=8004
TEST_UI_PORT=8080

# -----------------------------------------------------------------------------
# URLs (for inter-service communication)
# -----------------------------------------------------------------------------
HUB_BASE_URL=http://localhost:8003
AGENT_BASE_URL=http://localhost:8004

# -----------------------------------------------------------------------------
# Test Credentials (for integration testing)
# -----------------------------------------------------------------------------
TEST_API_KEY=efh_test_key_for_integration_testing_only
TEST_USERNAME=testuser
TEST_PASSWORD=testpass123
TEST_CUSTOMER_EMAIL=test@echoforge.local

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------
ENCRYPTION_KEY=dGVzdC1lbmNyeXB0aW9uLWtleS1mb3ItZGV2ZWxvcG1lbnQ=
```

### 3.2 Docker Compose for Infrastructure

**File:** `/dev-environment/docker-compose.yml`

```yaml
# EchoForge Unified Development Infrastructure
# Provides PostgreSQL and Redis for all services

services:
  postgres:
    image: pgvector/pgvector:pg15
    container_name: echoforge_dev_postgres
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-echoforge_hub}
      POSTGRES_USER: ${POSTGRES_USER:-echoforge}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-echoforge_dev_2025}
    ports:
      - "${POSTGRES_PORT:-5435}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-echoforge} -d ${POSTGRES_DB:-echoforge_hub}"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - echoforge_dev

  redis:
    image: redis:7-alpine
    container_name: echoforge_dev_redis
    command: redis-server --appendonly yes
    ports:
      - "${REDIS_PORT:-6382}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - echoforge_dev

volumes:
  postgres_data:
    name: echoforge_dev_postgres_data
  redis_data:
    name: echoforge_dev_redis_data

networks:
  echoforge_dev:
    name: echoforge_dev_network
    driver: bridge
```

---

## 4. Startup Scripts

### 4.1 Main Orchestrator

**File:** `/dev-environment/scripts/start.sh`

```bash
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"

# Load environment
source "$DEV_ENV_DIR/.env"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        EchoForge Development Environment Startup            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Parse arguments
AUTO_SEED=true
START_HUB=true
START_AGENT=true
SKIP_INFRA=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --no-seed) AUTO_SEED=false ;;
        --hub-only) START_AGENT=false ;;
        --agent-only) START_HUB=false ;;
        --infra-only) START_HUB=false; START_AGENT=false ;;
        --skip-infra) SKIP_INFRA=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Step 1: Start Docker infrastructure
if [ "$SKIP_INFRA" = false ]; then
    echo -e "\n${YELLOW}[1/5] Starting Docker infrastructure...${NC}"
    cd "$DEV_ENV_DIR"
    docker-compose up -d

    # Wait for services to be healthy
    echo -e "${YELLOW}      Waiting for PostgreSQL...${NC}"
    until docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; do
        sleep 1
    done
    echo -e "${GREEN}      ✓ PostgreSQL ready${NC}"

    echo -e "${YELLOW}      Waiting for Redis...${NC}"
    until docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; do
        sleep 1
    done
    echo -e "${GREEN}      ✓ Redis ready${NC}"
else
    echo -e "\n${YELLOW}[1/5] Skipping infrastructure (--skip-infra)${NC}"
fi

# Step 2: Run Hub migrations
if [ "$START_HUB" = true ]; then
    echo -e "\n${YELLOW}[2/5] Running Hub database migrations...${NC}"
    cd "$ECHOFORGE_ROOT/echoforge-hub/backend"
    source .venv/bin/activate 2>/dev/null || python3 -m venv .venv && source .venv/bin/activate
    python manage.py migrate --settings=echoforge_hub.settings.development
    echo -e "${GREEN}      ✓ Migrations complete${NC}"
else
    echo -e "\n${YELLOW}[2/5] Skipping Hub migrations${NC}"
fi

# Step 3: Seed test data (if enabled)
if [ "$AUTO_SEED" = true ] && [ "$START_HUB" = true ]; then
    echo -e "\n${YELLOW}[3/5] Seeding test data...${NC}"
    cd "$ECHOFORGE_ROOT/echoforge-hub/backend"
    python manage.py setup_test_data --settings=echoforge_hub.settings.development 2>/dev/null || true
    echo -e "${GREEN}      ✓ Test data ready${NC}"
else
    echo -e "\n${YELLOW}[3/5] Skipping test data seeding${NC}"
fi

# Step 4: Start Hub
if [ "$START_HUB" = true ]; then
    echo -e "\n${YELLOW}[4/5] Starting Hub server...${NC}"
    cd "$ECHOFORGE_ROOT/echoforge-hub/backend"

    # Check if Hub is already running
    if lsof -i :$HUB_PORT > /dev/null 2>&1; then
        echo -e "${YELLOW}      Hub already running on port $HUB_PORT${NC}"
    else
        echo -e "${GREEN}      Starting Hub on http://localhost:$HUB_PORT${NC}"
        echo -e "${YELLOW}      Run in separate terminal:${NC}"
        echo -e "      cd $ECHOFORGE_ROOT/echoforge-hub/backend && source .venv/bin/activate"
        echo -e "      python manage.py runserver $HUB_PORT"
    fi
else
    echo -e "\n${YELLOW}[4/5] Skipping Hub startup${NC}"
fi

# Step 5: Start Agent
if [ "$START_AGENT" = true ]; then
    echo -e "\n${YELLOW}[5/5] Starting Agent server...${NC}"
    cd "$ECHOFORGE_ROOT/echoforge-agent"

    # Check if Agent is already running
    if lsof -i :$AGENT_PORT > /dev/null 2>&1; then
        echo -e "${YELLOW}      Agent already running on port $AGENT_PORT${NC}"
    else
        echo -e "${GREEN}      Starting Agent on http://localhost:$AGENT_PORT${NC}"
        echo -e "${YELLOW}      Run in separate terminal:${NC}"
        echo -e "      cd $ECHOFORGE_ROOT/echoforge-agent && source .venv/bin/activate"
        echo -e "      uvicorn src.main:app --reload --port $AGENT_PORT"
    fi
else
    echo -e "\n${YELLOW}[5/5] Skipping Agent startup${NC}"
fi

# Summary
echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Development Environment                   ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  PostgreSQL:  localhost:$POSTGRES_PORT                          ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Redis:       localhost:$REDIS_PORT                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Hub:         http://localhost:$HUB_PORT                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Agent:       http://localhost:$AGENT_PORT                        ${BLUE}║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Test API Key: $TEST_API_KEY                                    ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
```

### 4.2 Database Password Recovery

**File:** `/dev-environment/scripts/fix-db-password.sh`

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

source "$DEV_ENV_DIR/.env"

echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║           Database Password Recovery                         ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}This script fixes PostgreSQL password authentication issues.${NC}"
echo -e "${YELLOW}Choose an option:${NC}"
echo ""
echo "  1) Update password in existing database (preserves data)"
echo "  2) Full reset - delete volume and recreate (DESTROYS DATA)"
echo ""
read -p "Enter choice [1/2]: " choice

case $choice in
    1)
        echo -e "\n${YELLOW}Updating password in existing database...${NC}"

        # Connect as postgres superuser to change password
        docker exec -it echoforge_dev_postgres psql -U postgres -c \
            "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" 2>/dev/null || {

            # If that fails, try direct file modification
            echo -e "${YELLOW}Direct password update failed. Trying volume recreation...${NC}"

            # Stop container
            cd "$DEV_ENV_DIR"
            docker-compose stop postgres

            # Remove only postgres volume
            docker volume rm echoforge_dev_postgres_data 2>/dev/null || true

            # Restart
            docker-compose up -d postgres

            echo -e "${YELLOW}Waiting for PostgreSQL to initialize...${NC}"
            sleep 5
            until docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; do
                sleep 1
            done
        }

        echo -e "${GREEN}✓ Password updated successfully${NC}"
        echo -e "${YELLOW}Note: You may need to re-run migrations and seed data${NC}"
        ;;

    2)
        echo -e "\n${RED}WARNING: This will delete all database data!${NC}"
        read -p "Are you sure? [y/N]: " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cd "$DEV_ENV_DIR"

            echo -e "${YELLOW}Stopping containers...${NC}"
            docker-compose down

            echo -e "${YELLOW}Removing volumes...${NC}"
            docker volume rm echoforge_dev_postgres_data echoforge_dev_redis_data 2>/dev/null || true

            echo -e "${YELLOW}Starting fresh...${NC}"
            docker-compose up -d

            echo -e "${YELLOW}Waiting for PostgreSQL...${NC}"
            sleep 5
            until docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; do
                sleep 1
            done

            echo -e "${GREEN}✓ Database reset complete${NC}"
            echo -e "${YELLOW}Run migrations and seed data:${NC}"
            echo -e "  ./scripts/start.sh"
        else
            echo "Cancelled."
        fi
        ;;

    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
```

### 4.3 Full Reset Script

**File:** `/dev-environment/scripts/reset.sh`

```bash
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

read -p "Are you sure you want to reset everything? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

cd "$DEV_ENV_DIR"

echo -e "\n${YELLOW}[1/4] Stopping all containers...${NC}"
docker-compose down 2>/dev/null || true

echo -e "${YELLOW}[2/4] Removing Docker volumes...${NC}"
docker volume rm echoforge_dev_postgres_data echoforge_dev_redis_data 2>/dev/null || true

echo -e "${YELLOW}[3/4] Cleaning up old Hub/Agent infrastructure...${NC}"
# Stop any old containers from individual projects
docker stop echoforge_hub_postgres echoforge_hub_redis 2>/dev/null || true
docker rm echoforge_hub_postgres echoforge_hub_redis 2>/dev/null || true
docker stop echoforge_agent echoforge_test_ui 2>/dev/null || true
docker rm echoforge_agent echoforge_test_ui 2>/dev/null || true

echo -e "${YELLOW}[4/4] Starting fresh environment...${NC}"
"$SCRIPT_DIR/start.sh"

echo -e "\n${GREEN}✓ Reset complete!${NC}"
```

### 4.4 Stop Script

**File:** `/dev-environment/scripts/stop.sh`

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

echo "Stopping EchoForge development environment..."

cd "$DEV_ENV_DIR"
docker-compose down

echo "✓ Infrastructure stopped"
echo ""
echo "Note: Hub and Agent servers must be stopped manually (Ctrl+C)"
```

### 4.5 Health Check Script

**File:** `/dev-environment/scripts/health-check.sh`

```bash
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"

source "$DEV_ENV_DIR/.env"

echo "EchoForge Development Environment Health Check"
echo "=============================================="

# PostgreSQL
if docker exec echoforge_dev_postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
    echo -e "PostgreSQL (port $POSTGRES_PORT): ${GREEN}HEALTHY${NC}"
else
    echo -e "PostgreSQL (port $POSTGRES_PORT): ${RED}UNHEALTHY${NC}"
fi

# Redis
if docker exec echoforge_dev_redis redis-cli ping > /dev/null 2>&1; then
    echo -e "Redis (port $REDIS_PORT):       ${GREEN}HEALTHY${NC}"
else
    echo -e "Redis (port $REDIS_PORT):       ${RED}UNHEALTHY${NC}"
fi

# Hub
if curl -s "http://localhost:$HUB_PORT/health/" > /dev/null 2>&1; then
    echo -e "Hub (port $HUB_PORT):           ${GREEN}RUNNING${NC}"
else
    echo -e "Hub (port $HUB_PORT):           ${YELLOW}NOT RUNNING${NC}"
fi

# Agent
if curl -s "http://localhost:$AGENT_PORT/v1/health" > /dev/null 2>&1; then
    echo -e "Agent (port $AGENT_PORT):         ${GREEN}RUNNING${NC}"
else
    echo -e "Agent (port $AGENT_PORT):         ${YELLOW}NOT RUNNING${NC}"
fi

echo ""
echo "Test API Key: $TEST_API_KEY"
```

---

## 5. Migration Path

### 5.1 Immediate Fix (Current Session)

To fix the immediate PostgreSQL password issue:

```bash
# Option A: Reset the database (if no important data)
cd /Users/jeffreysinason/Development/EchoForgeX/echoforge-hub/infrastructure/docker
docker-compose down
docker volume rm docker_postgres_data
docker-compose up -d

# Wait for PostgreSQL to be ready
sleep 10

# Run migrations and seed data
cd ../backend
source .venv/bin/activate
python manage.py migrate
python manage.py setup_test_data

# Option B: Update password in running container (preserves data)
docker exec -it echoforge_hub_postgres psql -U postgres -c \
    "ALTER USER echoforge WITH PASSWORD 'echoforge';"
```

### 5.2 Service Secret Fix

Update `/EchoForgeX/testing/.env`:

```bash
# Change from:
HUB_SERVICE_SECRET=test-service-secret-12345

# To (must match Hub's .env):
HUB_SERVICE_SECRET=test-service-secret-12345-min32chars
```

### 5.3 Full Migration to Unified System

```bash
# Step 1: Create dev-environment directory
mkdir -p /Users/jeffreysinason/Development/EchoForgeX/dev-environment/scripts

# Step 2: Create files (use the contents from this spec)
# - .env
# - .env.example
# - docker-compose.yml
# - scripts/*.sh

# Step 3: Make scripts executable
chmod +x /Users/jeffreysinason/Development/EchoForgeX/dev-environment/scripts/*.sh

# Step 4: Stop old infrastructure
cd /Users/jeffreysinason/Development/EchoForgeX/echoforge-hub/infrastructure/docker
docker-compose down

# Step 5: Start unified infrastructure
cd /Users/jeffreysinason/Development/EchoForgeX/dev-environment
./scripts/start.sh

# Step 6: Update individual project .env files to use shared credentials
# (or symlink them to dev-environment/.env)
```

---

## 6. Configuration Synchronization

### 6.1 Symlink Strategy

For each project, symlink shared variables:

```bash
# Hub: Create symlink for shared variables
cd /Users/jeffreysinason/Development/EchoForgeX/echoforge-hub/backend
ln -sf ../../dev-environment/.env .env.shared

# Agent: Create symlink
cd /Users/jeffreysinason/Development/EchoForgeX/echoforge-agent
ln -sf ../dev-environment/.env .env.shared

# Testing: Create symlink
cd /Users/jeffreysinason/Development/EchoForgeX/testing
ln -sf ../dev-environment/.env .env.shared
```

### 6.2 Project-Specific Overrides

Each project can have a `.env.local` for project-specific settings that source the shared config:

```bash
# echoforge-hub/backend/.env.local
source ../../dev-environment/.env

# Project-specific overrides
DJANGO_DEBUG=True
```

---

## 7. Service Port Reference

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5435 | Hub database |
| Redis | 6382 | Cache/queue for Hub + Agent |
| Hub API | 8003 | Management portal |
| Agent API | 8004 | AI runtime engine |
| Test UI | 8080 | Integration testing wireframe |

---

## 8. Credential Reference

| Credential | Value | Used By |
|------------|-------|---------|
| PostgreSQL User | `echoforge` | Hub Django |
| PostgreSQL Password | `echoforge_dev_2025` | Hub Django |
| Service Secret | `echoforge-dev-service-secret-2025-min32chars` | Agent → Hub auth |
| Test API Key | `efh_test_key_for_integration_testing_only` | Test UI → Agent |
| Test Username | `testuser` | Hub login |
| Test Password | `testpass123` | Hub login |

---

## 9. Troubleshooting

### PostgreSQL Password Authentication Failed

```bash
# Check which containers are running
docker ps -a | grep postgres

# If old container with wrong password:
cd /Users/jeffreysinason/Development/EchoForgeX/dev-environment
./scripts/fix-db-password.sh
```

### Agent Can't Connect to Hub

```bash
# Verify service secrets match
grep HUB_SERVICE_SECRET /Users/jeffreysinason/Development/EchoForgeX/echoforge-hub/backend/.env
grep HUB_SERVICE_SECRET /Users/jeffreysinason/Development/EchoForgeX/testing/.env
# These must be identical!

# Verify Hub is running
curl http://localhost:8003/health/
```

### Redis Connection Refused

```bash
# Check Redis is running
docker exec echoforge_dev_redis redis-cli ping
# Should return: PONG

# Check port mapping
docker port echoforge_dev_redis
# Should show: 6379/tcp -> 0.0.0.0:6382
```

### Migrations Not Applied

```bash
cd /Users/jeffreysinason/Development/EchoForgeX/echoforge-hub/backend
source .venv/bin/activate
python manage.py migrate --settings=echoforge_hub.settings.development
python manage.py setup_test_data --settings=echoforge_hub.settings.development
```

---

## 10. Implementation Checklist

- [ ] Create `/dev-environment/` directory structure
- [ ] Create unified `.env` file
- [ ] Create unified `docker-compose.yml`
- [ ] Create startup scripts (`start.sh`, `stop.sh`, `reset.sh`)
- [ ] Create database recovery script (`fix-db-password.sh`)
- [ ] Create health check script (`health-check.sh`)
- [ ] Fix immediate password mismatch in Hub
- [ ] Fix service secret mismatch in Testing
- [ ] Update project READMEs with new workflow
- [ ] Retire old infrastructure configs (mark deprecated)
- [ ] Test full integration flow

---

## 11. Future Enhancements

1. **Makefile Integration**: Add `make dev`, `make reset`, `make test` commands
2. **IDE Integration**: VS Code tasks.json for one-click startup
3. **Hot Reload for Docker**: Use Docker volumes for live code changes
4. **Automated Testing Pipeline**: CI/CD integration testing script
5. **Production-like Mode**: Optional full Docker deployment for testing

---

## Appendix A: Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│              EchoForge Development Quick Reference          │
├─────────────────────────────────────────────────────────────┤
│ Start Everything:   cd dev-environment && ./scripts/start.sh│
│ Stop Infrastructure: ./scripts/stop.sh                      │
│ Full Reset:          ./scripts/reset.sh                     │
│ Health Check:        ./scripts/health-check.sh              │
├─────────────────────────────────────────────────────────────┤
│ Hub:    http://localhost:8003   │ Postgres: localhost:5435  │
│ Agent:  http://localhost:8004   │ Redis:    localhost:6382  │
├─────────────────────────────────────────────────────────────┤
│ Test API Key: efh_test_key_for_integration_testing_only     │
│ Hub Login:    testuser / testpass123                        │
└─────────────────────────────────────────────────────────────┘
```
