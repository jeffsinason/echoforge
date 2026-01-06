# EchoForge Unified Development Environment

This directory provides centralized orchestration for the EchoForge development stack.

## Quick Start

```bash
# First time setup (run ONCE)
./scripts/setup.sh

# Edit .env to add your ANTHROPIC_API_KEY
nano .env

# Start everything (recommended)
./scripts/start-all.sh
```

The setup script will:
1. Check Python version (3.10+ required)
2. Create `.env` from `.env.example` if needed
3. Create virtual environments in `hub/backend/.venv` and `agent/.venv`
4. Install all dependencies

This single command will:
1. Start Docker infrastructure (PostgreSQL, Redis)
2. Run database migrations
3. Seed test data
4. Start Hub and Agent in tmux windows
5. Wait for all services to be healthy
6. Attach you to the tmux session

### tmux Navigation

Once attached to the tmux session:
- `Ctrl+B` then `0` - Hub logs
- `Ctrl+B` then `1` - Agent logs
- `Ctrl+B` then `2` - Health status (auto-refreshing)
- `Ctrl+B` then `d` - Detach (services keep running)
- `tmux attach -t echoforge` - Reattach later

### Stop Everything

```bash
./scripts/stop-all.sh        # Stop Hub and Agent only
./scripts/stop-all.sh --all  # Stop everything including Docker
```

## Alternative: Manual Startup

If you prefer separate terminals:

```bash
./scripts/start.sh        # Infrastructure + migrations
./scripts/start-hub.sh    # Terminal 1
./scripts/start-agent.sh  # Terminal 2
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Development Environment                   │
├─────────────────────────────────────────────────────────────┤
│  PostgreSQL (Docker)     │  Redis (Docker)                  │
│  localhost:5435          │  localhost:6382                  │
├─────────────────────────────────────────────────────────────┤
│  Hub (Native Python)     │  Agent (Native Python)           │
│  localhost:8003          │  localhost:8004                  │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
dev-environment/
├── .env                    # Your local credentials (git-ignored)
├── .env.example            # Template for new developers
├── docker-compose.yml      # PostgreSQL + Redis infrastructure
├── scripts/
│   ├── setup.sh            # First-time setup (creates venvs, installs deps)
│   ├── start-all.sh        # Full stack startup with tmux (recommended)
│   ├── stop-all.sh         # Stop all services
│   ├── restart.sh          # Quick restart Hub+Agent
│   ├── start.sh            # Infrastructure + migrations only
│   ├── start-hub.sh        # Start Hub server (manual mode)
│   ├── start-agent.sh      # Start Agent server (manual mode)
│   ├── stop.sh             # Stop Docker infrastructure
│   ├── reset.sh            # Full reset (destroys data)
│   ├── health-check.sh     # Check all services
│   ├── fix-db-password.sh  # Fix PostgreSQL auth issues
│   └── seed-data.sh        # Manually seed test data
└── README.md               # This file
```

## Quick Reference

```bash
# Most common commands:
./scripts/restart.sh           # Quick restart Hub+Agent (keeps Docker running)
./scripts/stop-all.sh          # Stop Hub+Agent, keep Docker
./scripts/stop-all.sh --all    # Stop everything including Docker
./scripts/start-all.sh         # Full startup from scratch
./scripts/health-check.sh      # Check all service status
```

## Scripts

### restart.sh (Recommended for Development)

Quick restart of Hub and Agent without touching Docker. Use this when:
- You've made code changes and need to restart
- Services crashed or became unresponsive
- Ports are stuck

```bash
./scripts/restart.sh              # Restart and attach to tmux
./scripts/restart.sh --no-attach  # Restart without attaching
```

This script:
1. Force kills ALL processes on Hub/Agent ports
2. Kills any stray Django/uvicorn processes
3. Verifies Docker is running
4. Starts fresh Hub and Agent in tmux
5. Waits for health checks

### start-all.sh (Full Startup)

Single command to start the entire stack with health verification.

```bash
./scripts/start-all.sh
```

What it does:
1. Starts Docker infrastructure and waits for health
2. Runs database migrations
3. Seeds test data and creates admin user
4. Starts Hub in tmux, waits for it to be healthy
5. Starts Agent in tmux, waits for it to be healthy
6. Opens a status window with auto-refreshing health checks
7. Attaches you to the tmux session

### stop-all.sh

Stops all services cleanly.

```bash
./scripts/stop-all.sh        # Stop Hub and Agent (keep Docker running)
./scripts/stop-all.sh --all  # Stop everything including Docker
```

### start.sh (Manual Mode)

Just starts infrastructure and runs migrations.

```bash
./scripts/start.sh              # Full startup (infra + migrations)
./scripts/start.sh --infra-only # Only start Docker infrastructure
./scripts/start.sh --no-migrate # Skip database migrations
```

