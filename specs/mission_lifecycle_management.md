---
title: "Mission Lifecycle Management"
version: "1.0"
status: ready-for-development
project: EchoForge
created: 2026-01-03
updated: 2026-01-03
github_issue: 25
---

# Mission Lifecycle Management

## Executive Summary

This spec defines a comprehensive mission lifecycle system that handles stale missions, resource optimization, user notifications, and observability. The design supports small-scale initial deployment with a clear path to enterprise scale.

### Problem Statement

Missions waiting for user input, email replies, or external events can consume system resources indefinitely:
- **Polling cycles** - Background jobs checking for responses
- **Database connections** - Queries on waiting missions
- **Memory/state** - Mission context held in memory
- **API rate limits** - Repeated checks against Gmail/Calendar APIs

Without proper lifecycle management, the system can accumulate stale missions that waste resources and create poor user experiences.

---

## 1. Mission Timeout System

### 1.1 Mission-Level Timeout

Each mission has a configurable maximum lifetime after which it's considered stale.

```python
# Mission model additions
class Mission(BaseModel):
    # Existing fields...

    # Lifecycle management
    max_lifetime_hours = models.IntegerField(
        default=168,  # 7 days default
        help_text="Maximum hours before mission is considered stale"
    )
    stale_notified_at = models.DateTimeField(
        null=True, blank=True,
        help_text="When user was notified of stale mission"
    )
    grace_period_ends_at = models.DateTimeField(
        null=True, blank=True,
        help_text="When grace period expires (soft delete occurs)"
    )
    last_user_engagement = models.DateTimeField(
        null=True, blank=True,
        help_text="Last time user interacted with this mission"
    )
    deleted_at = models.DateTimeField(
        null=True, blank=True,
        help_text="Soft delete timestamp"
    )

    @property
    def is_stale(self) -> bool:
        """Check if mission has exceeded its lifetime."""
        if self.status in [self.Status.COMPLETED, self.Status.CANCELLED, self.Status.FAILED]:
            return False

        age = timezone.now() - self.created_at
        return age.total_seconds() > (self.max_lifetime_hours * 3600)

    @property
    def effective_age(self) -> timedelta:
        """Age since last user engagement or creation."""
        reference = self.last_user_engagement or self.created_at
        return timezone.now() - reference

    def record_user_engagement(self):
        """Reset timeout on user engagement."""
        self.last_user_engagement = timezone.now()
        self.stale_notified_at = None  # Clear notification flag
        self.grace_period_ends_at = None  # Clear grace period
        self.save(update_fields=[
            'last_user_engagement',
            'stale_notified_at',
            'grace_period_ends_at'
        ])
```

### 1.2 Timeout Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MISSION LIFECYCLE                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Created] ──► [Active/Waiting] ──► [Stale Detected]                │
│                      │                     │                         │
│                      │              ┌──────▼──────┐                  │
│                      │              │   Notify    │                  │
│                      │              │    User     │                  │
│                      │              └──────┬──────┘                  │
│                      │                     │                         │
│            User      │              ┌──────▼──────┐                  │
│          Engages ◄───┼──────────────│ 24hr Grace  │                  │
│            (reset)   │              │   Period    │                  │
│                      │              └──────┬──────┘                  │
│                      │                     │                         │
│                      │              ┌──────▼──────┐                  │
│                      ▼              │ Soft Delete │                  │
│               [Completed]           │ (30 days)   │                  │
│                                     └──────┬──────┘                  │
│                                            │                         │
│                                     ┌──────▼──────┐                  │
│                                     │ Hard Delete │                  │
│                                     └─────────────┘                  │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.3 Default Timeouts by Mission Type

| Mission Type | Default Lifetime | Rationale |
|--------------|------------------|-----------|
| Quick task | 24 hours | Simple requests should complete quickly |
| Meeting scheduling | 7 days | Allow time for calendar coordination |
| Project planning | 14 days | Complex multi-step work |
| Research | 30 days | Long-running investigation |
| User-defined | Configurable | User sets at creation |

---

## 2. Task-Level Timeout Management

### 2.1 Human Input Timeout

```python
class MissionTask(BaseModel):
    # Existing fields...

    # Human input specific
    human_input_timeout_hours = models.IntegerField(
        default=168,  # 7 days default
        help_text="Hours to wait for human input before cancelling"
    )
    human_input_requested_at = models.DateTimeField(
        null=True, blank=True
    )
    human_input_reminder_sent_at = models.DateTimeField(
        null=True, blank=True
    )
```

