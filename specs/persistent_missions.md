---
title: Persistent Missions with Cross-Conversation Visibility
version: "1.0"
status: draft
project: echoforge-hub
created: 2026-01-03
updated: 2026-01-03
github_issue: 18
---

# 1. Executive Summary

Move mission/task storage from conversation-scoped Redis to a persistent Hub database. This enables:
- Users can see ALL active missions across conversations
- Agents can resume missions started in previous conversations
- Missions can run autonomously and notify users of progress
- Full mission history with key message snapshots

# 2. Current System State

## 2.1 Existing Architecture

Missions are stored in Redis with conversation-scoped keys:

```python
# echoforge-agent/src/services/tools/mission_tools.py
def _get_tasks_key(agent_id: str, conversation_id: str) -> str:
    return f"mission:{agent_id}:{conversation_id}:tasks"

def _get_mission_key(agent_id: str, conversation_id: str) -> str:
    return f"mission:{agent_id}:{conversation_id}:meta"
```

**Location:** `echoforge-agent/src/services/tools/mission_tools.py` lines 20-27

## 2.2 Current Limitations

1. **No cross-conversation visibility** - Each conversation has isolated mission storage
2. **No persistence** - Redis data can be lost; no long-term history
3. **No autonomous execution** - Missions only progress during active conversations
4. **Agent-scoped** - Can't see missions across different agent instances

## 2.3 Current Mission Tools

| Tool | Purpose |
|------|---------|
| `mission_create_task` | Create a task in current conversation |
| `mission_ask_user` | Request user input |
| `mission_complete` | Mark current mission complete |

**Missing:** `mission_list_all`, `mission_resume`, `mission_get_status`

# 3. Feature Requirements

## 3.1 Mission Model (Hub Database)

**Description:** New Django model to persist missions with full history.

### Model Definition

```python
class Mission(CustomerScopedModel):
    """
    A user's mission/goal being worked on by an agent.

    Missions persist across conversations and can run autonomously.
    """
    class Status(models.TextChoices):
        ACTIVE = 'active', 'Active'
        PAUSED = 'paused', 'Paused'
        WAITING = 'waiting', 'Waiting for External'  # e.g., waiting for email reply
        COMPLETED = 'completed', 'Completed'
        CANCELLED = 'cancelled', 'Cancelled'
        FAILED = 'failed', 'Failed'

    class Priority(models.TextChoices):
        LOW = 'low', 'Low'
        NORMAL = 'normal', 'Normal'
        HIGH = 'high', 'High'
        URGENT = 'urgent', 'Urgent'

    # Identity
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)

    # Ownership - user-scoped (not agent-scoped)
    user = models.ForeignKey(
        'customers.CustomerUser',
        on_delete=models.CASCADE,
        related_name='missions'
    )

    # Origin tracking
    created_by_agent = models.ForeignKey(
        'agents.AgentInstance',
        on_delete=models.SET_NULL,
        null=True,
        related_name='created_missions'
    )
    origin_conversation_id = models.CharField(
        max_length=255,
        help_text="Conversation where mission was created"
    )

    # Status
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE
    )
    priority = models.CharField(
        max_length=20,
        choices=Priority.choices,
        default=Priority.NORMAL
    )

    # Timing
    due_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    # Blocking info (when status=WAITING)
    blocked_by = models.CharField(
        max_length=255,
        blank=True,
        help_text="What this mission is waiting for (e.g., 'email_reply:tracking_id')"
    )
    blocked_since = models.DateTimeField(null=True, blank=True)

    # Autonomous execution
    can_run_autonomously = models.BooleanField(
        default=False,
        help_text="Whether this mission can progress without user interaction"
    )
    last_autonomous_check = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['status', 'blocked_by']),
        ]

    def __str__(self):
        return f"{self.title} ({self.status})"
```

### Files to Create/Modify

| File | Action |
|------|--------|
| `backend/apps/agents/models.py` | Add `Mission` model |
| `backend/apps/agents/admin.py` | Add admin for missions |

## 3.2 MissionTask Model

**Description:** Individual tasks within a mission.

### Model Definition

```python
class MissionTask(BaseModel):
    """
    Individual task within a mission.
    """
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        IN_PROGRESS = 'in_progress', 'In Progress'
        BLOCKED = 'blocked', 'Blocked'
        COMPLETED = 'completed', 'Completed'
        SKIPPED = 'skipped', 'Skipped'

    mission = models.ForeignKey(
        Mission,
        on_delete=models.CASCADE,
        related_name='tasks'
    )

    # Task details
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)
    order = models.IntegerField(default=0)

    # Status
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING
    )

    # Blocking info
    blocked_by = models.CharField(max_length=255, blank=True)
    blocked_reason = models.TextField(blank=True)

    # Completion
    completed_at = models.DateTimeField(null=True, blank=True)
    result = models.JSONField(
        default=dict,
        blank=True,
        help_text="Result/output from completing this task"
    )

    class Meta:
        ordering = ['mission', 'order']

    def __str__(self):
        return f"{self.title} ({self.status})"
```

