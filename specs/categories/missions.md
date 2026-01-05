---
title: "Missions Category"
version: "1.0"
status: draft
project: EchoForge
created: 2026-01-02
updated: 2026-01-03
github_issue: 21
dependencies:
  - issue: 18
    title: "Persistent Missions with Cross-Conversation Visibility"
    spec: "echoforge-hub/docs/specs/persistent_missions.md"
  - issue: 20
    title: "Multi-Reply Email Tracking"
    spec: "echoforge-hub/docs/specs/multi_reply_tracking.md"
---

# Category: Missions

> **Status:** Draft
> **Last Updated:** 2026-01-03
> **Owner:** EchoForge Team
> **GitHub Issue:** [#21](https://github.com/jeffsinason/EchoForgeX/issues/21)

## Prerequisites

This feature depends on:
- **#18** - [Persistent Missions](../echoforge-hub/docs/specs/persistent_missions.md): Must be implemented first to provide database storage and cross-conversation visibility
- **#20** - [Multi-Reply Email Tracking](../echoforge-hub/docs/specs/multi_reply_tracking.md): Required for email wait conditions to track all recipient replies

## 1. Overview

### 1.1 Purpose

Missions enable agents to handle complex, multi-step tasks that require:
- Breaking work into dependent subtasks
- Coordinating across multiple tool categories (email, calendar, etc.)
- Human-in-the-loop approval at key decision points
- Waiting for external events (email replies, calendar confirmations)
- Recovering from failures and replanning

**Example Mission:** "Schedule a meeting with Sarah and John next week about the Q1 budget"
- Task 1: Check my calendar availability
- Task 2: Email Sarah for her availability (async wait)
- Task 3: Email John for his availability (async wait)
- Task 4: Find optimal time slot (blocked on 2, 3)
- Task 5: Get user approval for proposed time
- Task 6: Create calendar event and send invites

### 1.2 Classification

| Attribute | Value |
|-----------|-------|
| **Type** | `capability` |
| **Billing** | `addon` |
| **Min Plan** | `professional` |
| **Meter Name** | N/A (flat add-on fee) |

### 1.3 Dependencies

- Requires at least one other category enabled (email, calendar, etc.) to be useful
- Uses tools from other categories to accomplish subtasks
- Relies on Hub for persistent state storage

---

## 2. Tools

### 2.1 Tool Summary

| Tool Name | Description | Async | Approval |
|-----------|-------------|-------|----------|
| `mission_create_task` | Create a subtask in the mission | No | No |
| `mission_ask_user` | Request human input/approval | Yes | N/A (is the approval) |
| `mission_complete` | Mark mission as complete with summary | No | No |

### 2.2 Tool Definitions

#### `mission_create_task`

**Description:** Creates a new task within the current mission. Tasks can have dependencies on other tasks and can be marked to wait for external events.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Short title describing the task"
    },
    "description": {
      "type": "string",
      "description": "Detailed description of what needs to be done"
    },
    "depends_on": {
      "type": "array",
      "items": {"type": "string"},
      "description": "List of task IDs this task depends on"
    },
    "wait_for_external": {
      "type": "boolean",
      "default": false,
      "description": "If true, task will wait for external event (e.g., email reply)"
    },
    "external_event_type": {
      "type": "string",
      "enum": ["email_reply", "calendar_response", "webhook"],
      "description": "Type of external event to wait for"
    },
    "timeout_hours": {
      "type": "number",
      "default": 24,
      "description": "Hours to wait before timing out"
    }
  },
  "required": ["title"]
}
```

**Output Schema:**
```json
{
  "success": true,
  "data": {
    "task_id": "uuid",
    "status": "pending",
    "position": 3
  }
}
```

**Error Cases:**
- `MISSION_NOT_FOUND`: No active mission in context
- `CIRCULAR_DEPENDENCY`: Task dependencies would create a cycle
- `INVALID_DEPENDENCY`: Referenced task ID doesn't exist

---

#### `mission_ask_user`

**Description:** Pauses execution to request input or approval from the user. The mission remains in a waiting state until the user responds.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "prompt": {
      "type": "string",
      "description": "The question or request to show the user"
    },
    "options": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "label": {"type": "string"},
          "description": {"type": "string"}
        }
      },
      "description": "Predefined options for the user to choose from"
    },
    "allow_freeform": {
      "type": "boolean",
      "default": true,
      "description": "Whether user can provide custom text response"
    },
    "context": {
      "type": "object",
      "description": "Additional context to display (e.g., calendar slots, email preview)"
    },
    "urgency": {
      "type": "string",
      "enum": ["low", "normal", "high"],
      "default": "normal",
      "description": "Affects notification behavior"
    },
    "expires_in_hours": {
      "type": "number",
      "default": 24,
      "description": "Hours until this request expires"
    }
  },
  "required": ["prompt"]
}
```

