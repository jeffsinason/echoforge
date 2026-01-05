---
title: Personal/Executive Assistant Agent
version: "1.0"
status: in_development
project: EchoForge Agent
created: 2025-12-31
updated: 2025-12-31
---

# 1. Executive Summary

This specification defines a Personal/Executive Assistant agent type that runs on the EchoForge Agent runtime. It handles complex, long-running tasks through an orchestrator pattern with specialized tool categories for calendar, email, research, and document operations.

**Key Capabilities:**
- Natural language task intake with intelligent clarification
- Complex task decomposition into executable steps (missions → tasks)
- Parallel execution of independent sub-tasks
- Asynchronous handling of external responses (email replies, approvals)
- Human-in-the-loop for approvals and decision points
- Integration with Google Calendar and Gmail (Phase 1), Apple (Phase 2)

**Target Use Cases:**
1. **Meeting Scheduling** - Coordinate availability across multiple attendees, propose times, handle negotiation via email
2. **Event Planning** - Research venues, coordinate vendors, create agendas
3. **Research & Reporting** - Gather information, synthesize findings, produce deliverables
4. **Administrative Coordination** - Multi-step workflows with email threads and approvals

---

# 2. Architecture Overview

## 2.1 Position in EchoForge Platform

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EchoForge Hub (Django)                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Missions   │  │ External     │  │ Background   │  │ User Accounts    │  │
│  │  & Tasks    │  │ Integrations │  │ Task Queue   │  │ (Calendar/Email) │  │
│  │  (State)    │  │ (OAuth)      │  │ (Django-Q2)  │  │                  │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ Internal API
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      EchoForge Agent (FastAPI)                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Orchestrator│  │ Calendar     │  │ Email        │  │ Research         │  │
│  │ (LLM +      │  │ Tools        │  │ Tools        │  │ Tools            │  │
│  │  Planning)  │  │              │  │              │  │                  │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
   ┌──────────┐        ┌───────────────┐    ┌───────────────┐
   │  Claude  │        │ Google APIs   │    │ Web Search    │
   │   API    │        │ Calendar/Gmail│    │ (Native)      │
   └──────────┘        └───────────────┘    └───────────────┘
