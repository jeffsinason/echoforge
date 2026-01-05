---
title: PlanLimit Model Update
version: "1.1"
status: deployed
project: SignShield
created: 2025-01-17
updated: 2025-12-22
---

# 1. Executive Summary

Update the `PlanLimit` model to add team member limits, kiosk device limits, and populate with finalized pricing tier values. This is a prerequisite for the Marketing Website, Tenant Self-Registration, and Kiosk Mode specs.

# 2. Current System State

## 2.1 Existing PlanLimit Model

Location: `apps/billing/models.py`

| Field | Type | Current |
|-------|------|---------|
| plan | CharField | choices: free, starter, professional, enterprise |
| display_name | CharField | Human-readable name |
| monthly_price_cents | IntegerField | Price in cents |
| stripe_price_id | CharField | Stripe integration |
| max_events | PositiveIntegerField | 0 = unlimited |
| max_waivers_per_month | PositiveIntegerField | 0 = unlimited |
| max_storage_mb | PositiveIntegerField | 0 = unlimited |
| video_enabled | BooleanField | Feature flag |
| custom_branding | BooleanField | Feature flag |
| api_access | BooleanField | Feature flag |
| priority_support | BooleanField | Feature flag |

## 2.2 Current Gaps

- No `max_team_members` field
- No `max_kiosk_devices` field
- No `offline_kiosk` feature flag
- No data populated in database (only fallback defaults in code)
- Annual pricing not tracked (can be calculated)

# 3. Feature Requirements

## 3.1 Model Changes

### New Fields

```python
# Add to PlanLimit model in apps/billing/models.py

# Team member limit
max_team_members = models.PositiveIntegerField(
    default=0,
    help_text="Maximum team members allowed. 0 = unlimited."
)

# Kiosk device limit
max_kiosk_devices = models.PositiveIntegerField(
    default=0,
    help_text="Maximum kiosk devices. 0 on free = disabled, 0 on paid = unlimited."
)

# Offline kiosk feature flag
offline_kiosk = models.BooleanField(
    default=False,
    help_text="Allow offline kiosk mode with background sync."
)
```

| Field | Type | Description |
|-------|------|-------------|
| `max_team_members` | PositiveIntegerField | Max team members (0 = unlimited) |
| `max_kiosk_devices` | PositiveIntegerField | Max kiosk devices (0 on free = disabled, 0 on paid = unlimited) |
| `offline_kiosk` | BooleanField | Enable offline kiosk with sync |

### Updated Model

```python
class PlanLimit(models.Model):
    """Defines limits and features for each pricing plan."""

    PLAN_CHOICES = [
        ('free', 'Free'),
        ('starter', 'Starter'),
        ('professional', 'Professional'),
        ('enterprise', 'Enterprise'),
    ]

    plan = models.CharField(max_length=20, choices=PLAN_CHOICES, unique=True)
    display_name = models.CharField(max_length=50)
    monthly_price_cents = models.IntegerField(default=0)
    stripe_price_id = models.CharField(max_length=255, blank=True)

    # Limits
    max_events = models.PositiveIntegerField(
        default=0,
        help_text="Maximum events allowed. 0 = unlimited."
    )
    max_waivers_per_month = models.PositiveIntegerField(
        default=0,
        help_text="Maximum waivers per month. 0 = unlimited."
    )
    max_storage_mb = models.PositiveIntegerField(
        default=0,
        help_text="Maximum storage in MB. 0 = unlimited."
    )
    max_team_members = models.PositiveIntegerField(
        default=0,
        help_text="Maximum team members allowed. 0 = unlimited."
    )
    max_kiosk_devices = models.PositiveIntegerField(
        default=0,
        help_text="Maximum kiosk devices. 0 on free = disabled, 0 on paid = unlimited."
    )

    # Feature flags
    video_enabled = models.BooleanField(default=False)
    custom_branding = models.BooleanField(default=False)
    api_access = models.BooleanField(default=False)
    priority_support = models.BooleanField(default=False)
    offline_kiosk = models.BooleanField(default=False)

    class Meta:
        ordering = ['monthly_price_cents']

    def __str__(self):
        return self.display_name

    @classmethod
    def get_plan(cls, plan_name):
        """Get plan limits by name, with fallback defaults."""
        try:
            return cls.objects.get(plan=plan_name)
        except cls.DoesNotExist:
            # Return default free plan if not found
            return cls(
                plan='free',
                display_name='Free',
                max_events=1,
                max_waivers_per_month=10,
                max_storage_mb=100,
                max_team_members=1,
                max_kiosk_devices=0,  # Disabled on free
                video_enabled=False,
                custom_branding=False,
                api_access=False,
                priority_support=False,
                offline_kiosk=False,
            )
```

