---
title: Plan Enforcement & Downgrade Rules
version: "1.2"
status: deployed
project: SignShield
created: 2025-01-17
updated: 2025-12-23
---

# 1. Executive Summary

Define and implement plan limit enforcement, downgrade validation rules, grace periods, and overage billing. This spec ensures tenants stay within their plan limits while providing a fair and predictable experience during plan changes.

Key features:
- **Limit enforcement** at creation time (events, team members, kiosks, waivers)
- **Downgrade validation** with blocking vs. warning issues
- **Overage billing** with admin-configurable rates
- **Grace periods** for payment failures and over-limit situations
- **Complimentary access** for beta testers, partners, and promotional accounts
- **Archive Only tier** for inactive tenants who need access to historical waivers

# 2. Current System State

## 2.1 Existing PlanLimit Model

Limits are defined but **not enforced**:

| Limit | Field | Enforcement |
|-------|-------|-------------|
| Events | `max_events` | ❌ Not enforced |
| Waivers/month | `max_waivers_per_month` | ❌ Not enforced |
| Storage | `max_storage_mb` | ❌ Not enforced |
| Team members | `max_team_members` | ❌ Not enforced |
| Kiosk devices | `max_kiosk_devices` | ❌ Not enforced |
| Video consent | `video_enabled` | ❌ Not enforced |
| Custom branding | `custom_branding` | ❌ Not enforced |
| API access | `api_access` | ❌ Not enforced |

## 2.2 Current Gaps

- No validation when creating events, waivers, team members
- No downgrade prevention or validation
- No grace period handling
- No overage tracking or billing
- No way to grant complimentary access
- No trial expiration handling

# 3. Downgrade Rules

## 3.1 Decision Summary

| Resource | Over Limit Behavior | Downgrade Rule |
|----------|---------------------|----------------|
| **Events** | Keep all, block new creation | Allow downgrade (soft block) |
| **Videos** | Keep existing, new can't have video | Allow downgrade |
| **Team Members** | N/A | **Prevent downgrade** until under limit |
| **Kiosks** | N/A | **Prevent downgrade** until under limit |
| **Storage** | Auto-archive oldest waivers | Allow downgrade (auto-resolve) |
| **Waivers/month** | Overage billing | Allow (billing handles it) |

## 3.2 Downgrade Validation

### Pre-Downgrade Check

```python
# apps/billing/services.py

class PlanDowngradeValidator:
    """Validates if a tenant can downgrade to a lower plan."""

    def __init__(self, tenant, new_plan):
        self.tenant = tenant
        self.current_plan = PlanLimit.get_plan(tenant.plan)
        self.new_plan = PlanLimit.get_plan(new_plan)
        self.blocking_issues = []
        self.warnings = []

    def validate(self):
        """Run all validation checks. Returns (can_downgrade, issues, warnings)."""
        self._check_team_members()
        self._check_kiosks()
        self._check_events()  # Warning only
        self._check_storage()  # Warning only
        self._check_videos()  # Warning only

        can_downgrade = len(self.blocking_issues) == 0
        return can_downgrade, self.blocking_issues, self.warnings

    def _check_team_members(self):
        """Team members BLOCK downgrade if over limit."""
        current_count = self.tenant.members.filter(is_active=True).count()
        new_limit = self.new_plan.max_team_members

        if new_limit > 0 and current_count > new_limit:
            self.blocking_issues.append({
                'type': 'team_members',
                'current': current_count,
                'limit': new_limit,
                'action_required': f'Remove {current_count - new_limit} team member(s)',
                'message': f'You have {current_count} team members but {self.new_plan.display_name} '
                           f'allows only {new_limit}. Please remove {current_count - new_limit} '
                           f'team member(s) before downgrading.'
            })

    def _check_kiosks(self):
        """Kiosks BLOCK downgrade if over limit."""
        current_count = KioskDevice.objects.filter(
            tenant=self.tenant,
            is_active=True
        ).count()
        new_limit = self.new_plan.max_kiosk_devices

        # Free plan: 0 means disabled, not unlimited
        if self.new_plan.plan == 'free' and current_count > 0:
            self.blocking_issues.append({
                'type': 'kiosks',
                'current': current_count,
                'limit': 0,
                'action_required': f'Deactivate all {current_count} kiosk device(s)',
                'message': f'Kiosk mode is not available on the Free plan. '
                           f'Please deactivate all {current_count} kiosk device(s) before downgrading.'
            })
        elif new_limit > 0 and current_count > new_limit:
            self.blocking_issues.append({
                'type': 'kiosks',
                'current': current_count,
                'limit': new_limit,
                'action_required': f'Deactivate {current_count - new_limit} kiosk device(s)',
                'message': f'You have {current_count} active kiosks but {self.new_plan.display_name} '
                           f'allows only {new_limit}. Please deactivate {current_count - new_limit} '
                           f'kiosk device(s) before downgrading.'
            })

    def _check_events(self):
        """Events generate WARNING only (soft block on creation)."""
        current_count = Event.objects.filter(tenant=self.tenant).count()
        new_limit = self.new_plan.max_events

        if new_limit > 0 and current_count > new_limit:
            self.warnings.append({
                'type': 'events',
                'current': current_count,
                'limit': new_limit,
                'message': f'You have {current_count} events but {self.new_plan.display_name} '
                           f'allows only {new_limit}. Your existing events will remain, '
                           f'but you won\'t be able to create new ones until you\'re under the limit.'
            })

    def _check_storage(self):
        """Storage generates WARNING only (auto-archive will handle)."""
        current_mb = self._calculate_storage_mb()
        new_limit = self.new_plan.max_storage_mb

        if new_limit > 0 and current_mb > new_limit:
            excess_mb = current_mb - new_limit
            self.warnings.append({
                'type': 'storage',
                'current': current_mb,
                'limit': new_limit,
                'message': f'You\'re using {current_mb} MB but {self.new_plan.display_name} '
                           f'allows only {new_limit} MB. Oldest waivers ({excess_mb} MB) '
                           f'will be archived to free up space.'
            })

    def _check_videos(self):
        """Videos generate WARNING only (existing kept, new blocked)."""
        if self.current_plan.video_enabled and not self.new_plan.video_enabled:
            video_count = SignedWaiver.objects.filter(
                tenant=self.tenant,
                video_file__isnull=False
            ).exclude(video_file='').count()

            if video_count > 0:
                self.warnings.append({
                    'type': 'videos',
                    'current': video_count,
                    'message': f'You have {video_count} waivers with video consent. '
                               f'These videos will be preserved, but new waivers on '
                               f'{self.new_plan.display_name} cannot include video recording.'
                })

    def _calculate_storage_mb(self):
        """Calculate total storage used by tenant."""
        from django.db.models import Sum
        from django.db.models.functions import Coalesce

        # This is approximate - actual implementation would query file sizes
        waiver_count = SignedWaiver.objects.filter(
            tenant=self.tenant,
            archival_status='active'
        ).count()

        # Estimate: 50KB PDF + 10KB signature + 15MB video average
        # In production, store actual file sizes
        avg_size_mb = 15  # Conservative estimate with video
        return waiver_count * avg_size_mb
```

