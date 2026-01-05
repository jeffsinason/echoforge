---
title: "Unified Missions Fix - Agent Tools & Dashboard UI"
version: "1.0"
status: in-development
project: EchoForge
created: 2026-01-03
updated: 2026-01-04
github_issues: [11, 12, 13, 18, 21]
---

# Unified Missions Fix

## Executive Summary

This spec addresses multiple interconnected issues blocking the missions feature:

| Issue | Problem | Solution |
|-------|---------|----------|
| #11, #12 | Agent has hardcoded tool list with wrong names | Use Hub config's `enabled_actions` |
| #18 | Mission tools not working | Tool names in hardcoded list don't match actual tools |
| #21 | No dashboard UI for missions | Create Django templates |

**Root Cause:** `PERSONAL_ASSISTANT_TOOLS` in `personal_assistant.py` is hardcoded and out of sync with actual tool implementations.

---

## Current State Analysis

### What EXISTS and WORKS

**Hub (echoforge-hub):**
- ✅ Models: `Mission`, `MissionTask`, `MissionEvent`, `HumanInputRequest` (models.py:428-840)
- ✅ API endpoints: `/api/internal/missions/*` with full CRUD
- ✅ Serializers: Complete request/response schemas
- ✅ `ToolCategory` model with mission tools defined

**Agent (echoforge-agent):**
- ✅ Mission tools implemented in `mission_tools.py`:
  - `mission_create` (line 22)
  - `mission_add_task` (line 117)
  - `mission_update_task` (line 225)
  - `mission_ask_user` (line 321)
  - `mission_complete` (line 445)
  - `mission_get_status` (line 538)
  - `mission_list` (line 621) ← EXISTS!
  - `mission_log_event` (line 695)

### What's BROKEN

**Agent `personal_assistant.py` lines 22-49:**
```python
PERSONAL_ASSISTANT_TOOLS = [
    # Mission management - WRONG NAMES!
    "mission_create_task",  # ❌ Should be: mission_create, mission_add_task
    "mission_ask_user",     # ✅ Correct
    "mission_complete",     # ✅ Correct
    # ... rest of list
]
```

**Missing from hardcoded list:**
- `mission_create`
- `mission_list` ← Why "what are my missions?" fails
- `mission_get_status`
- `mission_add_task`
- `mission_update_task`
- `mission_log_event`

### What's MISSING

**Hub Templates:**
- No `/dashboard/missions/` template
- No `/dashboard/missions/{id}/` template

---

## Fix 1: Remove Hardcoded Tool List (Issues #11, #12)

### Problem
`personal_assistant.py` line 100:
```python
tools_enabled = PERSONAL_ASSISTANT_TOOLS  # Hardcoded, out of sync
```

### Solution
Use `config.actions_enabled` from Hub instead:

**File:** `echoforge-agent/src/services/agent_types/personal_assistant.py`

**Before:**
```python
# All tools available for personal assistant
PERSONAL_ASSISTANT_TOOLS = [
    "mission_create_task",
    "mission_ask_user",
    # ... 30+ hardcoded tools
]

@register_agent_type
class PersonalAssistantHandler(AgentTypeHandler):
    agent_type = "personal_assistant"
    tools_enabled = PERSONAL_ASSISTANT_TOOLS  # ❌ Hardcoded
```

**After:**
```python
# Remove PERSONAL_ASSISTANT_TOOLS constant entirely

@register_agent_type
class PersonalAssistantHandler(AgentTypeHandler):
    agent_type = "personal_assistant"

    def __init__(self, config, hub_client, ...):
        super().__init__(config, hub_client, ...)
        # Get tools from Hub config
        self.tools_enabled = config.actions_enabled  # ✅ From Hub
```

### Verification
```python
# config.actions_enabled should contain:
[
    "mission_create",
    "mission_list",
    "mission_add_task",
    "mission_update_task",
    "mission_ask_user",
    "mission_complete",
    "mission_get_status",
    "mission_log_event",
    "calendar_list_events",
    "email_send",
    # ... etc
]
```

---

## Fix 2: Update Hub Tool Categories Seed (Issue #11 related)

Ensure the `missions` category in Hub has correct tool names:

**File:** `echoforge-hub/backend/apps/agents/management/commands/seed_tool_categories.py`