### 2.2 External Wait Timeout with Retries

```python
class ExternalWaitConfig(models.Model):
    """Configuration for external event waiting."""

    task = models.OneToOneField(
        MissionTask,
        on_delete=models.CASCADE,
        related_name='wait_config'
    )

    # Retry configuration
    max_retries = models.IntegerField(default=3)
    retry_count = models.IntegerField(default=0)
    retry_interval_hours = models.IntegerField(default=24)
    last_retry_at = models.DateTimeField(null=True, blank=True)
    next_retry_at = models.DateTimeField(null=True, blank=True)

    # Follow-up for emails
    send_follow_up = models.BooleanField(default=True)
    follow_up_template = models.TextField(blank=True)

    def should_retry(self) -> bool:
        return self.retry_count < self.max_retries

    def record_retry(self):
        self.retry_count += 1
        self.last_retry_at = timezone.now()
        self.next_retry_at = timezone.now() + timedelta(hours=self.retry_interval_hours)
        self.save()
```

---

## 3. Efficient Polling Architecture

### 3.1 Tiered Polling Strategy

Reduce resource consumption by polling less frequently as waits age:

```python
POLLING_TIERS = [
    # (max_age_hours, poll_interval_minutes)
    (1, 5),       # First hour: every 5 minutes
    (6, 15),      # Hours 1-6: every 15 minutes
    (24, 30),     # Hours 6-24: every 30 minutes
    (72, 60),     # Days 1-3: every hour
    (168, 180),   # Days 3-7: every 3 hours
    (None, 360),  # 7+ days: every 6 hours
]

def get_poll_tier(wait_started_at: datetime) -> int:
    """Get polling interval in minutes based on wait age."""
    age_hours = (timezone.now() - wait_started_at).total_seconds() / 3600

    for max_age, interval in POLLING_TIERS:
        if max_age is None or age_hours <= max_age:
            return interval

    return POLLING_TIERS[-1][1]
```

### 3.2 Batched Provider Checks

Instead of one API call per waiting task, batch by provider:

```python
@shared_task(name='agents.check_external_events_batched')
def check_external_events_batched():
    """
    Check for external events using batched API calls.

    Instead of:
        for each task: check_gmail(task.tracking_id)  # N API calls

    Do:
        tracking_ids = [t.tracking_id for t in waiting_tasks]
        results = gmail_batch_check(tracking_ids)  # 1 API call
    """
    now = timezone.now()

    # Group tasks by provider and customer
    tasks_by_provider = defaultdict(list)

    waiting_tasks = MissionTask.objects.filter(
        status=MissionTask.Status.WAITING_EXTERNAL,
        next_poll_at__lte=now,
    ).select_related('mission__customer')

    for task in waiting_tasks:
        key = (task.external_event_type, task.mission.customer_id)
        tasks_by_provider[key].append(task)

    # Batch check by provider
    for (event_type, customer_id), tasks in tasks_by_provider.items():
        if event_type == 'email_reply':
            check_email_replies_batched(customer_id, tasks)
        elif event_type == 'calendar_response':
            check_calendar_responses_batched(customer_id, tasks)
        # etc.
```

### 3.3 Webhook-First Architecture

Prefer push notifications where supported:

| Provider | Webhook Support | Fallback Polling |
|----------|-----------------|------------------|
| Gmail | Gmail Push Notifications | Every 10 min |
| Google Calendar | Push notifications | Every 15 min |
| Stripe | Full webhook support | None needed |
| Generic API | Varies | Configurable |

```python
class ExternalEventWebhook(models.Model):
    """Track webhook subscriptions for external events."""

    customer = models.ForeignKey('customers.Customer', on_delete=models.CASCADE)
    provider = models.CharField(max_length=50)  # gmail, gcal, etc.
    subscription_id = models.CharField(max_length=255)
    expires_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)

    # Webhook delivery tracking
    last_received_at = models.DateTimeField(null=True, blank=True)
    delivery_failures = models.IntegerField(default=0)

    @classmethod
    def ensure_subscription(cls, customer, provider):
        """Ensure active webhook subscription exists."""
        sub = cls.objects.filter(
            customer=customer,
            provider=provider,
            is_active=True,
            expires_at__gt=timezone.now()
        ).first()

        if not sub:
            # Create new subscription via provider API
            sub = create_webhook_subscription(customer, provider)

        return sub
```

---

