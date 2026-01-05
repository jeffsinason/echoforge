# Email Tools Implementation - Development Prompt

## Objective

Implement the Email tool category for EchoForge Hub, starting with Gmail as the first provider. This enables agents to send emails, search inbox, read messages, and track replies on behalf of users.

## Specification

Full spec: `docs/specs/categories/email.md`

## Scope: Phase 1 + Phase 2 (Gmail)

### Phase 1: Base Infrastructure (Hub)

**1. Create Models** (`echoforge-hub/apps/integrations/models.py`)

```python
class SentEmailTracking(CustomerScopedModel):
    """Track sent emails awaiting replies."""
    # See spec Section 6.1 for full model definition
    # Key fields: tracking_id, message_id, thread_id, status, expires_at

class KnownContact(CustomerScopedModel):
    """Contacts that don't require approval for emails."""
    # Fields: email, name, source, last_contact_at
```

**2. Create Abstract Base Class** (`echoforge-hub/apps/integrations/services/email_base.py`)

```python
class EmailProviderService(ABC):
    provider_slug: str = ""

    @abstractmethod
    def send_email(self, to, subject, body, **kwargs) -> Dict: pass

    @abstractmethod
    def search_emails(self, query, max_results, **kwargs) -> Dict: pass

    @abstractmethod
    def read_email(self, message_id) -> Dict: pass

    @abstractmethod
    def get_thread(self, thread_id) -> Dict: pass
```

**3. Create Provider Selection Logic** (`echoforge-hub/apps/integrations/services/email.py`)

```python
def get_email_service(customer: Customer) -> EmailProviderService:
    """Get the email service for a customer based on their active integration."""
    # See spec Section 3.4
```

**4. Wire Tool Execution Router**

Add email tools to the Hub's internal tool execution endpoint (`POST /api/internal/tools/execute`):
- `email_send`
- `email_search`
- `email_read`
- `email_check_replies`
- `email_send_followup`

### Phase 2: Gmail Provider

**1. Create GmailService** (`echoforge-hub/apps/integrations/services/gmail.py`)

Implement the full `GmailService` class from spec Section 6.3. Key methods:

| Method | Description | Key Requirements |
|--------|-------------|------------------|
| `send_email()` | Send via Gmail API | Threading headers, tracking record if `expect_reply=true` |
| `search_emails()` | Search with Gmail syntax | **Max 25 results, date desc order, snippets only by default** |
| `read_email()` | Get full message | Return headers, body_text, body_html, attachments |
| `check_replies()` | Check tracked emails | Query `SentEmailTracking`, check threads for new messages |
| `send_followup()` | Follow-up on tracked | Thread with original, increment `followup_count` |
| `is_known_contact()` | Check if known | Query `KnownContact` table |

**2. OAuth Integration**

- Scopes needed: `gmail.readonly`, `gmail.send`, `gmail.modify`
- Use existing OAuth infrastructure in Hub
- Implement token refresh via `get_valid_credentials()`

**3. Key Implementation Details for `search_emails`**

```python
def search_emails(self, query, max_results=10, include_body=False, folder='inbox'):
    # CRITICAL: Cap max_results at 25 for token efficiency
    max_results = min(max_results, 25)

    # Gmail API returns newest first by default
    # Only fetch metadata headers unless include_body=true
    # Return: messages[], result_count, has_more (not pagination tokens)
```

**4. Webhook for Push Notifications** (can defer to Phase 7)

- Endpoint: `POST /api/webhooks/gmail/push`
- Uses Google Cloud Pub/Sub
- Detects replies to tracked emails

## Tool Schemas (Agent-Facing)

The Agent already has stub tool classes in `echoforge-agent/src/services/tools/email_tools.py`. These call Hub via `call_hub_tool()`. No agent changes needed—just implement Hub-side execution.

### email_search Input/Output

**Input:**
```json
{
  "query": "from:john@example.com",
  "max_results": 10,        // default 10, max 25
  "include_body": false,    // default false - WARNING: increases tokens
  "folder": "inbox"         // inbox|sent|drafts|trash|all
}
```

**Output:**
```json
{
  "messages": [
    {
      "message_id": "msg_abc123",
      "thread_id": "thread_def456",
      "from": "sarah@example.com",
      "to": ["user@example.com"],
      "subject": "Re: Q1 Planning",
      "snippet": "Thanks for the invite, I'll be there...",
      "date": "2026-01-02T09:15:00Z",
      "labels": ["INBOX", "IMPORTANT"],
      "has_attachments": false
    }
  ],
  "result_count": 5,
  "has_more": true
}
```

**Notes:**
- Results always ordered by date descending (newest first)
- `snippet` truncated to ~100 characters
- `body` field only present if `include_body=true`

## Testing Requirements

1. **Unit Tests:**
   - GmailService with mocked API
   - Token refresh flow
   - MIME message construction
   - Threading headers
   - Search result formatting

2. **Integration Tests (with test Gmail account):**
   - OAuth connect/disconnect
   - Send and verify email
   - Search and verify results
   - Reply tracking end-to-end

## Files to Create/Modify

**Hub (echoforge-hub):**
```
apps/integrations/
├── models.py                    # Add SentEmailTracking, KnownContact
├── migrations/                  # New migration
├── services/
│   ├── email_base.py           # NEW: EmailProviderService ABC
│   ├── email.py                # NEW: get_email_service()
│   └── gmail.py                # NEW: GmailService
├── api/
│   └── internal_views.py       # Add email tool handlers
└── tests/
    └── test_gmail_service.py   # NEW: Unit tests
```

## Dependencies

Add to `requirements/base.txt`:
```
google-api-python-client>=2.100.0
google-auth>=2.23.0
google-auth-oauthlib>=1.1.0
```

## Success Criteria

1. Agent can call `email_search` and get results in date descending order
2. Agent can call `email_send` and email is delivered
3. Agent can call `email_send` with `expect_reply=true` and tracking record is created
4. Agent can call `email_check_replies` and see reply status
5. All search results capped at 25, return `result_count` and `has_more`
6. Snippets truncated to ~100 characters by default

## Reference

- Full spec: `docs/specs/categories/email.md`
- Tool execution contract: `docs/specs/tool_execution_contract.md`
- Existing calendar implementation: `apps/integrations/services/calendar.py` (pattern reference)
