---
title: Kiosk Mode
version: "1.1"
status: deployed
project: SignShield
created: 2025-01-17
updated: 2025-12-23
---

# 1. Executive Summary

Add kiosk mode to SignShield, enabling businesses to set up tablets or devices at their location where walk-in participants can sign waivers on the spot. Kiosk mode provides a streamlined, locked-down signing interface optimized for high-volume, in-person waiver collection.

# 2. Current System State

## 2.1 Existing Signing Flow

| Method | Description | Use Case |
|--------|-------------|----------|
| Email Link | SigningLink sent via email | Remote signing, advance registration |
| Direct Link | URL shared manually | SMS, QR codes, social media |

## 2.2 Current Gaps

- No on-site signing solution
- No device lockdown mode
- No offline capability
- No walk-in participant flow
- Businesses must email links even for in-person sign-ups

## 2.3 Market Context

Competitors with kiosk mode:
- WaiverSign ($29/mo for 1 kiosk)
- Waiver Forever (included in Pro plan)
- Smartwaiver ($50/mo add-on)

Kiosk mode is expected for businesses with physical locations.

# 3. Feature Requirements

## 3.1 Kiosk Device Model

### Data Structure

```python
# apps/waivers/models.py (add to existing)

class KioskDevice(TenantMixin):
    """Represents a registered kiosk device"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Device identification
    name = models.CharField(max_length=100)  # e.g., "Front Desk iPad"
    device_token = models.CharField(max_length=64, unique=True, db_index=True)

    # Configuration
    event = models.ForeignKey(
        'Event',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='kiosk_devices',
        help_text="Default event for this kiosk. If null, user selects event."
    )
    waiver_template = models.ForeignKey(
        'WaiverTemplate',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='kiosk_devices',
        help_text="Default template. If null, uses event's template."
    )

    # Security
    exit_pin = models.CharField(
        max_length=10,
        help_text="PIN required to exit kiosk mode"
    )
    auto_lock_minutes = models.PositiveIntegerField(
        default=5,
        help_text="Lock to home screen after inactivity"
    )

    # Capabilities
    allow_video = models.BooleanField(
        default=True,
        help_text="Enable video recording (requires plan support)"
    )
    allow_photo = models.BooleanField(
        default=False,
        help_text="Capture signer photo"
    )
    allow_minor_flow = models.BooleanField(
        default=True,
        help_text="Enable guardian signing for minors"
    )

    # Offline
    offline_enabled = models.BooleanField(
        default=False,
        help_text="Allow offline signing with sync (requires plan support)"
    )
    last_sync_at = models.DateTimeField(null=True, blank=True)

    # Status
    is_active = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return f"{self.name} ({self.tenant.name})"

    @classmethod
    def generate_device_token(cls):
        """Generate a secure device token"""
        import secrets
        return secrets.token_urlsafe(48)

    def check_plan_limits(self):
        """Verify tenant hasn't exceeded kiosk device limit"""
        from apps.billing.models import PlanLimit
        plan = PlanLimit.get_plan(self.tenant.plan)

        if plan.max_kiosk_devices == 0 and self.tenant.plan == 'free':
            raise ValidationError("Kiosk mode not available on Free plan")

        current_count = KioskDevice.objects.filter(
            tenant=self.tenant,
            is_active=True
        ).exclude(pk=self.pk).count()

        if plan.max_kiosk_devices > 0 and current_count >= plan.max_kiosk_devices:
            raise ValidationError(
                f"Kiosk device limit reached ({plan.max_kiosk_devices} devices)"
            )
```

| Field | Type | Description |
|-------|------|-------------|
| id | UUIDField | Primary key |
| name | CharField(100) | Human-readable device name |
| device_token | CharField(64) | Secure token for device auth |
| event | ForeignKey | Default event (optional) |
| waiver_template | ForeignKey | Default template (optional) |
| exit_pin | CharField(10) | PIN to exit kiosk mode |
| auto_lock_minutes | PositiveIntegerField | Inactivity timeout |
| allow_video | BooleanField | Enable video capture |
| allow_photo | BooleanField | Enable photo capture |
| allow_minor_flow | BooleanField | Enable guardian signing |
| offline_enabled | BooleanField | Enable offline mode |
| last_sync_at | DateTimeField | Last successful sync |
| is_active | BooleanField | Device active/deactivated |
| last_seen_at | DateTimeField | Last heartbeat |

## 3.2 Kiosk Session Model

### Data Structure