```python
{
    "slug": "missions",
    "name": "Missions",
    "category_type": "capability",
    "tools": [
        "mission_create",
        "mission_list",
        "mission_add_task",
        "mission_update_task",
        "mission_ask_user",
        "mission_complete",
        "mission_get_status",
        "mission_log_event",
    ],
    "billing_type": "addon",
    "min_plan_tier": "pro",
}
```

**Run after updating:**
```bash
python manage.py seed_tool_categories
```

---

## Fix 3: Verify Hub Client Methods (Issue #18)

**File:** `echoforge-agent/src/services/hub_client.py`

Ensure these methods exist and work:

| Method | Endpoint | Status |
|--------|----------|--------|
| `list_missions()` | GET `/api/internal/missions` | Verify |
| `get_mission()` | GET `/api/internal/missions/{id}` | Verify |
| `create_mission()` | POST `/api/internal/missions` | Verify |
| `update_mission()` | PATCH `/api/internal/missions/{id}` | Verify |
| `add_task()` | POST `/api/internal/missions/{id}/tasks` | Verify |
| `update_task()` | PATCH `/api/internal/missions/{id}/tasks/{task_id}` | Verify |
| `log_event()` | POST `/api/internal/missions/{id}/events` | Verify |
| `create_input_request()` | POST `/api/internal/missions/{id}/input-requests` | Verify |

---

## Fix 4: Create Dashboard Templates (Issue #21)

### Mission List Template

**File:** `echoforge-hub/backend/templates/agents/mission_list.html`

```html
{% extends "dashboard_base.html" %}
{% block title %}Missions{% endblock %}

{% block content %}
<div class="container mx-auto px-4 py-6">
    <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Missions</h1>
        <div class="flex gap-2">
            <select id="statusFilter" class="border rounded px-3 py-2">
                <option value="">All Status</option>
                <option value="active">Active</option>
                <option value="waiting">Waiting</option>
                <option value="completed">Completed</option>
            </select>
        </div>
    </div>

    <!-- Needs Attention Section -->
    {% if pending_missions %}
    <div class="mb-8">
        <h2 class="text-lg font-semibold text-red-600 mb-4">
            ⚠️ Needs Attention ({{ pending_missions|length }})
        </h2>
        <div class="space-y-4">
            {% for mission in pending_missions %}
            <div class="bg-white border-l-4 border-red-500 shadow rounded-lg p-4">
                <div class="flex justify-between items-start">
                    <div>
                        <h3 class="font-semibold">{{ mission.title }}</h3>
                        <p class="text-sm text-gray-600">
                            Waiting for your input since {{ mission.blocked_since|timesince }}
                        </p>
                    </div>
                    <a href="{% url 'mission_detail' mission.id %}"
                       class="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700">
                        Respond Now
                    </a>
                </div>
                <!-- Task Progress -->
                <div class="mt-3">
                    {% for task in mission.tasks.all %}
                    <div class="flex items-center gap-2 text-sm">
                        {% if task.status == 'completed' %}
                            <span class="text-green-600">✅</span>
                        {% elif task.status == 'waiting_human' %}
                            <span class="text-red-600">🛑</span>
                        {% elif task.status == 'in_progress' %}
                            <span class="text-blue-600">🔄</span>
                        {% else %}
                            <span class="text-gray-400">⬚</span>
                        {% endif %}
                        {{ task.title }}
                    </div>
                    {% endfor %}
                </div>
            </div>
            {% endfor %}
        </div>
    </div>
    {% endif %}

    <!-- Active Missions -->
    <div class="mb-8">
        <h2 class="text-lg font-semibold mb-4">🔄 In Progress ({{ active_missions|length }})</h2>
        <div class="space-y-4">
            {% for mission in active_missions %}
            <div class="bg-white shadow rounded-lg p-4">
                <a href="{% url 'mission_detail' mission.id %}" class="block">
                    <div class="flex justify-between items-start">
                        <div>
                            <h3 class="font-semibold">{{ mission.title }}</h3>
                            <p class="text-sm text-gray-500">
                                Started {{ mission.created_at|timesince }} ago
                            </p>
                        </div>
                        <span class="text-sm bg-blue-100 text-blue-800 px-2 py-1 rounded">
                            {{ mission.get_status_display }}
                        </span>
                    </div>
                    <!-- Progress bar -->
                    <div class="mt-3 bg-gray-200 rounded-full h-2">
                        <div class="bg-blue-600 h-2 rounded-full"
                             style="width: {{ mission.progress_percent }}%"></div>
                    </div>
                    <p class="text-xs text-gray-500 mt-1">
                        {{ mission.completed_task_count }}/{{ mission.task_count }} tasks
                    </p>
                </a>
            </div>
            {% empty %}
            <p class="text-gray-500">No active missions</p>
            {% endfor %}
        </div>
    </div>

    <!-- Completed Missions -->
    <div>
        <h2 class="text-lg font-semibold mb-4">✅ Recently Completed</h2>
        <div class="space-y-2">
            {% for mission in completed_missions %}
            <div class="bg-gray-50 rounded-lg p-3 flex justify-between items-center">
                <div>
                    <span class="text-green-600">✅</span>
                    <span class="ml-2">{{ mission.title }}</span>
                </div>
                <span class="text-sm text-gray-500">{{ mission.completed_at|timesince }} ago</span>
            </div>
            {% empty %}
            <p class="text-gray-500">No completed missions</p>
            {% endfor %}
        </div>
    </div>
</div>
{% endblock %}
```

