---
title: "Calendar Category"
version: "1.0"
status: in_development
project: EchoForge
created: 2026-01-02
updated: 2026-01-02
---

# Category: Calendar

> **Status:** Implemented (Google Calendar)
> **Last Updated:** 2026-01-02
> **Owner:** EchoForge Team

## 1. Overview

### 1.1 Purpose

Calendar enables agents to manage the user's schedule - viewing events, checking availability, finding optimal meeting times, and creating/updating/deleting events. This is essential for scheduling-related tasks like "schedule a meeting with John" or "what do I have on my calendar tomorrow?"

### 1.2 Classification

| Attribute | Value |
|-----------|-------|
| **Type** | `integration` |
| **Billing** | `included` |
| **Min Plan** | `starter` |
| **Meter Name** | N/A |

### 1.3 Dependencies

- Requires OAuth connection to a calendar provider (Google Calendar, Outlook Calendar)
- Often used in conjunction with **email** category for external attendee coordination
- Commonly used within **missions** for multi-step scheduling workflows

---

## 2. Tools

### 2.1 Tool Summary

| Tool Name | Description | Async | Approval |
|-----------|-------------|-------|----------|
| `calendar_list_events` | List events with full details | No | No |
| `calendar_get_availability` | Check free/busy times | No | No |
| `calendar_find_optimal_times` | Find best meeting slots | No | No |
| `calendar_create_event` | Create event and send invites | No | Optional |
| `calendar_update_event` | Update existing event | No | No |
| `calendar_delete_event` | Delete/cancel event | No | Optional |

### 2.2 Tool Definitions

#### `calendar_list_events`

**Description:** List calendar events over a date range with full details including titles, descriptions, attendees (with response status), locations, and video conferencing links. This is the primary tool for answering questions like "what meetings do I have?" or "who are my meetings with?"

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "start_date": {
      "type": "string",
      "format": "date",
      "description": "Start date (YYYY-MM-DD)"
    },
    "end_date": {
      "type": "string",
      "format": "date",
      "description": "End date (YYYY-MM-DD)"
    },
    "max_results": {
      "type": "integer",
      "default": 10,
      "description": "Maximum number of events to return (max 50)"
    },
    "calendar_id": {
      "type": "string",
      "default": "primary",
      "description": "Calendar ID"
    }
  },
  "required": ["start_date", "end_date"]
}
```

**Output Schema:**
```json
{
  "events": [
    {
      "event_id": "abc123",
      "summary": "Team Standup",
      "start": "2026-01-02T09:00:00-08:00",
      "end": "2026-01-02T09:30:00-08:00",
      "status": "confirmed",
      "html_link": "https://calendar.google.com/event?eid=...",
      "location": "Conference Room A",
      "description": "Daily sync meeting",
      "attendees": [
        {
          "email": "john@example.com",
          "display_name": "John Smith",
          "response_status": "accepted",
          "organizer": false,
          "self": false
        }
      ],
      "organizer": "user@example.com",
      "creator": "user@example.com",
      "hangout_link": "https://meet.google.com/...",
      "conference_data": []
    }
  ],
  "next_page_token": null
}
```

**Error Cases:**
- `AUTH_ERROR`: OAuth token invalid or revoked
- `PERMISSION_DENIED`: No access to calendar
- `RATE_LIMITED`: Too many API requests

---

#### `calendar_get_availability`

**Description:** Check free/busy availability for one or more calendars over a date range. Returns only busy time slots WITHOUT event details. Use this when checking if someone is free, not for viewing meeting details.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "emails": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Email addresses to check availability for"
    },
    "start_date": {
      "type": "string",
      "format": "date-time",
      "description": "Start of date range (ISO 8601)"
    },
    "end_date": {
      "type": "string",
      "format": "date-time",
      "description": "End of date range (ISO 8601)"
    },
    "timezone": {
      "type": "string",
      "description": "IANA timezone (e.g., 'America/New_York')"
    }
  },
  "required": ["emails", "start_date", "end_date"]
}
```

**Output Schema:**
```json
{
  "busy_times": [
    {
      "start": "2026-01-02T10:00:00Z",
      "end": "2026-01-02T11:00:00Z"
    }
  ],
  "working_hours": {
    "start": "09:00",
    "end": "17:00",
    "timezone": "America/Los_Angeles"
  },
  "calendar_id": "primary",
  "time_range": {
    "start": "2026-01-02T00:00:00Z",
    "end": "2026-01-03T23:59:59Z"
  }
}
```