### Downgrade Validation Flow

```
User requests downgrade
         │
         ▼
┌─────────────────────────┐
│ Run PlanDowngradeValidator │
└─────────────────────────┘
         │
         ▼
    ┌─────────┐
    │ Blocking │───Yes───▶ Show blocking issues
    │ Issues?  │           User must resolve
    └─────────┘           before downgrading
         │ No
         ▼
    ┌─────────┐
    │ Warnings │───Yes───▶ Show warnings
    │   ?      │           User confirms
    └─────────┘           understanding
         │ No/Confirmed
         ▼
┌─────────────────────────┐
│ Process Downgrade       │
│ - Update plan           │
│ - Archive excess storage│
│ - Apply soft blocks     │
└─────────────────────────┘
```

## 3.3 Downgrade UI

### Downgrade Confirmation Page

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Downgrade to Starter                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⚠️  ACTION REQUIRED                                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ You have 5 active team members but Starter allows only 3.           │   │
│  │                                                                     │   │
│  │ Please remove 2 team members before downgrading.                    │   │
│  │                                                             [Manage Team] │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ℹ️  CHANGES TO EXPECT                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • You have 15 events (Starter limit: 10)                            │   │
│  │   Your events will be preserved, but you can't create new ones      │   │
│  │   until you're under the limit.                                     │   │
│  │                                                                     │   │
│  │ • You're using 8 GB storage (Starter limit: 5 GB)                   │   │
│  │   Oldest waivers will be archived to free up 3 GB.                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [Cancel]                              [Downgrade to Starter] (disabled)   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

# 4. Limit Enforcement

## 4.1 Enforcement Points

| Resource | Enforcement Point | Behavior When Over Limit |
|----------|-------------------|--------------------------|
| Events | `Event.save()` / Create view | Block creation |
| Waivers/month | `SignedWaiver.save()` | Allow + track overage |
| Team Members | `TenantUser.save()` / Invite view | Block invite |
| Kiosks | `KioskDevice.save()` | Block creation |
| Storage | `SignedWaiver.save()` | Allow + warn |
| Video | Signing view / Kiosk | Disable video option |

## 4.2 Enforcement Middleware/Mixin

```python
# apps/billing/enforcement.py

from functools import wraps
from django.core.exceptions import PermissionDenied
from apps.billing.models import PlanLimit

class PlanLimitExceeded(PermissionDenied):
    """Raised when a plan limit is exceeded."""
    def __init__(self, limit_type, current, maximum, message=None):
        self.limit_type = limit_type
        self.current = current
        self.maximum = maximum
        self.message = message or f'{limit_type} limit exceeded ({current}/{maximum})'
        super().__init__(self.message)


class PlanEnforcementMixin:
    """Mixin for views that need plan limit enforcement."""

    def check_event_limit(self, tenant):
        """Check if tenant can create another event."""
        plan = PlanLimit.get_plan(tenant.plan)
        if plan.max_events == 0:  # Unlimited
            return True

        current = Event.objects.filter(tenant=tenant).count()
        if current >= plan.max_events:
            raise PlanLimitExceeded(
                'events',
                current,
                plan.max_events,
                f'You\'ve reached your event limit ({plan.max_events}). '
                f'Please upgrade your plan or delete unused events.'
            )
        return True

    def check_team_member_limit(self, tenant):
        """Check if tenant can add another team member."""
        plan = PlanLimit.get_plan(tenant.plan)
        if plan.max_team_members == 0:  # Unlimited
            return True

        current = tenant.members.filter(is_active=True).count()
        if current >= plan.max_team_members:
            raise PlanLimitExceeded(
                'team_members',
                current,
                plan.max_team_members,
                f'You\'ve reached your team member limit ({plan.max_team_members}). '
                f'Please upgrade your plan or remove inactive members.'
            )
        return True

    def check_kiosk_limit(self, tenant):
        """Check if tenant can add another kiosk."""
        plan = PlanLimit.get_plan(tenant.plan)

        # Free plan: kiosks disabled
        if tenant.plan == 'free':
            raise PlanLimitExceeded(
                'kiosks',
                0,
                0,
                'Kiosk mode is not available on the Free plan. Please upgrade.'
            )

        if plan.max_kiosk_devices == 0:  # Unlimited for paid plans
            return True

        current = KioskDevice.objects.filter(tenant=tenant, is_active=True).count()
        if current >= plan.max_kiosk_devices:
            raise PlanLimitExceeded(
                'kiosks',
                current,
                plan.max_kiosk_devices,
                f'You\'ve reached your kiosk device limit ({plan.max_kiosk_devices}). '
                f'Please upgrade your plan or deactivate unused kiosks.'
            )
        return True

    def check_video_enabled(self, tenant):
        """Check if tenant's plan includes video consent."""
        plan = PlanLimit.get_plan(tenant.plan)
        return plan.video_enabled

    def check_custom_branding(self, tenant):
        """Check if tenant's plan includes custom branding."""
        plan = PlanLimit.get_plan(tenant.plan)
        return plan.custom_branding

    def check_api_access(self, tenant):
        """Check if tenant's plan includes API access."""
        plan = PlanLimit.get_plan(tenant.plan)
        if not plan.api_access:
            raise PlanLimitExceeded(
                'api_access',
                0,
                0,
                'API access is not available on your plan. Please upgrade to Enterprise.'
            )
        return True
```

