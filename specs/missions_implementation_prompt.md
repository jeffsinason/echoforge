---
title: "Missions Implementation Prompt"
version: "1.0"
created: 2026-01-03
github_issues: [18, 21]
---

# Developer Prompt: Implement Persistent Missions Feature

## Overview

Implement the Missions feature that enables agents to handle complex, multi-step tasks with persistence across conversations, user dashboard visibility, and approval workflows.

**GitHub Issues:** #18 (foundation), #21 (full feature)

**Specs to Reference:**
- `echoforge-hub/docs/specs/persistent_missions.md` - Database models, Hub API, agent tools
- `docs/specs/categories/missions.md` - Full feature spec with UI wireframes, state machines, approval workflows

## Implementation Order

Complete in this sequence - each phase builds on the previous:

---

## Phase 1: Data Models (Issue #18)

**Location:** `backend/apps/agents/models.py`

Create three new models:

**1. Mission Model**
```python
class Mission(CustomerScopedModel):
    """User's mission/goal being worked on by an agent."""

    class Status(models.TextChoices):
        ACTIVE = 'active', 'Active'
        PAUSED = 'paused', 'Paused'
        WAITING = 'waiting', 'Waiting for External'
        COMPLETED = 'completed', 'Completed'
        CANCELLED = 'cancelled', 'Cancelled'
        FAILED = 'failed', 'Failed'

    class Priority(models.TextChoices):
        LOW = 'low', 'Low'
        NORMAL = 'normal', 'Normal'
        HIGH = 'high', 'High'
        URGENT = 'urgent', 'Urgent'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)

    # User-scoped (not agent-scoped) - critical design decision
    user = models.ForeignKey('customers.CustomerUser', on_delete=models.CASCADE, related_name='missions')

    # Origin tracking
    created_by_agent = models.ForeignKey('agents.AgentInstance', on_delete=models.SET_NULL, null=True, related_name='created_missions')
    origin_conversation_id = models.CharField(max_length=255)

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE)
    priority = models.CharField(max_length=20, choices=Priority.choices, default=Priority.NORMAL)

    due_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    # Blocking info
    blocked_by = models.CharField(max_length=255, blank=True)
    blocked_since = models.DateTimeField(null=True, blank=True)

    # Autonomous execution
    can_run_autonomously = models.BooleanField(default=False)
    last_autonomous_check = models.DateTimeField(null=True, blank=True)
```

**2. MissionTask Model**
```python
class MissionTask(BaseModel):
    """Individual task within a mission."""

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        IN_PROGRESS = 'in_progress', 'In Progress'
        BLOCKED = 'blocked', 'Blocked'
        COMPLETED = 'completed', 'Completed'
        SKIPPED = 'skipped', 'Skipped'

    mission = models.ForeignKey(Mission, on_delete=models.CASCADE, related_name='tasks')
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)
    order = models.IntegerField(default=0)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    blocked_by = models.CharField(max_length=255, blank=True)
    blocked_reason = models.TextField(blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    result = models.JSONField(default=dict, blank=True)
```

**3. MissionEvent Model**
```python
class MissionEvent(BaseModel):
    """Key events and message snapshots for mission history."""

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

    mission = models.ForeignKey(Mission, on_delete=models.CASCADE, related_name='events')
    event_type = models.CharField(max_length=30, choices=EventType.choices)
    conversation_id = models.CharField(max_length=255, blank=True)
    agent_id = models.UUIDField(null=True, blank=True)
    title = models.CharField(max_length=500, blank=True)
    content = models.TextField(blank=True)
    metadata = models.JSONField(default=dict, blank=True)
```

**Tasks:**
- [ ] Add models to `backend/apps/agents/models.py`
- [ ] Generate migrations: `python manage.py makemigrations agents`
- [ ] Run migrations: `python manage.py migrate`
- [ ] Add admin interfaces in `backend/apps/agents/admin.py`

---

## Phase 2: Hub API Endpoints (Issue #18)

**Location:** `backend/api/internal/missions.py` (new file)