**Error Cases:**
- `AUTH_ERROR`: OAuth token invalid
- `PERMISSION_DENIED`: Cannot view availability for requested calendar

---

#### `calendar_find_optimal_times`

**Description:** Find optimal meeting times given attendee availability, duration requirements, and preferences. Returns ranked time slots that work for all (or most) attendees within working hours.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "duration_minutes": {
      "type": "integer",
      "enum": [30, 60, 90, 120],
      "description": "Meeting duration in minutes"
    },
    "start_date": {
      "type": "string",
      "description": "Start of search window"
    },
    "end_date": {
      "type": "string",
      "description": "End of search window"
    },
    "attendees": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Attendee email addresses"
    },
    "working_hours_start": {
      "type": "string",
      "default": "09:00",
      "description": "Start of working hours (HH:MM)"
    },
    "working_hours_end": {
      "type": "string",
      "default": "17:00",
      "description": "End of working hours (HH:MM)"
    },
    "timezone": {
      "type": "string",
      "default": "UTC",
      "description": "Timezone for working hours"
    },
    "max_suggestions": {
      "type": "integer",
      "default": 5,
      "description": "Maximum number of suggestions"
    }
  },
  "required": ["duration_minutes", "start_date", "end_date"]
}
```

**Output Schema:**
```json
{
  "suggestions": [
    {
      "start": "2026-01-03T10:00:00Z",
      "end": "2026-01-03T11:00:00Z"
    },
    {
      "start": "2026-01-03T14:00:00Z",
      "end": "2026-01-03T15:00:00Z"
    }
  ],
  "duration_minutes": 60,
  "search_range": {
    "start": "2026-01-02T00:00:00Z",
    "end": "2026-01-07T23:59:59Z"
  },
  "working_hours": {
    "start": "09:00",
    "end": "17:00",
    "timezone": "America/Los_Angeles"
  }
}
```

---

#### `calendar_create_event`

**Description:** Create a new calendar event. Can send invites to attendees and add video conferencing (Google Meet).

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Event title"
    },
    "start": {
      "type": "string",
      "format": "date-time",
      "description": "Event start time (ISO 8601)"
    },
    "end": {
      "type": "string",
      "format": "date-time",
      "description": "Event end time (ISO 8601)"
    },
    "attendees": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "email": {"type": "string"},
          "optional": {"type": "boolean", "default": false}
        }
      },
      "description": "List of attendees"
    },
    "location": {
      "type": "string",
      "description": "Event location"
    },
    "description": {
      "type": "string",
      "description": "Event description/notes"
    },
    "video_conference": {
      "type": "boolean",
      "default": false,
      "description": "Add Google Meet link"
    },
    "send_invites": {
      "type": "boolean",
      "default": true,
      "description": "Send invite emails to attendees"
    }
  },
  "required": ["title", "start", "end"]
}
```

**Output Schema:**
```json
{
  "event_id": "abc123xyz",
  "html_link": "https://calendar.google.com/event?eid=...",
  "status": "confirmed",
  "summary": "Q1 Planning Meeting",
  "start": "2026-01-03T10:00:00-08:00",
  "end": "2026-01-03T11:00:00-08:00",
  "attendees": ["john@example.com", "sarah@example.com"],
  "created": "2026-01-02T15:30:00Z"
}
```

**Approval Guidance:**
- External attendees (outside organization): Consider approval
- Unknown recipients: Require approval
- Large meetings (>5 attendees): Consider approval

---

#### `calendar_update_event`

**Description:** Update an existing calendar event. Can modify time, title, attendees, location, and other properties.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "event_id": {
      "type": "string",
      "description": "ID of the event to update"
    },
    "title": {"type": "string"},
    "start": {"type": "string", "format": "date-time"},
    "end": {"type": "string", "format": "date-time"},
    "attendees": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "email": {"type": "string"},
          "optional": {"type": "boolean"}
        }
      }
    },
    "location": {"type": "string"},
    "description": {"type": "string"},
    "send_updates": {
      "type": "boolean",
      "default": true,
      "description": "Notify attendees of changes"
    }
  },
  "required": ["event_id"]
}
```

**Output Schema:**
```json
{
  "event_id": "abc123xyz",
  "html_link": "https://calendar.google.com/event?eid=...",
  "status": "confirmed",
  "summary": "Q1 Planning Meeting (Updated)",
  "start": "2026-01-03T14:00:00-08:00",
  "end": "2026-01-03T15:00:00-08:00",
  "updated": "2026-01-02T16:00:00Z"
}
```

**Error Cases:**
- `NOT_FOUND`: Event doesn't exist
- `NO_CHANGES`: No fields provided to update

---

#### `calendar_delete_event`

**Description:** Delete/cancel a calendar event. Optionally sends cancellation notifications to attendees.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "event_id": {
      "type": "string",
      "description": "ID of the event to delete"
    },
    "send_cancellation": {
      "type": "boolean",
      "default": true,
      "description": "Notify attendees of cancellation"
    },
    "cancellation_message": {
      "type": "string",
      "description": "Optional message in cancellation"
    }
  },
  "required": ["event_id"]
}
```

