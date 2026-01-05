---
title: Dev Environment Dynamic .env Loading
version: "1.0"
status: testing
project: dev-environment
created: 2026-01-03
updated: 2026-01-03
github_issue: 17
---

# 1. Executive Summary

Fix the dev environment scripts to dynamically load ALL environment variables from `.env` files instead of using hardcoded export lists. This eliminates the need to manually update scripts when adding new environment variables, and resolves integration failures caused by missing variables (e.g., Gmail OAuth credentials).

# 2. Current System State

## 2.1 Existing Data Structures

| File | Purpose | Location |
|------|---------|----------|
| `.env` | Central environment config | `dev-environment/.env` |
| `.env` | Hub-specific config | `echoforge-hub/backend/.env` |
| `.env.example` | Agent template | `echoforge-agent/.env.example` |
| `start-all.sh` | Full environment startup | `dev-environment/scripts/` |
| `restart.sh` | Quick service restart | `dev-environment/scripts/` |

## 2.2 Existing Workflows

### Current Startup Flow

1. Script runs `set -a; source .env; set +a` (loads vars into script's shell)
2. Script creates tmux windows with **hardcoded export lists**
3. Each tmux window only receives the hardcoded subset of variables
4. Services start but may be missing newly added variables

### Current Variable Count

The `dev-environment/.env` contains ~37 variables, but only ~18 are passed via hardcoded exports.

## 2.3 Current Gaps

1. **Hardcoded export lists** in tmux commands don't include all variables
2. **New variables require manual updates** to multiple files
3. **No documentation** on which variables are required vs optional
4. **Inconsistent .env locations** - some services have their own, some don't
5. **Gmail OAuth failure** - `GMAIL_CLIENT_ID` was in .env but not exported

### Evidence: Hardcoded Exports in restart.sh (lines 101-122)

```bash
tmux new-session -d -s "$SESSION_NAME" -n "hub" \
    "cd '$ECHOFORGE_ROOT/echoforge-hub/backend' && \
     source .venv/bin/activate && \
     export POSTGRES_PASSWORD='$POSTGRES_PASSWORD' \
            POSTGRES_HOST='$POSTGRES_HOST' \
            POSTGRES_PORT='$POSTGRES_PORT' \
            POSTGRES_DB='$POSTGRES_DB' \
            POSTGRES_USER='$POSTGRES_USER' \
            REDIS_URL='$REDIS_URL' \
            HUB_SERVICE_SECRET='$HUB_SERVICE_SECRET' \
            GOOGLE_CALENDAR_CLIENT_ID='$GOOGLE_CALENDAR_CLIENT_ID' \
            GOOGLE_CALENDAR_CLIENT_SECRET='$GOOGLE_CALENDAR_CLIENT_SECRET' \
            ENCRYPTION_KEY='$ENCRYPTION_KEY' && \
     python manage.py runserver ${HUB_PORT:-8003}; ..."
```

**Missing:** `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `ANTHROPIC_API_KEY`, `STRIPE_*`, etc.

# 3. Feature Requirements

## 3.1 Dynamic .env Loading in Scripts

**Description:** Replace hardcoded export lists with dynamic sourcing that loads ALL variables from the .env file.

### Code Changes

**Before (hardcoded):**
```bash
tmux new-session -d -s "$SESSION_NAME" -n "hub" \
    "cd '$HUB_DIR' && \
     source .venv/bin/activate && \
     export POSTGRES_PASSWORD='$POSTGRES_PASSWORD' \
            POSTGRES_HOST='$POSTGRES_HOST' \
            ... more hardcoded vars ... && \
     python manage.py runserver 8003"
```

**After (dynamic):**
```bash
tmux new-session -d -s "$SESSION_NAME" -n "hub" \
    "cd '$HUB_DIR' && \
     source .venv/bin/activate && \
     set -a && source '$DEV_ENV_DIR/.env' && set +a && \
     python manage.py runserver \${HUB_PORT:-8003}"
```

### Business Rules

- `set -a` enables auto-export of all variables sourced
- `set +a` disables auto-export after sourcing (good hygiene)
- Variables in .env are immediately available to the service
- No manual maintenance of export lists required

### Files to Modify

| File | Changes |
|------|---------|
| `dev-environment/scripts/restart.sh` | Replace hardcoded exports with dynamic sourcing |
| `dev-environment/scripts/start-all.sh` | Replace hardcoded exports with dynamic sourcing |

## 3.2 Standardized .env.example Files

**Description:** Create/update .env.example files with all available variables, organized by category with documentation.

### Template Structure

```bash
# =============================================================================
# EchoForge Development Environment Configuration
# =============================================================================
# Copy this file to .env and fill in your values
# All variables are loaded automatically by the dev environment scripts
# =============================================================================

# -----------------------------------------------------------------------------
# Infrastructure
# -----------------------------------------------------------------------------
POSTGRES_HOST=localhost
POSTGRES_PORT=5435
POSTGRES_DB=echoforge_hub
POSTGRES_USER=echoforge
POSTGRES_PASSWORD=your_password_here

REDIS_HOST=localhost
REDIS_PORT=6382
REDIS_URL=redis://localhost:6382

# -----------------------------------------------------------------------------
# Service URLs & Ports
# -----------------------------------------------------------------------------
HUB_BASE_URL=http://localhost:8003
HUB_PORT=8003
AGENT_BASE_URL=http://localhost:8004
AGENT_PORT=8004

# -----------------------------------------------------------------------------
# Security & Secrets
# -----------------------------------------------------------------------------
DJANGO_SECRET_KEY=generate-a-secure-key-here
HUB_SERVICE_SECRET=shared-secret-between-hub-and-agent
ENCRYPTION_KEY=32-byte-encryption-key-here

# -----------------------------------------------------------------------------
# AI/LLM APIs
# -----------------------------------------------------------------------------
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# -----------------------------------------------------------------------------
# Stripe (Billing)
# -----------------------------------------------------------------------------
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# -----------------------------------------------------------------------------
# Google APIs
# -----------------------------------------------------------------------------
GOOGLE_CALENDAR_CLIENT_ID=...
GOOGLE_CALENDAR_CLIENT_SECRET=...
GMAIL_CLIENT_ID=...
GMAIL_CLIENT_SECRET=...

# -----------------------------------------------------------------------------
# AWS (Knowledge Base Storage)
# -----------------------------------------------------------------------------
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_S3_BUCKET=echoforge-knowledge
AWS_S3_REGION=us-east-1

# -----------------------------------------------------------------------------
# Development/Testing
# -----------------------------------------------------------------------------
DJANGO_ENV=development
DJANGO_DEBUG=True
LOG_LEVEL=INFO
TEST_UI_PORT=8080
```

### Files to Create/Update

| File | Action |
|------|--------|
| `dev-environment/.env.example` | Update with all variables |
| `echoforge-hub/backend/.env.example` | Update to match |
| `echoforge-agent/.env.example` | Update to match |

## 3.3 Documentation Update

**Description:** Add clear documentation on how to add new environment variables.

### Add to dev-environment/README.md

```markdown
## Environment Variables

All environment variables are stored in `.env` and automatically loaded by the startup scripts.

### Adding New Variables

1. Add the variable to `dev-environment/.env`
2. Add it to `.env.example` with documentation
3. Restart services: `./scripts/restart.sh`

That's it! No script modifications needed.

### Variable Categories

| Category | Examples |
|----------|----------|
| Infrastructure | `POSTGRES_*`, `REDIS_*` |
| Service URLs | `HUB_BASE_URL`, `AGENT_PORT` |
| Security | `DJANGO_SECRET_KEY`, `ENCRYPTION_KEY` |
| AI/LLM | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` |
| Integrations | `STRIPE_*`, `GOOGLE_*`, `GMAIL_*`, `AWS_*` |
| Development | `DJANGO_DEBUG`, `LOG_LEVEL` |
```

# 4. Future Considerations (Out of Scope)

Features noted for potential future development but not included in this spec:

- **Per-service .env files**: Let each service have its own .env with only needed vars
- **Secret management**: Use HashiCorp Vault or AWS Secrets Manager
- **Environment validation**: Script to verify all required vars are set before startup
- **Production parity**: Ensure dev .env structure matches production env var naming

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Fix Scripts (Primary Fix)**

1. Update `restart.sh` to use dynamic sourcing
2. Update `start-all.sh` to use dynamic sourcing
3. Test that all services receive all variables

**Phase 2: Documentation**

1. Update `dev-environment/.env.example` with all variables
2. Update `echoforge-hub/backend/.env.example`
3. Update `echoforge-agent/.env.example`
4. Add documentation to `dev-environment/README.md`

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| tmux | Already required by dev environment |
| bash | `set -a` is POSIX-compatible |

## 5.3 Testing Plan

1. Add a test variable to `.env`: `TEST_NEW_VAR=hello`
2. Run `restart.sh`
3. Verify in Django shell: `import os; print(os.environ.get('TEST_NEW_VAR'))`
4. Verify in Agent: Check logs or add debug endpoint
5. Remove test variable

# 6. Acceptance Criteria

## 6.1 Script Changes

- [ ] `restart.sh` uses `set -a; source .env; set +a` instead of hardcoded exports
- [ ] `start-all.sh` uses `set -a; source .env; set +a` instead of hardcoded exports
- [ ] No hardcoded export lists remain in either script
- [ ] Both Hub and Agent receive all variables from .env

## 6.2 .env.example Files

- [ ] `dev-environment/.env.example` contains all ~37 variables
- [ ] Variables are organized by category with comments
- [ ] Each variable has a description or example value
- [ ] `echoforge-hub/backend/.env.example` is consistent
- [ ] `echoforge-agent/.env.example` is consistent

## 6.3 Documentation

- [ ] `dev-environment/README.md` explains how to add new variables
- [ ] Documentation confirms no script changes needed for new vars

## 6.4 Verification

- [ ] Adding a new variable to `.env` works without script changes
- [ ] `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` are now passed to Hub
- [ ] All existing functionality continues to work

---

*End of Specification*