```python
# apps/waivers/models.py

class KioskSession(models.Model):
    """Tracks individual signing sessions on a kiosk"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    kiosk_device = models.ForeignKey(
        'KioskDevice',
        on_delete=models.CASCADE,
        related_name='sessions'
    )

    # Link to signed waiver (once complete)
    signed_waiver = models.OneToOneField(
        'SignedWaiver',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='kiosk_session'
    )

    # Session tracking
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    abandoned_at = models.DateTimeField(null=True, blank=True)

    # For offline sync
    offline_data = models.JSONField(null=True, blank=True)
    synced_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-started_at']
```

## 3.3 Kiosk URL Structure

```python
# URLs for kiosk mode

urlpatterns = [
    # Kiosk setup & management (dashboard)
    path('dashboard/kiosks/', KioskListView.as_view(), name='kiosk_list'),
    path('dashboard/kiosks/new/', KioskCreateView.as_view(), name='kiosk_create'),
    path('dashboard/kiosks/<uuid:pk>/', KioskDetailView.as_view(), name='kiosk_detail'),
    path('dashboard/kiosks/<uuid:pk>/edit/', KioskUpdateView.as_view(), name='kiosk_update'),
    path('dashboard/kiosks/<uuid:pk>/deactivate/', KioskDeactivateView.as_view(), name='kiosk_deactivate'),

    # Kiosk device interface (public, token-authenticated)
    path('kiosk/<str:token>/', KioskHomeView.as_view(), name='kiosk_home'),
    path('kiosk/<str:token>/sign/', KioskSignView.as_view(), name='kiosk_sign'),
    path('kiosk/<str:token>/sign/submit/', KioskSubmitView.as_view(), name='kiosk_submit'),
    path('kiosk/<str:token>/success/', KioskSuccessView.as_view(), name='kiosk_success'),
    path('kiosk/<str:token>/exit/', KioskExitView.as_view(), name='kiosk_exit'),

    # Kiosk API (for offline sync)
    path('api/v1/kiosk/<str:token>/sync/', KioskSyncView.as_view(), name='kiosk_sync'),
    path('api/v1/kiosk/<str:token>/heartbeat/', KioskHeartbeatView.as_view(), name='kiosk_heartbeat'),
]
```