**Output Schema:**
```json
{
  "deleted": true,
  "event_id": "abc123xyz"
}
```

**Approval Guidance:**
- Events with external attendees: Consider approval
- Recurring events: May need approval
- Events within 24 hours: Consider approval

---

## 3. Providers

### 3.1 Provider Summary

| Provider | Slug | Status | Notes |
|----------|------|--------|-------|
| Google Calendar | `google_calendar` | Implemented | Full feature support |
| Outlook Calendar | `outlook_calendar` | Planned | Microsoft Graph API |

### 3.2 Provider Details

#### Google Calendar

**OAuth Scopes Required:**
- `https://www.googleapis.com/auth/calendar` - Full calendar access
- `https://www.googleapis.com/auth/calendar.events` - Event management (alternative)

**API Endpoints Used:**
- `GET /calendar/v3/calendars/{id}/events` - List events
- `POST /calendar/v3/calendars/{id}/events` - Create event
- `PATCH /calendar/v3/calendars/{id}/events/{eventId}` - Update event
- `DELETE /calendar/v3/calendars/{id}/events/{eventId}` - Delete event
- `POST /calendar/v3/freeBusy` - Get availability

**Rate Limits:**
- 1,000,000 queries/day per project
- 500 requests per 100 seconds per user
- Exponential backoff recommended on 429 errors

**Provider-Specific Behavior:**
- All-day events use `date` instead of `dateTime`
- Recurring events expand to individual instances with `singleEvents=true`
- Google Meet links can be auto-generated with `conferenceDataVersion=1`

#### Outlook Calendar (Planned)

**OAuth Scopes Required:**
- `Calendars.ReadWrite` - Full calendar access
- `Calendars.Read` - Read-only access

**API Endpoints:**
- Microsoft Graph API: `https://graph.microsoft.com/v1.0/me/calendar/events`

---

## 4. Logic Flows

### 4.1 Scheduling Workflow

Common pattern for scheduling meetings:

```
User: "Schedule a meeting with John next week"
                    │
                    ▼
┌─────────────────────────────────────┐
│ 1. calendar_get_availability        │
│    Check user's calendar            │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ 2. calendar_find_optimal_times      │
│    Find slots that work             │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ 3. Present options to user          │
│    (or check John's availability)   │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ 4. calendar_create_event            │
│    Create meeting, send invites     │
└─────────────────────────────────────┘
```

### 4.2 External Attendee Flow

When scheduling with people outside the organization:

```
                    ┌────────────────────────┐
                    │ Is attendee in system? │
                    └───────────┬────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
            ┌───────────┐           ┌───────────────┐
            │    Yes    │           │      No       │
            └─────┬─────┘           └───────┬───────┘
                  │                         │
                  ▼                         ▼
    ┌─────────────────────┐    ┌─────────────────────────┐
    │ Check their calendar│    │ Email to ask for        │
    │ via get_availability│    │ availability (email cat)│
    └─────────────────────┘    └─────────────────────────┘
```

---

## 5. UI/UX

### 5.1 Chat Interface

**Event Card (after calendar_list_events):**
```
┌─────────────────────────────────────────────────────────┐
│ 📅 Your meetings tomorrow (Jan 3):                      │
│                                                         │
│ 9:00 AM - 9:30 AM   Team Standup                       │
│                      📍 Zoom (link available)           │
│                      👥 5 attendees                     │
│                                                         │
│ 2:00 PM - 3:00 PM   1:1 with Sarah                     │
│                      📍 Conference Room B               │
│                      👥 2 attendees                     │
│                                                         │
│ 4:00 PM - 5:00 PM   Q1 Planning                        │
│                      📍 Google Meet                     │
│                      👥 8 attendees                     │
└─────────────────────────────────────────────────────────┘
```