**Output Schema:**
```json
{
  "success": true,
  "data": {
    "request_id": "uuid",
    "status": "pending",
    "expires_at": "2026-01-03T10:00:00Z"
  }
}
```

**When User Responds:**
```json
{
  "success": true,
  "data": {
    "request_id": "uuid",
    "status": "responded",
    "response": {
      "selected_option": "option_id",
      "freeform_text": "User's additional input",
      "responded_at": "2026-01-02T15:30:00Z"
    }
  }
}
```

**Error Cases:**
- `MISSION_NOT_FOUND`: No active mission in context
- `REQUEST_EXPIRED`: User didn't respond in time

---

#### `mission_complete`

**Description:** Marks the mission as complete with a final summary for the user.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "summary": {
      "type": "string",
      "description": "Human-readable summary of what was accomplished"
    },
    "outcome": {
      "type": "string",
      "enum": ["success", "partial", "failed", "cancelled"],
      "default": "success"
    },
    "details": {
      "type": "object",
      "description": "Structured data about results (created events, sent emails, etc.)"
    }
  },
  "required": ["summary"]
}
```

**Output Schema:**
```json
{
  "success": true,
  "data": {
    "mission_id": "uuid",
    "status": "completed",
    "outcome": "success",
    "completed_at": "2026-01-02T16:00:00Z"
  }
}
```

---

## 3. Providers

> *Not applicable - Missions is a `capability` type category*

---

## 4. Logic Flows

### 4.1 Mission State Machine

```
                              ┌──────────────────────────────────┐
                              │                                  │
                              ▼                                  │
┌─────────┐  create   ┌──────────────┐  tasks    ┌───────────┐  │  replan
│ (none)  │──────────▶│   planning   │──────────▶│ executing │──┘
└─────────┘           └──────────────┘           └─────┬─────┘
                                                       │
                      ┌────────────────────────────────┼────────────────────────────────┐
                      │                                │                                │
                      ▼                                ▼                                ▼
               ┌─────────────┐                 ┌──────────────┐                ┌────────────┐
               │   waiting   │                 │  completed   │                │   failed   │
               │ (human/ext) │                 │              │                │            │
               └──────┬──────┘                 └──────────────┘                └────────────┘
                      │
                      │ response/event
                      ▼
               ┌─────────────┐
               │  executing  │ (resume)
               └─────────────┘
```

### 4.2 Task State Machine

```
┌─────────┐  dependencies met   ┌────────────┐  tool call   ┌─────────────┐
│ pending │────────────────────▶│   ready    │─────────────▶│ in_progress │
└─────────┘                     └────────────┘              └──────┬──────┘
                                                                   │
                    ┌──────────────────────────────────────────────┼───────────────┐
                    │                                              │               │
                    ▼                                              ▼               ▼
            ┌───────────────┐                              ┌───────────┐   ┌────────────┐
            │ waiting_human │                              │ completed │   │   failed   │
            └───────┬───────┘                              └───────────┘   └────────────┘
                    │
                    │ user responds
                    ▼
            ┌───────────────┐
            │ in_progress   │ (resume)
            └───────────────┘


            ┌────────────────┐
            │ waiting_external│ (email reply, etc.)
            └───────┬────────┘
                    │
                    │ external event received
                    ▼
            ┌───────────────┐
            │ in_progress   │ (resume)
            └───────────────┘
```

### 4.3 Approval Workflows

**When Approval is Required:**

The LLM decides when to use `mission_ask_user` based on guidelines in the orchestrator prompt:

| Scenario | Approval Required | Reason |
|----------|-------------------|--------|
| Unknown email recipient | Yes | Privacy/correctness |
| Financial transaction | Yes | Always |
| Calendar booking with external attendees | Yes | Confirm time/attendees |
| Sending on user's behalf | Depends | Known contacts: No, Unknown: Yes |
| Destructive action (delete, cancel) | Yes | Irreversible |

**Approval Flow:**

```
Agent determines approval needed
            │
            ▼
