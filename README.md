# EchoForge Platform

AI agent platform enabling businesses to deploy customized AI agents with dynamic onboarding, knowledge base integration, and third-party service connections.

## Architecture

| Component | Technology | Purpose |
|-----------|------------|---------|
| [Hub](hub/) | Django 5.2 | Customer portal, agent provisioning, billing |
| [Agent](agent/) | FastAPI | Runtime engine, conversation handling, tool execution |

## Quick Start

```bash
# Clone with submodules
git clone --recursive git@github.com:jeffsinason/echoforge.git
cd echoforge

# Start development environment
./dev-environment/scripts/start-all.sh

# Check health
./dev-environment/scripts/health-check.sh
```

## Development

```bash
# Quick restart after code changes
./dev-environment/scripts/restart.sh

# Stop all services
./dev-environment/scripts/stop-all.sh
```

**Test UI:** http://localhost:8080

**tmux session:** `tmux attach -t echoforge`

## Ports

| Service | Port |
|---------|------|
| Hub (Django) | 8003 |
| Agent (FastAPI) | 8001 |
| PostgreSQL | 5435 |
| Redis | 6382 |

## Workflow

### Creating Issues
```bash
/new-issue
```

### Designing Features
```bash
/architect
```

### Managing Specs
```bash
/specs              # List all specs
/specs dashboard    # Kanban view
/specs work <file>  # Start implementing
```

## Structure

```
echoforge/
├── specs/              # Feature specifications
├── docs/               # Documentation
├── dev-environment/    # Unified dev scripts
├── hub/                # Django portal (submodule)
└── agent/              # FastAPI runtime (submodule)
```

## Related

- **Organization:** [EchoForgeX](https://github.com/jeffsinason/EchoForgeX)
- **Hub:** [echoforge-hub](https://github.com/jeffsinason/echoforge-hub)
- **Agent:** [echoforge-agent](https://github.com/jeffsinason/echoforge-agent)