## 4.3 Model-Level Enforcement

```python
# apps/waivers/models/event.py

class Event(TenantMixin):
    # ... existing fields ...

    def save(self, *args, **kwargs):
        # Skip enforcement for updates
        if not self.pk:
            self._enforce_plan_limit()
        super().save(*args, **kwargs)

    def _enforce_plan_limit(self):
        """Enforce event limit on creation."""
        # Skip if tenant has complimentary access
        if self.tenant.is_complimentary:
            return

        plan = PlanLimit.get_plan(self.tenant.plan)
        if plan.max_events == 0:
            return  # Unlimited

        current = Event.objects.filter(tenant=self.tenant).count()
        if current >= plan.max_events:
            from apps.billing.enforcement import PlanLimitExceeded
            raise PlanLimitExceeded(
                'events', current, plan.max_events,
                f'Event limit reached ({plan.max_events}). Upgrade to create more events.'
            )
```

# 5. Overage Billing

## 5.1 Waiver Overage Tracking

When a tenant exceeds their monthly waiver limit, allow the waiver but track for billing.

### Overage Model

```python
# apps/billing/models.py

class UsageOverage(models.Model):
    """Tracks usage overages for billing."""

    tenant = models.ForeignKey('core.Tenant', on_delete=models.CASCADE, related_name='overages')
    billing_period_start = models.DateField()
    billing_period_end = models.DateField()

    # Waiver overage
    waivers_included = models.PositiveIntegerField(default=0)
    waivers_used = models.PositiveIntegerField(default=0)
    waivers_overage = models.PositiveIntegerField(default=0)
    overage_rate_cents = models.PositiveIntegerField(default=50)  # $0.50 per waiver

    # Calculated
    overage_amount_cents = models.PositiveIntegerField(default=0)

    # Billing status
    invoiced_at = models.DateTimeField(null=True, blank=True)
    invoice_id = models.CharField(max_length=100, blank=True)  # Stripe invoice ID

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['tenant', 'billing_period_start']
        ordering = ['-billing_period_start']

    def calculate_overage(self):
        """Calculate overage amount."""
        if self.waivers_used > self.waivers_included:
            self.waivers_overage = self.waivers_used - self.waivers_included
            self.overage_amount_cents = self.waivers_overage * self.overage_rate_cents
        else:
            self.waivers_overage = 0
            self.overage_amount_cents = 0
        self.save()
```

### Overage Tracking on Waiver Creation

```python
# apps/waivers/signals.py

from django.db.models.signals import post_save
from django.dispatch import receiver

@receiver(post_save, sender=SignedWaiver)
def track_waiver_usage(sender, instance, created, **kwargs):
    """Track waiver usage for overage billing."""
    if not created:
        return

    tenant = instance.tenant

    # Skip if complimentary
    if tenant.is_complimentary:
        return

    plan = PlanLimit.get_plan(tenant.plan)
    if plan.max_waivers_per_month == 0:
        return  # Unlimited

    # Get or create current billing period overage record
    today = timezone.now().date()
    period_start = today.replace(day=1)
    period_end = (period_start + timedelta(days=32)).replace(day=1) - timedelta(days=1)

    overage, created = UsageOverage.objects.get_or_create(
        tenant=tenant,
        billing_period_start=period_start,
        defaults={
            'billing_period_end': period_end,
            'waivers_included': plan.max_waivers_per_month,
            'overage_rate_cents': 50,  # $0.50 per waiver
        }
    )

    overage.waivers_used = SignedWaiver.objects.filter(
        tenant=tenant,
        signed_at__date__gte=period_start,
        signed_at__date__lte=period_end,
    ).count()

    overage.calculate_overage()

    # Notify tenant if they just went over
    if overage.waivers_used == overage.waivers_included + 1:
        send_overage_notification.delay(tenant.id, overage.id)
```

### Overage Notification

```python
@shared_task
def send_overage_notification(tenant_id, overage_id):
    """Notify tenant they've exceeded their waiver limit."""
    tenant = Tenant.objects.get(id=tenant_id)
    overage = UsageOverage.objects.get(id=overage_id)

    send_mail(
        subject=f'You\'ve exceeded your monthly waiver limit',
        message=f'''
Hi {tenant.company_name},

You've signed {overage.waivers_used} waivers this month, exceeding your plan limit of {overage.waivers_included}.

Additional waivers will be billed at ${overage.overage_rate_cents / 100:.2f} each.

Current overage: {overage.waivers_overage} waivers = ${overage.overage_amount_cents / 100:.2f}

To avoid overage charges, consider upgrading your plan:
https://{tenant.slug}.signshield.io/dashboard/settings/billing/

- The SignShield Team
        ''',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[tenant.owner_email],
    )
```

## 5.2 Configurable Pricing Model

Overage rates and storage costs are **admin-configurable**, not hardcoded.

### PricingConfig Model

