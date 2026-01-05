---
title: Internal API Contract (Hub ↔ Agent)
version: "1.0"
status: testing
project: EchoForge Hub
created: 2025-12-30
updated: 2025-12-31
---

# 1. Executive Summary

This specification defines the internal API contract between EchoForge Hub (Django) and EchoForge Agent (FastAPI runtime). It covers authentication, configuration fetching, usage reporting, and failure handling. The API enables a stateless Agent runtime that fetches all configuration from Hub and reports usage back asynchronously.

---

# 2. Architecture Overview

```
┌──────────────┐                    ┌──────────────────┐                    ┌──────────────┐
│   End User   │                    │  EchoForge Agent │                    │ EchoForge Hub│
│  (Browser/   │───── API Key ─────►│    (FastAPI)     │───── Internal ────►│   (Django)   │
│   Widget)    │                    │                  │      API           │              │
└──────────────┘                    └──────────────────┘                    └──────────────┘
                                            │                                       │
                                            │                                       │
                                            ▼                                       ▼
                                    ┌──────────────┐                    ┌──────────────────┐
                                    │   LLM API    │                    │   PostgreSQL     │
                                    │  (Claude)    │                    │   (pgvector)     │
                                    └──────────────┘                    └──────────────────┘
```

## 2.1 Deployment Model

- **Single shared Agent service** handling all customers
- **Customer isolation** via configuration (agent instance ID)
- **Horizontal scaling** supported (Agent is stateless)

---

# 3. Authentication

## 3.1 End User → Agent (Public API)

**Method:** API Key (per Agent Instance)

```
POST /v1/chat
Authorization: Bearer {agent_api_key}
Content-Type: application/json
```

**Validation:**
1. Agent validates API key locally (cached, 5-min TTL)
2. Agent enforces `embed_domains` if request includes `Origin` header
3. Invalid key → 401 Unauthorized
4. Invalid domain → 403 Forbidden

**API Key Format:**
- Prefix: `efk_` (EchoForge Key)
- Example: `efk_abc123def456...`
- Stored: Hashed in Hub DB, prefix stored plaintext for identification

## 3.2 Agent → Hub (Internal API)

**Method:** Hybrid (Service Secret + Agent Instance ID)

```
GET /api/internal/agent/{agent_id}/config
Authorization: Bearer {HUB_SERVICE_SECRET}
X-Agent-Instance-ID: {agent_uuid}
```

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `Authorization` | Yes | `Bearer {HUB_SERVICE_SECRET}` |
| `X-Agent-Instance-ID` | Yes | UUID of agent instance making request |
| `X-Request-ID` | No | Request tracing ID |

**Validation (Hub):**
1. Verify service secret matches `HUB_SERVICE_SECRET` env var
2. Verify agent instance exists and `is_active=True`
3. Verify customer subscription is valid (not canceled, not expired)
4. Verify customer has available usage or balance
5. Return scoped configuration for that agent

**Error Responses:**

| Status | Reason |
|--------|--------|
| 401 | Invalid or missing service secret |
| 404 | Agent instance not found |
| 403 | Agent inactive or customer subscription invalid |
| 429 | Rate limit exceeded |
| 503 | Hub temporarily unavailable |

---

# 4. Configuration API

## 4.1 Get Agent Configuration

**Endpoint:** `GET /api/internal/agent/{agent_id}/config`

**Response:**
```json
{
  "agent_id": "uuid",
  "agent_type": "support_agent",
  "customer_id": "uuid",

  "identity": {
    "name": "Acme Support Bot",
    "avatar_url": "https://...",
    "greeting": "Hi! How can I help you today?"
  },

  "system_prompt": "You are a support assistant for Acme Corp...",

  "knowledge_base": {
    "id": "uuid",
    "enabled": true
  },

  "integrations": {
    "ticketing": {
      "provider": "zendesk",
      "config": {
        "default_priority": "normal"
      }
    }
  },

  "actions_enabled": [
    "create_ticket",
    "search_knowledge_base",
    "escalate_to_human"
  ],

  "rate_limits": {
    "messages_per_minute": 20,
    "tokens_per_minute": 10000
  },

  "embed_domains": [
    "acme.com",
    "support.acme.com"
  ],

  "billing": {
    "can_respond": true,
    "usage_remaining": {
      "messages": 450,
      "tokens": 50000
    },
    "in_grace_period": false
  },

  "config_version": "2025-01-15T10:30:00Z"
}
```