## 3.4 Kiosk Signing Flow

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     KIOSK HOME SCREEN                       │
│                                                             │
│     ┌─────────────────────────────────────────────┐        │
│     │                                             │        │
│     │           [Company Logo]                    │        │
│     │                                             │        │
│     │     Welcome to {Company Name}              │        │
│     │                                             │        │
│     │  ┌─────────────────────────────────────┐   │        │
│     │  │                                     │   │        │
│     │  │      TAP TO SIGN WAIVER            │   │        │
│     │  │                                     │   │        │
│     │  └─────────────────────────────────────┘   │        │
│     │                                             │        │
│     │     {Event Name} • {Date}                  │        │
│     │                                             │        │
│     └─────────────────────────────────────────────┘        │
│                                                             │
│  [Exit]                           Powered by SignShield    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    PARTICIPANT INFO                         │
│                                                             │
│     First Name: [________________]                         │
│     Last Name:  [________________]                         │
│     Email:      [________________]                         │
│     Phone:      [________________] (optional)              │
│                                                             │
│     ┌─────────────────────────────────────┐                │
│     │ ☐ I am signing for a minor (under 18) │                │
│     └─────────────────────────────────────┘                │
│                                                             │
│     [Cancel]                            [Continue →]       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    WAIVER CONTENT                           │
│                                                             │
│     ┌─────────────────────────────────────────────┐        │
│     │                                             │        │
│     │  [Scrollable waiver text]                  │        │
│     │                                             │        │
│     │  ...                                        │        │
│     │                                             │        │
│     └─────────────────────────────────────────────┘        │
│                                                             │
│     ☑ I have read and agree to the terms above            │
│                                                             │
│     [← Back]                            [Continue →]       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    VIDEO CONSENT                            │
│                    (if enabled)                             │
│                                                             │
│     ┌─────────────────────────────────────────────┐        │
│     │                                             │        │
│     │           [Camera Preview]                 │        │
│     │                                             │        │
│     └─────────────────────────────────────────────┘        │
│                                                             │
│     Please state: "My name is [your name] and I           │
│     agree to the waiver terms."                            │
│                                                             │
│     [← Back]         [🔴 Record]        [Skip if optional] │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      SIGNATURE                              │
│                                                             │
│     Please sign below:                                     │
│     ┌─────────────────────────────────────────────┐        │
│     │                                             │        │
│     │         [Signature Pad Canvas]             │        │
│     │                                             │        │
│     └─────────────────────────────────────────────┘        │
│     [Clear]                                                │
│                                                             │
│     ☑ I agree this is my legal signature                  │
│                                                             │
│     [← Back]                      [Complete Signing →]     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      SUCCESS                                │
│                                                             │
│                       ✓                                    │
│                                                             │
│              Thank you, {First Name}!                      │
│                                                             │
│           Your waiver has been submitted.                  │
│                                                             │
│     ┌─────────────────────────────────────────────┐        │
│     │  Email confirmation sent to {email}        │        │
│     └─────────────────────────────────────────────┘        │
│                                                             │
│           [Tap anywhere to continue]                       │
│                                                             │
│           Auto-reset in 5 seconds...                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    (Returns to Home Screen)
```

### Business Rules

1. **Auto-reset**: After success screen, return to home after 5 seconds or tap
2. **Timeout**: If no activity for X minutes, return to home (clear any partial data)
3. **Exit PIN**: Tapping "Exit" requires PIN entry to leave kiosk mode
4. **Video follows plan**: Video recording only available if plan has `video_enabled`
5. **Offline follows plan**: Offline mode only if plan has `offline_kiosk`
6. **Branding**: Show tenant logo/colors if plan has `custom_branding`, else SignShield default

## 3.5 Minor Participant Flow

When "signing for a minor" is checked:

```
┌─────────────────────────────────────────────────────────────┐
│                  MINOR INFORMATION                          │
│                                                             │
│     Minor's Information:                                   │
│     First Name: [________________]                         │
│     Last Name:  [________________]                         │
│     Date of Birth: [__/__/____]                           │
│                                                             │
│     Guardian Information (you):                            │
│     First Name: [________________]                         │
│     Last Name:  [________________]                         │
│     Email:      [________________]                         │
│     Relationship: [Parent/Guardian ▼]                      │
│                                                             │
│     [Cancel]                            [Continue →]       │
└─────────────────────────────────────────────────────────────┘
```

The signed waiver records:
- Minor's name as the participant
- Guardian's name as the signer
- Guardian's signature and video (if applicable)
- Relationship to minor

## 3.6 Kiosk Management Dashboard

### Kiosk List View

```
┌─────────────────────────────────────────────────────────────┐
│  Kiosk Devices                              [+ Add Kiosk]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🟢 Front Desk iPad                                  │   │
│  │    Event: Saturday Morning Yoga                     │   │
│  │    Last seen: 2 minutes ago                         │   │
│  │    Today: 23 waivers signed                         │   │
│  │    [View] [Edit] [Get Link]                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🟡 Check-in Station 2                               │   │
│  │    Event: Drop-in Climbing                          │   │
│  │    Last seen: 15 minutes ago                        │   │
│  │    Today: 8 waivers signed                          │   │
│  │    [View] [Edit] [Get Link]                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🔴 Rental Counter Tablet                            │   │
│  │    Event: Equipment Rentals                         │   │
│  │    Last seen: 3 days ago                            │   │
│  │    Today: 0 waivers signed                          │   │
│  │    [View] [Edit] [Get Link]                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Using 3 of 3 kiosk devices (Professional plan)           │
│  [Upgrade for more devices]                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Kiosk Setup View

```
┌─────────────────────────────────────────────────────────────┐
│  Set Up Kiosk Device                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Device Name: [Front Desk iPad_________]                   │
│                                                             │
│  Default Event: [Saturday Morning Yoga ▼]                  │
│                 ☐ Let user select event on kiosk           │
│                                                             │
│  Exit PIN: [1234__]                                        │
│            Required to exit kiosk mode                     │
│                                                             │
│  Options:                                                  │
│  ☑ Enable video recording                                  │
│  ☑ Allow minor/guardian signing                            │
│  ☐ Capture signer photo                                    │
│  ☐ Enable offline mode (sync when connected)              │
│                                                             │
│  Auto-lock after: [5 ▼] minutes of inactivity             │
│                                                             │
│  [Cancel]                            [Create Kiosk]        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Kiosk Link/QR View

```
┌─────────────────────────────────────────────────────────────┐
│  Kiosk Setup: Front Desk iPad                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Open this link on your kiosk device:                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ https://acme.signshield.io/kiosk/abc123def456...    │   │
│  │                                          [Copy]     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Or scan this QR code:                                     │
│                                                             │
│  ┌─────────────────────┐                                   │
│  │                     │                                   │
│  │    [QR CODE]        │                                   │
│  │                     │                                   │
│  └─────────────────────┘                                   │
│                                                             │
│  Setup Instructions:                                       │
│  1. Open Safari on your iPad                               │
│  2. Navigate to the link above                             │
│  3. Tap "Add to Home Screen" (share icon → Add)           │
│  4. Enable Guided Access in Settings for lockdown          │
│                                                             │
│  [Download Setup Guide PDF]                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 3.7 Offline Mode (Professional+ Plans)