┌─────────────────────────┐
│ Call mission_ask_user   │
│ with options & context  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Hub creates             │
│ HumanInputRequest       │
│ status: pending         │
└───────────┬─────────────┘
            │
            ├─────────────────────────────────┐
            ▼                                 ▼
┌───────────────────────┐       ┌───────────────────────┐
│ Push to chat client   │       │ Show in dashboard     │
│ via WebSocket         │       │ "Pending Inputs"      │
└───────────────────────┘       └───────────────────────┘
            │                                 │
            └────────────┬────────────────────┘
                         ▼
              ┌─────────────────────┐
              │ User selects option │
              │ or provides input   │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ Hub updates request │
              │ status: responded   │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ Agent resumes task  │
              │ with user response  │
              └─────────────────────┘
```

### 4.4 Async Patterns

**External Wait Pattern (Email Reply Example):**

```
1. Agent sends email via email_send
   └─▶ Hub records: expecting reply to message_id=abc123

2. Agent creates task with wait_for_external=true
   └─▶ Task status: waiting_external
   └─▶ Mission status: waiting

3. User replies to email (external event)
   └─▶ Gmail webhook → Hub receives reply
   └─▶ Hub matches reply to waiting task
   └─▶ Hub updates task with reply content
   └─▶ Task status: ready

4. Agent scheduler detects ready task
   └─▶ Resumes mission execution
   └─▶ Agent receives reply content in context
```

**Wait Conditions:**
- `email_reply`: Waiting for response to a sent email
- `calendar_response`: Waiting for attendee RSVP
- `webhook`: Waiting for external system callback

**Resume Triggers:**
- Email reply received matching thread
- Calendar RSVP received
- Webhook called with matching correlation ID
- Timeout expires (with fallback behavior)

**Timeout Handling:**
- Default: 24 hours
- On timeout: Task marked `failed` with reason
- Agent can replan or ask user how to proceed

---

## 5. UI/UX

### 5.1 Chat Interface

**Inline Components:**

| Component | Trigger | Description |
|-----------|---------|-------------|
| Mission Started Card | Mission created | Shows mission title, initial tasks |
| Approval Request Card | `mission_ask_user` | Options, context, approve/reject buttons |
| Task Progress | Task completes | Brief status update |
| Mission Complete Card | `mission_complete` | Summary, outcome, details |

**Approval Request Card:**
```
┌─────────────────────────────────────────────────────────┐
│ 🔔 Approval Required                                    │
│                                                         │
│ I found these available times for the meeting with      │
│ Sarah and John:                                         │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 📅 Tuesday, Jan 7 at 2:00 PM                        │ │
│ │    All attendees available                          │ │
│ │    [Select]                                         │ │
│ ├─────────────────────────────────────────────────────┤ │
│ │ 📅 Wednesday, Jan 8 at 10:00 AM                     │ │
│ │    All attendees available                          │ │
│ │    [Select]                                         │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ [None of these work - suggest alternatives]             │
└─────────────────────────────────────────────────────────┘
```

**Mission Complete Card:**
```
┌─────────────────────────────────────────────────────────┐
│ ✅ Mission Complete                                     │
│                                                         │
│ "Schedule meeting with Sarah and John"                  │
│                                                         │
│ Summary:                                                │
│ • Created meeting: "Q1 Budget Review"                   │
│ • Date: Tuesday, Jan 7 at 2:00 PM                       │
│ • Attendees: Sarah, John (invites sent)                 │
│ • Location: Conference Room B                           │
│                                                         │
│ [View in Calendar]                                      │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Dashboard Components