## 3.2 Data Population

### Pricing Tier Values

| Plan | Price | Events | Waivers/mo | Storage | Team | Kiosks | Video | Branding | Offline Kiosk | API | Priority |
|------|-------|--------|------------|---------|------|--------|-------|----------|---------------|-----|----------|
| **free** | $0 | 1 | 10 | 100 MB | 1 | - | ✗ | ✗ | ✗ | ✗ | ✗ |
| **starter** | $29 | 10 | 100 | 5 GB | 3 | 1 | ✓ | ✓ | ✗ | ✗ | ✗ |
| **professional** | $79 | 50 | 500 | 25 GB | 10 | 3 | ✓ | ✓ | ✓ | ✗ | ✗ |
| **enterprise** | $199 | ∞ | ∞ | 100 GB | ∞ | ∞ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Note:** Custom branding moved to Starter tier to support kiosk branding on device.

### Data Migration

```python
# Create a data migration after the schema migration

from django.db import migrations

def populate_plan_limits(apps, schema_editor):
    PlanLimit = apps.get_model('billing', 'PlanLimit')

    plans = [
        {
            'plan': 'free',
            'display_name': 'Free',
            'monthly_price_cents': 0,
            'max_events': 1,
            'max_waivers_per_month': 10,
            'max_storage_mb': 100,
            'max_team_members': 1,
            'max_kiosk_devices': 0,  # Disabled (not just unlimited)
            'video_enabled': False,
            'custom_branding': False,
            'api_access': False,
            'priority_support': False,
            'offline_kiosk': False,
        },
        {
            'plan': 'starter',
            'display_name': 'Starter',
            'monthly_price_cents': 2900,  # $29.00
            'max_events': 10,
            'max_waivers_per_month': 100,
            'max_storage_mb': 5120,  # 5 GB
            'max_team_members': 3,
            'max_kiosk_devices': 1,
            'video_enabled': True,
            'custom_branding': True,  # Moved to Starter for kiosk branding
            'api_access': False,
            'priority_support': False,
            'offline_kiosk': False,
        },
        {
            'plan': 'professional',
            'display_name': 'Professional',
            'monthly_price_cents': 7900,  # $79.00
            'max_events': 50,
            'max_waivers_per_month': 500,
            'max_storage_mb': 25600,  # 25 GB
            'max_team_members': 10,
            'max_kiosk_devices': 3,
            'video_enabled': True,
            'custom_branding': True,
            'api_access': False,
            'priority_support': False,
            'offline_kiosk': True,
        },
        {
            'plan': 'enterprise',
            'display_name': 'Enterprise',
            'monthly_price_cents': 19900,  # $199.00
            'max_events': 0,  # unlimited
            'max_waivers_per_month': 0,  # unlimited
            'max_storage_mb': 102400,  # 100 GB
            'max_team_members': 0,  # unlimited
            'max_kiosk_devices': 0,  # unlimited (0 means unlimited on paid plans)
            'video_enabled': True,
            'custom_branding': True,
            'api_access': True,
            'priority_support': True,
            'offline_kiosk': True,
        },
    ]

    for plan_data in plans:
        PlanLimit.objects.update_or_create(
            plan=plan_data['plan'],
            defaults=plan_data
        )

def reverse_populate(apps, schema_editor):
    PlanLimit = apps.get_model('billing', 'PlanLimit')
    PlanLimit.objects.all().delete()

class Migration(migrations.Migration):

    dependencies = [
        ('billing', 'XXXX_add_kiosk_fields'),  # Previous migration
    ]

    operations = [
        migrations.RunPython(populate_plan_limits, reverse_populate),
    ]
```