```python
# apps/billing/models.py

class PricingConfig(models.Model):
    """Admin-configurable pricing for overages and storage."""

    # Singleton - only one row
    class Meta:
        verbose_name = "Pricing Configuration"
        verbose_name_plural = "Pricing Configuration"

    # Waiver overage rates (cents per waiver)
    overage_rate_starter_cents = models.PositiveIntegerField(
        default=50, help_text="Cents per waiver over limit (Starter plan)"
    )
    overage_rate_professional_cents = models.PositiveIntegerField(
        default=35, help_text="Cents per waiver over limit (Professional plan)"
    )

    # Archive storage costs (cents per GB per month)
    archive_storage_rate_cents = models.PositiveIntegerField(
        default=10, help_text="Cents per GB per month for archive storage"
    )

    # Archive restore costs (cents per restore request)
    archive_restore_rate_cents = models.PositiveIntegerField(
        default=100, help_text="Cents per archive restore request"
    )

    # Archive Only tier pricing (cents per month)
    archive_only_base_price_cents = models.PositiveIntegerField(
        default=500, help_text="Base monthly price for Archive Only tier (cents)"
    )

    updated_at = models.DateTimeField(auto_now=True)
    updated_by = models.ForeignKey(
        'auth.User', on_delete=models.SET_NULL, null=True, blank=True
    )

    @classmethod
    def get_config(cls):
        """Get or create the singleton config."""
        config, _ = cls.objects.get_or_create(pk=1)
        return config

    def get_overage_rate(self, plan):
        """Get overage rate in cents for a plan."""
        rates = {
            'starter': self.overage_rate_starter_cents,
            'professional': self.overage_rate_professional_cents,
        }
        return rates.get(plan, 0)
```

### Default Overage Rates

| Plan | Included Waivers | Default Overage Rate |
|------|------------------|----------------------|
| Free | 10 | N/A (blocked) |
| Starter | 100 | $0.50/waiver |
| Professional | 500 | $0.35/waiver |
| Enterprise | Unlimited | N/A |
| Archive Only | 0 | N/A (no new waivers) |

**Free plan:** No overage - hard block at limit.

### Admin Interface

```python
# apps/billing/admin.py

@admin.register(PricingConfig)
class PricingConfigAdmin(admin.ModelAdmin):
    list_display = ['__str__', 'overage_rate_starter_cents', 'overage_rate_professional_cents',
                    'archive_storage_rate_cents', 'updated_at']

    fieldsets = (
        ('Waiver Overage Rates', {
            'fields': ('overage_rate_starter_cents', 'overage_rate_professional_cents'),
            'description': 'Cost per waiver when tenant exceeds monthly limit'
        }),
        ('Archive Storage', {
            'fields': ('archive_storage_rate_cents', 'archive_restore_rate_cents'),
            'description': 'Costs for archived waiver storage and retrieval'
        }),
        ('Archive Only Tier', {
            'fields': ('archive_only_base_price_cents',),
            'description': 'Base monthly price for Archive Only tier'
        }),
    )

    def has_add_permission(self, request):
        return not PricingConfig.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
```

```python
# In waiver creation view/model

def check_waiver_limit(tenant):
    plan = PlanLimit.get_plan(tenant.plan)

    if plan.max_waivers_per_month == 0:
        return True  # Unlimited

    current_month_count = get_current_month_waiver_count(tenant)

    # Free plan: hard block
    if tenant.plan == 'free' and current_month_count >= plan.max_waivers_per_month:
        raise PlanLimitExceeded(
            'waivers',
            current_month_count,
            plan.max_waivers_per_month,
            'You\'ve reached your monthly waiver limit. Upgrade to sign more waivers.'
        )

    # Paid plans: allow overage
    return True
```

# 6. Grace Period

## 6.1 Grace Period Rules

| Trigger | Grace Period | After Expiry |
|---------|--------------|--------------|
| Trial ends | 14 days | Auto-downgrade to Free |
| Payment failed | 14 days | Block creation, force limits |
| Over limit (downgrade) | 14 days | Block creation, force limits |

## 6.2 Grace Period Model

```python
# apps/billing/models.py

class GracePeriod(models.Model):
    """Tracks grace periods for over-limit situations."""

    REASON_CHOICES = [
        ('trial_ended', 'Trial Ended'),
        ('payment_failed', 'Payment Failed'),
        ('downgrade_overlimit', 'Over Limit After Downgrade'),
    ]

    tenant = models.ForeignKey('core.Tenant', on_delete=models.CASCADE, related_name='grace_periods')
    reason = models.CharField(max_length=30, choices=REASON_CHOICES)

    started_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()

    # What limits are in grace
    over_limit_events = models.BooleanField(default=False)
    over_limit_storage = models.BooleanField(default=False)
    over_limit_team = models.BooleanField(default=False)
    over_limit_kiosks = models.BooleanField(default=False)

    # Resolution
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolution = models.CharField(max_length=50, blank=True)  # 'upgraded', 'reduced', 'expired'

    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['-started_at']

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at

    @property
    def days_remaining(self):
        if self.is_expired:
            return 0
        return (self.expires_at - timezone.now()).days

    @classmethod
    def create_for_tenant(cls, tenant, reason, days=14):
        """Create a grace period for a tenant."""
        # Deactivate any existing grace periods
        cls.objects.filter(tenant=tenant, is_active=True).update(
            is_active=False,
            resolved_at=timezone.now(),
            resolution='superseded'
        )

        return cls.objects.create(
            tenant=tenant,
            reason=reason,
            expires_at=timezone.now() + timedelta(days=days),
        )
```

## 6.3 Grace Period Enforcement

```python
# apps/billing/enforcement.py

def check_grace_period(tenant):
    """Check if tenant is in an expired grace period."""
    grace = GracePeriod.objects.filter(
        tenant=tenant,
        is_active=True,
    ).first()

    if not grace:
        return None

    if grace.is_expired:
        return {
            'expired': True,
            'reason': grace.get_reason_display(),
            'message': get_grace_expired_message(grace),
        }

    return {
        'expired': False,
        'days_remaining': grace.days_remaining,
        'reason': grace.get_reason_display(),
        'message': f'You have {grace.days_remaining} days to resolve your account status.',
    }


def get_grace_expired_message(grace):
    """Get appropriate message for expired grace period."""
    messages = {
        'trial_ended': 'Your trial has ended. Your account has been downgraded to the Free plan.',
        'payment_failed': 'Your payment has failed. Please update your payment method to continue.',
        'downgrade_overlimit': 'Your grace period has expired. Some features are now restricted.',
    }
    return messages.get(grace.reason, 'Your grace period has expired.')
```

## 6.4 Grace Period Expiry Task