**Mission Dashboard Page:** `/dashboard/missions`

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 📋 Missions                                              [+ New Mission] │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ ┌─ Filters ──────────────────────────────────────────────────────────┐   │
│ │ Status: [All ▼]  Agent: [All ▼]  Date: [Last 30 days ▼]           │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│ ┌─ Needs Attention (2) ──────────────────────────────────────────────┐   │
│ │                                                                    │   │
│ │ ┌────────────────────────────────────────────────────────────────┐ │   │
│ │ │ 🔴 Research competitors              Needs Input: 30m ago     │ │   │
│ │ │    Agent: Personal Assistant                                  │ │   │
│ │ │    ├─ ✅ Search for competitor list                           │ │   │
│ │ │    ├─ 🛑 WAITING: Select competitors to analyze               │ │   │
│ │ │    └─ ⬚ Generate comparison report                            │ │   │
│ │ │                                                                │ │   │
│ │ │ [Respond Now] [View Details] [Cancel]                         │ │   │
│ │ └────────────────────────────────────────────────────────────────┘ │   │
│ │                                                                    │   │
│ │ ┌────────────────────────────────────────────────────────────────┐ │   │
│ │ │ 🟡 Schedule PTA meeting                      Started: 2h ago  │ │   │
│ │ │    Agent: Personal Assistant                                  │ │   │
│ │ │    ├─ ✅ Check calendar availability                          │ │   │
│ │ │    ├─ ✅ Email Sarah for her availability                     │ │   │
│ │ │    ├─ ⏳ Waiting: Sarah's reply (expires in 22h)              │ │   │
│ │ │    └─ ⬚ Create calendar event                                 │ │   │
│ │ │                                                                │ │   │
│ │ │ [View Details] [Cancel]                                       │ │   │
│ │ └────────────────────────────────────────────────────────────────┘ │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│ ┌─ In Progress (3) ──────────────────────────────────────────────────┐   │
│ │ ... similar cards without "Needs Attention" badge ...             │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│ ┌─ Recently Completed ───────────────────────────────────────────────┐   │
│ │ ✅ Book restaurant reservation    Completed: Yesterday            │   │
│ │ ✅ Send weekly report             Completed: 2 days ago           │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Mission Detail Page:** `/dashboard/missions/{id}`

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ← Back to Missions                                                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ 📋 Schedule PTA meeting with class parents                               │
│ Status: 🟡 In Progress (Waiting for External)                            │
│ Started: Jan 2, 2026 at 10:30 AM                                         │
│ Agent: Personal Assistant                                                │
│                                                                          │
│ ┌─ Tasks ────────────────────────────────────────────────────────────┐   │
│ │                                                                    │   │
│ │  ✅ 1. Check my calendar for next week                            │   │
│ │      Completed: 10:31 AM                                          │   │
│ │      Result: 3 available slots found                              │   │
│ │                                                                    │   │
│ │  ✅ 2. Email Sarah to ask for her availability                    │   │
│ │      Completed: 10:32 AM                                          │   │
│ │      Result: Email sent to sarah@email.com                        │   │
│ │                                                                    │   │
│ │  ⏳ 3. Wait for Sarah's reply                                     │   │
│ │      Status: Waiting (expires in 22h)                             │   │
│ │      [Mark as received manually]                                   │   │
│ │                                                                    │   │
│ │  ⬚ 4. Find optimal meeting time                                   │   │
│ │      Blocked by: Task 3                                           │   │
│ │                                                                    │   │
│ │  ⬚ 5. Get user approval for proposed time                         │   │
│ │      Blocked by: Task 4                                           │   │
│ │                                                                    │   │
│ │  ⬚ 6. Create calendar event                                       │   │
│ │      Blocked by: Task 5                                           │   │
│ │                                                                    │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│ ┌─ Activity Log ─────────────────────────────────────────────────────┐   │
│ │ 10:32 AM  Email sent to sarah@email.com                           │   │
│ │ 10:31 AM  Found 3 available slots: Tue 2pm, Wed 10am, Thu 3pm     │   │
│ │ 10:30 AM  Mission started                                         │   │
│ └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│ [Cancel Mission] [Retry Failed Tasks]                                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**User Actions:**
- **Respond Now**: Opens approval dialog for pending input requests
- **View Details**: Navigate to mission detail page
- **Cancel**: Cancel mission with confirmation
- **Mark as received manually**: For external waits, manually trigger resume
- **Retry Failed Tasks**: Retry failed tasks with optional modification

### 5.3 Notifications

| Event | Chat | Dashboard | Email | Push |
|-------|------|-----------|-------|------|
| Mission created | Message | - | - | - |
| Task completed | Message | Badge update | - | - |
| Approval needed | Card + sound | Badge + banner | If idle >1h | If enabled |
| External wait started | Message | Status update | - | - |
| External event received | Message | Status update | - | - |
| Mission complete | Summary card | Move to completed | If >1h duration | - |
| Mission failed | Error card | Banner | Yes | If enabled |
| Approval expiring (1h left) | Reminder | Banner | Yes | If enabled |

