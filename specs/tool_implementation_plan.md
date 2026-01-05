# Tool Implementation Plan

Parallel development plan for Agent and Hub tool execution.

> **Documentation Sync:** When updating dev-environment scripts, also update the "Development Environment" section in both `echoforge-hub/CLAUDE.md` and `echoforge-agent/CLAUDE.md`.

## Work Breakdown

### AGENT WORK (echoforge-agent)

Can proceed **immediately** - no Hub dependencies for Phase 1-2.

#### Phase 1: Local Tools (No External APIs)

These tools work entirely within the Agent using Redis for state.

| Tool | Status | Description |
|------|--------|-------------|
| `mission_create_task` | Implement | Create task in Redis |
| `mission_ask_user` | Implement | Return question to conversation |
| `mission_complete` | Implement | Mark mission complete |
| `document_create` | Implement | Store document in Redis |
| `document_edit` | Implement | Update document in Redis |
| `document_get` | Implement | Retrieve document from Redis |

**Files to modify:**
- `src/services/tools/mission_tools.py`
- `src/services/tools/document_tools.py`
- Add Redis state management

**Dependencies:** Redis (already available)

#### Phase 2: Direct API Tools

These tools call external APIs directly from Agent.

| Tool | Status | API Provider |
|------|--------|--------------|
| `research_web_search` | Implement | Tavily API |
| `research_fetch_page` | Implement | Direct HTTP + readability |
| `research_summarize` | Implement | Claude API (already have) |

**Files to modify:**
- `src/services/tools/research_tools.py`
- `src/core/config.py` (add TAVILY_API_KEY)

**Dependencies:** Tavily API key (~$5/month or free tier)

#### Phase 3: Hub Integration

Connect calendar/email tools to Hub (after Hub implements endpoint).

| Tool | Status | Notes |
|------|--------|-------|
| `calendar_*` | Update | Change to use Hub contract |
| `email_*` | Update | Change to use Hub contract |

**Files to modify:**
- `src/services/tools/calendar_tools.py`
- `src/services/tools/email_tools.py`

**Dependencies:** Hub `/api/internal/tools/execute/` endpoint

#### Phase 4: Mock Mode for Development

Add mock responses so Agent can be tested without Hub.

**Files to create:**
- `src/services/tools/mocks.py`

---

### HUB WORK (echoforge-hub)

Can proceed **immediately** - start with stubs.

#### Phase 1: Tool Execution API Scaffold

Create the endpoint with stub responses.

| Task | Description |
|------|-------------|
| Create endpoint | `POST /api/internal/tools/execute/` |
| Add authentication | ServiceSecret validation |
| Add request validation | Validate against contract schema |
| Return stub responses | Match contract format |

**Files to create:**
- `api/internal/views/tools.py`
- `api/internal/serializers/tools.py`
- Update `api/internal/urls.py`

**Dependencies:** None

#### Phase 2: Integration Infrastructure

Build the OAuth and credential storage system.

| Task | Description |
|------|-------------|
| Integration model | Store connected integrations per customer |
| Credential encryption | Encrypt OAuth tokens at rest |
| OAuth flow | Google OAuth consent flow |
| Token refresh | Background refresh of expiring tokens |

**Files to create/modify:**
- `integrations/models.py`
- `integrations/services/oauth.py`
- `integrations/services/google.py`
- `integrations/views.py` (OAuth callback)

**Dependencies:** Google Cloud Console project with OAuth credentials

#### Phase 3: Calendar Tool Implementation

Implement Google Calendar integration.

| Tool | Google API |
|------|------------|
| `calendar_get_availability` | `freebusy.query` |
| `calendar_create_event` | `events.insert` |
| `calendar_update_event` | `events.patch` |
| `calendar_delete_event` | `events.delete` |
| `calendar_find_optimal_times` | `freebusy.query` + logic |

**Files to create:**
- `integrations/services/calendar.py`
- `integrations/tools/calendar.py`

**Dependencies:** Phase 2 complete

#### Phase 4: Email Tool Implementation

Implement Gmail integration.

| Tool | Google API |
|------|------------|
| `email_send` | `messages.send` |
| `email_search` | `messages.list` |
| `email_read` | `messages.get` |
| `email_check_replies` | `threads.get` |

**Files to create:**
- `integrations/services/gmail.py`
- `integrations/tools/email.py`

**Dependencies:** Phase 2 complete

---

## Parallel Development Timeline

```
Week 1:
  Agent: Phase 1 (Local tools) + Phase 2 (Research tools)
  Hub:   Phase 1 (API scaffold with stubs)

Week 2:
  Agent: Phase 4 (Mock mode) + Testing
  Hub:   Phase 2 (OAuth infrastructure)

Week 3:
  Agent: Phase 3 (Hub integration) - once Hub Phase 1 done
  Hub:   Phase 3 (Calendar tools)

Week 4:
  Agent: Integration testing
  Hub:   Phase 4 (Email tools)

Week 5:
  Both:  End-to-end testing and refinement
```

---

## Testing Strategy

### Agent Testing (Independent)

```bash
# Test local tools
pytest tests/tools/test_mission_tools.py
pytest tests/tools/test_document_tools.py

# Test research tools (needs Tavily key)
TAVILY_API_KEY=xxx pytest tests/tools/test_research_tools.py

# Test with mock Hub
MOCK_HUB=true pytest tests/tools/test_calendar_tools.py
```

### Hub Testing (Independent)

```bash
# Test tool endpoint with stubs
pytest tests/api/test_tool_execution.py

# Test OAuth flow
pytest tests/integrations/test_oauth.py

# Test calendar integration (needs Google creds)
pytest tests/integrations/test_calendar.py
```

### Integration Testing (Together)

```bash
# Full stack test
cd dev-environment
./scripts/start-all.sh
pytest ../tests/integration/test_tools_e2e.py
```

---

## Environment Variables

### Agent (.env)

```bash
# Phase 2: Research tools
TAVILY_API_KEY=tvly-xxxxx

# Phase 3: Hub integration (already exists)
HUB_BASE_URL=http://localhost:8003
HUB_SERVICE_SECRET=xxx
```

### Hub (.env)

```bash
# Phase 2: Google OAuth
GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxxxx
GOOGLE_REDIRECT_URI=http://localhost:8003/integrations/google/callback

# Encryption for stored credentials
CREDENTIAL_ENCRYPTION_KEY=xxxxx
```

---

## Quick Start Commands

### Start Agent Work

```bash
cd echoforge-agent

# Phase 1: Local tools - edit these files:
# - src/services/tools/mission_tools.py
# - src/services/tools/document_tools.py

# Phase 2: Research tools - edit:
# - src/services/tools/research_tools.py
# - Add TAVILY_API_KEY to .env
```

### Start Hub Work

```bash
cd echoforge-hub/backend

# Phase 1: Create tool endpoint
# - api/internal/views/tools.py
# - api/internal/urls.py

# Test with:
curl -X POST http://localhost:8003/api/internal/tools/execute/ \
  -H "Authorization: ServiceSecret xxx" \
  -H "Content-Type: application/json" \
  -d '{"tool": "calendar_create_event", "inputs": {...}}'
```