### How Offline Works

1. **Initial Sync**: When kiosk loads, it downloads:
   - Waiver template content
   - Event details
   - Tenant branding assets
   - Signing configuration

2. **Offline Signing**: When network unavailable:
   - Signatures collected and stored locally (IndexedDB)
   - Video recorded and stored locally
   - "Offline" indicator shown
   - Waiver marked as pending sync

3. **Sync on Reconnect**: When network restored:
   - Pending waivers uploaded in background
   - Conflicts resolved (duplicate email check)
   - Sync status shown to staff

### Offline Data Storage

```javascript
// IndexedDB schema for offline kiosk
const kioskDB = {
  stores: {
    config: {
      // Tenant branding, template, event info
      keyPath: 'id'
    },
    pendingWaivers: {
      // Waivers awaiting sync
      keyPath: 'localId',
      indexes: ['createdAt', 'syncStatus']
    },
    pendingMedia: {
      // Videos and signatures awaiting upload
      keyPath: 'localId',
      indexes: ['waiverLocalId', 'type']
    }
  }
};
```

### Offline Indicator UI

```
┌─────────────────────────────────────────────────────────────┐
│  ⚠️ OFFLINE MODE                                           │
│  Waivers will sync when connection is restored             │
│  3 waivers pending sync                                    │
└─────────────────────────────────────────────────────────────┘
```

## 3.8 Kiosk Security

### Device Lockdown Recommendations

For iPad (documented in setup guide):
1. **Guided Access**: Lock device to kiosk URL
2. **Single App Mode** (MDM): For enterprise deployments
3. **Disable notifications**: Prevent interruptions
4. **Auto-lock off**: Keep screen on

For Android tablets:
1. **Screen Pinning**: Lock to browser
2. **Kiosk launcher apps**: Third-party lockdown
3. **Enterprise MDM**: Knox, etc.

### Kiosk Security Features

| Feature | Description |
|---------|-------------|
| Exit PIN | Required to leave kiosk mode |
| Token rotation | Device tokens can be regenerated |
| Deactivation | Instantly disable a device remotely |
| Session timeout | Clear data after inactivity |
| Audit log | Track all kiosk activity |

## 3.9 Plan Integration

### Feature Availability by Plan

| Feature | Free | Starter | Professional | Enterprise |
|---------|------|---------|--------------|------------|
| Kiosk devices | - | 1 | 3 | Unlimited |
| Video on kiosk | - | ✓ | ✓ | ✓ |
| Minor flow | - | ✓ | ✓ | ✓ |
| Photo capture | - | - | ✓ | ✓ |
| Offline mode | - | - | ✓ | ✓ |
| Custom branding | - | ✓ | ✓ | ✓ |

### Enforcement

```python
# In KioskDevice.save()
def save(self, *args, **kwargs):
    self.check_plan_limits()

    plan = PlanLimit.get_plan(self.tenant.plan)

    # Enforce feature flags
    if self.allow_video and not plan.video_enabled:
        self.allow_video = False

    if self.offline_enabled and not plan.offline_kiosk:
        self.offline_enabled = False

    if self.allow_photo and self.tenant.plan not in ['professional', 'enterprise']:
        self.allow_photo = False

    super().save(*args, **kwargs)
```

# 4. Future Considerations (Out of Scope)

- ID scanning / driver's license OCR
- Facial recognition for repeat visitors
- Integration with check-in systems (Mindbody, etc.)
- Hardware recommendations / partnerships
- Multi-language kiosk interface
- Waiver kiosk mobile app (native iOS/Android)
- Queue management display ("Now serving #...")
- SMS confirmation option (in addition to email)

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Core Kiosk (MVP)**
1. KioskDevice model + migrations
2. Device registration flow in dashboard
3. Basic kiosk signing interface
4. Device token authentication
5. Success/reset flow

**Phase 2: Enhanced Features**
1. Minor participant flow
2. Video recording on kiosk
3. Photo capture
4. Exit PIN security
5. Activity timeout

**Phase 3: Offline Mode**
1. Service worker for offline support
2. IndexedDB storage
3. Background sync
4. Conflict resolution
5. Offline indicator UI

**Phase 4: Management & Polish**
1. Kiosk analytics (signings per device)
2. Device status monitoring
3. Setup guide documentation
4. QR code generation
5. Mobile-responsive kiosk UI

## 5.2 Spec Dependencies

This spec has dependencies on other specs that must be implemented first.

### Dependency Chain