### Mission Detail Template

**File:** `echoforge-hub/backend/templates/agents/mission_detail.html`

```html
{% extends "dashboard_base.html" %}
{% block title %}{{ mission.title }}{% endblock %}

{% block content %}
<div class="container mx-auto px-4 py-6">
    <!-- Header -->
    <div class="mb-6">
        <a href="{% url 'mission_list' %}" class="text-blue-600 hover:underline">
            ← Back to Missions
        </a>
        <h1 class="text-2xl font-bold mt-2">{{ mission.title }}</h1>
        <div class="flex items-center gap-4 mt-2">
            <span class="px-3 py-1 rounded-full text-sm
                {% if mission.status == 'active' %}bg-blue-100 text-blue-800
                {% elif mission.status == 'waiting' %}bg-yellow-100 text-yellow-800
                {% elif mission.status == 'completed' %}bg-green-100 text-green-800
                {% else %}bg-gray-100 text-gray-800{% endif %}">
                {{ mission.get_status_display }}
            </span>
            <span class="text-sm text-gray-500">
                Started {{ mission.created_at|date:"M d, Y g:i A" }}
            </span>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Tasks Column -->
        <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-lg font-semibold mb-4">Tasks</h2>
                <div class="space-y-4">
                    {% for task in mission.tasks.all %}
                    <div class="border-l-4 pl-4 py-2
                        {% if task.status == 'completed' %}border-green-500
                        {% elif task.status == 'in_progress' %}border-blue-500
                        {% elif task.status == 'waiting_human' %}border-red-500
                        {% elif task.status == 'waiting_external' %}border-yellow-500
                        {% else %}border-gray-300{% endif %}">
                        <div class="flex items-start justify-between">
                            <div>
                                <div class="flex items-center gap-2">
                                    {% if task.status == 'completed' %}
                                        <span class="text-green-600">✅</span>
                                    {% elif task.status == 'waiting_human' %}
                                        <span class="text-red-600">🛑</span>
                                    {% elif task.status == 'waiting_external' %}
                                        <span class="text-yellow-600">⏳</span>
                                    {% elif task.status == 'in_progress' %}
                                        <span class="text-blue-600">🔄</span>
                                    {% else %}
                                        <span class="text-gray-400">⬚</span>
                                    {% endif %}
                                    <span class="font-medium">{{ task.title }}</span>
                                </div>
                                {% if task.description %}
                                <p class="text-sm text-gray-600 mt-1">{{ task.description }}</p>
                                {% endif %}
                                {% if task.completed_at %}
                                <p class="text-xs text-gray-500 mt-1">
                                    Completed {{ task.completed_at|date:"M d g:i A" }}
                                </p>
                                {% endif %}
                                {% if task.blocked_by %}
                                <p class="text-xs text-yellow-600 mt-1">
                                    Waiting for: {{ task.blocked_by }}
                                </p>
                                {% endif %}
                            </div>
                        </div>
                    </div>
                    {% endfor %}
                </div>
            </div>

            <!-- Pending Approval -->
            {% if pending_inputs %}
            <div class="bg-white shadow rounded-lg p-6 mt-6 border-2 border-red-500">
                <h2 class="text-lg font-semibold text-red-600 mb-4">
                    🔔 Approval Required
                </h2>
                {% for input_request in pending_inputs %}
                <div class="mb-4">
                    <p class="font-medium">{{ input_request.prompt }}</p>
                    {% if input_request.options %}
                    <div class="mt-3 space-y-2">
                        {% for option in input_request.options %}
                        <form method="post" action="{% url 'respond_to_input' input_request.id %}">
                            {% csrf_token %}
                            <input type="hidden" name="selected_option" value="{{ option.id }}">
                            <button type="submit"
                                    class="w-full text-left p-3 border rounded-lg hover:bg-gray-50">
                                <span class="font-medium">{{ option.label }}</span>
                                {% if option.description %}
                                <span class="text-sm text-gray-600 block">{{ option.description }}</span>
                                {% endif %}
                            </button>
                        </form>
                        {% endfor %}
                    </div>
                    {% endif %}
                    {% if input_request.allow_freeform %}
                    <form method="post" action="{% url 'respond_to_input' input_request.id %}" class="mt-3">
                        {% csrf_token %}
                        <textarea name="freeform_text" rows="2"
                                  class="w-full border rounded-lg p-2"
                                  placeholder="Or type a custom response..."></textarea>
                        <button type="submit"
                                class="mt-2 bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
                            Submit Response
                        </button>
                    </form>
                    {% endif %}
                </div>
                {% endfor %}
            </div>
            {% endif %}
        </div>

        <!-- Activity Log Column -->
        <div>
            <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-lg font-semibold mb-4">Activity Log</h2>
                <div class="space-y-3">
                    {% for event in mission.events.all|slice:":20" %}
                    <div class="text-sm border-l-2 border-gray-200 pl-3 py-1">
                        <span class="text-gray-500">{{ event.created_at|date:"M d g:i A" }}</span>
                        <p>{{ event.title }}</p>
                        {% if event.content %}
                        <p class="text-gray-600 text-xs mt-1">{{ event.content|truncatewords:20 }}</p>
                        {% endif %}
                    </div>
                    {% endfor %}
                </div>
            </div>

            <!-- Actions -->
            <div class="bg-white shadow rounded-lg p-6 mt-6">
                <h2 class="text-lg font-semibold mb-4">Actions</h2>
                <div class="space-y-2">
                    {% if mission.status != 'completed' and mission.status != 'cancelled' %}
                    <form method="post" action="{% url 'cancel_mission' mission.id %}">
                        {% csrf_token %}
                        <button type="submit"
                                class="w-full border border-red-600 text-red-600 px-4 py-2 rounded hover:bg-red-50"
                                onclick="return confirm('Are you sure you want to cancel this mission?')">
                            Cancel Mission
                        </button>
                    </form>
                    {% endif %}
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
```

