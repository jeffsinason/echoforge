# EchoForge Platform

## Project Vision

EchoForge is an AI agent platform enabling businesses to deploy customized AI agents with dynamic onboarding, knowledge base integration, and third-party service connections.

## Architecture Overview

The platform consists of two components:

| Component | Technology | Purpose |
|-----------|------------|---------|
| Hub | Django 5.2 | Customer portal, agent provisioning, billing |
| Agent | FastAPI | Runtime engine, conversation handling, tool execution |

### Component Interaction

```
Customer Browser → Hub (Django) → Database
                      ↓
                   Agent Runtime (FastAPI) → External APIs
                      ↓
                 Knowledge Base / LLM
```

## Key Design Decisions

- **Multi-tenant architecture**: All data scoped by customer
- **Dynamic onboarding**: Agent types define onboarding via JSON schema
- **Encrypted credentials**: OAuth tokens encrypted at rest
- **Internal API**: Hub exposes API for Agent runtime to fetch config/knowledge

## Specifications

All specs live in `specs/`. Use `/specs` to manage them.

## Issues

Issues are tracked in this repository (jeffsinason/echoforge).
Use `/new-issue` to create issues.

## Development Environment

The unified dev environment is in `dev-environment/`:

```bash
# Start all services
./dev-environment/scripts/start-all.sh

# Quick restart after code changes
./dev-environment/scripts/restart.sh

# Stop all services
./dev-environment/scripts/stop-all.sh

# Health check
./dev-environment/scripts/health-check.sh
```

**Test UI:** http://localhost:8080 (after starting environment)

**tmux session:** `tmux attach -t echoforge` to see logs

## Component Work

For implementation details, see component CLAUDE.md files:
- `hub/CLAUDE.md` - Django patterns, models, views
- `agent/CLAUDE.md` - FastAPI patterns, agent runtime

## Ports

| Service | Port |
|---------|------|
| Hub (Django) | 8003 |
| Agent (FastAPI) | 8001 |
| PostgreSQL | 5435 |
| Redis | 6382 |

## Related

- **Organization:** `../` (EchoForgeX) - Cross-project governance
- **Specs:** `specs/` - All platform specifications