Create REST endpoints for agent-to-Hub communication:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/internal/missions` | List user's missions |
| POST | `/api/internal/missions` | Create new mission |
| GET | `/api/internal/missions/{id}` | Get mission with tasks + events |
| PATCH | `/api/internal/missions/{id}` | Update mission status |
| POST | `/api/internal/missions/{id}/tasks` | Add task |
| PATCH | `/api/internal/missions/{id}/tasks/{task_id}` | Update task |
| POST | `/api/internal/missions/{id}/events` | Log event |
| POST | `/api/internal/missions/{id}/resume` | Resume mission |

**Query Parameters for GET /missions:**
```
?status=active,waiting      # Filter by status
?priority=high,urgent       # Filter by priority
?include_tasks=true         # Include tasks in response
?include_recent_events=5    # Include N most recent events
```

**Tasks:**
- [ ] Create `backend/api/internal/missions.py` with ViewSet
- [ ] Create `backend/api/internal/serializers/missions.py`
- [ ] Add routes to `backend/api/internal/urls.py`
- [ ] Add authentication (require valid agent auth header)
- [ ] Write API tests

---

## Phase 3: Agent Mission Tools (Issue #18)

**Location:** `echoforge-agent/src/services/tools/mission_tools.py`

Replace Redis-based tools with Hub-backed tools:

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

**Hub Client Methods:** Add to `echoforge-agent/src/services/hub_client.py`:
```python
async def list_missions(self, status: List[str] = None, include_tasks: bool = True) -> Dict
async def create_mission(self, title: str, description: str = "", priority: str = "normal") -> Dict
async def get_mission(self, mission_id: str, include_events: int = 5) -> Dict
async def update_mission(self, mission_id: str, **kwargs) -> Dict
async def add_mission_task(self, mission_id: str, title: str, **kwargs) -> Dict
async def update_mission_task(self, mission_id: str, task_id: str, **kwargs) -> Dict
async def log_mission_event(self, mission_id: str, event_type: str, **kwargs) -> Dict
async def resume_mission(self, mission_id: str) -> Dict
```

**Critical:** Remove Redis-based mission storage. Hub database is now the source of truth.

**Tasks:**
- [ ] Add Hub client methods
- [ ] Rewrite mission tools to use Hub API
- [ ] Remove Redis keys: `mission:{agent_id}:{conversation_id}:*`
- [ ] Update agent prompts to describe new cross-conversation capabilities
- [ ] Write integration tests

---

## Phase 4: HumanInputRequest Model (Issue #21)

**Location:** `backend/apps/agents/models.py`

```python
class HumanInputRequest(BaseModel):
    """Pending request for human input/approval."""

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        RESPONDED = 'responded', 'Responded'
        EXPIRED = 'expired', 'Expired'
        CANCELLED = 'cancelled', 'Cancelled'

    class Urgency(models.TextChoices):
        LOW = 'low', 'Low'
        NORMAL = 'normal', 'Normal'
        HIGH = 'high', 'High'

    mission = models.ForeignKey(Mission, on_delete=models.CASCADE, related_name='input_requests')
    task = models.ForeignKey(MissionTask, on_delete=models.CASCADE, null=True, blank=True)
    conversation_id = models.UUIDField(db_index=True)

    prompt = models.TextField()
    options = models.JSONField(default=list)
    allow_freeform = models.BooleanField(default=True)
    context = models.JSONField(null=True, blank=True)
    urgency = models.CharField(max_length=10, choices=Urgency.choices, default=Urgency.NORMAL)

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    response = models.JSONField(null=True, blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField()
```

---

## Phase 5: Mission State Machine (Issue #21)

Implement state transitions per `docs/specs/categories/missions.md` Section 4.1:

```
(none) → planning → executing → waiting → completed
                  ↘          ↗         ↘ failed
                    ← replan ←
```

**Task State Machine:**
```
pending → ready → in_progress → completed
                             ↘ waiting_human → in_progress
                             ↘ waiting_external → in_progress
                             ↘ failed
```

---

## Phase 6: Autonomous Execution (Issue #18)

**Location:** `backend/apps/agents/tasks.py`

```python
@shared_task
def check_autonomous_missions():
    """Periodic task to check and progress autonomous missions."""
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

Register in `backend/echoforge_hub/celery.py` to run every 5 minutes.

---

## Phase 7: Email Integration (Issue #21)

Connect email reply tracking (Issue #20, already implemented) to mission blockers:

**When email reply received:**
1. Check if any mission task is blocked by `email_reply:{tracking_id}`
2. If found, update task status and unblock
3. Check if mission can resume (all blockers resolved)
4. If `all_replied` status reached, auto-progress mission

**Location:** Modify `backend/apps/integrations/services/gmail.py` `check_replies()` to call mission service.

---

## Acceptance Criteria

### Issue #18 - Persistent Missions:
- [ ] Mission, MissionTask, MissionEvent models created
- [ ] Hub API endpoints functional with auth
- [ ] Agent tools use Hub API (not Redis)
- [ ] Cross-conversation test passes:
  - Create mission in conversation A
  - Start conversation B
  - `mission_list` returns mission from A
  - `mission_resume` loads full context

### Issue #21 - Full Missions:
- [ ] HumanInputRequest model with approval workflow
- [ ] State machines implemented correctly
- [ ] `mission_ask_user` tool pauses execution
- [ ] User can respond via API
- [ ] Mission resumes after approval
- [ ] Email reply unblocks waiting tasks
- [ ] Autonomous execution works for eligible missions

---

## Testing Commands

```bash
# Run migrations
cd echoforge-hub/backend
python manage.py makemigrations agents
python manage.py migrate

# Test API
curl -X POST http://localhost:8003/api/internal/missions \
  -H "Authorization: Bearer $HUB_SERVICE_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Mission", "user_id": "uuid", "agent_id": "uuid", "conversation_id": "test-123"}'

# Test cross-conversation
# In conversation A:
curl -X POST http://localhost:8004/v1/chat \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"message": "Create a mission to schedule meeting with John", "conversation_id": "conv-A"}'

# In conversation B:
curl -X POST http://localhost:8004/v1/chat \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"message": "What are my current tasks?", "conversation_id": "conv-B"}'
# Should return mission from conv-A
```

---

## Key Files to Create/Modify

| File | Action |
|------|--------|
| `backend/apps/agents/models.py` | Add Mission, MissionTask, MissionEvent, HumanInputRequest |
| `backend/apps/agents/admin.py` | Add admin interfaces |
| `backend/apps/agents/tasks.py` | Add Celery tasks for autonomous execution |
| `backend/api/internal/missions.py` | New - mission API viewset |
| `backend/api/internal/serializers/missions.py` | New - serializers |
| `backend/api/internal/urls.py` | Add mission routes |
| `echoforge-agent/src/services/tools/mission_tools.py` | Rewrite with Hub-backed tools |
| `echoforge-agent/src/services/hub_client.py` | Add mission API methods |

---

## Dependencies

- Django 5.2 (existing)
- Celery (existing)
- PostgreSQL (existing)
- Issue #20 Multi-Reply Email Tracking (complete ✅)