## 4. Notification System

### 4.1 Notification Channels

```python
class NotificationChannel(models.TextChoices):
    IN_APP = 'in_app', 'In-App Dashboard'
    EMAIL = 'email', 'Email'
    PUSH = 'push', 'Push Notification'
    AGENT = 'agent', 'Agent Reminder'


class MissionNotification(models.Model):
    """Track notifications sent for missions."""

    mission = models.ForeignKey(Mission, on_delete=models.CASCADE, related_name='notifications')
    notification_type = models.CharField(max_length=50)  # stale_warning, timeout_imminent, etc.
    channel = models.CharField(max_length=20, choices=NotificationChannel.choices)
    sent_at = models.DateTimeField(auto_now_add=True)
    acknowledged_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ['mission', 'notification_type', 'channel']
```

### 4.2 Notification Types

| Type | Trigger | Channels | Message |
|------|---------|----------|---------|
| `stale_warning` | Mission exceeds lifetime | All | "Your mission '{title}' needs attention" |
| `timeout_imminent` | 4 hours before grace period ends | Email, Push | "Mission will be cancelled in 4 hours" |
| `human_input_reminder` | 3 days after input request | All | "Waiting for your response on '{title}'" |
| `retry_failed` | Max retries exhausted | Email | "Unable to get response, mission cancelled" |
| `mission_completed` | Mission completed | In-app | "Mission '{title}' completed successfully" |

### 4.3 User Notification Preferences

```python
class UserNotificationPreferences(models.Model):
    """User preferences for mission notifications."""

    user = models.OneToOneField(
        'customers.CustomerUser',
        on_delete=models.CASCADE,
        related_name='notification_preferences'
    )

    # Channel preferences
    enable_email = models.BooleanField(default=True)
    enable_push = models.BooleanField(default=True)
    enable_agent_reminders = models.BooleanField(default=True)

    # Frequency
    digest_mode = models.BooleanField(
        default=False,
        help_text="Batch notifications into daily digest"
    )
    quiet_hours_start = models.TimeField(null=True, blank=True)
    quiet_hours_end = models.TimeField(null=True, blank=True)

    # Per-type settings
    stale_warning_channels = ArrayField(
        models.CharField(max_length=20),
        default=list
    )
```

---

## 5. Smart Agent Context

### 5.1 Context-Aware Mission Reminders

The agent should mention pending missions when relevant to the conversation:

```python
def get_relevant_pending_missions(
    user_id: str,
    conversation_context: str,
    max_missions: int = 3
) -> list[Mission]:
    """
    Find pending missions relevant to current conversation.

    Uses semantic similarity to determine if a pending mission
    is related to what the user is currently discussing.
    """
    pending = Mission.objects.filter(
        user_id=user_id,
        status__in=[Mission.Status.ACTIVE, Mission.Status.WAITING],
        deleted_at__isnull=True,
    ).order_by('-priority', '-created_at')[:10]

    if not pending:
        return []

    # Score relevance using embeddings
    context_embedding = get_embedding(conversation_context)

    scored_missions = []
    for mission in pending:
        mission_text = f"{mission.title} {mission.description}"
        mission_embedding = get_embedding(mission_text)
        score = cosine_similarity(context_embedding, mission_embedding)

        # Boost score for urgent/stale missions
        if mission.priority == 'urgent':
            score *= 1.5
        if mission.is_stale:
            score *= 1.3

        scored_missions.append((mission, score))

    # Return top N relevant missions above threshold
    threshold = 0.3
    relevant = [m for m, s in sorted(scored_missions, key=lambda x: -x[1]) if s > threshold]
    return relevant[:max_missions]
```

### 5.2 Agent System Prompt Injection

```python
def build_mission_context_prompt(missions: list[Mission]) -> str:
    """Build prompt section about pending missions."""
    if not missions:
        return ""

    lines = ["\n## Pending Missions (mention if relevant to conversation)"]

    for m in missions:
        urgency = ""
        if m.is_stale:
            urgency = " [NEEDS ATTENTION]"
        elif m.priority == 'urgent':
            urgency = " [URGENT]"

        lines.append(f"- {m.title}{urgency}: {m.description[:100]}")

        # Add wait status
        if m.status == Mission.Status.WAITING:
            lines.append(f"  └─ Waiting for: {m.wait_reason}")

    return "\n".join(lines)
```

---

## 6. Soft Delete and Archival

### 6.1 Soft Delete Implementation