**Caching:**
- Agent caches configuration with 5-minute TTL
- `config_version` timestamp enables cache invalidation comparison
- If cached version matches, Agent can skip full config fetch (304 Not Modified)

## 4.2 Validate API Key

**Endpoint:** `GET /api/internal/agent/validate-key`

**Request:**
```
GET /api/internal/agent/validate-key
Authorization: Bearer {HUB_SERVICE_SECRET}
X-API-Key: {agent_api_key}
```

**Response:**
```json
{
  "valid": true,
  "agent_instance_id": "uuid",
  "customer_id": "uuid",
  "embed_domains": ["acme.com"],
  "is_active": true
}
```

**Agent Behavior:**
- Cache valid keys for 5 minutes
- On cache miss, validate with Hub
- On 401/403, reject request immediately

## 4.3 Check Can Respond

**Endpoint:** `GET /api/internal/billing/can-respond/{agent_id}`

Quick check before processing a message (optional, can use cached billing info).

**Response:**
```json
{
  "allowed": true,
  "reason": "OK",
  "in_grace_period": false,
  "grace_period_ends_at": null
}
```

Or if blocked:
```json
{
  "allowed": false,
  "reason": "Usage limit exceeded and no balance available",
  "in_grace_period": false,
  "customer_message": "We've reached our usage limit. Please contact support."
}
```

---

# 5. Knowledge Base API

## 5.1 Search Knowledge Base

**Endpoint:** `POST /api/internal/knowledge/{kb_id}/search`

**Request:**
```json
{
  "query": "how do I reset my password",
  "top_k": 5,
  "min_score": 0.7
}
```

**Response:**
```json
{
  "results": [
    {
      "chunk_id": "uuid",
      "content": "To reset your password, click the 'Forgot Password' link...",
      "score": 0.92,
      "metadata": {
        "document_id": "uuid",
        "document_title": "User Guide",
        "source_url": "https://docs.acme.com/password-reset",
        "chunk_index": 5
      }
    }
  ],
  "query_embedding_tokens": 12
}
```

---

# 6. Integration Credentials API

## 6.1 Get Integration Credentials

**Endpoint:** `GET /api/internal/integration/{integration_id}/credentials`

Returns decrypted credentials for Agent to use with external services.

**Response:**
```json
{
  "provider": "zendesk",
  "access_token": "eyJ...",
  "account_id": "acme",
  "base_url": "https://acme.zendesk.com",
  "expires_at": "2025-01-15T12:00:00Z",
  "scopes": ["tickets:write", "users:read"]
}
```

**Security:**
- Credentials decrypted only when requested
- Short-lived tokens refreshed by Hub automatically
- Agent should not cache credentials beyond immediate use

---

# 7. Usage Reporting API

## 7.1 Report Usage (Batch)

**Endpoint:** `POST /api/internal/usage/batch`

Agent batches usage locally and reports every 30-60 seconds.

**Request:**
```json
{
  "reports": [
    {
      "agent_instance_id": "uuid",
      "timestamp": "2025-01-15T10:30:00Z",
      "metrics": {
        "messages": 1,
        "input_tokens": 150,
        "output_tokens": 320,
        "knowledge_queries": 1
      },
      "conversation_id": "uuid",
      "request_id": "uuid"
    },
    {
      "agent_instance_id": "uuid",
      "timestamp": "2025-01-15T10:30:05Z",
      "metrics": {
        "messages": 1,
        "input_tokens": 200,
        "output_tokens": 450,
        "knowledge_queries": 0
      },
      "conversation_id": "uuid",
      "request_id": "uuid"
    }
  ]
}
```

**Response:**
```json
{
  "accepted": 2,
  "rejected": 0,
  "errors": []
}
```

**Agent Behavior:**
- Queue usage reports locally
- Batch send every 30-60 seconds
- On failure, retry with exponential backoff
- Local queue limit: 1000 reports (prevent memory issues)
- If queue full, drop oldest reports (log warning)

## 7.2 Report Structure

