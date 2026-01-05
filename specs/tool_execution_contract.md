# Tool Execution Contract

This document defines the API contract between EchoForge Agent and Hub for tool execution.

## Overview

Tools are categorized by execution location:

| Category | Execution | Examples |
|----------|-----------|----------|
| **Local** | Agent only | mission_*, document_* |
| **Direct** | Agent → External API | research_web_search, research_fetch_page |
| **Hub-Proxied** | Agent → Hub → External API | calendar_*, email_* |

## Hub-Proxied Tool API

### Endpoint

```
POST /api/internal/tools/execute/
Authorization: ServiceSecret {secret}
Content-Type: application/json
```

### Request Schema

```json
{
  "tool": "string",           // Tool name (e.g., "calendar_create_event")
  "agent_id": "uuid",         // Agent instance ID
  "customer_id": "uuid",      // Customer ID (for credential lookup)
  "user_id": "string|null",   // End-user ID within customer's system
  "inputs": {                 // Tool-specific inputs
    // ... varies by tool
  },
  "context": {                // Optional context
    "conversation_id": "string",
    "request_id": "string"
  }
}
```

### Response Schema (Success)

```json
{
  "success": true,
  "tool": "calendar_create_event",
  "result": {
    // Tool-specific result data
  },
  "metadata": {
    "execution_time_ms": 234,
    "api_calls": 1
  }
}
```

### Response Schema (Error)

```json
{
  "success": false,
  "tool": "calendar_create_event",
  "error": {
    "code": "INTEGRATION_NOT_CONNECTED",
    "message": "Google Calendar is not connected for this customer",
    "details": {
      "integration": "google_calendar",
      "setup_url": "https://hub.echoforge.ai/integrations/google"
    }
  }
}
```

### Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `INTEGRATION_NOT_CONNECTED` | 400 | Customer hasn't connected this integration |
| `INTEGRATION_EXPIRED` | 401 | OAuth token expired and refresh failed |
| `INTEGRATION_PERMISSION_DENIED` | 403 | Integration lacks required scopes |
| `TOOL_NOT_FOUND` | 404 | Unknown tool name |
| `EXTERNAL_API_ERROR` | 502 | External service (Google, etc.) returned error |
| `RATE_LIMITED` | 429 | Customer hit rate limit |

---

## Tool Specifications

### Calendar Tools

#### calendar_get_availability

**Purpose:** Get free/busy times for scheduling.

**Inputs:**
```json
{
  "start_date": "2024-01-15",
  "end_date": "2024-01-20",
  "timezone": "America/New_York",
  "calendars": ["primary"]  // Optional, defaults to primary
}
```

**Result:**
```json
{
  "busy_periods": [
    {
      "start": "2024-01-15T09:00:00-05:00",
      "end": "2024-01-15T10:00:00-05:00",
      "calendar": "primary"
    }
  ],
  "working_hours": {
    "start": "09:00",
    "end": "17:00",
    "days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
  }
}
```

#### calendar_create_event

**Inputs:**
```json
{
  "title": "Meeting with John",
  "start": "2024-01-15T14:00:00-05:00",
  "end": "2024-01-15T15:00:00-05:00",
  "description": "Discuss Q1 planning",
  "location": "Zoom",
  "attendees": ["john@example.com"],
  "send_notifications": true
}
```

**Result:**
```json
{
  "event_id": "abc123",
  "html_link": "https://calendar.google.com/event?eid=abc123",
  "status": "confirmed",
  "attendees": [
    {"email": "john@example.com", "response_status": "needsAction"}
  ]
}
```

#### calendar_update_event

**Inputs:**
```json
{
  "event_id": "abc123",
  "updates": {
    "title": "Updated: Meeting with John",
    "start": "2024-01-15T15:00:00-05:00",
    "end": "2024-01-15T16:00:00-05:00"
  },
  "send_notifications": true
}
```

#### calendar_delete_event

**Inputs:**
```json
{
  "event_id": "abc123",
  "send_notifications": true
}
```

#### calendar_find_optimal_times

