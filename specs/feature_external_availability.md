# Feature: External Party Availability Checking

## Summary

When a user asks to schedule a meeting with external parties, the agent should intelligently determine whether it has calendar access to those parties and fall back to email-based availability requests when direct access isn't available.

## User Story

> "Schedule a meeting with john@external.com for next week"

The agent should:
1. Check if it has calendar access to john@external.com
2. If yes → query their calendar directly
3. If no → draft and send an email requesting their availability

## How Calendar Access Works

### Types of Calendar Access

| Access Type | How It Works | Scope |
|-------------|--------------|-------|
| **Same Organization** | Google Workspace domain-wide delegation | All users in same domain |
| **Shared Calendar** | User explicitly shared their calendar with our user | Individual permission |
| **FreeBusy Access** | Organization allows external FreeBusy queries | Varies by org policy |
| **Delegated Access** | User granted our user delegate access | Individual permission |
| **None** | No direct access | Must request via email |

### Google Calendar Access Levels

When someone shares their calendar, they can grant:
- **See only free/busy** - Can see when they're busy but not event details
- **See all event details** - Can see full event information
- **Make changes to events** - Can modify their calendar
- **Make changes and manage sharing** - Full access

### Determining Access

```python
async def check_calendar_access(user_email: str) -> CalendarAccess:
    """
    Check what level of access we have to a user's calendar.

    Returns:
        CalendarAccess with:
        - has_access: bool
        - access_level: "freebusy" | "read" | "write" | "none"
        - calendar_id: str (if accessible)
    """
    try:
        # Try to query their FreeBusy - this works if:
        # 1. Same organization with FreeBusy enabled
        # 2. They shared their calendar with us
        # 3. They have public FreeBusy

        freebusy = service.freebusy().query(body={
            "timeMin": now,
            "timeMax": now + 1 day,
            "items": [{"id": user_email}]
        }).execute()

        # Check if we got actual data or an error
        calendar_data = freebusy.get("calendars", {}).get(user_email, {})

        if "errors" in calendar_data:
            return CalendarAccess(has_access=False, access_level="none")

        return CalendarAccess(
            has_access=True,
            access_level="freebusy",
            calendar_id=user_email
        )

    except HttpError as e:
        if e.resp.status == 404:
            return CalendarAccess(has_access=False, access_level="none")
        raise
```

## Proposed Agent Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  User: "Schedule meeting with alice@company.com and            │
│         bob@external.com for next Tuesday"                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Parse attendees and check calendar access for each          │
│                                                                 │
│     alice@company.com → Same org, have FreeBusy access ✓        │
│     bob@external.com  → No access, need to email ✗              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. For accessible calendars: Query availability directly       │
│                                                                 │
│     Alice's availability for Tuesday:                           │
│     - 9am-10am: Free                                           │
│     - 10am-12pm: Busy                                          │
│     - 1pm-5pm: Free                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. For inaccessible calendars: Draft availability request      │
│                                                                 │
│     To: bob@external.com                                        │
│     Subject: Availability Request for Meeting                   │
│                                                                 │
│     Hi Bob,                                                     │
│                                                                 │
│     [User] would like to schedule a meeting with you and        │
│     Alice for next Tuesday. Based on other attendees'           │
│     availability, the following times work:                     │
│                                                                 │
│     - Tuesday 9:00 AM - 10:00 AM                               │
│     - Tuesday 1:00 PM - 5:00 PM                                │
│                                                                 │
│     Could you let us know which time works best for you?        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Ask user for approval before sending                        │
│                                                                 │
│     Agent: "I can see Alice's calendar but don't have access    │
│     to Bob's. I've drafted an email to Bob asking for his       │
│     availability. Based on Alice's calendar, I'm suggesting     │
│     Tuesday 9am or Tuesday 1-5pm. Should I send this email?"    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. After Bob replies: Parse response and continue              │
│                                                                 │
│     Bob's reply: "Tuesday 2pm works for me"                     │
│                                                                 │
│     Agent: "Bob confirmed Tuesday 2pm. Should I create the      │
│     calendar invite for you, Alice, and Bob at that time?"      │
└─────────────────────────────────────────────────────────────────┘
```

## Tool Changes Required

### New Tool: `calendar_check_access`

```python
class CalendarCheckAccessTool(ToolHandler):
    """Check what calendar access we have for a list of attendees."""

    name = "calendar_check_access"
    description = """Check if we have calendar access for specified
    email addresses. Returns access level for each: 'freebusy',
    'read', 'write', or 'none'. Use before scheduling to determine
    if we need to email external parties for availability."""

    input_schema = {
        "type": "object",
        "properties": {
            "emails": {
                "type": "array",
                "items": {"type": "string", "format": "email"},
                "description": "Email addresses to check access for"
            }
        },
        "required": ["emails"]
    }
