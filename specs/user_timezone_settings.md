---
title: User Timezone Settings
version: "1.0"
status: deployed
project: EchoForge Hub
issue: "#33"
created: 2026-01-04
updated: 2026-01-04
---

# User Timezone Settings Specification

---

## Overview

Users need a stored timezone preference that's automatically used by the Agent for scheduling, calendar operations, and time-aware responses. This spec covers the full implementation including backend models, API changes, UI components, and time display formatting.

### Goals

1. **Persistent preferences** - Users set timezone once, used everywhere
2. **Sensible defaults** - Customer-level default with user override
3. **Clear display** - Show times in user's timezone with original context
4. **Mobile support** - Device timezone for mobile apps

### Non-Goals

- Timezone conversion for historical data (display only)
- Automatic DST notifications
- Per-agent timezone settings

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Timezone Flow                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Customer   │───▶│ CustomerUser│───▶│   Agent     │         │
│  │  (default)  │    │ (override)  │    │  (runtime)  │         │
│  │             │    │             │    │             │         │
│  │ timezone:   │    │ timezone:   │    │ Resolves:   │         │
│  │ America/    │    │ null or     │    │ 1. Request  │         │
│  │ New_York    │    │ Europe/     │    │ 2. User     │         │
│  │             │    │ London      │    │ 3. Customer │         │
│  └─────────────┘    └─────────────┘    │ 4. UTC      │         │
│                                        └─────────────┘         │
│                                                                 │
│  Mobile App:                                                    │
│  ┌─────────────┐                                               │
│  │   Device    │───▶ Uses device timezone automatically        │
│  │  Timezone   │                                               │
│  └─────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Models

### Customer (Updated)

```python
class Customer(BaseModel):
    """Add default timezone for organization."""

    # ... existing fields ...

    default_timezone = models.CharField(
        max_length=50,
        default='UTC',
        validators=[validate_timezone],
        help_text='Default IANA timezone for new users (e.g., America/New_York)'
    )
```

### CustomerUser (Updated)

```python
class CustomerUser(BaseModel):
    """Add user-specific timezone override."""

    # ... existing fields ...

    timezone = models.CharField(
        max_length=50,
        null=True,
        blank=True,
        validators=[validate_timezone],
        help_text='User timezone override. If null, uses customer default.'
    )
    timezone_confirmed = models.BooleanField(
        default=False,
        help_text='True if user has confirmed their timezone setting'
    )

    def get_effective_timezone(self) -> str:
        """Return user's effective timezone (user override or customer default)."""
        if self.timezone:
            return self.timezone
        return self.customer.default_timezone or 'UTC'
```

### Timezone Validator

```python
# core/validators.py

from zoneinfo import available_timezones
from django.core.exceptions import ValidationError

VALID_TIMEZONES = available_timezones()

def validate_timezone(value: str) -> None:
    """Validate that value is a valid IANA timezone."""
    if value not in VALID_TIMEZONES:
        raise ValidationError(
            f'"{value}" is not a valid IANA timezone. '
            f'Examples: America/New_York, Europe/London, Asia/Tokyo'
        )
```

---

## API Changes

### Config API (Internal)

Update `/api/internal/config/{api_key}/` to include timezone:

```python
# Current response structure
{
    "agent_id": "uuid",
    "agent_type": "personal_assistant",
    "system_prompt": "...",
    "enabled_tools": [...],
    # ... existing fields ...
}

# Updated response structure
{
    "agent_id": "uuid",
    "agent_type": "personal_assistant",
    "system_prompt": "...",
    "enabled_tools": [...],
    # ... existing fields ...

    "user_defaults": {
        "timezone": "America/New_York",
        "timezone_confirmed": true
    }
}
```

**Implementation:**