```python
class SoftDeleteManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

    def with_deleted(self):
        return super().get_queryset()

    def deleted_only(self):
        return super().get_queryset().filter(deleted_at__isnull=False)


class Mission(BaseModel):
    # ... existing fields ...

    objects = SoftDeleteManager()
    all_objects = models.Manager()  # Includes deleted

    def soft_delete(self):
        """Soft delete mission and related data."""
        now = timezone.now()
        self.deleted_at = now
        self.status = self.Status.CANCELLED
        self.save()

        # Log event
        MissionEvent.objects.create(
            mission=self,
            event_type=MissionEvent.EventType.STATUS_CHANGED,
            title='Mission soft deleted',
            content='Deleted due to timeout with no user response',
        )
```

### 6.2 Hard Delete After Retention Period

```python
@shared_task(name='agents.hard_delete_old_missions')
def hard_delete_old_missions():
    """
    Permanently delete missions that were soft-deleted over 30 days ago.

    Run weekly.
    """
    cutoff = timezone.now() - timedelta(days=30)

    old_missions = Mission.all_objects.filter(
        deleted_at__lt=cutoff,
        deleted_at__isnull=False,
    )

    count = old_missions.count()

    # Delete in batches to avoid long transactions
    for mission in old_missions.iterator():
        # Delete related objects first
        mission.tasks.all().delete()
        mission.events.all().delete()
        mission.input_requests.all().delete()
        mission.notifications.all().delete()
        mission.delete()

    logger.info(f"Hard deleted {count} old missions")
    return {'deleted': count}
```

---

## 7. Observability and Metrics

### 7.1 Metrics to Track

```python
# Using Django's built-in metrics or a library like django-prometheus

MISSION_METRICS = {
    # Counts
    'missions_total': Counter('Total missions created'),
    'missions_by_status': Gauge('Missions by status'),
    'missions_completed': Counter('Missions completed'),
    'missions_timed_out': Counter('Missions that timed out'),

    # Timing
    'mission_duration_seconds': Histogram('Mission duration'),
    'task_wait_duration_seconds': Histogram('Time tasks spend waiting'),

    # Polling efficiency
    'external_checks_total': Counter('External event checks'),
    'external_checks_by_provider': Counter('Checks by provider'),
    'webhook_deliveries': Counter('Webhook deliveries received'),

    # Resource usage
    'polling_tasks_running': Gauge('Active polling tasks'),
    'api_rate_limit_remaining': Gauge('API rate limit remaining by provider'),
}
```

### 7.2 Admin Dashboard Views

```python
# backend/apps/agents/admin.py additions

class MissionHealthDashboard:
    """Admin dashboard for mission lifecycle health."""

    @staticmethod
    def get_metrics():
        now = timezone.now()

        return {
            # Status breakdown
            'by_status': Mission.objects.values('status').annotate(count=Count('id')),

            # Stale missions
            'stale_count': Mission.objects.filter(
                status__in=[Mission.Status.ACTIVE, Mission.Status.WAITING],
            ).annotate(
                age_hours=(now - F('created_at')) / 3600
            ).filter(age_hours__gt=F('max_lifetime_hours')).count(),

            # Waiting breakdown
            'waiting_by_reason': Mission.objects.filter(
                status=Mission.Status.WAITING
            ).values('wait_reason').annotate(count=Count('id')),

            # Average wait times
            'avg_wait_hours': MissionTask.objects.filter(
                status=MissionTask.Status.WAITING_EXTERNAL,
            ).annotate(
                wait_hours=(now - F('started_at')) / 3600
            ).aggregate(avg=Avg('wait_hours'))['avg'],

            # Timeout rate
            'timeout_rate_7d': calculate_timeout_rate(days=7),

            # Polling efficiency
            'polling_stats': get_polling_stats(),
        }
```

### 7.3 Automated Alerts

```python
class MissionHealthAlert(models.Model):
    """Configuration for automated alerts."""

    class AlertType(models.TextChoices):
        STALE_THRESHOLD = 'stale_threshold', 'Stale mission count exceeds threshold'
        TIMEOUT_RATE = 'timeout_rate', 'Timeout rate exceeds threshold'
        POLLING_BACKLOG = 'polling_backlog', 'Polling tasks backed up'
        API_RATE_LIMIT = 'api_rate_limit', 'API rate limit warning'

    alert_type = models.CharField(max_length=50, choices=AlertType.choices)
    threshold = models.FloatField()
    is_enabled = models.BooleanField(default=True)
    last_triggered_at = models.DateTimeField(null=True, blank=True)
    notify_emails = ArrayField(models.EmailField())


@shared_task(name='agents.check_mission_health_alerts')
def check_mission_health_alerts():
    """Check all alert conditions and notify if triggered."""
    metrics = MissionHealthDashboard.get_metrics()

    for alert in MissionHealthAlert.objects.filter(is_enabled=True):
        value = get_metric_value(metrics, alert.alert_type)

        if value > alert.threshold:
            send_alert_notification(alert, value)
            alert.last_triggered_at = timezone.now()
            alert.save()
```