## 3.3 MissionEvent Model

**Description:** Key message snapshots and events for mission history.

### Model Definition

```python
class MissionEvent(BaseModel):
    """
    Key events and message snapshots for a mission.

    Stores important moments rather than full conversation transcript.
    """
    class EventType(models.TextChoices):
        CREATED = 'created', 'Mission Created'
        TASK_ADDED = 'task_added', 'Task Added'
        TASK_COMPLETED = 'task_completed', 'Task Completed'
        STATUS_CHANGED = 'status_changed', 'Status Changed'
        USER_MESSAGE = 'user_message', 'User Message'
        AGENT_MESSAGE = 'agent_message', 'Agent Message'
        EXTERNAL_EVENT = 'external_event', 'External Event'
        RESUMED = 'resumed', 'Mission Resumed'
        BLOCKED = 'blocked', 'Mission Blocked'
        COMPLETED = 'completed', 'Mission Completed'

    mission = models.ForeignKey(
        Mission,
        on_delete=models.CASCADE,
        related_name='events'
    )

    event_type = models.CharField(max_length=30, choices=EventType.choices)

    # Context
    conversation_id = models.CharField(max_length=255, blank=True)
    agent_id = models.UUIDField(null=True, blank=True)

    # Content
    title = models.CharField(max_length=500, blank=True)
    content = models.TextField(blank=True, help_text="Message content or event details")
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"{self.event_type} at {self.created_at}"
```

## 3.4 Hub API Endpoints

**Description:** Internal API for agent to manage missions.

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/internal/missions` | List user's missions |
| POST | `/api/internal/missions` | Create new mission |
| GET | `/api/internal/missions/{id}` | Get mission details + tasks |
| PATCH | `/api/internal/missions/{id}` | Update mission status |
| POST | `/api/internal/missions/{id}/tasks` | Add task to mission |
| PATCH | `/api/internal/missions/{id}/tasks/{task_id}` | Update task |
| POST | `/api/internal/missions/{id}/events` | Log event |
| POST | `/api/internal/missions/{id}/resume` | Resume mission in current conversation |

### Query Parameters for GET /missions

```
?status=active,waiting      # Filter by status (comma-separated)
?priority=high,urgent       # Filter by priority
?include_tasks=true         # Include tasks in response
?include_recent_events=5    # Include N most recent events
```

### Response Format

```json
{
  "missions": [
    {
      "id": "uuid",
      "title": "Schedule Zoom call with Brian and Jeff",
      "status": "waiting",
      "priority": "normal",
      "created_at": "2026-01-03T10:00:00Z",
      "blocked_by": "email_reply",
      "blocked_since": "2026-01-03T10:30:00Z",
      "tasks": [
        {
          "id": "uuid",
          "title": "Send availability request",
          "status": "completed",
          "completed_at": "2026-01-03T10:30:00Z"
        },
        {
          "id": "uuid",
          "title": "Wait for confirmations",
          "status": "in_progress",
          "blocked_by": "email_reply:tracking_123"
        },
        {
          "id": "uuid",
          "title": "Create calendar event",
          "status": "pending"
        }
      ],
      "recent_events": [
        {
          "event_type": "blocked",
          "title": "Waiting for email replies",
          "created_at": "2026-01-03T10:30:00Z"
        }
      ]
    }
  ]
}
```

### Files to Create

| File | Action |
|------|--------|
| `backend/api/internal/missions.py` | New viewset for mission endpoints |
| `backend/api/internal/serializers/missions.py` | Serializers |
| `backend/api/internal/urls.py` | Add mission routes |

## 3.5 Agent Mission Tools (Updated)

**Description:** New and updated tools for mission management.

### New Tools

| Tool | Purpose |
|------|---------|
| `mission_list` | List all user's missions (cross-conversation) |
| `mission_get` | Get specific mission with tasks and recent events |
| `mission_create` | Create new mission (persisted to Hub) |
| `mission_update` | Update mission status/priority |
| `mission_add_task` | Add task to existing mission |
| `mission_update_task` | Update task status/result |
| `mission_log_event` | Log important event/message |
| `mission_resume` | Resume mission, loading context |

### Tool Definitions

```python
@ToolRegistry.register
class MissionListTool(ToolHandler):
    name = "mission_list"
    description = """List all of the user's missions across all conversations.
    Shows active, waiting, and recent completed missions with their tasks."""
    category = "mission"

    input_schema = {
        "type": "object",
        "properties": {
            "status": {
                "type": "array",
                "items": {"type": "string", "enum": ["active", "waiting", "paused", "completed"]},
                "description": "Filter by status (default: active, waiting)"
            },
            "include_tasks": {
                "type": "boolean",
                "default": True,
                "description": "Include task list for each mission"
            }
        }
    }