```python
# api/internal/views.py

class AgentConfigView(APIView):
    def get(self, request, api_key):
        # ... existing logic ...

        # Get user's effective timezone
        customer_user = agent_instance.customer.users.filter(
            user=request.user
        ).first()

        user_timezone = 'UTC'
        timezone_confirmed = False

        if customer_user:
            user_timezone = customer_user.get_effective_timezone()
            timezone_confirmed = customer_user.timezone_confirmed

        return Response({
            # ... existing fields ...
            'user_defaults': {
                'timezone': user_timezone,
                'timezone_confirmed': timezone_confirmed,
            }
        })
```

### User Settings API (External)

New endpoints for timezone management:

```python
# GET /api/v1/users/me/settings/
{
    "timezone": "America/New_York",
    "timezone_confirmed": true,
    "customer_default_timezone": "America/New_York"
}

# PATCH /api/v1/users/me/settings/
{
    "timezone": "Europe/London"
}
# Response: 200 OK with updated settings

# GET /api/v1/timezones/
# Returns curated list of common timezones
{
    "common": [
        {"value": "America/New_York", "label": "Eastern Time (New York)", "offset": "-05:00"},
        {"value": "America/Chicago", "label": "Central Time (Chicago)", "offset": "-06:00"},
        {"value": "America/Denver", "label": "Mountain Time (Denver)", "offset": "-07:00"},
        {"value": "America/Los_Angeles", "label": "Pacific Time (Los Angeles)", "offset": "-08:00"},
        {"value": "Europe/London", "label": "London", "offset": "+00:00"},
        {"value": "Europe/Paris", "label": "Paris", "offset": "+01:00"},
        {"value": "Europe/Berlin", "label": "Berlin", "offset": "+01:00"},
        {"value": "Asia/Tokyo", "label": "Tokyo", "offset": "+09:00"},
        {"value": "Asia/Shanghai", "label": "Shanghai", "offset": "+08:00"},
        {"value": "Australia/Sydney", "label": "Sydney", "offset": "+11:00"},
        # ... more common timezones
    ],
    "all_valid": true  # Indicates any IANA timezone is accepted
}

# GET /api/v1/timezones/validate/?tz=America/New_York
# Validates a timezone string
{
    "valid": true,
    "timezone": "America/New_York",
    "label": "Eastern Time (New York)",
    "current_offset": "-05:00"
}
```

---

## Agent Changes

### Timezone Resolution

Update `echoforge-agent` to use Hub-provided timezone:

```python
# src/api/routes/chat.py

@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    config: AgentConfig = Depends(check_billing_status),
):
    # Resolve timezone with priority:
    # 1. Per-request override (from context)
    # 2. User's saved timezone (from config)
    # 3. Fallback to UTC

    user_timezone = 'UTC'

    # Priority 1: Request context override
    if request.context and request.context.timezone:
        user_timezone = request.context.timezone
    # Priority 2: Hub-provided user default
    elif config.user_defaults and config.user_defaults.get('timezone'):
        user_timezone = config.user_defaults['timezone']

    # ... rest of chat logic using user_timezone
```

### Mobile Detection

For mobile apps, the client should:
1. Detect device timezone
2. Pass it in request context
3. This overrides saved preference automatically

```python
# Mobile client request example
{
    "message": "Schedule a meeting for tomorrow at 3pm",
    "context": {
        "user_id": "...",
        "timezone": "America/Denver",  # From device
        "is_mobile": true
    }
}
```

---

## User Interface

### First Login Timezone Prompt

When `timezone_confirmed` is false, show a modal:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  🌍 Confirm Your Timezone                                       │
│                                                                 │
│  We detected your timezone as:                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  America/New_York (Eastern Time)              [Change ▼] │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Current time in this timezone: 3:45 PM                        │
│                                                                 │
│  This will be used for scheduling and time-aware features.     │
│                                                                 │
│                              [Confirm]  [Ask me later]          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Detection Logic:**

```javascript
// Frontend timezone detection
const detectedTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
// Returns IANA timezone like "America/New_York"
```

### Settings Page - Timezone Section

