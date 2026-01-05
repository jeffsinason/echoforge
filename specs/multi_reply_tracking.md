---
title: Multi-Reply Email Tracking
version: "1.0"
status: complete
project: echoforge-hub
created: 2026-01-03
updated: 2026-01-03
github_issue: 20
---

# 1. Executive Summary

Enhance the `SentEmailTracking` model to support tracking multiple replies from different recipients. This enables missions to understand when all expected replies have been received and take appropriate action (proceed to next step, notify user of non-affirming responses, etc.).

# 2. Current System State

## 2.1 Existing Data Model

The `SentEmailTracking` model stores only ONE reply:

```python
class SentEmailTracking(CustomerScopedModel):
    # ... existing fields ...

    # Single reply fields (limitation)
    reply_message_id = models.CharField(max_length=255, blank=True)
    reply_received_at = models.DateTimeField(null=True, blank=True)
    reply_from = models.EmailField(blank=True)
    reply_snippet = models.TextField(blank=True)
```

**Location:** `backend/apps/integrations/models.py` lines 172-222

## 2.2 Current Behavior

1. Email sent to multiple recipients (e.g., Brian and Jeff)
2. Brian replies first → his info stored in `reply_*` fields
3. Jeff replies later → his info **overwrites** Brian's
4. System loses track of Brian's reply

## 2.3 Current `check_replies()` Behavior

The `check_replies()` method in `gmail.py`:
- Returns all replies found in the `replies` list
- But only persists the LAST reply in the database
- No way to query historical replies

**Location:** `backend/apps/integrations/services/gmail.py` lines 299-407

# 3. Feature Requirements

## 3.1 New EmailReply Model

**Description:** Create a separate model to store individual replies, linked to the parent tracking record.

### Model Definition

```python
class EmailReply(CustomerScopedModel):
    """
    Individual reply to a tracked email.

    Supports multi-recipient emails where each recipient may reply separately.
    """
    tracking = models.ForeignKey(
        SentEmailTracking,
        on_delete=models.CASCADE,
        related_name='replies'
    )

    # Reply identification
    message_id = models.CharField(
        max_length=255,
        unique=True,
        help_text="Gmail message ID"
    )

    # Sender info
    from_address = models.EmailField(help_text="Reply sender email")
    from_name = models.CharField(max_length=255, blank=True)

    # Timing
    received_at = models.DateTimeField()

    # Content
    snippet = models.TextField(blank=True, help_text="First ~500 chars of reply")

    # Parsed response (for mission automation)
    parsed_response = models.JSONField(
        default=dict,
        blank=True,
        help_text="Extracted info: {available: bool, times: [], sentiment: str}"
    )

    # Mission notification tracking
    notified_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="When mission was notified of this reply"
    )

    class Meta:
        ordering = ['received_at']
        indexes = [
            models.Index(fields=['tracking', 'received_at']),
            models.Index(fields=['from_address']),
        ]

    def __str__(self):
        return f"Reply from {self.from_address} at {self.received_at}"
```

### Files to Create/Modify

| File | Action |
|------|--------|
| `backend/apps/integrations/models.py` | Add `EmailReply` model |
| `backend/apps/integrations/admin.py` | Add inline admin for replies |

## 3.2 Enhanced SentEmailTracking Model

**Description:** Add fields to track expected recipients and overall reply status.

### Model Changes