---

## 6. Hub Implementation

### 6.1 Models

```python
# apps/agents/models.py

class Mission(CustomerScopedModel):
    """A complex, multi-step task being executed by an agent."""

    class Status(models.TextChoices):
        PLANNING = 'planning', 'Planning'
        EXECUTING = 'executing', 'Executing'
        WAITING = 'waiting', 'Waiting'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'
        CANCELLED = 'cancelled', 'Cancelled'

    class Outcome(models.TextChoices):
        SUCCESS = 'success', 'Success'
        PARTIAL = 'partial', 'Partial Success'
        FAILED = 'failed', 'Failed'
        CANCELLED = 'cancelled', 'Cancelled'

    agent_instance = models.ForeignKey(
        'AgentInstance',
        on_delete=models.CASCADE,
        related_name='missions'
    )
    conversation_id = models.UUIDField(db_index=True)

    title = models.CharField(max_length=200)
    raw_input = models.TextField()  # Original user request
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PLANNING
    )
    outcome = models.CharField(
        max_length=20,
        choices=Outcome.choices,
        null=True,
        blank=True
    )
    summary = models.TextField(blank=True)  # Final summary

    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    # For resumption after waiting
    wait_reason = models.CharField(max_length=50, blank=True)
    resume_after = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-started_at']
        indexes = [
            models.Index(fields=['customer', 'status']),
            models.Index(fields=['agent_instance', 'status']),
        ]


class MissionTask(BaseModel):
    """A single task within a mission."""

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        READY = 'ready', 'Ready'
        IN_PROGRESS = 'in_progress', 'In Progress'
        WAITING_HUMAN = 'waiting_human', 'Waiting for Human'
        WAITING_EXTERNAL = 'waiting_external', 'Waiting for External'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'
        SKIPPED = 'skipped', 'Skipped'

    mission = models.ForeignKey(
        Mission,
        on_delete=models.CASCADE,
        related_name='tasks'
    )

    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    position = models.IntegerField(default=0)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING
    )

    # Dependencies
    depends_on = models.ManyToManyField(
        'self',
        symmetrical=False,
        related_name='dependents',
        blank=True
    )

    # External wait configuration
    wait_for_external = models.BooleanField(default=False)
    external_event_type = models.CharField(max_length=50, blank=True)
    external_correlation_id = models.CharField(max_length=200, blank=True)
    timeout_at = models.DateTimeField(null=True, blank=True)

    # Execution tracking
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    result = models.JSONField(null=True, blank=True)
    error = models.TextField(blank=True)

    class Meta:
        ordering = ['position']


class HumanInputRequest(BaseModel):
    """A pending request for human input/approval."""

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        RESPONDED = 'responded', 'Responded'
        EXPIRED = 'expired', 'Expired'
        CANCELLED = 'cancelled', 'Cancelled'

    class Urgency(models.TextChoices):
        LOW = 'low', 'Low'
        NORMAL = 'normal', 'Normal'
        HIGH = 'high', 'High'

    mission = models.ForeignKey(
        Mission,
        on_delete=models.CASCADE,
        related_name='input_requests'
    )
    task = models.ForeignKey(
        MissionTask,
        on_delete=models.CASCADE,
        related_name='input_requests',
        null=True,
        blank=True
    )
    conversation_id = models.UUIDField(db_index=True)

    prompt = models.TextField()
    options = models.JSONField(default=list)
    allow_freeform = models.BooleanField(default=True)
    context = models.JSONField(null=True, blank=True)
    urgency = models.CharField(
        max_length=10,
        choices=Urgency.choices,
        default=Urgency.NORMAL
    )

    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING
    )
    response = models.JSONField(null=True, blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField()

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', 'expires_at']),
            models.Index(fields=['conversation_id', 'status']),
        ]
```

### 6.2 API Endpoints