### Add URL Routes

**File:** `echoforge-hub/backend/apps/agents/urls.py`

```python
from django.urls import path
from . import views

urlpatterns = [
    # ... existing routes ...
    path('dashboard/missions/', views.mission_list, name='mission_list'),
    path('dashboard/missions/<uuid:mission_id>/', views.mission_detail, name='mission_detail'),
    path('dashboard/missions/<uuid:mission_id>/cancel/', views.cancel_mission, name='cancel_mission'),
    path('dashboard/input-requests/<uuid:request_id>/respond/', views.respond_to_input, name='respond_to_input'),
]
```

### Add Views

**File:** `echoforge-hub/backend/apps/agents/views.py`

```python
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.utils import timezone

from .models import Mission, HumanInputRequest


@login_required
def mission_list(request):
    """Display list of user's missions."""
    user = request.user.customer_user

    missions = Mission.objects.filter(
        user=user
    ).prefetch_related('tasks').order_by('-created_at')

    pending_missions = missions.filter(
        status='waiting',
        input_requests__status='pending'
    ).distinct()

    active_missions = missions.filter(
        status__in=['active', 'planning', 'executing']
    ).exclude(id__in=pending_missions)

    completed_missions = missions.filter(
        status='completed'
    )[:10]

    return render(request, 'agents/mission_list.html', {
        'pending_missions': pending_missions,
        'active_missions': active_missions,
        'completed_missions': completed_missions,
    })


@login_required
def mission_detail(request, mission_id):
    """Display mission detail with tasks and events."""
    user = request.user.customer_user

    mission = get_object_or_404(
        Mission.objects.prefetch_related('tasks', 'events', 'input_requests'),
        id=mission_id,
        user=user
    )

    pending_inputs = mission.input_requests.filter(status='pending')

    return render(request, 'agents/mission_detail.html', {
        'mission': mission,
        'pending_inputs': pending_inputs,
    })


@login_required
def cancel_mission(request, mission_id):
    """Cancel a mission."""
    if request.method != 'POST':
        return redirect('mission_detail', mission_id=mission_id)

    user = request.user.customer_user
    mission = get_object_or_404(Mission, id=mission_id, user=user)

    mission.status = Mission.Status.CANCELLED
    mission.save()

    messages.success(request, f'Mission "{mission.title}" has been cancelled.')
    return redirect('mission_list')


@login_required
def respond_to_input(request, request_id):
    """Handle user response to input request."""
    if request.method != 'POST':
        return redirect('mission_list')

    user = request.user.customer_user
    input_request = get_object_or_404(
        HumanInputRequest,
        id=request_id,
        mission__user=user,
        status='pending'
    )

    selected_option = request.POST.get('selected_option')
    freeform_text = request.POST.get('freeform_text')

    input_request.response = {
        'selected_option': selected_option,
        'freeform_text': freeform_text,
    }
    input_request.status = HumanInputRequest.Status.RESPONDED
    input_request.responded_at = timezone.now()
    input_request.save()

    # Update mission status
    mission = input_request.mission
    mission.status = Mission.Status.ACTIVE
    mission.wait_reason = ''
    mission.save()

    messages.success(request, 'Your response has been recorded.')
    return redirect('mission_detail', mission_id=mission.id)
```