**Inputs:**
```json
{
  "duration_minutes": 60,
  "attendees": ["john@example.com", "jane@example.com"],
  "date_range": {
    "start": "2024-01-15",
    "end": "2024-01-20"
  },
  "preferences": {
    "preferred_hours": {"start": "10:00", "end": "16:00"},
    "avoid_mondays": true
  }
}
```

**Result:**
```json
{
  "suggestions": [
    {
      "start": "2024-01-16T10:00:00-05:00",
      "end": "2024-01-16T11:00:00-05:00",
      "score": 0.95,
      "conflicts": []
    },
    {
      "start": "2024-01-17T14:00:00-05:00",
      "end": "2024-01-17T15:00:00-05:00",
      "score": 0.85,
      "conflicts": [{"attendee": "jane@example.com", "type": "tentative"}]
    }
  ]
}
```

---

### Email Tools

#### email_send

**Inputs:**
```json
{
  "to": ["recipient@example.com"],
  "cc": [],
  "bcc": [],
  "subject": "Meeting Follow-up",
  "body": "Hi, thanks for meeting today...",
  "body_type": "text",  // or "html"
  "reply_to_message_id": null  // For threading
}
```

**Result:**
```json
{
  "message_id": "msg_abc123",
  "thread_id": "thread_xyz789",
  "status": "sent"
}
```

#### email_search

**Inputs:**
```json
{
  "query": "from:john@example.com subject:proposal",
  "max_results": 10,
  "include_body": false
}
```

**Result:**
```json
{
  "messages": [
    {
      "message_id": "msg_abc123",
      "thread_id": "thread_xyz789",
      "from": "john@example.com",
      "to": ["me@example.com"],
      "subject": "Q1 Proposal",
      "snippet": "Here's the proposal we discussed...",
      "date": "2024-01-10T09:30:00Z",
      "has_attachments": true
    }
  ],
  "total_results": 1
}
```

#### email_read

**Inputs:**
```json
{
  "message_id": "msg_abc123",
  "mark_as_read": true
}
```

**Result:**
```json
{
  "message_id": "msg_abc123",
  "thread_id": "thread_xyz789",
  "from": "john@example.com",
  "to": ["me@example.com"],
  "subject": "Q1 Proposal",
  "body": "Full email body here...",
  "date": "2024-01-10T09:30:00Z",
  "attachments": [
    {"filename": "proposal.pdf", "size": 102400, "mime_type": "application/pdf"}
  ]
}
```

#### email_check_replies

**Inputs:**
```json
{
  "thread_id": "thread_xyz789",
  "since": "2024-01-10T09:30:00Z"
}
```

**Result:**
```json
{
  "has_new_replies": true,
  "replies": [
    {
      "message_id": "msg_def456",
      "from": "john@example.com",
      "snippet": "Thanks, I've reviewed and...",
      "date": "2024-01-11T14:22:00Z"
    }
  ]
}
```

---

## Integration Status Endpoint

Agent can check if integrations are connected before attempting tool calls.

### Endpoint

```
GET /api/internal/integrations/status/{customer_id}/
Authorization: ServiceSecret {secret}
```

### Response

```json
{
  "customer_id": "uuid",
  "integrations": {
    "google_calendar": {
      "connected": true,
      "scopes": ["calendar.readonly", "calendar.events"],
      "email": "user@gmail.com",
      "expires_at": "2024-02-15T00:00:00Z"
    },
    "google_gmail": {
      "connected": false,
      "setup_url": "https://hub.echoforge.ai/integrations/google"
    }
  }
}
```

---

## Development Workflow

### Agent Team (can start immediately)

1. Implement local tools (mission_*, document_*) - no Hub dependency
2. Implement direct API tools (research_*) - no Hub dependency
3. Create mock Hub responses for calendar/email tools
4. Integrate with real Hub when ready

### Hub Team (can start immediately)

1. Create `/api/internal/tools/execute/` endpoint with stub responses
2. Build OAuth infrastructure for Google
3. Implement calendar tools
4. Implement email tools

### Integration Testing

Both teams can work independently using:
- Agent: Mock Hub responses matching this contract
- Hub: Test endpoint directly with curl/Postman

Once both are ready, integration testing verifies the contract.