**Internal API (Agent → Hub):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/internal/missions` | Create new mission |
| `GET` | `/api/internal/missions/{id}` | Get mission state |
| `PATCH` | `/api/internal/missions/{id}` | Update mission status |
| `POST` | `/api/internal/missions/{id}/tasks` | Create task |
| `PATCH` | `/api/internal/missions/{id}/tasks/{task_id}` | Update task |
| `POST` | `/api/internal/missions/{id}/input-requests` | Create input request |
| `GET` | `/api/internal/missions/{id}/input-requests/{req_id}` | Check request status |

**External API (Dashboard → Hub):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/missions/` | List user's missions |
| `GET` | `/api/v1/missions/{id}/` | Get mission detail |
| `POST` | `/api/v1/missions/{id}/cancel/` | Cancel mission |
| `GET` | `/api/v1/missions/pending-inputs/` | Get pending input requests |
| `POST` | `/api/v1/input-requests/{id}/respond/` | Submit response |

### 6.3 Services

```python
# apps/agents/services/mission_service.py

from typing import Dict, List, Optional
from django.utils import timezone
from apps.agents.models import Mission, MissionTask, HumanInputRequest


class MissionService:
    """Service for managing mission lifecycle."""

    def create_mission(
        self,
        agent_instance_id: str,
        conversation_id: str,
        raw_input: str,
        title: Optional[str] = None,
    ) -> Mission:
        """Create a new mission."""
        from apps.agents.models import AgentInstance

        agent = AgentInstance.objects.get(id=agent_instance_id)

        mission = Mission.objects.create(
            customer=agent.customer,
            agent_instance=agent,
            conversation_id=conversation_id,
            raw_input=raw_input,
            title=title or raw_input[:100],
            status=Mission.Status.PLANNING,
        )

        return mission

    def create_task(
        self,
        mission_id: str,
        title: str,
        description: str = "",
        depends_on: List[str] = None,
        wait_for_external: bool = False,
        external_event_type: str = "",
        timeout_hours: int = 24,
    ) -> MissionTask:
        """Create a task within a mission."""
        mission = Mission.objects.get(id=mission_id)

        # Get next position
        max_pos = mission.tasks.aggregate(
            max=models.Max('position')
        )['max'] or 0

        task = MissionTask.objects.create(
            mission=mission,
            title=title,
            description=description,
            position=max_pos + 1,
            wait_for_external=wait_for_external,
            external_event_type=external_event_type,
            timeout_at=timezone.now() + timezone.timedelta(hours=timeout_hours)
            if wait_for_external else None,
        )

        # Add dependencies
        if depends_on:
            deps = MissionTask.objects.filter(id__in=depends_on)
            task.depends_on.set(deps)

        # Check if ready to execute
        self._update_task_readiness(task)

        return task

    def create_input_request(
        self,
        mission_id: str,
        task_id: Optional[str],
        prompt: str,
        options: List[Dict] = None,
        allow_freeform: bool = True,
        context: Dict = None,
        urgency: str = "normal",
        expires_in_hours: int = 24,
    ) -> HumanInputRequest:
        """Create a human input request."""
        mission = Mission.objects.get(id=mission_id)

        request = HumanInputRequest.objects.create(
            mission=mission,
            task_id=task_id,
            conversation_id=mission.conversation_id,
            prompt=prompt,
            options=options or [],
            allow_freeform=allow_freeform,
            context=context,
            urgency=urgency,
            expires_at=timezone.now() + timezone.timedelta(hours=expires_in_hours),
        )

        # Update mission/task status
        mission.status = Mission.Status.WAITING
        mission.wait_reason = 'human_input'
        mission.save()

        if task_id:
            MissionTask.objects.filter(id=task_id).update(
                status=MissionTask.Status.WAITING_HUMAN
            )

        # Trigger notification
        self._notify_input_required(request)

        return request

    def respond_to_input(
        self,
        request_id: str,
        response: Dict,
    ) -> HumanInputRequest:
        """Process user response to input request."""
        request = HumanInputRequest.objects.get(id=request_id)

        if request.status != HumanInputRequest.Status.PENDING:
            raise ValueError(f"Request is not pending: {request.status}")

        request.response = response
        request.status = HumanInputRequest.Status.RESPONDED
        request.responded_at = timezone.now()
        request.save()

        # Resume task/mission
        self._resume_after_input(request)

        return request

    def handle_external_event(
        self,
        event_type: str,
        correlation_id: str,
        event_data: Dict,
    ) -> Optional[MissionTask]:
        """Handle incoming external event (email reply, etc.)."""
        task = MissionTask.objects.filter(
            status=MissionTask.Status.WAITING_EXTERNAL,
            external_event_type=event_type,
            external_correlation_id=correlation_id,
        ).first()

        if not task:
            return None

        task.result = event_data
        task.status = MissionTask.Status.COMPLETED
        task.completed_at = timezone.now()
        task.save()

        # Check if mission can resume
        self._check_mission_resume(task.mission)

        return task

    def complete_mission(
        self,
        mission_id: str,
        summary: str,
        outcome: str = "success",
        details: Dict = None,
    ) -> Mission:
        """Mark mission as complete."""
        mission = Mission.objects.get(id=mission_id)

        mission.status = Mission.Status.COMPLETED
        mission.outcome = outcome
        mission.summary = summary
        mission.completed_at = timezone.now()
        mission.save()

        return mission

    def _update_task_readiness(self, task: MissionTask):
        """Check if task dependencies are met and mark ready."""
        if task.status != MissionTask.Status.PENDING:
            return

        deps_complete = all(
            dep.status == MissionTask.Status.COMPLETED
            for dep in task.depends_on.all()
        )

        if deps_complete:
            task.status = MissionTask.Status.READY
            task.save()

    def _check_mission_resume(self, mission: Mission):
        """Check if mission can resume after external event."""
        # Check for any remaining waits
        waiting = mission.tasks.filter(
            status__in=[
                MissionTask.Status.WAITING_HUMAN,
                MissionTask.Status.WAITING_EXTERNAL,
            ]
        ).exists()

        if not waiting:
            mission.status = Mission.Status.EXECUTING
            mission.wait_reason = ''
            mission.save()

            # Trigger agent to resume
            self._trigger_mission_resume(mission)

    def _resume_after_input(self, request: HumanInputRequest):
        """Resume mission after user input."""
        mission = request.mission

        if request.task:
            request.task.status = MissionTask.Status.READY
            request.task.result = request.response
            request.task.save()

        self._check_mission_resume(mission)

    def _notify_input_required(self, request: HumanInputRequest):
        """Send notifications for input request."""
        # TODO: Implement WebSocket push, email notifications
        pass

    def _trigger_mission_resume(self, mission: Mission):
        """Trigger agent to resume mission execution."""
        # TODO: Implement via Celery task or WebSocket
        pass
```