---

## Implementation Order

### Step 1: Fix Agent Tool List (30 mins)
1. Edit `personal_assistant.py`
2. Remove `PERSONAL_ASSISTANT_TOOLS` constant
3. Change `tools_enabled` to use `config.actions_enabled`
4. Test with "what are my missions?"

### Step 2: Verify Hub Seed Data (15 mins)
1. Check `seed_tool_categories.py` has correct mission tool names
2. Run `python manage.py seed_tool_categories`
3. Verify in Django admin

### Step 3: Verify Hub Client Methods (30 mins)
1. Check all mission methods exist in `hub_client.py`
2. Test each endpoint with curl
3. Fix any missing methods

### Step 4: Create Dashboard Templates (2 hrs)
1. Create `mission_list.html`
2. Create `mission_detail.html`
3. Add URL routes
4. Add views
5. Test in browser

### Step 5: Update Tests (1 hr)
1. Update agent tests to mock `config.actions_enabled`
2. Remove tests that rely on hardcoded tool list
3. Add dashboard view tests

---

## Acceptance Criteria

### Issue #11, #12 - Agent Tool Config
- [ ] `PERSONAL_ASSISTANT_TOOLS` constant removed
- [ ] `tools_enabled` populated from `config.actions_enabled`
- [ ] No hardcoded tool lists in agent type handlers

### Issue #18 - Mission Tools Working
- [ ] "What are my missions?" returns user's missions
- [ ] `mission_list` tool executes successfully
- [ ] All mission tools accessible to agent

### Issue #21 - Dashboard UI
- [ ] `/dashboard/missions/` shows mission list
- [ ] `/dashboard/missions/{id}/` shows mission detail
- [ ] User can respond to approval requests
- [ ] User can cancel missions

---

## Testing Commands

```bash
# Test mission list via Agent API
curl -X POST http://localhost:8004/v1/chat \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"message": "What are my current missions?", "conversation_id": "test-missions"}'

# Test Hub missions API directly
curl http://localhost:8003/api/internal/missions \
  -H "Authorization: Bearer $HUB_SERVICE_SECRET"

# Test dashboard (in browser)
open http://localhost:8003/dashboard/missions/
```

---

*End of Specification*