| Field | Type | Description |
|-------|------|-------------|
| `agent_instance_id` | UUID | Which agent |
| `timestamp` | ISO8601 | When the usage occurred |
| `messages` | int | Number of conversation turns |
| `input_tokens` | int | Tokens in user message |
| `output_tokens` | int | Tokens in agent response |
| `knowledge_queries` | int | KB searches performed |
| `conversation_id` | UUID | For grouping (optional) |
| `request_id` | UUID | For deduplication |

---

# 8. Error Handling

## 8.1 Hub Unavailable

**Agent Behavior:**

| Scenario | Action |
|----------|--------|
| Config fetch fails, cache valid | Use cached config, log warning |
| Config fetch fails, cache expired | Return 503 to user with friendly message |
| Usage report fails | Queue locally, retry later |
| KB search fails | Respond without KB context, log warning |
| Credentials fetch fails | Skip integration action, log error |

**Retry Policy:**
- Exponential backoff: 1s, 2s, 4s, 8s, max 60s
- Max retries for sync operations: 3
- Async operations (usage): retry indefinitely with backoff

## 8.2 Grace Period Handling

When Hub returns `in_grace_period: true`:

```json
{
  "allowed": true,
  "reason": "In grace period",
  "in_grace_period": true,
  "grace_period_ends_at": "2025-01-16T10:30:00Z",
  "customer_message": "Your usage limit has been reached. Service will pause in 23 hours unless you add funds."
}
```

**Agent Behavior:**
- Continue responding normally
- Include warning in response metadata (for widget to display)
- Log grace period status

---

# 9. Rate Limiting

## 9.1 Internal API Limits

| Endpoint | Limit | Scope |
|----------|-------|-------|
| Config fetch | 100/min | Per agent instance |
| KB search | 60/min | Per agent instance |
| Credentials fetch | 30/min | Per integration |
| Usage report | 10/min | Per Agent service |

## 9.2 Rate Limit Response

```
HTTP 429 Too Many Requests
Retry-After: 30

{
  "error": "rate_limit_exceeded",
  "retry_after_seconds": 30
}
```

---

# 10. Security Considerations

## 10.1 Service Secret Management

- Stored in environment variable: `HUB_SERVICE_SECRET`
- Minimum 32 characters, cryptographically random
- Rotatable without downtime (support multiple valid secrets during rotation)
- Never logged, never in error messages

## 10.2 Domain Allowlist Enforcement

```python
def validate_origin(request, embed_domains):
    """Validate request origin against allowed domains."""
    origin = request.headers.get('Origin') or request.headers.get('Referer')

    if not embed_domains:
        return True  # No restrictions configured

    if not origin:
        # No origin = likely server-to-server, allow if API key valid
        return True

    origin_domain = extract_domain(origin)  # e.g., "acme.com"

    for allowed in embed_domains:
        if origin_domain == allowed or origin_domain.endswith('.' + allowed):
            return True

    return False
```

## 10.3 Request Tracing

All requests should include:
- `X-Request-ID`: Unique request identifier (UUID)
- Logged on both Agent and Hub for debugging
- Returned in responses for client correlation

---

# 11. Implementation Checklist

## 11.1 Hub Endpoints to Implement

- [ ] `GET /api/internal/agent/{agent_id}/config`
- [ ] `GET /api/internal/agent/validate-key`
- [ ] `GET /api/internal/billing/can-respond/{agent_id}`
- [ ] `POST /api/internal/knowledge/{kb_id}/search`
- [ ] `GET /api/internal/integration/{integration_id}/credentials`
- [ ] `POST /api/internal/usage/batch`

## 11.2 Agent Components to Implement

- [ ] Hub API client with retry logic
- [ ] Configuration cache (5-min TTL)
- [ ] API key validation cache
- [ ] Usage report queue and batch sender
- [ ] Origin/domain validation
- [ ] Error handling and graceful degradation

---

# 12. Acceptance Criteria

- [ ] Agent can fetch config from Hub with service secret
- [ ] Agent caches config for 5 minutes
- [ ] Agent validates API keys locally with cache
- [ ] Agent enforces embed_domains allowlist
- [ ] Agent reports usage in batches
- [ ] Agent handles Hub unavailability gracefully
- [ ] Agent respects grace period warnings
- [ ] Rate limiting works correctly
- [ ] Request tracing enables debugging

---

*End of Specification*