---

## 7. Agent Implementation

### 7.1 Tool Classes

```python
# src/services/tools/mission_tools.py

from typing import Any, Dict, List, Optional
from .base import BaseTool, ToolResult, ToolRegistry


@ToolRegistry.register
class MissionCreateTaskTool(BaseTool):
    """Create a subtask within the current mission."""

    name = "mission_create_task"
    description = (
        "Create a new task within the current mission. Tasks can depend on "
        "other tasks and can wait for external events like email replies."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "title": {
                "type": "string",
                "description": "Short title describing the task"
            },
            "description": {
                "type": "string",
                "description": "Detailed description of what needs to be done"
            },
            "depends_on": {
                "type": "array",
                "items": {"type": "string"},
                "description": "List of task IDs this task depends on"
            },
            "wait_for_external": {
                "type": "boolean",
                "description": "If true, task will wait for external event"
            },
            "external_event_type": {
                "type": "string",
                "enum": ["email_reply", "calendar_response", "webhook"],
                "description": "Type of external event to wait for"
            },
            "timeout_hours": {
                "type": "number",
                "description": "Hours to wait before timing out"
            }
        },
        "required": ["title"]
    }

    async def execute(self, inputs: Dict[str, Any]) -> ToolResult:
        if not self.mission_id:
            return ToolResult(
                success=False,
                error="No active mission. Create a mission first."
            )

        try:
            result = await self.hub_client.post(
                f"/api/internal/missions/{self.mission_id}/tasks",
                json=inputs
            )
            return ToolResult(success=True, data=result)
        except Exception as e:
            return ToolResult(success=False, error=str(e))


@ToolRegistry.register
class MissionAskUserTool(BaseTool):
    """Request input or approval from the user."""

    name = "mission_ask_user"
    description = (
        "Pause execution to request input or approval from the user. "
        "Use this for important decisions, confirmations, or when you need "
        "the user to choose between options."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "prompt": {
                "type": "string",
                "description": "The question or request to show the user"
            },
            "options": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string"},
                        "label": {"type": "string"},
                        "description": {"type": "string"}
                    }
                },
                "description": "Predefined options for the user"
            },
            "allow_freeform": {
                "type": "boolean",
                "description": "Whether user can provide custom response"
            },
            "context": {
                "type": "object",
                "description": "Additional context to display"
            },
            "urgency": {
                "type": "string",
                "enum": ["low", "normal", "high"],
                "description": "Affects notification behavior"
            }
        },
        "required": ["prompt"]
    }

    async def execute(self, inputs: Dict[str, Any]) -> ToolResult:
        if not self.mission_id:
            return ToolResult(
                success=False,
                error="No active mission."
            )

        try:
            result = await self.hub_client.post(
                f"/api/internal/missions/{self.mission_id}/input-requests",
                json=inputs
            )
            return ToolResult(
                success=True,
                data=result,
                requires_approval=True,
                approval_request_id=result.get("request_id")
            )
        except Exception as e:
            return ToolResult(success=False, error=str(e))


@ToolRegistry.register
class MissionCompleteTool(BaseTool):
    """Mark the mission as complete."""

    name = "mission_complete"
    description = (
        "Mark the current mission as complete with a summary of what was "
        "accomplished. Call this when all tasks are done."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "summary": {
                "type": "string",
                "description": "Human-readable summary of what was accomplished"
            },
            "outcome": {
                "type": "string",
                "enum": ["success", "partial", "failed", "cancelled"],
                "description": "Overall outcome of the mission"
            },
            "details": {
                "type": "object",
                "description": "Structured data about results"
            }
        },
        "required": ["summary"]
    }

    async def execute(self, inputs: Dict[str, Any]) -> ToolResult:
        if not self.mission_id:
            return ToolResult(
                success=False,
                error="No active mission."
            )

        try:
            result = await self.hub_client.patch(
                f"/api/internal/missions/{self.mission_id}",
                json={
                    "status": "completed",
                    **inputs
                }
            )
            return ToolResult(success=True, data=result)
        except Exception as e:
            return ToolResult(success=False, error=str(e))
```