```
┌─────────────────────────────────────────────────────────────────┐
│ Settings > Preferences                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ TIMEZONE                                                        │
│                                                                 │
│ Your timezone                                                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │  🔍 Search timezones...                                     │ │
│ ├─────────────────────────────────────────────────────────────┤ │
│ │  ★ America/New_York (Eastern Time) - Current            ✓  │ │
│ │    America/Chicago (Central Time)                           │ │
│ │    America/Denver (Mountain Time)                           │ │
│ │    America/Los_Angeles (Pacific Time)                       │ │
│ │  ──────────────────────────────────────────────────────     │ │
│ │    Europe/London (GMT)                                      │ │
│ │    Europe/Paris (Central European Time)                     │ │
│ │    Asia/Tokyo (Japan Standard Time)                         │ │
│ │  ──────────────────────────────────────────────────────     │ │
│ │  Type any IANA timezone (e.g., Pacific/Auckland)            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Current time: 3:45 PM EST (8:45 PM UTC)                        │
│                                                                 │
│ ℹ️ Organization default: America/New_York                       │
│    Your setting overrides the organization default.            │
│                                                                 │
│ [ ] Use organization default                                    │
│                                                                 │
│                                             [Save Changes]      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Customer Settings - Organization Default

```
┌─────────────────────────────────────────────────────────────────┐
│ Organization Settings > General                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ DEFAULT TIMEZONE                                                │
│                                                                 │
│ New team members will use this timezone by default.             │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │  America/New_York (Eastern Time)                       [▼]  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ℹ️ Team members can override this in their personal settings.   │
│                                                                 │
│                                             [Save Changes]      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Time Display Formatting

### Display Rules

All times displayed to users should follow this format:

**User's timezone (original timezone)**

Examples:
- `3:00 PM EST (8:00 PM UTC)`
- `Tomorrow at 2:30 PM PST (5:30 PM EST)`
- `Jan 15, 2026 10:00 AM EST (Jan 15, 2026 3:00 PM UTC)`

### Utility Functions

```python
# core/timezone_utils.py

from datetime import datetime
from zoneinfo import ZoneInfo
from typing import Optional

def format_time_dual(
    dt: datetime,
    user_timezone: str,
    original_timezone: str = 'UTC',
    include_date: bool = False
) -> str:
    """
    Format datetime showing user's timezone with original in parentheses.

    Args:
        dt: The datetime to format (should be timezone-aware)
        user_timezone: User's IANA timezone
        original_timezone: Original timezone to show in parentheses
        include_date: Whether to include the date

    Returns:
        Formatted string like "3:00 PM EST (8:00 PM UTC)"
    """
    user_tz = ZoneInfo(user_timezone)
    orig_tz = ZoneInfo(original_timezone)

    user_dt = dt.astimezone(user_tz)
    orig_dt = dt.astimezone(orig_tz)

    if include_date:
        user_fmt = user_dt.strftime('%b %d, %Y %I:%M %p %Z')
        orig_fmt = orig_dt.strftime('%b %d, %Y %I:%M %p %Z')
    else:
        user_fmt = user_dt.strftime('%I:%M %p %Z')
        orig_fmt = orig_dt.strftime('%I:%M %p %Z')

    # Don't show duplicate if same timezone
    if user_timezone == original_timezone:
        return user_fmt

    return f"{user_fmt} ({orig_fmt})"


def get_timezone_label(tz: str) -> str:
    """Get human-readable label for timezone."""
    labels = {
        'America/New_York': 'Eastern Time',
        'America/Chicago': 'Central Time',
        'America/Denver': 'Mountain Time',
        'America/Los_Angeles': 'Pacific Time',
        'Europe/London': 'London',
        'Europe/Paris': 'Paris',
        'Asia/Tokyo': 'Tokyo',
        # ... more
    }
    return labels.get(tz, tz)


def get_current_offset(tz: str) -> str:
    """Get current UTC offset for timezone (handles DST)."""
    now = datetime.now(ZoneInfo(tz))
    offset = now.strftime('%z')
    return f"{offset[:3]}:{offset[3:]}"  # Format as +00:00
```