**Event Created Card:**
```
┌─────────────────────────────────────────────────────────┐
│ ✅ Meeting Created                                      │
│                                                         │
│ "Q1 Budget Review"                                      │
│ 📅 Tuesday, Jan 7 at 2:00 PM - 3:00 PM                 │
│ 📍 Conference Room A                                    │
│ 👥 Invites sent to: john@example.com, sarah@example.com │
│                                                         │
│ [View in Google Calendar]                               │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Dashboard Components

Calendar integration is managed in **Settings > Integrations**:

```
┌──────────────────────────────────────────────────────────────────┐
│ 📅 Calendar                                                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ ✅ Google Calendar                              Connected  │   │
│ │    user@gmail.com                                          │   │
│ │    Last synced: 2 minutes ago                              │   │
│ │                                                            │   │
│ │    [Disconnect] [Test Connection]                          │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ ⬚ Outlook Calendar                          Not Connected │   │
│ │                                                            │   │
│ │    [Connect with Microsoft]                                │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.3 Notifications

| Event | Chat | Dashboard | Email | Push |
|-------|------|-----------|-------|------|
| Event created | Confirmation card | - | - | - |
| Event updated | Brief message | - | - | - |
| Event deleted | Confirmation | - | - | - |
| OAuth expired | Warning message | Banner | Yes | - |

---

## 6. Hub Implementation

### 6.1 Models

Calendar uses the existing Integration model from `apps/integrations`:

```python
# apps/integrations/models.py

class IntegrationProvider(BaseModel):
    """Provider definition - e.g., Google Calendar"""
    slug = models.SlugField(unique=True)  # 'google_calendar'
    name = models.CharField(max_length=100)  # 'Google Calendar'
    category = models.ForeignKey('agents.ToolCategory', ...)
    oauth_config = models.JSONField()  # Scopes, URLs, etc.


class Integration(CustomerScopedModel):
    """Customer's connection to a provider"""
    provider = models.ForeignKey(IntegrationProvider, ...)
    access_token = EncryptedTextField()
    refresh_token = EncryptedTextField()
    token_expires_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)
    metadata = models.JSONField()  # email, calendar_id, etc.
```

### 6.2 API Endpoints

**Tool Execution (Internal API):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/internal/tools/execute` | Execute calendar tool |

**Integration Management (External API):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/integrations/` | List connected integrations |
| `POST` | `/api/v1/integrations/google-calendar/connect/` | Initiate OAuth |
| `POST` | `/api/v1/integrations/{id}/disconnect/` | Disconnect |
| `POST` | `/api/v1/integrations/{id}/test/` | Test connection |

### 6.3 Services

```python
# apps/integrations/services/google_calendar.py

class GoogleCalendarError(Exception):
    """Exception raised when a Google Calendar operation fails."""
    def __init__(self, code: str, message: str, details: dict = None):
        self.code = code
        self.message = message
        self.details = details or {}


class GoogleCalendarService:
    """Service for Google Calendar API operations."""

    def __init__(self, integration: Integration):
        self.integration = integration
        self._service = None

    def _get_credentials(self) -> Credentials:
        """Build Google credentials from stored tokens."""
        creds_data = get_valid_credentials(self.integration)
        if not creds_data:
            raise GoogleCalendarError(
                code='CREDENTIALS_INVALID',
                message='Unable to obtain valid credentials.'
            )
        return Credentials(
            token=creds_data['access_token'],
            refresh_token=self.integration.refresh_token,
            # ... OAuth config
        )

    def _get_service(self):
        """Get or create the Calendar service instance."""
        if self._service is None:
            creds = self._get_credentials()
            self._service = build('calendar', 'v3', credentials=creds)
        return self._service

    def list_events(self, start_date, end_date, max_results=10,
                    calendar_id='primary', timezone='UTC') -> dict:
        """List upcoming calendar events."""
        # Implementation...

    def get_availability(self, start_date, end_date,
                         calendar_id='primary', timezone='UTC') -> dict:
        """Get busy times for a calendar."""
        # Implementation...

    def find_optimal_times(self, duration_minutes, start_date, end_date,
                           attendees=None, working_hours_start='09:00',
                           working_hours_end='17:00', ...) -> dict:
        """Find optimal meeting times."""
        # Implementation...

    def create_event(self, title, start, end, description='',
                     location='', attendees=None, ...) -> dict:
        """Create a calendar event."""
        # Implementation...

    def update_event(self, event_id, title=None, start=None,
                     end=None, ...) -> dict:
        """Update an existing event."""
        # Implementation...

    def delete_event(self, event_id, calendar_id='primary',
                     send_notifications=True) -> dict:
        """Delete a calendar event."""
        # Implementation...
```