### start-hub.sh / start-agent.sh (Manual Mode)

For running services in separate terminals instead of tmux.

```bash
./scripts/start-hub.sh    # Terminal 1
./scripts/start-agent.sh  # Terminal 2
```

### stop.sh

Stops Docker infrastructure (Hub/Agent must be stopped manually).

```bash
./scripts/stop.sh
```

### reset.sh

Full environment reset - **destroys all data**.

```bash
./scripts/reset.sh
./scripts/reset.sh --force  # Skip confirmation prompt
```

### health-check.sh

Check status of all services.

```bash
./scripts/health-check.sh
```

### fix-db-password.sh

Fix PostgreSQL authentication issues (common when Docker volumes persist old credentials).

```bash
./scripts/fix-db-password.sh
```

### seed-data.sh

Manually seed test data (runs migrations first).

```bash
./scripts/seed-data.sh
```

## Service Ports

| Service    | Port | Purpose                    |
|------------|------|----------------------------|
| PostgreSQL | 5435 | Hub database               |
| Redis      | 6382 | Cache/queue (Hub + Agent)  |
| Hub        | 8003 | Management portal (Django) |
| Agent      | 8004 | AI runtime (FastAPI)       |
| Test UI    | 8080 | Integration testing        |

## Test Credentials

| Credential      | Value                                    |
|-----------------|------------------------------------------|
| Test API Key    | `efh_test_key_for_integration_testing_only` |
| Hub Username    | `testuser`                               |
| Hub Password    | `testpass123`                            |
| Customer Email  | `test@echoforge.local`                   |

## Troubleshooting

### PostgreSQL "password authentication failed"

This happens when Docker volumes persist credentials from a previous run with different settings.

```bash
./scripts/fix-db-password.sh
# Choose option 1 (full reset) if you don't need the data
```

### Agent can't connect to Hub

Verify the service secret matches in both services:

```bash
grep HUB_SERVICE_SECRET .env
# Should be: test-service-secret-12345-min32chars
```

### Redis connection refused

```bash
docker exec echoforge_dev_redis redis-cli ping
# Should return: PONG
```

### Migrations not applied

```bash
./scripts/seed-data.sh
# This runs migrations before seeding
```

## Environment Variables

All environment variables are stored in `.env` and **automatically loaded** by the startup scripts using dynamic sourcing. No more hardcoded export lists!

### Adding New Variables

1. Add the variable to `dev-environment/.env`
2. Add it to `.env.example` with documentation
3. Restart services: `./scripts/restart.sh`

**That's it!** No script modifications needed. The scripts use `set -a; source .env; set +a` to automatically export all variables.

### Variable Categories

| Category | Examples | Description |
|----------|----------|-------------|
| Infrastructure | `POSTGRES_*`, `REDIS_*` | Database and cache settings |
| Service URLs | `HUB_BASE_URL`, `AGENT_PORT` | Service endpoints and ports |
| Security | `DJANGO_SECRET_KEY`, `ENCRYPTION_KEY`, `HUB_SERVICE_SECRET` | Secrets and auth |
| AI/LLM | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` | AI provider credentials |
| Integrations | `STRIPE_*`, `GOOGLE_*`, `GMAIL_*`, `AWS_*` | Third-party service credentials |
| Development | `DJANGO_DEBUG`, `LOG_LEVEL` | Development settings |

### Key Variables

```bash
# Database
POSTGRES_PASSWORD=echoforge_dev_2025
POSTGRES_PORT=5435

# Redis
REDIS_PORT=6382

# Inter-service auth (must be 32+ chars)
HUB_SERVICE_SECRET=test-service-secret-12345-min32chars

# Required for Agent
ANTHROPIC_API_KEY=sk-ant-your-key-here

# Google OAuth (for Calendar/Gmail)
GOOGLE_CALENDAR_CLIENT_ID=your-client-id
GOOGLE_CALENDAR_CLIENT_SECRET=your-secret
GMAIL_CLIENT_ID=your-client-id
GMAIL_CLIENT_SECRET=your-secret
```

See `.env.example` for the complete list of available variables with descriptions.

## Maintaining Documentation

**IMPORTANT:** When making changes to the dev-environment scripts or workflow:

1. Update this README with any new commands or changed behavior
2. Update **both** component CLAUDE.md files to keep them in sync:
   - `../hub/CLAUDE.md` - "Development Environment" section
   - `../agent/CLAUDE.md` - "Development Environment" section

This ensures Claude Code sessions working in either component know how to use the dev environment.

## Related Projects

- **Hub**: Management portal (`../hub/`)
- **Agent**: AI runtime (`../agent/`)
- **Specifications**: `../specs/`