```python
# apps/billing/tasks.py

@shared_task
def process_expired_grace_periods():
    """Daily task to handle expired grace periods."""
    expired = GracePeriod.objects.filter(
        is_active=True,
        expires_at__lt=timezone.now(),
    ).select_related('tenant')

    for grace in expired:
        tenant = grace.tenant

        if grace.reason == 'trial_ended':
            # Downgrade to Free
            tenant.plan = 'free'
            tenant.save()
            grace.resolution = 'auto_downgraded'

        elif grace.reason == 'payment_failed':
            # Block account until payment resolved
            tenant.is_active = False
            tenant.save()
            grace.resolution = 'account_blocked'

        elif grace.reason == 'downgrade_overlimit':
            # Apply hard limits
            apply_hard_limits(tenant, grace)
            grace.resolution = 'limits_enforced'

        grace.is_active = False
        grace.resolved_at = timezone.now()
        grace.save()

        # Notify tenant
        send_grace_expired_notification.delay(tenant.id, grace.id)


def apply_hard_limits(tenant, grace):
    """Apply hard limits after grace period expires."""
    plan = PlanLimit.get_plan(tenant.plan)

    # Events: soft block already in place (can't create new)

    # Storage: archive excess
    if grace.over_limit_storage:
        archive_excess_storage.delay(tenant.id)

    # Team: deactivate excess members (keep owner + most recent)
    # Actually, we require them to fix this before downgrade, so shouldn't happen

    # Kiosks: deactivate excess
    # Same - required before downgrade
```

# 7. Complimentary Access

## 7.1 Complimentary Access Flag

For beta testers, partners, employees, and promotional accounts.

### Tenant Model Addition

```python
# apps/core/models.py - Add to Tenant model

class Tenant(models.Model):
    # ... existing fields ...

    # Complimentary access
    is_complimentary = models.BooleanField(
        default=False,
        help_text="Grant free access at current plan level (no billing)"
    )
    complimentary_reason = models.CharField(
        max_length=50,
        blank=True,
        choices=[
            ('beta_tester', 'Beta Tester'),
            ('partner', 'Partner'),
            ('employee', 'Employee'),
            ('promotional', 'Promotional'),
            ('investor', 'Investor'),
            ('nonprofit', 'Nonprofit'),
            ('other', 'Other'),
        ]
    )
    complimentary_notes = models.TextField(
        blank=True,
        help_text="Internal notes about complimentary access"
    )
    complimentary_granted_at = models.DateTimeField(null=True, blank=True)
    complimentary_granted_by = models.ForeignKey(
        'auth.User',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='complimentary_grants'
    )
    complimentary_expires_at = models.DateTimeField(
        null=True, blank=True,
        help_text="When complimentary access expires (null = never)"
    )
```

| Field | Type | Description |
|-------|------|-------------|
| `is_complimentary` | BooleanField | Enable free access |
| `complimentary_reason` | CharField | Why they have free access |
| `complimentary_notes` | TextField | Internal notes |
| `complimentary_granted_at` | DateTimeField | When granted |
| `complimentary_granted_by` | ForeignKey | Admin who granted |
| `complimentary_expires_at` | DateTimeField | When it expires (null = never) |

## 7.2 Complimentary Access Behavior

When `is_complimentary = True`:

| Feature | Behavior |
|---------|----------|
| Plan limits | **Enforced** (at their plan level) |
| Billing | **Skipped** (no charges) |
| Overage billing | **Skipped** |
| Trial expiration | **Skipped** |
| Downgrade validation | **Normal** (still enforced) |
| Feature access | **Based on plan** |