```python
class SentEmailTracking(CustomerScopedModel):
    class Status(models.TextChoices):
        AWAITING_REPLY = 'awaiting_reply', 'Awaiting Reply'
        SOME_REPLIED = 'some_replied', 'Some Recipients Replied'
        ALL_REPLIED = 'all_replied', 'All Recipients Replied'
        FOLLOWUP_SENT = 'followup_sent', 'Follow-up Sent'
        EXPIRED = 'expired', 'Expired'
        CANCELLED = 'cancelled', 'Cancelled'

    # Existing fields remain...

    # NEW: Expected recipient tracking
    expected_recipients = models.JSONField(
        default=list,
        help_text="List of email addresses expected to reply"
    )

    # DEPRECATED: Single reply fields (keep for migration, mark deprecated)
    # These will be migrated to EmailReply records
    reply_message_id = models.CharField(max_length=255, blank=True)  # DEPRECATED
    reply_received_at = models.DateTimeField(null=True, blank=True)  # DEPRECATED
    reply_from = models.EmailField(blank=True)  # DEPRECATED
    reply_snippet = models.TextField(blank=True)  # DEPRECATED

    # Helper methods
    @property
    def replies_received_count(self) -> int:
        """Number of replies received."""
        return self.replies.count()

    @property
    def expected_reply_count(self) -> int:
        """Number of expected replies (based on to_addresses or expected_recipients)."""
        return len(self.expected_recipients or self.to_addresses or [])

    @property
    def pending_recipients(self) -> list:
        """Recipients who haven't replied yet."""
        replied = set(self.replies.values_list('from_address', flat=True))
        expected = set(self.expected_recipients or self.to_addresses or [])
        return list(expected - replied)

    def update_status(self):
        """Update status based on reply count."""
        if self.replies_received_count == 0:
            self.status = self.Status.AWAITING_REPLY
        elif self.replies_received_count >= self.expected_reply_count:
            self.status = self.Status.ALL_REPLIED
        else:
            self.status = self.Status.SOME_REPLIED
        self.save(update_fields=['status'])
```

### Files to Modify

| File | Changes |
|------|---------|
| `backend/apps/integrations/models.py` | Add new Status choices, expected_recipients field, helper methods |

## 3.3 Updated check_replies() Method

**Description:** Modify to create `EmailReply` records and update tracking status.

### New Behavior

```python
def check_replies(
    self,
    tracking_ids: List[str] = None,
    max_age_hours: int = 168,
) -> Dict:
    """
    Check for replies to tracked emails.

    Returns:
        Dict with:
        - replies: List of all replies (new and existing)
        - new_replies: List of newly discovered replies
        - pending: List of tracking records still awaiting replies
        - all_replied: List of tracking records with all replies received
    """
    # ... existing query setup ...

    results = {
        'replies': [],
        'new_replies': [],
        'pending': [],
        'all_replied': [],
    }

    for tracking in query:
        # Get existing reply message IDs
        existing_reply_ids = set(
            tracking.replies.values_list('message_id', flat=True)
        )

        # Fetch thread from Gmail
        thread = service.users().threads().get(...)

        for msg in thread.get('messages', []):
            if msg['id'] == tracking.message_id:
                continue  # Skip sent message
            if msg['id'] in existing_reply_ids:
                continue  # Already recorded

            # Check if reply (after sent time)
            msg_date = ...
            if msg_date > tracking.sent_at:
                # Create EmailReply record
                full_msg = service.users().messages().get(...)

                reply = EmailReply.objects.create(
                    customer=tracking.customer,
                    tracking=tracking,
                    message_id=msg['id'],
                    from_address=self._extract_email(full_msg),
                    from_name=self._extract_name(full_msg),
                    received_at=msg_date,
                    snippet=full_msg.get('snippet', '')[:500],
                )

                results['new_replies'].append(self._format_reply(reply))

        # Update tracking status
        tracking.update_status()

        # Add all replies to results
        for reply in tracking.replies.all():
            results['replies'].append(self._format_reply(reply))

        # Categorize tracking record
        if tracking.status == SentEmailTracking.Status.ALL_REPLIED:
            results['all_replied'].append(self._format_tracking(tracking))
        elif tracking.status in [SentEmailTracking.Status.AWAITING_REPLY,
                                  SentEmailTracking.Status.SOME_REPLIED]:
            results['pending'].append({
                **self._format_tracking(tracking),
                'pending_from': tracking.pending_recipients,
                'received_from': list(tracking.replies.values_list('from_address', flat=True)),
            })

    return results
```

### Files to Modify

| File | Changes |
|------|---------|
| `backend/apps/integrations/services/gmail.py` | Rewrite check_replies() to use EmailReply model |

## 3.4 Updated send_email() Method

**Description:** Populate `expected_recipients` when sending tracked emails.

### Changes

```python
def send_email(self, ...):
    # ... existing send logic ...

    if expect_reply:
        # Create tracking with expected recipients
        tracking = SentEmailTracking.objects.create(
            customer=customer,
            message_id=message_id,
            thread_id=thread_id,
            to_addresses=to,
            expected_recipients=to,  # NEW: track who we expect to reply
            subject=subject,
            sent_at=timezone.now(),
            status=SentEmailTracking.Status.AWAITING_REPLY,
            expires_at=timezone.now() + timedelta(days=7),
        )
```