### 7.2 Integration with Handler

The Personal Assistant handler initiates missions for complex requests:

```python
# In PersonalAssistantHandler

async def handle_message(self, message: str) -> str:
    """Process incoming user message."""

    # Determine if this requires a mission
    if self._requires_mission(message):
        # Create mission in Hub
        mission = await self.create_mission(
            raw_input=message,
            conversation_id=self.conversation_id,
        )
        self.mission_id = mission["mission_id"]

    # Continue with normal LLM processing
    # LLM will use mission tools if mission is active
    return await self._process_with_llm(message)

def _requires_mission(self, message: str) -> bool:
    """Heuristic to determine if request needs a mission."""
    # Complex requests that need missions:
    # - Multiple steps mentioned
    # - External coordination (email someone, schedule with)
    # - Time-spanning tasks
    # Simple LLM check or keyword detection
    pass
```

---

## 8. Testing

### 8.1 Unit Tests

- [ ] Mission creation with valid agent instance
- [ ] Task creation with dependencies
- [ ] Circular dependency detection
- [ ] Input request creation and expiration
- [ ] Response processing
- [ ] External event matching
- [ ] Task readiness calculation
- [ ] Mission state transitions

### 8.2 Integration Tests

- [ ] Full mission lifecycle (create → tasks → complete)
- [ ] Human-in-the-loop approval flow
- [ ] External wait and resume (mocked email reply)
- [ ] Mission cancellation
- [ ] Timeout handling

### 8.3 E2E Scenarios

- [ ] "Schedule a meeting with John" - calendar + email + approval
- [ ] "Research competitors and create a report" - research + document + approval
- [ ] "Send weekly update to team" - email + wait for replies
- [ ] User cancels mid-mission
- [ ] Approval request expires

---

## 9. Future Considerations

- **Mission Templates**: Pre-defined mission structures for common tasks
- **Recurring Missions**: Schedule missions to run periodically
- **Mission Sharing**: Share mission patterns between users/customers
- **Mission Analytics**: Track success rates, common failures, optimization
- **Parallel Task Execution**: Run independent tasks concurrently
- **Sub-Missions**: Nest missions for very complex workflows
- **Mission Pause/Resume**: User-initiated pause of in-progress missions
- **Mission Delegation**: Transfer mission to another user/agent

---

## 10. Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-01-02 | Initial draft with full architecture | Claude |