### Kiosk Device Limit Logic

The `max_kiosk_devices` field uses special logic:

```python
def is_kiosk_enabled(plan_limit):
    """Check if kiosk is available for this plan."""
    # Free plan: 0 means disabled
    if plan_limit.plan == 'free':
        return False
    # Paid plans: 0 means unlimited, >0 means limited
    return True

def get_kiosk_limit(plan_limit):
    """Get the actual kiosk device limit."""
    if plan_limit.plan == 'free':
        return 0  # Disabled
    if plan_limit.max_kiosk_devices == 0:
        return float('inf')  # Unlimited
    return plan_limit.max_kiosk_devices
```

## 3.3 Update Fallback in get_plan()

Update the fallback in `get_plan()` classmethod to include all new fields:

```python
@classmethod
def get_plan(cls, plan_name):
    """Get plan limits by name, with fallback defaults."""
    try:
        return cls.objects.get(plan=plan_name)
    except cls.DoesNotExist:
        return cls(
            plan='free',
            display_name='Free',
            max_events=1,
            max_waivers_per_month=10,
            max_storage_mb=100,
            max_team_members=1,
            max_kiosk_devices=0,  # Disabled on free
            video_enabled=False,
            custom_branding=False,
            api_access=False,
            priority_support=False,
            offline_kiosk=False,
        )
```

# 4. Future Considerations (Out of Scope)

- Annual pricing field (`annual_price_cents`) — can be calculated as monthly * 10
- Stripe price IDs for annual plans
- Plan comparison helper methods
- Usage enforcement middleware

# 5. Implementation Approach

## 5.1 Recommended Steps

1. Add `max_team_members` field to PlanLimit model
2. Run `makemigrations` and `migrate`
3. Create data migration to populate plan values
4. Update `get_plan()` fallback
5. Update admin display to show new field
6. Test plan retrieval

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| None | This is a foundational change |

# 6. Acceptance Criteria

## 6.1 Model Changes

- [ ] `max_team_members` field added to PlanLimit
- [ ] `max_kiosk_devices` field added to PlanLimit
- [ ] `offline_kiosk` field added to PlanLimit
- [ ] Migration runs without errors
- [ ] Fallback in `get_plan()` updated with all new fields

## 6.2 Data Population

- [ ] All 4 plans populated in database
- [ ] Free plan: events=1, waivers=10, storage=100MB, team=1, kiosks=0 (disabled)
- [ ] Starter plan: events=10, waivers=100, storage=5GB, team=3, kiosks=1
- [ ] Professional plan: events=50, waivers=500, storage=25GB, team=10, kiosks=3
- [ ] Enterprise plan: unlimited (0) for events/waivers/team/kiosks, storage=100GB

## 6.3 Feature Flags

- [ ] Free: all flags False
- [ ] Starter: video_enabled=True, custom_branding=True
- [ ] Professional: video_enabled=True, custom_branding=True, offline_kiosk=True
- [ ] Enterprise: all flags True (including offline_kiosk)

## 6.4 Kiosk Limits

- [ ] Free plan: kiosk disabled (max_kiosk_devices=0)
- [ ] Starter plan: 1 kiosk device allowed
- [ ] Professional plan: 3 kiosk devices, offline mode enabled
- [ ] Enterprise plan: unlimited kiosk devices, offline mode enabled

## 6.5 Admin

- [ ] `max_team_members` visible in admin
- [ ] `max_kiosk_devices` visible in admin
- [ ] `offline_kiosk` visible in admin
- [ ] All plan data visible and editable

---

# Changelog

## v1.1 - 2025-01-17
- Added `max_kiosk_devices` field for kiosk mode limits
- Added `offline_kiosk` feature flag
- Moved `custom_branding` to Starter tier (for kiosk branding)
- Added kiosk device limit logic documentation

## v1.0 - 2025-01-17
- Initial specification with `max_team_members`

---
*End of Specification*