---

## 8. Celery Task Schedule

```python
# settings/base.py - Updated CELERY_BEAT_SCHEDULE

CELERY_BEAT_SCHEDULE = {
    # ... existing schedules ...

    # Mission lifecycle (new)
    'check-stale-missions': {
        'task': 'agents.check_stale_missions',
        'schedule': crontab(minute='*/30'),  # Every 30 minutes
    },
    'process-grace-period-expirations': {
        'task': 'agents.process_grace_period_expirations',
        'schedule': crontab(minute='*/60'),  # Every hour
    },
    'send-mission-notifications': {
        'task': 'agents.send_mission_notifications',
        'schedule': crontab(minute='*/15'),  # Every 15 minutes
    },

    # Efficient polling (updated)
    'check-external-events-batched': {
        'task': 'agents.check_external_events_batched',
        'schedule': crontab(minute='*/5'),  # Every 5 minutes (uses tiered internally)
    },

    # Cleanup
    'hard-delete-old-missions': {
        'task': 'agents.hard_delete_old_missions',
        'schedule': crontab(day_of_week=0, hour=4),  # Weekly Sunday 4am
    },

    # Health monitoring
    'check-mission-health-alerts': {
        'task': 'agents.check_mission_health_alerts',
        'schedule': crontab(minute='*/10'),  # Every 10 minutes
    },
}
```

---

## 9. Implementation Phases

### Phase 1: Core Lifecycle (MVP)
- [ ] Add lifecycle fields to Mission model
- [ ] Implement stale detection and timeout
- [ ] Basic email notifications for stale missions
- [ ] Soft delete with 30-day retention
- [ ] Hard delete cleanup task

### Phase 2: Smart Polling
- [ ] Implement tiered polling strategy
- [ ] Add batched provider checks
- [ ] Track `next_poll_at` per task
- [ ] Webhook subscription management

### Phase 3: Notifications
- [ ] User notification preferences model
- [ ] Multi-channel notification dispatch
- [ ] Push notification integration (for mobile app)
- [ ] Notification acknowledgment tracking

### Phase 4: Agent Integration
- [ ] Smart context relevance scoring
- [ ] System prompt injection for pending missions
- [ ] User engagement tracking to reset timeouts

### Phase 5: Observability
- [ ] Metrics collection
- [ ] Admin dashboard view
- [ ] Automated health alerts
- [ ] Grafana/monitoring integration

---

## 10. Acceptance Criteria

### Lifecycle Management
- [ ] Missions older than configured lifetime trigger notifications
- [ ] User engagement (message, action) resets mission timeout
- [ ] 24-hour grace period after notification before soft delete
- [ ] Soft-deleted missions are hard-deleted after 30 days

### Resource Efficiency
- [ ] Polling frequency decreases for older waiting tasks
- [ ] Provider API calls are batched per customer
- [ ] Webhook subscriptions are preferred where available
- [ ] No mission waits indefinitely (max lifetime enforced)

### User Experience
- [ ] Users receive notifications before mission timeout
- [ ] Agent mentions relevant pending missions contextually
- [ ] Users can configure notification preferences
- [ ] Mission status visible in dashboard

### Observability
- [ ] Admin dashboard shows mission health metrics
- [ ] Alerts trigger when thresholds exceeded
- [ ] Timeout and wait time metrics tracked

---

## 11. Dependencies

- Issue #18 - Persistent Missions (models exist)
- Issue #21 - Dashboard UI (templates)
- Issue #23 - WebSocket for mobile (push notifications)
- Issue #24 - Push notification infrastructure

---

## 12. Open Questions

1. **Timeout configuration UI**: Should users be able to set timeout at mission creation, or is this admin-only?
2. **Follow-up email content**: Should the agent generate follow-up text, or use templates?
3. **Cost tracking**: Should we track and expose API call costs for polling?