## 3.5 API Response Format

**Description:** Updated response format for `email_check_replies` tool.

### Response Schema

```json
{
  "replies": [
    {
      "tracking_id": "uuid",
      "reply_id": "uuid",
      "original_subject": "Meeting Request",
      "original_to": ["brian@example.com", "jeff@example.com"],
      "from_address": "brian@example.com",
      "from_name": "Brian Smith",
      "received_at": "2026-01-03T15:30:00Z",
      "snippet": "Yes, I'm available Tuesday at 2pm...",
      "parsed_response": {
        "available": true,
        "suggested_times": ["Tuesday 2pm"]
      }
    }
  ],
  "new_replies": [
    // Same format, only newly discovered replies
  ],
  "pending": [
    {
      "tracking_id": "uuid",
      "original_subject": "Meeting Request",
      "original_to": ["brian@example.com", "jeff@example.com"],
      "sent_at": "2026-01-03T10:00:00Z",
      "hours_waiting": 5.5,
      "pending_from": ["jeff@example.com"],
      "received_from": ["brian@example.com"]
    }
  ],
  "all_replied": [
    {
      "tracking_id": "uuid",
      "original_subject": "Meeting Request",
      "reply_count": 2,
      "status": "all_replied"
    }
  ]
}
```

# 4. Future Considerations (Out of Scope)

- **Reply parsing AI:** Use LLM to extract structured availability/confirmation from reply text
- **Auto-proceed missions:** Automatically advance mission when all_replied status reached
- **Reminder scheduling:** Auto-send follow-ups to pending recipients after X hours
- **Reply sentiment analysis:** Detect negative/hesitant responses

# 5. Implementation Approach

## 5.1 Phases

**Phase 1: Model Changes**
1. Create `EmailReply` model
2. Add `expected_recipients` field to `SentEmailTracking`
3. Add new Status choices
4. Generate and run migrations
5. Add admin inlines

**Phase 2: Service Updates**
1. Update `send_email()` to populate `expected_recipients`
2. Rewrite `check_replies()` to create `EmailReply` records
3. Update response format

**Phase 3: Data Migration**
1. Migrate existing `reply_*` fields to `EmailReply` records
2. Backfill `expected_recipients` from `to_addresses`
3. Update existing tracking statuses

**Phase 4: Cleanup**
1. Remove deprecated `reply_*` field usage from code
2. (Optional) Remove deprecated fields in future migration

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| Django 5.2 | Existing |
| PostgreSQL | Existing |

## 5.3 Testing Plan

1. Unit tests for `EmailReply` model
2. Unit tests for `SentEmailTracking` helper methods
3. Integration tests for `check_replies()` with multiple recipients
4. Test data migration script
5. Manual test: send email to 2 recipients, have both reply, verify both captured

# 6. Acceptance Criteria

## 6.1 Model Changes

- [ ] `EmailReply` model created with all specified fields
- [ ] `SentEmailTracking.expected_recipients` field added
- [ ] New Status choices added (SOME_REPLIED, ALL_REPLIED)
- [ ] Helper methods work correctly (pending_recipients, update_status)
- [ ] Migrations run without errors

## 6.2 Service Updates

- [ ] `send_email()` populates `expected_recipients`
- [ ] `check_replies()` creates `EmailReply` records for new replies
- [ ] `check_replies()` returns enhanced response with all categories
- [ ] Duplicate replies not created (idempotent)
- [ ] Status automatically updated when replies received

## 6.3 API Response

- [ ] Response includes `replies`, `new_replies`, `pending`, `all_replied`
- [ ] `pending` items show `pending_from` and `received_from` lists
- [ ] Agent can determine when all expected replies received

## 6.4 Data Migration

- [ ] Existing `reply_*` data migrated to `EmailReply` records
- [ ] Existing tracking records have `expected_recipients` backfilled
- [ ] No data loss during migration

## 6.5 Integration

- [ ] Agent correctly identifies when all recipients have replied
- [ ] Agent can list who has/hasn't replied for a tracked email
- [ ] Mission can proceed when `all_replied` status reached

---

*End of Specification*