```

**Response:**
```json
{
    "results": [
        {
            "email": "alice@company.com",
            "has_access": true,
            "access_level": "freebusy",
            "source": "organization"
        },
        {
            "email": "bob@external.com",
            "has_access": false,
            "access_level": "none",
            "source": null,
            "suggestion": "Send email to request availability"
        }
    ]
}
```

### Updated: `calendar_find_optimal_times`

Add parameter to handle mixed access:

```python
input_schema = {
    "type": "object",
    "properties": {
        "attendees": {
            "type": "array",
            "items": {"type": "string", "format": "email"}
        },
        "duration_minutes": {"type": "integer"},
        "date_range": {
            "type": "object",
            "properties": {
                "start": {"type": "string", "format": "date"},
                "end": {"type": "string", "format": "date"}
            }
        },
        "skip_inaccessible": {
            "type": "boolean",
            "default": true,
            "description": "If true, find times based only on accessible calendars"
        }
    }
}
```

**Response includes access info:**
```json
{
    "suggestions": [...],
    "attendee_access": {
        "alice@company.com": {"has_access": true},
        "bob@external.com": {"has_access": false, "needs_email": true}
    },
    "note": "Times based on 1 of 2 attendees. Bob's availability unknown."
}
```

## Email Template for Availability Request

```
Subject: Availability Request: Meeting with {organizer_name}

Hi {recipient_name},

{organizer_name} would like to schedule a {duration}-minute meeting
with you{and_others}.

{#if has_suggested_times}
Based on other attendees' availability, here are some times that work:

{#each suggested_times}
• {day}, {date} at {time} ({timezone})
{/each}

Could you reply with which time(s) work for you, or suggest alternatives?
{/if}

{#if no_suggested_times}
Could you share your availability for {date_range}?
{/if}

Thanks,
{organizer_name}'s Assistant
```

## Edge Cases

### 1. All Attendees External
If no attendees have accessible calendars, agent should:
- Ask user for their own availability preferences
- Draft emails to all external parties with those preferences

### 2. Partial Responses
If some external attendees don't respond:
- Agent tracks pending responses
- Can send follow-up emails
- Can proceed with confirmed attendees if user approves

### 3. Conflicting Responses
If external attendees provide conflicting availability:
- Agent identifies overlap
- If no overlap, presents options to user
- Can iterate with another round of emails

### 4. Calendar Permissions Change
Cache access results briefly (5 min) but re-check for scheduling operations.

## Implementation Phases

### Phase 1: Access Detection
- Implement `calendar_check_access` tool
- Update `calendar_find_optimal_times` to report access status

### Phase 2: Email Fallback
- Integrate with email tools for availability requests
- Create email templates
- Add approval flow for sending

### Phase 3: Response Handling
- Parse availability from email replies
- Update scheduling flow with external responses
- Handle follow-ups

## Open Questions

1. **Should we support Calendly/scheduling links?**
   - Could detect if external party has a scheduling link in their email signature
   - Could generate our own scheduling link for them to pick a time

2. **How to handle timezone differences?**
   - Always include timezone in availability requests
   - Convert times when displaying to user

3. **Should we integrate with other calendar providers?**
   - Microsoft Outlook/365
   - Apple Calendar
   - Would require additional OAuth integrations

4. **Rate limiting on access checks?**
   - Google has quotas on FreeBusy queries
   - May need to batch or cache aggressively