```
┌─────────────────────────────┐
│     planlimit_update        │
│     (In Development)        │
│                             │
│  Provides:                  │
│  • max_kiosk_devices field  │
│  • offline_kiosk flag       │
│  • Plan-based limits        │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐    ┌───────────────────────────────┐
│       kiosk_mode            │───►│  waiver_email_notifications   │
│       (This Spec)           │    │  (Draft)                      │
│                             │    │                               │
│  Uses:                      │    │  Needs:                       │
│  • PlanLimit.max_kiosk_     │    │  • Kiosk waiver email handling│
│    devices                  │    │  • KioskSession for context   │
│  • PlanLimit.offline_kiosk  │    └───────────────────────────────┘
└─────────────────────────────┘
               │
               │ Also uses:
               ▼
┌─────────────────────────────┐
│     brand_guidelines        │
│     (In Development)        │
│                             │
│  Provides:                  │
│  • Kiosk UI styling         │
│  • Tablet-optimized layout  │
└─────────────────────────────┘
```

### Dependency Details

| Spec | Status | Required For | Specific Dependencies |
|------|--------|--------------|----------------------|
| **planlimit_update.md** | In Development | Plan enforcement | `max_kiosk_devices`, `offline_kiosk` fields |
| **brand_guidelines.md** | In Development | Kiosk UI | CSS variables, tablet layout, component styles |

### What This Spec Provides To Others

| Downstream Spec | What We Provide |
|-----------------|-----------------|
| **waiver_email_notifications** | KioskSession model, kiosk-signed waiver context |
| **plan_enforcement** | KioskDevice model for limit checks |

### Fields Required from planlimit_update

```python
# From PlanLimit model (planlimit_update.md)
plan.max_kiosk_devices   # 0=disabled on free, 0=unlimited on paid, >0=limited
plan.offline_kiosk       # Enable offline mode with IndexedDB sync
```

### Plan Limits for Kiosk

| Plan | max_kiosk_devices | offline_kiosk |
|------|-------------------|---------------|
| Free | 0 (disabled) | False |
| Starter | 1 | False |
| Professional | 3 | True |
| Enterprise | 0 (unlimited) | True |

### Implementation Order

```
1. planlimit_update.md    ─┐
2. brand_guidelines.md     ├──► kiosk_mode.md ──► waiver_email_notifications.md
```

**Note:** The kiosk limit enforcement (`check_kiosk_limit()`) is defined in `plan_enforcement.md`, but kiosk_mode.md can be implemented first with basic limit checks. Full enforcement comes with plan_enforcement.

## 5.3 Infrastructure Dependencies

| Dependency | Notes |
|------------|-------|
| Existing signing flow | Kiosk reuses waiver display, signature pad, video capture |
| SignedWaiver model | Kiosk creates standard SignedWaiver records |
| Service Worker | For offline mode (Phase 3) |
| IndexedDB | For offline storage (Phase 3) |

# 6. Acceptance Criteria

## 6.1 Device Management

- [ ] Can create kiosk device from dashboard
- [ ] Can set device name, event, PIN
- [ ] Can view device list with status indicators
- [ ] Can deactivate/reactivate devices
- [ ] Can regenerate device token
- [ ] Device limit enforced per plan

## 6.2 Kiosk Interface

- [ ] Kiosk loads with token authentication
- [ ] Home screen shows branding and event
- [ ] Participant info form works
- [ ] Waiver content displays and scrolls
- [ ] Signature pad captures signature
- [ ] Success screen displays and auto-resets
- [ ] Exit PIN required to leave

## 6.3 Video (if enabled)

- [ ] Camera preview displays
- [ ] Video records on kiosk device
- [ ] Video saved with signed waiver
- [ ] Video disabled if plan doesn't support

## 6.4 Minor Flow

- [ ] "Signing for minor" checkbox works
- [ ] Minor info form displays
- [ ] Guardian info captured
- [ ] Signed waiver shows both minor and guardian

## 6.5 Offline Mode (Professional+)

- [ ] Kiosk detects offline state
- [ ] Signing works without network
- [ ] Data persisted to IndexedDB
- [ ] Sync triggers on reconnect
- [ ] Sync status visible

## 6.6 Security

- [ ] Invalid token shows error
- [ ] Deactivated device cannot sign
- [ ] Session timeout clears data
- [ ] Exit requires correct PIN

## 6.7 Plan Enforcement

- [ ] Free plan cannot create kiosks
- [ ] Starter limited to 1 device
- [ ] Professional limited to 3 devices
- [ ] Enterprise unlimited
- [ ] Offline mode only for Professional+

---
*End of Specification*