@ToolRegistry.register
class MissionResumeTool(ToolHandler):
    name = "mission_resume"
    description = """Resume working on a mission from a previous conversation.
    Loads the mission context, tasks, and recent events to continue where we left off."""
    category = "mission"

    input_schema = {
        "type": "object",
        "properties": {
            "mission_id": {
                "type": "string",
                "description": "UUID of the mission to resume"
            }
        },
        "required": ["mission_id"]
    }
```

### Files to Create/Modify

| File | Action |
|------|--------|
| `echoforge-agent/src/services/tools/mission_tools.py` | Rewrite with Hub-backed tools |
| `echoforge-agent/src/services/hub_client.py` | Add mission API methods |

## 3.6 Autonomous Mission Execution

**Description:** Background worker to progress missions that can run autonomously.

### Celery Task

```python
@shared_task
def check_autonomous_missions():
    """
    Periodic task to check and progress autonomous missions.

    Runs every 5 minutes. Checks:
    - Missions with can_run_autonomously=True
    - Missions in 'waiting' status where blocker is resolved
    """
    # Find missions that might be able to progress
    missions = Mission.objects.filter(
        status__in=['active', 'waiting'],
        can_run_autonomously=True,
        last_autonomous_check__lt=timezone.now() - timedelta(minutes=5)
    )

    for mission in missions:
        try:
            progress_mission_autonomously(mission)
        except Exception as e:
            logger.error(f"Autonomous mission error: {mission.id}", exc_info=e)
```

### Files to Create

| File | Action |
|------|--------|
| `backend/apps/agents/tasks.py` | Add Celery tasks |
| `backend/echoforge_hub/celery.py` | Register periodic task |

# 4. Future Considerations (Out of Scope)

- **Mission templates:** Pre-defined mission structures for common tasks
- **Mission sharing:** Share missions between users
- **Mission dependencies:** Missions that depend on other missions
- **Scheduled missions:** Missions that start at a specific time
- **Mission analytics:** Dashboard showing mission completion rates, common blockers

# 5. Implementation Approach

## 5.1 Phases

**Phase 1: Data Models**
1. Create Mission, MissionTask, MissionEvent models
2. Generate migrations
3. Add admin interfaces

**Phase 2: Hub API**
1. Create mission API endpoints
2. Add serializers
3. Add to internal API router
4. Test endpoints

**Phase 3: Agent Tools**
1. Create new Hub-backed mission tools
2. Add Hub client methods for mission API
3. Remove Redis-based mission storage
4. Update agent prompts to use new tools

**Phase 4: Autonomous Execution**
1. Create Celery task for mission checking
2. Add blocker resolution logic
3. Add user notification for mission progress

**Phase 5: Integration**
1. Connect email reply tracking to mission blockers
2. Connect calendar events to mission completion
3. End-to-end testing

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| Django 5.2 | Existing |
| Celery | Existing (for Hub) |
| PostgreSQL | Existing |

## 5.3 Testing Plan

1. Unit tests for Mission models
2. API tests for mission endpoints
3. Integration tests for agent tools
4. Test mission resume flow (create in conv A, resume in conv B)
5. Test autonomous execution with email reply trigger
6. Load test with many concurrent missions

# 6. Acceptance Criteria

## 6.1 Data Models

- [ ] Mission model created with all fields
- [ ] MissionTask model with ordering and status
- [ ] MissionEvent model for history tracking
- [ ] Migrations run without errors
- [ ] Admin interfaces functional

## 6.2 Hub API

- [ ] GET /missions returns user's missions across all conversations
- [ ] POST /missions creates mission persisted to database
- [ ] PATCH /missions/{id} updates status
- [ ] POST /missions/{id}/tasks adds task
- [ ] POST /missions/{id}/resume loads context for current conversation
- [ ] Proper authentication/authorization

## 6.3 Agent Tools

- [ ] `mission_list` returns all user missions (not just current conversation)
- [ ] `mission_create` persists to Hub database
- [ ] `mission_resume` loads mission context and continues
- [ ] `mission_log_event` snapshots key messages
- [ ] Redis storage removed (Hub is source of truth)

## 6.4 Cross-Conversation Flow

- [ ] User creates mission in conversation A
- [ ] User starts new conversation B
- [ ] User asks "what are my tasks?" and sees mission from A
- [ ] Agent can resume and continue mission from A

## 6.5 Autonomous Execution

- [ ] Missions can be marked as autonomous
- [ ] Background task checks for blocker resolution
- [ ] Mission progresses when email reply received
- [ ] User notified of autonomous progress

## 6.6 Integration

- [ ] Email reply tracking can unblock waiting missions
- [ ] Mission status reflects when all replies received
- [ ] Calendar creation can mark tasks complete

---

*End of Specification*