### Frontend Formatting

```javascript
// utils/timezone.js

export function formatTimeDual(isoString, userTimezone, originalTimezone = 'UTC') {
  const date = new Date(isoString);

  const userOptions = {
    timeZone: userTimezone,
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short'
  };

  const origOptions = {
    timeZone: originalTimezone,
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short'
  };

  const userFormatted = date.toLocaleTimeString('en-US', userOptions);
  const origFormatted = date.toLocaleTimeString('en-US', origOptions);

  if (userTimezone === originalTimezone) {
    return userFormatted;
  }

  return `${userFormatted} (${origFormatted})`;
}

// Usage in React component
<span>{formatTimeDual(event.start_time, userTimezone, event.original_timezone)}</span>
// Output: "3:00 PM EST (8:00 PM UTC)"
```

---

## Common Timezones List

Curated list for dropdown (approximately 40 entries):

```python
COMMON_TIMEZONES = [
    # North America
    ('America/New_York', 'Eastern Time (New York)'),
    ('America/Chicago', 'Central Time (Chicago)'),
    ('America/Denver', 'Mountain Time (Denver)'),
    ('America/Los_Angeles', 'Pacific Time (Los Angeles)'),
    ('America/Anchorage', 'Alaska Time'),
    ('Pacific/Honolulu', 'Hawaii Time'),
    ('America/Phoenix', 'Arizona (No DST)'),
    ('America/Toronto', 'Toronto'),
    ('America/Vancouver', 'Vancouver'),

    # Europe
    ('Europe/London', 'London (GMT/BST)'),
    ('Europe/Dublin', 'Dublin'),
    ('Europe/Paris', 'Paris'),
    ('Europe/Berlin', 'Berlin'),
    ('Europe/Amsterdam', 'Amsterdam'),
    ('Europe/Madrid', 'Madrid'),
    ('Europe/Rome', 'Rome'),
    ('Europe/Zurich', 'Zurich'),
    ('Europe/Stockholm', 'Stockholm'),
    ('Europe/Warsaw', 'Warsaw'),
    ('Europe/Moscow', 'Moscow'),

    # Asia
    ('Asia/Dubai', 'Dubai'),
    ('Asia/Kolkata', 'India (Mumbai)'),
    ('Asia/Bangkok', 'Bangkok'),
    ('Asia/Singapore', 'Singapore'),
    ('Asia/Hong_Kong', 'Hong Kong'),
    ('Asia/Shanghai', 'Shanghai'),
    ('Asia/Tokyo', 'Tokyo'),
    ('Asia/Seoul', 'Seoul'),

    # Oceania
    ('Australia/Sydney', 'Sydney'),
    ('Australia/Melbourne', 'Melbourne'),
    ('Australia/Perth', 'Perth'),
    ('Pacific/Auckland', 'Auckland'),

    # South America
    ('America/Sao_Paulo', 'São Paulo'),
    ('America/Buenos_Aires', 'Buenos Aires'),
    ('America/Mexico_City', 'Mexico City'),

    # Africa
    ('Africa/Cairo', 'Cairo'),
    ('Africa/Johannesburg', 'Johannesburg'),
    ('Africa/Lagos', 'Lagos'),

    # UTC
    ('UTC', 'UTC (Coordinated Universal Time)'),
]
```

---

## Migration

```python
# customers/migrations/XXXX_add_timezone_fields.py

from django.db import migrations, models
import apps.core.validators

class Migration(migrations.Migration):

    dependencies = [
        ('customers', 'previous_migration'),
    ]

    operations = [
        # Add Customer.default_timezone
        migrations.AddField(
            model_name='customer',
            name='default_timezone',
            field=models.CharField(
                default='UTC',
                max_length=50,
                validators=[apps.core.validators.validate_timezone],
                help_text='Default IANA timezone for new users'
            ),
        ),

        # Add CustomerUser.timezone
        migrations.AddField(
            model_name='customeruser',
            name='timezone',
            field=models.CharField(
                blank=True,
                max_length=50,
                null=True,
                validators=[apps.core.validators.validate_timezone],
                help_text='User timezone override'
            ),
        ),

        # Add CustomerUser.timezone_confirmed
        migrations.AddField(
            model_name='customeruser',
            name='timezone_confirmed',
            field=models.BooleanField(
                default=False,
                help_text='True if user has confirmed their timezone'
            ),
        ),
    ]
```