**Example:**
- Tenant on Professional plan with `is_complimentary = True`
- Gets all Professional features (50 events, 3 kiosks, etc.)
- No monthly charge
- No overage charges
- Limits still enforced (can't exceed Professional limits)

## 7.3 Admin Interface

```python
# apps/core/admin.py

@admin.register(Tenant)
class TenantAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'plan', 'is_complimentary', 'is_active']
    list_filter = ['plan', 'is_complimentary', 'is_active', 'complimentary_reason']

    fieldsets = (
        (None, {
            'fields': ('name', 'slug', 'company_name', 'owner_email')
        }),
        ('Plan', {
            'fields': ('plan', 'is_active')
        }),
        ('Complimentary Access', {
            'fields': (
                'is_complimentary',
                'complimentary_reason',
                'complimentary_notes',
                'complimentary_expires_at',
            ),
            'classes': ('collapse',),
        }),
    )

    actions = ['grant_complimentary_access', 'revoke_complimentary_access']

    def grant_complimentary_access(self, request, queryset):
        queryset.update(
            is_complimentary=True,
            complimentary_granted_at=timezone.now(),
            complimentary_granted_by=request.user,
        )
        self.message_user(request, f'Granted complimentary access to {queryset.count()} tenant(s)')
    grant_complimentary_access.short_description = "Grant complimentary access"

    def revoke_complimentary_access(self, request, queryset):
        queryset.update(is_complimentary=False)
        self.message_user(request, f'Revoked complimentary access from {queryset.count()} tenant(s)')
    revoke_complimentary_access.short_description = "Revoke complimentary access"
```

## 7.4 Complimentary Expiry Task

```python
@shared_task
def check_complimentary_expiry():
    """Daily task to expire complimentary access."""
    expired = Tenant.objects.filter(
        is_complimentary=True,
        complimentary_expires_at__lt=timezone.now(),
    )

    for tenant in expired:
        tenant.is_complimentary = False
        tenant.save()

        # Notify tenant
        send_mail(
            subject='Your complimentary SignShield access has ended',
            message=f'''
Hi {tenant.company_name},

Your complimentary access to SignShield has ended.

To continue using SignShield, please add a payment method:
https://{tenant.slug}.signshield.io/dashboard/settings/billing/

Your current plan: {tenant.get_plan_display()}

If you have questions, please contact support.

- The SignShield Team
            ''',
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[tenant.owner_email],
        )

    return expired.count()
```

# 8. Trial Period Handling

## 8.1 Trial Flow

```
New tenant signs up
         │
         ▼
┌─────────────────────────┐
│ Start on FREE plan      │
│ is_complimentary = False│
└─────────────────────────┘
         │
         │ (No trial - start free)
         ▼
    Use free plan
         │
         │ Upgrade when ready
         ▼
    Choose paid plan
```

**Note:** Based on earlier decision, new users start on FREE plan (not trial). They upgrade when ready. No trial period to manage.

# 9. Archive Only Tier

## 9.1 Purpose

The **Archive Only** tier is for tenants who have cancelled their subscription but still need access to their historical waiver data. They can't create new waivers or events, but can search and restore archived waivers.

## 9.2 Tier Characteristics

| Feature | Archive Only |
|---------|--------------|
| Price | $5/month base (configurable) + storage costs |
| Events | 0 (read-only access to existing) |
| Waivers/month | 0 (cannot create new) |
| Storage | Pay per GB ($0.10/GB/month default) |
| Team members | 1 (owner only) |
| Kiosk devices | 0 |
| Video enabled | N/A |
| Custom branding | No |
| API access | No |
| Archive access | ✅ Yes |
| Restore duration | **15 days** (vs 30 for active plans) |

## 9.3 Billing Model

```python
# Monthly Archive Only bill calculation

def calculate_archive_bill(tenant):
    """Calculate monthly bill for Archive Only tier."""
    config = PricingConfig.get_config()

    # Base price
    base_price_cents = config.archive_only_base_price_cents  # Default: 500 ($5)

    # Storage cost
    archive_storage_gb = get_tenant_archive_storage_gb(tenant)
    storage_cost_cents = archive_storage_gb * config.archive_storage_rate_cents  # Default: 10¢/GB

    # Restore requests this month
    restore_count = ArchiveRestoreRequest.objects.filter(
        tenant=tenant,
        requested_at__month=timezone.now().month,
        requested_at__year=timezone.now().year,
    ).count()
    restore_cost_cents = restore_count * config.archive_restore_rate_cents  # Default: $1/restore

    total_cents = base_price_cents + storage_cost_cents + restore_cost_cents

    return {
        'base_price_cents': base_price_cents,
        'storage_gb': archive_storage_gb,
        'storage_cost_cents': storage_cost_cents,
        'restore_count': restore_count,
        'restore_cost_cents': restore_cost_cents,
        'total_cents': total_cents,
    }
```

### Example Bills

| Scenario | Base | Storage | Restores | Total |
|----------|------|---------|----------|-------|
| 5 GB archived, 0 restores | $5.00 | $0.50 | $0.00 | $5.50 |
| 20 GB archived, 2 restores | $5.00 | $2.00 | $2.00 | $9.00 |
| 100 GB archived, 5 restores | $5.00 | $10.00 | $5.00 | $20.00 |

## 9.4 15-Day Restore Window

For Archive Only tenants, restored waivers are only accessible for **15 days** (vs 30 days for active plans). This encourages tenants to download/export what they need and return to archived state.

```python
# apps/waivers/tasks.py

@shared_task
def restore_archived_waiver(waiver_id):
    """Restore a waiver from archive."""
    waiver = SignedWaiver.objects.get(id=waiver_id)
    tenant = waiver.tenant

    # Determine restore duration based on plan
    if tenant.plan == 'archive_only':
        restore_days = 15
    else:
        restore_days = 30

    waiver.archival_status = 'restoring'
    waiver.restore_expires_at = timezone.now() + timedelta(days=restore_days)
    waiver.save()

    # Trigger S3 Glacier restore (from waiver_archival spec)
    initiate_glacier_restore(waiver)
```

## 9.5 Tenant Downgrade to Archive Only

When a tenant cancels or chooses Archive Only:

```
Active tenant cancels subscription
              │
              ▼
    ┌─────────────────────────┐
    │  Archive all active     │
    │  waivers immediately    │
    └─────────────────────────┘
              │
              ▼
    ┌─────────────────────────┐
    │  Deactivate all:        │
    │  - Events               │
    │  - Kiosks               │
    │  - Team members         │
    │  (Owner remains)        │
    └─────────────────────────┘
              │
              ▼
    ┌─────────────────────────┐
    │  Set plan = archive_only│
    │  Begin archive billing  │
    └─────────────────────────┘
```

### Downgrade to Archive Only Task

```python
@shared_task
def downgrade_to_archive_only(tenant_id):
    """Downgrade tenant to Archive Only tier."""
    tenant = Tenant.objects.get(id=tenant_id)

    # Archive all active waivers
    active_waivers = SignedWaiver.objects.filter(
        tenant=tenant,
        archival_status='active'
    )
    for waiver in active_waivers:
        archive_waiver.delay(waiver.id)

    # Deactivate events
    Event.objects.filter(tenant=tenant).update(is_active=False)

    # Deactivate kiosks
    KioskDevice.objects.filter(tenant=tenant).update(is_active=False)

    # Remove team members (keep owner)
    TenantUser.objects.filter(
        tenant=tenant,
        is_owner=False
    ).update(is_active=False)

    # Update plan
    tenant.plan = 'archive_only'
    tenant.save()

    # Notify tenant
    send_mail(
        subject='Your SignShield account is now on Archive Only',
        message=f'''
Hi {tenant.company_name},

Your SignShield account has been switched to the Archive Only plan.

What this means:
- You cannot create new waivers or events
- Your existing waivers are archived in cold storage
- You can search and restore archived waivers anytime
- Restored waivers are accessible for 15 days

Monthly billing:
- Base fee: ${config.archive_only_base_price_cents / 100:.2f}/month
- Storage: ${config.archive_storage_rate_cents / 100:.2f}/GB/month
- Restores: ${config.archive_restore_rate_cents / 100:.2f} per restore request

To view your archived waivers:
https://{tenant.slug}.signshield.io/dashboard/archives/

To reactivate your account, upgrade to any active plan.

- The SignShield Team
        ''',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[tenant.owner_email],
    )
```

## 9.6 Archive Only Dashboard

Archive Only tenants see a simplified dashboard:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Archive Only Plan                                     [Upgrade to Reactivate]│
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  📦 Your Archives                                                           │
│                                                                             │
│  Total archived waivers: 1,247                                              │
│  Archive storage: 15.3 GB                                                   │
│  Estimated monthly cost: $6.53                                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  🔍 Search Archives                                                  │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │  Signer name, email, or waiver ID...                          │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                             [Search] [Advanced]     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Recently Restored (expires in X days)                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ John Smith - Adventure Waiver - expires in 12 days    [View] [Download] │
│  │ Jane Doe - Liability Waiver - expires in 3 days       [View] [Download] │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 9.7 PlanLimit Entry for Archive Only

```python
# Add to plan choices
PLAN_CHOICES = [
    ('free', 'Free'),
    ('starter', 'Starter'),
    ('professional', 'Professional'),
    ('enterprise', 'Enterprise'),
    ('archive_only', 'Archive Only'),  # New
]

# PlanLimit defaults for Archive Only
{
    'plan': 'archive_only',
    'display_name': 'Archive Only',
    'max_events': 0,
    'max_waivers_per_month': 0,
    'max_storage_mb': 0,  # Unlimited archive storage (pay per GB)
    'max_team_members': 1,
    'max_kiosk_devices': 0,
    'video_enabled': False,
    'custom_branding': False,
    'api_access': False,
    'offline_kiosk': False,
}
```

# 10. Dashboard Notifications

## 10.1 Limit Warning Banner

When tenant is approaching or over limits:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ⚠️  You've used 95 of 100 waivers this month.                    [Upgrade] │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ ⚠️  You have 15 events but your plan allows 10.                            │
│     You can't create new events until you upgrade or delete some.          │
│                                                        [Upgrade] [Manage Events] │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ ⏰  Your grace period expires in 5 days.                                    │
│     Please upgrade or reduce usage to avoid service interruption.          │
│                                                        [Upgrade] [Learn More] │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 10.2 Usage Dashboard Widget

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Plan Usage - Starter ($29/mo)                            [Upgrade Plan]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Events              ████████████████░░░░░░░░░░░░░░░░░░░░░░░░   8 / 10    │
│  Waivers this month  ████████████████████████████████░░░░░░░░  85 / 100   │
│  Team members        ████████████████████░░░░░░░░░░░░░░░░░░░░   2 / 3     │
│  Kiosk devices       ██████████████████████████████████████████  1 / 1     │
│  Storage             ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  1.2 / 5 GB │
│                                                                             │
│  ✓ Video consent enabled                                                   │
│  ✓ Custom branding enabled                                                 │
│  ✗ API access (upgrade to Enterprise)                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

# 11. Implementation Approach

## 11.1 Recommended Phases

**Phase 1: Data Models**
1. Create PricingConfig model (singleton for configurable pricing)
2. Add complimentary access fields to Tenant
3. Add archival_status to SignedWaiver (if not done)
4. Create UsageOverage model
5. Create GracePeriod model
6. Add 'archive_only' to PLAN_CHOICES
7. Run migrations

**Phase 2: Enforcement Logic**
1. Create PlanEnforcementMixin
2. Add enforcement to Event creation
3. Add enforcement to TenantUser creation
4. Add enforcement to KioskDevice creation
5. Add waiver count enforcement (Free = hard, Paid = soft)

**Phase 3: Downgrade Validation**
1. Create PlanDowngradeValidator
2. Add validation to plan change flow
3. Create downgrade confirmation UI
4. Handle auto-archive for storage excess (automatic, no confirmation)

**Phase 4: Overage Billing**
1. Track waiver usage per billing period
2. Send overage notifications
3. Integrate with Stripe for overage invoicing
4. Use PricingConfig for configurable rates

**Phase 5: Grace Periods**
1. Create grace period on payment failure
2. Create grace period on over-limit downgrade
3. Daily task to process expired grace periods
4. Grace period notifications

**Phase 6: Archive Only Tier**
1. Add archive_only plan to PlanLimit
2. Create downgrade_to_archive_only task
3. Create archive billing calculation
4. Create Archive Only dashboard view
5. Implement 15-day restore window for archive_only tenants

**Phase 7: Admin & UI**
1. PricingConfig admin interface
2. Usage dashboard widget
3. Limit warning banners
4. Upgrade prompts
5. Admin complimentary access management

## 11.2 Spec Dependencies

This spec has **hard dependencies** on other specs that must be implemented first.

### Required Before Implementation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEPENDENCY CHAIN                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐       ┌─────────────────────┐                     │
│  │  planlimit_update   │       │  waiver_archival    │                     │
│  │  (In Development)   │       │  (Draft)            │                     │
│  │                     │       │                     │                     │
│  │  Provides:          │       │  Provides:          │                     │
│  │  • PlanLimit model  │       │  • archival_status  │                     │
│  │  • max_events       │       │  • S3 Glacier       │                     │
│  │  • max_waivers      │       │  • restore workflow │                     │
│  │  • max_storage_mb   │       │  • archive search   │                     │
│  │  • max_team_members │       │                     │                     │
│  │  • max_kiosk_devices│       │                     │                     │
│  │  • video_enabled    │       │                     │                     │
│  │  • custom_branding  │       │                     │                     │
│  │  • api_access       │       │                     │                     │
│  │  • offline_kiosk    │       │                     │                     │
│  └──────────┬──────────┘       └──────────┬──────────┘                     │
│             │                              │                                │
│             │         REQUIRED BY          │                                │
│             └──────────────┬───────────────┘                                │
│                            ▼                                                │
│              ┌─────────────────────────┐                                   │
│              │   plan_enforcement      │                                   │
│              │   (This Spec)           │                                   │
│              │                         │                                   │
│              │   Uses from planlimit:  │                                   │
│              │   • All limit fields    │                                   │
│              │   • PlanLimit.get_plan()│                                   │
│              │   • PLAN_CHOICES        │                                   │
│              │                         │                                   │
│              │   Uses from archival:   │                                   │
│              │   • archival_status     │                                   │
│              │   • archive_waiver()    │                                   │
│              │   • restore_waiver()    │                                   │
│              │   • Archive Only tier   │                                   │
│              └─────────────────────────┘                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Dependency Details

| Spec | Status | Required For | Specific Dependencies |
|------|--------|--------------|----------------------|
| **planlimit_update.md** | In Development | All enforcement | `PlanLimit.get_plan()`, all `max_*` fields, feature flags |
| **waiver_archival.md** | Draft | Archive Only tier, storage excess handling | `archival_status` field, `archive_waiver()` task, S3 integration |

### Fields Required from planlimit_update

The `PlanEnforcementMixin` and `PlanDowngradeValidator` require these fields to exist:

```python
# From PlanLimit model (planlimit_update.md)
plan.max_events              # Event limit enforcement
plan.max_waivers_per_month   # Waiver limit + overage billing
plan.max_storage_mb          # Storage limit + auto-archive
plan.max_team_members        # Team member limit (blocks downgrade)
plan.max_kiosk_devices       # Kiosk limit (blocks downgrade)
plan.video_enabled           # Video consent enforcement
plan.custom_branding         # Branding feature check
plan.api_access              # API access enforcement
plan.offline_kiosk           # Offline kiosk feature check
```

### Functions Required from waiver_archival

The Archive Only tier and storage excess handling require these:

```python
# From waiver_archival.md
waiver.archival_status       # 'active', 'archived', 'restoring', 'restored'
archive_waiver.delay(id)     # Celery task to archive a waiver
restore_archived_waiver.delay(id)  # Celery task to restore
get_tenant_archive_storage_gb(tenant)  # Calculate archive size
```

### PLAN_CHOICES Update Required

This spec adds `archive_only` to PLAN_CHOICES. This should be done in this spec's migration, after planlimit_update is complete:

```python
# Update PLAN_CHOICES in PlanLimit model
PLAN_CHOICES = [
    ('free', 'Free'),
    ('starter', 'Starter'),
    ('professional', 'Professional'),
    ('enterprise', 'Enterprise'),
    ('archive_only', 'Archive Only'),  # Added by plan_enforcement
]
```

### Implementation Order

```
1. planlimit_update.md     ─┐
                            ├──► 3. plan_enforcement.md
2. waiver_archival.md      ─┘
```

**Note:** Phases 1-5 of plan_enforcement can begin once planlimit_update is complete. Phase 6 (Archive Only Tier) requires waiver_archival to be complete.

## 11.3 Infrastructure Dependencies

| Dependency | Required For | Notes |
|------------|--------------|-------|
| Stripe integration | Overage/archive billing | Existing in billing app |
| Celery Beat | Scheduled tasks | Grace expiry, complimentary expiry |
| Email configuration | Notifications | Overage, grace, expiry emails |
| AWS S3 + Glacier | Archive Only tier | From waiver_archival spec |

# 12. Acceptance Criteria

## 12.1 Limit Enforcement

- [ ] Cannot create event over limit (except complimentary)
- [ ] Cannot add team member over limit
- [ ] Cannot add kiosk over limit
- [ ] Cannot record video if not enabled on plan
- [ ] Free plan hard blocked at waiver limit
- [ ] Paid plans allow waiver overage

## 12.2 Downgrade Validation

- [ ] Blocked if team members over new limit
- [ ] Blocked if kiosks over new limit
- [ ] Warning shown for events over limit
- [ ] Warning shown for storage over limit
- [ ] Warning shown for videos on non-video plan
- [ ] Downgrade button disabled until blocking issues resolved
- [ ] Storage excess automatically archived (no confirmation)

## 12.3 Overage Billing

- [ ] Waiver overage tracked per billing period
- [ ] Notification sent when limit exceeded
- [ ] Overage amount calculated correctly
- [ ] Overage invoiced via Stripe
- [ ] Overage rates configurable in admin

## 12.4 Grace Periods

- [ ] Grace period created on payment failure
- [ ] Grace period created on over-limit downgrade
- [ ] 14-day grace period duration
- [ ] Notifications sent during grace period
- [ ] Auto-downgrade to Free when trial grace expires
- [ ] Creation blocked when grace period expires

## 12.5 Complimentary Access

- [ ] Can grant complimentary via admin
- [ ] Can set expiration date
- [ ] No billing for complimentary tenants
- [ ] Limits still enforced at plan level
- [ ] Auto-expire complimentary access
- [ ] Notification sent on expiry

## 12.6 Configurable Pricing

- [ ] PricingConfig model created as singleton
- [ ] Admin can edit overage rates (Starter, Professional)
- [ ] Admin can edit archive storage rate
- [ ] Admin can edit archive restore rate
- [ ] Admin can edit Archive Only base price
- [ ] Billing calculations use PricingConfig values

## 12.7 Archive Only Tier

- [ ] 'archive_only' plan added to choices
- [ ] Tenant can downgrade to Archive Only
- [ ] All active waivers archived on downgrade
- [ ] Events, kiosks, team members deactivated on downgrade
- [ ] Archive Only dashboard shows storage and costs
- [ ] Archive search works for Archive Only tenants
- [ ] Restored waivers expire after 15 days (not 30)
- [ ] Monthly billing: base + storage + restores
- [ ] Can upgrade from Archive Only to active plan

## 12.8 Dashboard UI

- [ ] Usage widget shows all limits
- [ ] Warning banner for approaching limits
- [ ] Warning banner for grace period
- [ ] Upgrade prompts at appropriate points
- [ ] Archive Only dashboard shows simplified view

---

# Changelog

## v1.2 - 2025-01-17
- Added comprehensive dependency documentation (Section 11.2)
- Documented dependency on planlimit_update.md and waiver_archival.md
- Added dependency chain diagram
- Clarified implementation order requirements

## v1.1 - 2025-01-17
- Added PricingConfig model for admin-configurable overage and storage rates
- Added Archive Only tier (Section 9)
- Archive Only: $5/month base + $0.10/GB storage + $1.00/restore
- Archive Only: 15-day restore window (vs 30 for active plans)
- Clarified automatic storage archival (no user confirmation needed)
- Added Phase 6 and 7 to implementation approach

## v1.0 - 2025-01-17
- Initial specification
- Limit enforcement, downgrade validation, overage billing
- Grace periods, complimentary access

---
*End of Specification*