```

## 2.2 Key Design Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| State Storage | Hub PostgreSQL | Missions/tasks need persistence beyond Agent's stateless design |
| Task Queue | Django-Q2 in Hub | Background processing for email polling, follow-ups |
| Calendar (MVP) | Google Calendar | Better APIs, OAuth, faster to build |
| Email (MVP) | Gmail API | Same OAuth as calendar, threading, push capability |
| Orchestration | LLM with tools | Claude manages planning, dispatches tool calls |
| Phase 2 | Apple Calendar/Email | CalDAV + IMAP for broader compatibility |

## 2.3 Agent Type Configuration

When a customer creates a Personal Assistant agent in Hub, this configuration is generated:

```json
{
  "agent_type": "personal_assistant",
  "system_prompt": "[Orchestrator prompt - see Section 8]",
  "tools_enabled": [
    "mission_create_task",
    "mission_ask_user",
    "mission_complete",
    "calendar_get_availability",
    "calendar_find_optimal_times",
    "calendar_create_event",
    "calendar_update_event",
    "calendar_delete_event",
    "email_send",
    "email_check_replies",
    "email_parse_reply",
    "email_search",
    "email_read",
    "email_send_followup",
    "research_web_search",
    "research_fetch_page",
    "research_summarize",
    "document_create",
    "document_edit",
    "document_get"
  ],
  "integrations_required": [
    "google_calendar",
    "gmail"
  ],
  "features": {
    "missions_enabled": true,
    "async_tasks_enabled": true,
    "human_approval_enabled": true
  }
}
```

---

# 3. Hub Extensions Required

## 3.1 New Data Models

### Mission Model

```python
class Mission(models.Model):
    """Top-level user request container"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    agent_instance = models.ForeignKey('AgentInstance', on_delete=models.CASCADE)
    user = models.ForeignKey(User, on_delete=models.CASCADE)  # End user

    raw_input = models.TextField()  # Original user request
    parsed_intent = models.JSONField(null=True)  # Structured understanding

    status = models.CharField(max_length=32, choices=[
        ('planning', 'Planning'),
        ('executing', 'Executing'),
        ('blocked', 'Blocked - Awaiting Input'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
        ('cancelled', 'Cancelled'),
    ])

    context = models.JSONField(default=dict)  # Shared mission knowledge
    conversation_id = models.CharField(max_length=64)  # Link to Agent conversation

    created_at = models.DateTimeField(auto_now_add=True)
    deadline = models.DateTimeField(null=True)
    completed_at = models.DateTimeField(null=True)

    class Meta:
        indexes = [
            models.Index(fields=['agent_instance', 'status']),
            models.Index(fields=['user', 'created_at']),
        ]
```

### Task Model

```python
class MissionTask(models.Model):
    """Single unit of work in mission DAG"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    mission = models.ForeignKey(Mission, on_delete=models.CASCADE, related_name='tasks')

    task_type = models.CharField(max_length=64)  # e.g., 'email_send', 'calendar_create'
    description = models.TextField()

    inputs = models.JSONField(default=dict)
    outputs = models.JSONField(null=True)

    status = models.CharField(max_length=32, choices=[
        ('pending', 'Pending'),
        ('ready', 'Ready'),
        ('running', 'Running'),
        ('waiting_external', 'Waiting for external response'),
        ('waiting_human', 'Waiting for human input'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
        ('skipped', 'Skipped'),
    ])

    error = models.TextField(null=True)
    retry_count = models.IntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    started_at = models.DateTimeField(null=True)
    completed_at = models.DateTimeField(null=True)
    wait_until = models.DateTimeField(null=True)  # For scheduled retries

    # Dependencies
    depends_on = models.ManyToManyField('self', symmetrical=False, related_name='dependents')
```

### Human Input Request Model

```python
class HumanInputRequest(models.Model):
    """Pending approval or input needed from user"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    mission = models.ForeignKey(Mission, on_delete=models.CASCADE)
    task = models.ForeignKey(MissionTask, on_delete=models.CASCADE, null=True)

    request_type = models.CharField(max_length=32, choices=[
        ('approval', 'Approval Required'),
        ('clarification', 'Clarification Needed'),
        ('selection', 'Selection Required'),
        ('confirmation', 'Confirmation Required'),
    ])

    prompt = models.TextField()  # What to show the user
    options = models.JSONField(null=True)  # For selection type
    context = models.JSONField(default=dict)  # Additional context

    response = models.JSONField(null=True)
    responded_at = models.DateTimeField(null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True)
```

### External Account Models

```python
class UserCalendarAccount(models.Model):
    """OAuth tokens for calendar access"""
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    provider = models.CharField(max_length=20, choices=[
        ('google', 'Google'),
        ('apple', 'Apple'),
    ])

    # Encrypted OAuth tokens
    access_token = encrypt(models.TextField(null=True))
    refresh_token = encrypt(models.TextField(null=True))
    token_expires_at = models.DateTimeField(null=True)

    email = models.EmailField()  # Calendar account email
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    last_sync = models.DateTimeField(null=True)


class UserEmailAccount(models.Model):
    """OAuth tokens for email access"""
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    provider = models.CharField(max_length=20, choices=[
        ('google', 'Google'),
        ('apple', 'Apple'),
    ])

    access_token = encrypt(models.TextField(null=True))
    refresh_token = encrypt(models.TextField(null=True))
    token_expires_at = models.DateTimeField(null=True)

    email = models.EmailField()
    is_active = models.BooleanField(default=True)
    can_read_all_inbox = models.BooleanField(default=False)  # Privacy opt-in

    created_at = models.DateTimeField(auto_now_add=True)


class SentEmail(models.Model):
    """Track emails sent for reply matching"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    task = models.ForeignKey(MissionTask, on_delete=models.CASCADE)
    email_account = models.ForeignKey(UserEmailAccount, on_delete=models.CASCADE)

    reference_id = models.CharField(max_length=20, unique=True)  # [REF:xxx]
    message_id = models.CharField(max_length=255)  # Email Message-ID header

    to_addresses = models.JSONField()
    subject = models.CharField(max_length=500)
    sent_at = models.DateTimeField(auto_now_add=True)

    expecting_reply = models.BooleanField(default=True)
    reply_received = models.BooleanField(default=False)


class Contact(models.Model):
    """Known contacts - emails to these don't require approval"""
    owner = models.ForeignKey(User, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    email = models.EmailField()
    group = models.ForeignKey('ContactGroup', on_delete=models.SET_NULL, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    last_contacted = models.DateTimeField(null=True)


class ContactGroup(models.Model):
    """Named groups of contacts"""
    owner = models.ForeignKey(User, on_delete=models.CASCADE)
    name = models.CharField(max_length=100)
    aliases = models.JSONField(default=list)  # ["paragliding friends", "flying buddies"]
```

## 3.2 New Hub API Endpoints

### Mission Management

```
# Internal API (Agent → Hub)
POST   /api/internal/missions                    # Create mission
GET    /api/internal/missions/{id}               # Get mission state
PATCH  /api/internal/missions/{id}               # Update mission status
POST   /api/internal/missions/{id}/tasks         # Create task
GET    /api/internal/missions/{id}/tasks         # List tasks
PATCH  /api/internal/tasks/{id}                  # Update task
POST   /api/internal/missions/{id}/human-input   # Request human input
GET    /api/internal/human-input/pending         # Get pending requests
```

### External Account Management

```
# Public API (User-facing, through Hub frontend)
GET    /api/v1/accounts/calendar                 # List calendar accounts
POST   /api/v1/oauth/google/calendar/authorize   # Start OAuth
GET    /api/v1/oauth/google/calendar/callback    # OAuth callback
DELETE /api/v1/accounts/calendar/{id}            # Disconnect

GET    /api/v1/accounts/email                    # List email accounts
POST   /api/v1/oauth/google/email/authorize      # Start OAuth
GET    /api/v1/oauth/google/email/callback       # OAuth callback
DELETE /api/v1/accounts/email/{id}               # Disconnect

# Internal API (Agent → Hub)
GET    /api/internal/accounts/{user_id}/calendar # Get calendar credentials
GET    /api/internal/accounts/{user_id}/email    # Get email credentials
```

### Sent Email Tracking

```
POST   /api/internal/emails/sent                 # Record sent email
GET    /api/internal/emails/awaiting-reply       # Get emails awaiting reply
POST   /api/internal/emails/{id}/reply-received  # Mark reply received
```

---

# 4. Agent Tool Specifications

## 4.1 Mission Management Tools

### `mission_create_task`

Create a new task in the current mission's execution graph.

```python
# Input Schema
{
    "task_type": "string",           # e.g., "email_send", "calendar_get_availability"
    "description": "string",         # Human-readable description
    "inputs": {},                    # Task-specific inputs
    "depends_on": ["task_id"],       # Optional task IDs this depends on
    "wait_for_external": true|false  # Whether task waits for external response
}

# Output Schema
{
    "task_id": "uuid",
    "status": "pending"
}
```

### `mission_ask_user`

Request clarification or approval from the user.

```python
# Input Schema
{
    "request_type": "approval" | "clarification" | "selection" | "confirmation",
    "prompt": "string",              # What to show the user
    "options": ["string"],           # For selection type
    "context": {}                    # Additional context to display
}

# Output Schema
{
    "request_id": "uuid",
    "status": "pending"
}
```

### `mission_complete`

Mark the mission as completed with a summary.

```python
# Input Schema
{
    "summary": "string",             # What was accomplished
    "deliverables": [                # Any outputs produced
        {"type": "event", "id": "...", "title": "..."},
        {"type": "document", "id": "...", "title": "..."}
    ]
}

# Output Schema
{
    "mission_id": "uuid",
    "status": "completed"
}
```

## 4.2 Calendar Tools

### `calendar_get_availability`

Get free/busy times for people over a date range.

```python
# Input Schema
{
    "emails": ["string"],            # Email addresses to check
    "start_date": "ISO8601",
    "end_date": "ISO8601",
    "timezone": "string"             # Optional, IANA timezone
}

# Output Schema
{
    "results": [
        {
            "email": "string",
            "status": "success" | "not_found" | "needs_email_outreach",
            "busy_slots": [
                {"start": "ISO8601", "end": "ISO8601"}
            ],
            "source": "google_api" | "email_pending"
        }
    ],
    "emails_needing_outreach": ["string"]
}
```

### `calendar_find_optimal_times`

Find the best meeting slots given availability constraints.

```python
# Input Schema
{
    "duration_minutes": 30 | 60 | 90 | 120,
    "attendees": [
        {
            "email": "string",
            "required": true | false,
            "busy_slots": [{"start": "ISO8601", "end": "ISO8601"}]
        }
    ],
    "date_range": {"start": "ISO8601", "end": "ISO8601"},
    "preferences": {
        "preferred_times": ["morning", "afternoon", "evening"],
        "avoid_days": ["Saturday", "Sunday"],
        "working_hours": {"start": "09:00", "end": "17:00"},
        "timezone": "string"
    },
    "max_results": 5
}

# Output Schema
{
    "slots": [
        {
            "start": "ISO8601",
            "end": "ISO8601",
            "score": 0.0-1.0,
            "attendee_status": {"email": "available" | "busy" | "unknown"},
            "conflicts": ["string"]
        }
    ],
    "has_perfect_slot": true | false,
    "unknown_availability": ["string"]
}
```

### `calendar_create_event`

Create a calendar event and send invites.

```python
# Input Schema
{
    "title": "string",
    "start": "ISO8601",
    "end": "ISO8601",
    "attendees": [{"email": "string", "optional": false}],
    "location": "string",
    "description": "string",
    "video_conference": true | false,
    "send_invites": true | false
}

# Output Schema
{
    "success": true | false,
    "event_id": "string",
    "event_link": "string",
    "video_link": "string" | null,
    "invites_sent_to": ["string"],
    "error": "string" | null
}
```

### `calendar_update_event` / `calendar_delete_event`

Modify or cancel existing events (schemas follow similar patterns).

## 4.3 Email Tools

### `email_send`

Send an email on behalf of the user.

```python
# Input Schema
{
    "to": ["string"],
    "subject": "string",
    "body": "string",
    "cc": ["string"],
    "reply_to_message_id": "string",  # For threading
    "expect_reply": true | false
}

# Output Schema
{
    "success": true | false,
    "message_id": "string",
    "reference_id": "string",         # The [REF:xxx] code
    "approval_required": true | false,
    "pending_approval_id": "string" | null,
    "error": "string" | null
}
```

**Approval Logic:**
- Known contacts (in Contact table): Send directly
- Unknown recipients: Return `approval_required: true`

### `email_check_replies`

Check for replies to sent emails.

```python
# Input Schema
{
    "sent_email_ids": ["string"],     # Optional, checks all pending if empty
    "max_age_hours": 168              # Default 7 days
}

# Output Schema
{
    "replies_found": [
        {
            "sent_email_id": "string",
            "reference_id": "string",
            "reply": {
                "message_id": "string",
                "from": "string",
                "subject": "string",
                "body_text": "string",
                "received_at": "ISO8601"
            }
        }
    ],
    "still_waiting": ["string"],
    "expired": ["string"]
}
```

### `email_parse_reply`

Extract structured meaning from an email reply (uses AI).

```python
# Input Schema
{
    "email_body": "string",
    "expected_content": "availability" | "confirmation" | "general",
    "context": "string"               # What we originally asked
}

# Output Schema
{
    "intent": "provides_availability" | "confirms" | "declines" | "proposes_alternative" | "asks_question" | "unclear",
    "availability": {
        "available_times": [{"start": "ISO8601", "end": "ISO8601"}],
        "unavailable_times": [{"start": "ISO8601", "end": "ISO8601"}],
        "preferences": ["string"]
    },
    "confidence": 0.0-1.0,
    "requires_human_review": true | false
}
```

### `email_send_followup`

Send a follow-up for an unanswered request.

```python
# Input Schema
{
    "sent_email_id": "string",
    "followup_message": "string",     # Optional, AI generates if not provided
    "urgency": "low" | "normal" | "high"
}

# Output Schema
{
    "success": true | false,
    "message_id": "string",
    "followup_number": 1 | 2 | 3,
    "error": "string" | null
}
```

## 4.4 Research Tools

### `research_web_search`

Search the web for information (uses Claude's native web search).

```python
# Input Schema
{
    "query": "string",
    "num_results": 10
}

# Output Schema
{
    "results": [
        {"title": "string", "url": "string", "snippet": "string"}
    ]
}
```

### `research_fetch_page`

Retrieve full content of a web page.

```python
# Input Schema
{
    "url": "string"
}

# Output Schema
{
    "url": "string",
    "title": "string",
    "content": "string",
    "fetch_time": "ISO8601"
}
```

### `research_summarize`

Synthesize multiple sources into findings (uses AI).

```python
# Input Schema
{
    "sources": [
        {"url": "string", "title": "string", "content": "string"}
    ],
    "focus": "string",
    "format": "bullets" | "prose" | "comparison_table",
    "max_length": 500
}

# Output Schema
{
    "summary": "string",
    "key_findings": ["string"],
    "confidence": "high" | "medium" | "low",
    "gaps": ["string"]
}
```

## 4.5 Document Tools

### `document_create`

Generate a document from structured content.

```python
# Input Schema
{
    "title": "string",
    "doc_type": "agenda" | "report" | "summary" | "email_draft" | "notes",
    "content": {
        "sections": [
            {"heading": "string", "body": "string", "items": ["string"]}
        ],
        "metadata": {
            "date": "ISO8601",
            "attendees": ["string"],
            "location": "string"
        }
    },
    "format": "markdown" | "plain_text",
    "style": "formal" | "casual"
}

# Output Schema
{
    "document_id": "string",
    "content": "string",
    "word_count": 123
}
```

---

# 5. Approval Workflow

## 5.1 Autonomy Levels

| Action | Default Autonomy | Notes |
|--------|-----------------|-------|
| Read own calendar/email | Auto | No approval needed |
| Send email to known contacts | Auto | Contact exists in system |
| Send email to unknown contacts | Require approval | First-time recipients |
| Create event (user only) | Auto | No external impact |
| Send invites (after time approved) | Auto | Time selection = implicit approval |
| Send invites (new request) | Require approval | User approves proposed time |
| Book external services | Require approval | Always |
| Financial transactions | Require approval | Always |

## 5.2 Trust Mode

Optional opt-in that auto-executes most actions with warning notifications:

```python
class UserAssistantPreferences(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)

    trust_mode = models.BooleanField(default=False)
    trust_mode_enabled_at = models.DateTimeField(null=True)

    # Always require approval even in trust mode
    always_approve_financial = models.BooleanField(default=True)
    always_approve_external_bookings = models.BooleanField(default=True)

    default_followup_hours = models.IntegerField(default=24)
```

---

# 6. Background Task Processing

## 6.1 Hub Background Tasks (Django-Q2)

Add to Hub for Personal Assistant support:

| Task | Frequency | Purpose |
|------|-----------|---------|
| `check_email_replies` | Every 5 min | Poll for replies to sent emails |
| `send_scheduled_followups` | Hourly | Send follow-ups for unanswered requests |
| `refresh_oauth_tokens` | Every 30 min | Refresh expiring tokens |
| `mission_timeout_check` | Every 15 min | Handle stalled missions |

## 6.2 Email Polling Flow

```
1. Background task queries SentEmail where expecting_reply=True
2. For each email account, poll Gmail API for replies
3. Match replies using [REF:xxx] tag in subject
4. Store in ReceivedEmail table
5. Update related MissionTask status to 'ready'
6. Agent picks up on next conversation turn or scheduled check
```

---

# 7. API Contract Extensions

## 7.1 Agent → Hub (New Endpoints)

### Create Mission

```
POST /api/internal/missions
Authorization: Bearer {HUB_SERVICE_SECRET}

{
    "agent_instance_id": "uuid",
    "user_id": "uuid",
    "conversation_id": "string",
    "raw_input": "Schedule a meeting with the marketing team next week"
}

Response:
{
    "mission_id": "uuid",
    "status": "planning"
}
```

### Create Task

```
POST /api/internal/missions/{mission_id}/tasks
Authorization: Bearer {HUB_SERVICE_SECRET}

{
    "task_type": "calendar_get_availability",
    "description": "Check availability for marketing team",
    "inputs": {
        "emails": ["alice@company.com", "bob@company.com"],
        "date_range": {...}
    },
    "depends_on": []
}

Response:
{
    "task_id": "uuid",
    "status": "pending"
}
```

### Execute Tool (Calendar/Email)

```
POST /api/internal/tools/execute
Authorization: Bearer {HUB_SERVICE_SECRET}

{
    "tool": "calendar_get_availability",
    "user_id": "uuid",
    "inputs": {...}
}

Response:
{
    "success": true,
    "result": {...}
}
```

---

# 8. System Prompts

## 8.1 Orchestrator System Prompt

```
You are a personal assistant orchestrating complex tasks. You manage missions by breaking them into executable tasks, coordinating tools, and ensuring successful completion.

RESPONSIBILITIES:
1. UNDERSTAND - Parse requests, identify intent, ask clarifying questions when needed
2. PLAN - Break down into tasks with clear dependencies
3. EXECUTE - Call appropriate tools to complete each task
4. MONITOR - Track progress, detect failures, handle blocked states
5. REPLAN - Adjust strategy when tasks fail or circumstances change
6. SYNTHESIZE - Aggregate results and report back to user

AVAILABLE TOOLS:
- Mission: create_task, ask_user, complete
- Calendar: get_availability, find_optimal_times, create_event, update_event, delete_event
- Email: send, check_replies, parse_reply, search, read, send_followup
- Research: web_search, fetch_page, summarize
- Document: create, edit, get

WORKFLOW GUIDELINES:
- For scheduling: First check availability, then propose times, then create event
- For external attendees: Email for availability if not in system
- For complex requests: Create task graph with dependencies
- For human approval: Use ask_user tool and wait for response
- For async operations (email replies): Create task with wait_for_external=true

APPROVAL RULES:
- Known contacts: Proceed directly
- Unknown recipients: Request approval first
- Time-sensitive: Note urgency in approval request
- Financial/booking: Always require explicit approval

OUTPUT: Tool calls, status updates, clarifying questions, or final summary.
Current user: {user_name}
Current time: {current_time}
User timezone: {user_timezone}
```

---

# 9. Development Phases

## Phase 1: Foundation
- Hub models: Mission, Task, HumanInputRequest
- Hub: Google OAuth for Calendar + Gmail
- Agent: Orchestrator system prompt
- Agent: Basic calendar tools (get_availability, create_event)
- Agent: Basic email tools (send, check_replies)

## Phase 2: Full Calendar/Email
- Agent: All calendar tools
- Agent: All email tools
- Hub: Background email polling
- Hub: Contact management
- Agent: Approval workflow

## Phase 3: Research & Documents
- Agent: Research tools (web_search, fetch_page, summarize)
- Agent: Document tools (create, edit)
- Hub: Document storage

## Phase 4: Apple Integration
- Hub: Apple CalDAV OAuth
- Hub: Apple IMAP/SMTP
- Agent: Provider abstraction layer

---

# 10. Acceptance Criteria

## 10.1 Core Orchestration

- [ ] Agent can create and manage missions
- [ ] Agent decomposes requests into task graphs
- [ ] Agent handles task dependencies correctly
- [ ] Agent requests human input when needed
- [ ] Mission state persists in Hub

## 10.2 Calendar Integration

- [ ] User can connect Google Calendar via OAuth
- [ ] Agent can check availability
- [ ] Agent can create events with invites
- [ ] Agent handles external attendee coordination

## 10.3 Email Integration

- [ ] User can connect Gmail via OAuth
- [ ] Agent can send emails on behalf of user
- [ ] Agent tracks sent emails for replies
- [ ] Background task polls for replies
- [ ] Agent parses reply content intelligently

## 10.4 Approval Workflow

- [ ] Unknown recipients require approval
- [ ] User can respond to approval requests
- [ ] Trust mode bypasses non-critical approvals
- [ ] Financial actions always require approval

---

# Appendix A: Migration from Standalone Spec

This specification adapts the original standalone Personal Assistant spec to run on EchoForge:

| Original | EchoForge Equivalent |
|----------|---------------------|
| Django app | EchoForge Hub (extended) |
| Django-Q2 | Hub Django-Q2 (new) |
| React SPA | Hub UI (existing) |
| Orchestrator Agent (Python) | Agent LLM with tools |
| Specialist Agents | Agent tool handlers |
| PostgreSQL models | Hub PostgreSQL models |
| JWT auth | Hub auth + Agent API key |

---

*End of Specification*