---

## 7. Agent Implementation

### 7.1 Tool Classes

```python
# src/services/tools/calendar_tools.py

@ToolRegistry.register
class CalendarListEventsTool(ToolHandler):
    """List calendar events with full details."""

    name = "calendar_list_events"
    description = """List calendar events over a date range with full details.
    Returns event titles, descriptions, attendees, locations, and conferencing links.
    Use this for questions like "what meetings do I have?" or "who am I meeting with?"
    """
    category = "calendar"

    input_schema = {
        "type": "object",
        "properties": {
            "start_date": {"type": "string", "format": "date"},
            "end_date": {"type": "string", "format": "date"},
            "max_results": {"type": "integer", "default": 10},
            "calendar_id": {"type": "string", "default": "primary"}
        },
        "required": ["start_date", "end_date"]
    }

    async def execute(self, inputs: Dict[str, Any]) -> ToolResult:
        return await self.call_hub_tool(inputs)


@ToolRegistry.register
class CalendarGetAvailabilityTool(ToolHandler):
    name = "calendar_get_availability"
    # ... similar pattern


@ToolRegistry.register
class CalendarFindOptimalTimesTool(ToolHandler):
    name = "calendar_find_optimal_times"
    # ... similar pattern


@ToolRegistry.register
class CalendarCreateEventTool(ToolHandler):
    name = "calendar_create_event"
    may_require_approval = True
    # ... similar pattern


@ToolRegistry.register
class CalendarUpdateEventTool(ToolHandler):
    name = "calendar_update_event"
    # ... similar pattern


@ToolRegistry.register
class CalendarDeleteEventTool(ToolHandler):
    name = "calendar_delete_event"
    # ... similar pattern
```

### 7.2 Integration with Handler

All calendar tools use the Hub-proxied pattern:

```python
async def call_hub_tool(self, inputs: Dict[str, Any]) -> ToolResult:
    """Execute tool via Hub's tool execution endpoint."""
    try:
        result = await self.hub_client.post(
            "/api/internal/tools/execute",
            json={
                "tool_name": self.name,
                "inputs": inputs,
                "agent_id": self.agent_id,
                "customer_id": self.customer_id,
            }
        )
        return ToolResult(success=True, data=result)
    except Exception as e:
        return ToolResult(success=False, error=str(e))
```

---

## 8. Testing

### 8.1 Unit Tests

- [x] GoogleCalendarService initialization with valid credentials
- [x] Token refresh when access token expires
- [x] list_events returns properly formatted events
- [x] get_availability returns busy times
- [x] find_optimal_times respects working hours and weekends
- [x] create_event with various attendee configurations
- [x] update_event with partial updates
- [x] delete_event with notification options
- [x] Error handling for invalid credentials
- [x] Error handling for rate limiting

### 8.2 Integration Tests

- [x] Full OAuth flow (connect → use → refresh → disconnect)
- [x] Tool execution through internal API
- [x] Agent tool calls proxied to Hub correctly

### 8.3 E2E Scenarios

- [x] "What meetings do I have tomorrow?" → list_events
- [x] "Am I free at 2pm on Tuesday?" → get_availability
- [x] "Schedule a 1-hour meeting with John next week" → find_optimal_times + create_event
- [x] "Move my 2pm meeting to 3pm" → update_event
- [x] "Cancel my meeting with Sarah" → delete_event

---

## 9. Future Considerations

- **Outlook Calendar Provider**: Microsoft Graph API integration
- **Apple Calendar**: CalDAV integration
- **Calendar Sync**: Two-way sync for offline access
- **Recurring Events**: Better handling of recurring event modifications
- **Room Booking**: Integration with room/resource calendars
- **Smart Scheduling**: ML-based optimal time suggestions based on user patterns
- **Time Zone Intelligence**: Better handling of multi-timezone attendees
- **Conflict Resolution**: Automatic rescheduling suggestions for conflicts

---

## 10. Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-01-02 | Initial spec documenting existing implementation | Claude |
| 2026-01-02 | Google Calendar integration implemented (Phase 3) | Team |