---

## Implementation Phases

### Phase 1: Backend Foundation
- Add timezone fields to Customer and CustomerUser models
- Add timezone validator
- Create migration
- Update config API to include timezone
- Add user settings API endpoints
- Add timezones list endpoint

### Phase 2: Agent Integration
- Update agent to read timezone from config
- Implement timezone resolution priority
- Update prompt templates to use effective timezone
- Test with calendar/scheduling tools

### Phase 3: User Interface
- First login timezone detection modal
- User settings timezone picker
- Customer settings default timezone
- Searchable dropdown component

### Phase 4: Time Display Formatting
- Create timezone utility functions (backend + frontend)
- Update all time displays to use dual format
- Update email templates with timezone-aware formatting
- Test across different timezone combinations

---

## Testing

### Unit Tests

```python
# customers/tests/test_timezone.py

class TimezoneValidatorTests(TestCase):
    def test_valid_timezone(self):
        validate_timezone('America/New_York')  # Should not raise

    def test_invalid_timezone(self):
        with self.assertRaises(ValidationError):
            validate_timezone('Invalid/Timezone')

    def test_abbreviation_rejected(self):
        with self.assertRaises(ValidationError):
            validate_timezone('EST')  # Must use IANA format


class CustomerUserTimezoneTests(TestCase):
    def test_effective_timezone_user_override(self):
        customer = CustomerFactory(default_timezone='America/New_York')
        user = CustomerUserFactory(customer=customer, timezone='Europe/London')

        self.assertEqual(user.get_effective_timezone(), 'Europe/London')

    def test_effective_timezone_customer_default(self):
        customer = CustomerFactory(default_timezone='America/New_York')
        user = CustomerUserFactory(customer=customer, timezone=None)

        self.assertEqual(user.get_effective_timezone(), 'America/New_York')

    def test_effective_timezone_utc_fallback(self):
        customer = CustomerFactory(default_timezone=None)
        user = CustomerUserFactory(customer=customer, timezone=None)

        self.assertEqual(user.get_effective_timezone(), 'UTC')
```

### Integration Tests

```python
# api/internal/tests/test_config_timezone.py

class ConfigAPITimezoneTests(APITestCase):
    def test_config_includes_user_timezone(self):
        user = CustomerUserFactory(timezone='America/Los_Angeles')
        agent = AgentInstanceFactory(customer=user.customer)

        response = self.client.get(f'/api/internal/config/{agent.api_key}/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data['user_defaults']['timezone'],
            'America/Los_Angeles'
        )
```

---

## Acceptance Criteria

- [ ] Customer model has `default_timezone` field
- [ ] CustomerUser model has `timezone` and `timezone_confirmed` fields
- [ ] Timezone validation accepts only valid IANA timezones
- [ ] Config API includes user's effective timezone
- [ ] Agent uses Hub-provided timezone as default
- [ ] Per-request timezone override works
- [ ] First login shows timezone confirmation modal
- [ ] User settings page has timezone picker
- [ ] Customer settings has default timezone option
- [ ] Times display in dual format (user's TZ + original)
- [ ] Mobile apps use device timezone
- [ ] Searchable timezone dropdown with curated list
- [ ] Custom IANA timezone can be typed and validated
- [ ] Spec in `docs/specs/echoforge_hub.md` updated

---

## References

- IANA Time Zone Database: https://www.iana.org/time-zones
- Python zoneinfo: https://docs.python.org/3/library/zoneinfo.html
- JavaScript Intl.DateTimeFormat: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat
