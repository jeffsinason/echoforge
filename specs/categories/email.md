---
title: "Email Category"
version: "1.0"
status: draft
project: EchoForge
created: 2026-01-02
updated: 2026-01-02
---

# Category: Email

> **Status:** Stub (Agent tools defined, Hub returns stubs)
> **Last Updated:** 2026-01-02
> **Owner:** EchoForge Team
> **Priority:** High - Implement quickly

## 1. Overview

### 1.1 Purpose

Email enables agents to communicate on behalf of users - sending emails, searching inbox, reading messages, and tracking replies. This is essential for coordination tasks like "email John to ask about his availability" or "check if Sarah replied to my message."

Key capabilities:
- **Send emails** on behalf of the user
- **Search inbox** for relevant context
- **Track replies** for async coordination
- **Follow-up** on unanswered emails

### 1.2 Classification

| Attribute | Value |
|-----------|-------|
| **Type** | `integration` |
| **Billing** | `included` |
| **Min Plan** | `starter` |
| **Meter Name** | N/A |

### 1.3 Dependencies

- Requires OAuth connection to email provider (Gmail, Outlook)
- Often used with **calendar** for scheduling workflows
- Commonly used within **missions** for async coordination (wait for reply)
- May trigger **approval workflows** for unknown recipients

---

## 2. Tools

### 2.1 Tool Summary

| Tool Name | Description | Async | Approval |
|-----------|-------------|-------|----------|
| `email_send` | Send email from user's account | No* | Required for unknown recipients |
| `email_search` | Search inbox with query | No | No |
| `email_read` | Read full email by ID | No | No |
| `email_check_replies` | Check for replies to sent emails | No | No |
| `email_parse_reply` | Extract structured data from reply | No | No |
| `email_send_followup` | Send follow-up for unanswered email | No | Optional |

*`email_send` with `expect_reply=true` creates an async tracking entry

### 2.2 Tool Definitions

#### `email_send`

**Description:** Send an email from the user's connected email account. Emails to known contacts are sent automatically. Emails to unknown recipients may require user approval first. Use `expect_reply=true` when you need to track responses.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "to": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Recipient email addresses"
    },
    "subject": {
      "type": "string",
      "description": "Email subject line"
    },
    "body": {
      "type": "string",
      "description": "Email body (plain text or HTML)"
    },
    "cc": {
      "type": "array",
      "items": {"type": "string"},
      "description": "CC recipients"
    },
    "bcc": {
      "type": "array",
      "items": {"type": "string"},
      "description": "BCC recipients"
    },
    "reply_to_message_id": {
      "type": "string",
      "description": "Message-ID to reply to (for threading)"
    },
    "expect_reply": {
      "type": "boolean",
      "default": false,
      "description": "Whether to track this email for replies"
    }
  },
  "required": ["to", "subject", "body"]
}
```

**Output Schema:**
```json
{
  "message_id": "msg_abc123xyz",
  "thread_id": "thread_def456",
  "to": ["john@example.com"],
  "subject": "Meeting availability?",
  "status": "sent",
  "sent_at": "2026-01-02T10:30:00Z",
  "tracking_id": "track_789"
}
```

**Approval Guidance:**
- Known contacts (in user's contacts or previous correspondence): Auto-send
- Unknown recipients: Require approval with preview
- Emails with attachments: Consider approval
- Emails to >5 recipients: Consider approval

**Error Cases:**
- `AUTH_ERROR`: OAuth token invalid
- `RECIPIENT_INVALID`: Invalid email address
- `RATE_LIMITED`: Too many emails sent
- `APPROVAL_REQUIRED`: Unknown recipient needs approval

---

#### `email_search`

**Description:** Search the user's inbox for emails matching criteria. Returns results in **date descending order** (newest first). The search is performed server-side by the email provider (Gmail/Outlook) to minimize token usage—only metadata and snippets are returned by default.

**Token Efficiency:** This tool is designed to minimize context window usage:
- Returns only essential metadata by default (no full body)
- Snippets are truncated to ~100 characters
- Use `max_results` to limit response size (default: 10)
- Use `email_read` to fetch full content only when needed

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query (supports Gmail/Outlook operators)"
    },
    "max_results": {
      "type": "integer",
      "default": 10,
      "minimum": 1,
      "maximum": 25,
      "description": "Maximum results to return. Keep low to minimize tokens."
    },
    "include_body": {
      "type": "boolean",
      "default": false,
      "description": "Include full email body in results. WARNING: Significantly increases token usage. Only use when snippet is insufficient."
    },
    "folder": {
      "type": "string",
      "enum": ["inbox", "sent", "drafts", "trash", "all"],
      "default": "inbox",
      "description": "Which folder to search"
    }
  },
  "required": ["query"]
}
```

**Output Schema:**
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
      "has_attachments": false,
      "body": "..."
    }
  ],
  "result_count": 5,
  "has_more": true
}
```

**Output Notes:**
- Results are always ordered by date descending (newest first)
- `snippet` is truncated to ~100 characters from the email body
- `body` field only present if `include_body=true` was requested
- `result_count` shows how many results returned (up to `max_results`)
- `has_more` indicates if more results exist beyond `max_results`

**Query Examples:**
- `from:john@example.com` - Emails from John
- `subject:meeting` - Subject contains "meeting"
- `after:2026/01/01 before:2026/01/15` - Date range
- `is:unread` - Unread emails
- `has:attachment filename:pdf` - PDFs attached

---

#### `email_read`

**Description:** Read the full content of a specific email by its message ID. Returns complete email including headers, body, and attachment metadata.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "message_id": {
      "type": "string",
      "description": "Message ID to read"
    },
    "format": {
      "type": "string",
      "enum": ["full", "metadata", "minimal"],
      "default": "full",
      "description": "How much detail to return"
    }
  },
  "required": ["message_id"]
}
```

**Output Schema:**
```json
{
  "message_id": "msg_abc123",
  "thread_id": "thread_def456",
  "from": {
    "email": "sarah@example.com",
    "name": "Sarah Johnson"
  },
  "to": [{"email": "user@example.com", "name": "User"}],
  "cc": [],
  "subject": "Re: Q1 Planning Meeting",
  "date": "2026-01-02T09:15:00Z",
  "body_text": "Plain text version...",
  "body_html": "<html>HTML version...</html>",
  "labels": ["INBOX", "IMPORTANT"],
  "attachments": [
    {
      "filename": "agenda.pdf",
      "mime_type": "application/pdf",
      "size_bytes": 245000,
      "attachment_id": "att_xyz"
    }
  ],
  "headers": {
    "message_id": "<abc123@mail.gmail.com>",
    "in_reply_to": "<prev123@mail.gmail.com>",
    "references": ["<prev123@mail.gmail.com>"]
  }
}
```

---

#### `email_check_replies`

**Description:** Check for replies to previously sent emails that are being tracked. Returns any new replies found. Use this to follow up on emails sent with `expect_reply=true`.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "tracking_ids": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Specific tracking IDs to check (empty = all pending)"
    },
    "max_age_hours": {
      "type": "integer",
      "default": 168,
      "description": "Maximum age of tracked emails to check (default 7 days)"
    }
  }
}
```

**Output Schema:**
```json
{
  "replies": [
    {
      "tracking_id": "track_789",
      "original_message_id": "msg_abc123",
      "original_subject": "Meeting availability?",
      "original_to": ["john@example.com"],
      "reply": {
        "message_id": "msg_reply456",
        "from": "john@example.com",
        "date": "2026-01-02T14:30:00Z",
        "snippet": "Tuesday at 2pm works for me...",
        "body_text": "Full reply text..."
      }
    }
  ],
  "pending": [
    {
      "tracking_id": "track_790",
      "original_message_id": "msg_def456",
      "original_subject": "Project update?",
      "original_to": ["sarah@example.com"],
      "sent_at": "2026-01-01T10:00:00Z",
      "hours_waiting": 28
    }
  ]
}
```

---

#### `email_parse_reply`

**Description:** Parse an email reply to extract structured information like availability times, confirmations, or answers to questions. Uses AI to understand intent and extract relevant data.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "email_body": {
      "type": "string",
      "description": "The email body text to parse"
    },
    "expected_content": {
      "type": "string",
      "enum": ["availability", "confirmation", "yes_no", "general"],
      "description": "What type of response we're expecting"
    },
    "context": {
      "type": "string",
      "description": "Context about what we originally asked"
    }
  },
  "required": ["email_body", "expected_content"]
}
```

**Output Schema (availability):**
```json
{
  "parsed_type": "availability",
  "confidence": 0.92,
  "data": {
    "available_times": [
      {"date": "2026-01-07", "start": "14:00", "end": "15:00"},
      {"date": "2026-01-08", "start": "10:00", "end": "11:00"}
    ],
    "unavailable_times": [
      {"date": "2026-01-06", "reason": "out of office"}
    ],
    "preferences": "Prefers mornings"
  },
  "raw_interpretation": "John indicated he's free Tuesday 2-3pm or Wednesday 10-11am. He's OOO Monday."
}
```

**Output Schema (confirmation):**
```json
{
  "parsed_type": "confirmation",
  "confidence": 0.95,
  "data": {
    "confirmed": true,
    "confirmed_item": "Meeting on Tuesday at 2pm",
    "conditions": null,
    "additional_notes": "Will bring the Q1 reports"
  }
}
```

---

#### `email_send_followup`

**Description:** Send a polite follow-up email for a previous message that hasn't received a response. Automatically threads with the original email.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "tracking_id": {
      "type": "string",
      "description": "Tracking ID of the original sent email"
    },
    "followup_message": {
      "type": "string",
      "description": "Follow-up message (AI generates if not provided)"
    },
    "urgency": {
      "type": "string",
      "enum": ["low", "normal", "high"],
      "default": "normal",
      "description": "Urgency level affects message tone"
    }
  },
  "required": ["tracking_id"]
}
```

**Output Schema:**
```json
{
  "message_id": "msg_followup789",
  "thread_id": "thread_def456",
  "to": ["john@example.com"],
  "subject": "Re: Meeting availability?",
  "body": "Hi John, just following up on my previous email...",
  "status": "sent",
  "followup_number": 1
}
```

---

## 3. Providers

### 3.1 Provider Summary

| Provider | Slug | Status | Priority | Notes |
|----------|------|--------|----------|-------|
| Gmail | `gmail` | **To Implement** | 1 | Google Workspace & personal Gmail |
| Outlook | `outlook_mail` | **To Implement** | 2 | Microsoft 365 & Outlook.com |
| iCloud | `icloud_mail` | **To Implement** | 3 | Apple iCloud Mail |
| IMAP/SMTP | `imap_smtp` | **To Implement** | 4 | Generic fallback for any provider |

### 3.2 Provider Architecture

All providers implement a common `EmailProviderService` interface:

```python
class EmailProviderService(ABC):
    """Base interface for email providers."""

    provider_slug: str = ""

    @abstractmethod
    def send_email(self, to, subject, body, **kwargs) -> Dict: pass

    @abstractmethod
    def search_emails(self, query, max_results, **kwargs) -> Dict: pass

    @abstractmethod
    def read_email(self, message_id) -> Dict: pass

    @abstractmethod
    def get_thread(self, thread_id) -> Dict: pass

    @abstractmethod
    def setup_push_notifications(self, webhook_url) -> Dict: pass
```

### 3.3 Provider Details

---

#### Gmail

**Provider Slug:** `gmail`

**Use Cases:**
- Google Workspace (business)
- Personal Gmail accounts
- Recommended for users already using Google Calendar

**OAuth Configuration:**

| Field | Value |
|-------|-------|
| Authorization URL | `https://accounts.google.com/o/oauth2/v2/auth` |
| Token URL | `https://oauth2.googleapis.com/token` |
| Scopes | `gmail.readonly`, `gmail.send`, `gmail.modify` |

**OAuth Scopes Required:**
- `https://www.googleapis.com/auth/gmail.readonly` - Read emails and metadata
- `https://www.googleapis.com/auth/gmail.send` - Send emails
- `https://www.googleapis.com/auth/gmail.modify` - Modify labels, mark read/unread

**API Endpoints:**

| Operation | Method | Endpoint |
|-----------|--------|----------|
| List messages | GET | `/gmail/v1/users/me/messages` |
| Get message | GET | `/gmail/v1/users/me/messages/{id}` |
| Send message | POST | `/gmail/v1/users/me/messages/send` |
| Search | GET | `/gmail/v1/users/me/messages?q={query}` |
| Get thread | GET | `/gmail/v1/users/me/threads/{id}` |
| Watch (push) | POST | `/gmail/v1/users/me/watch` |
| Stop watch | POST | `/gmail/v1/users/me/stop` |

**Rate Limits:**
- 250 quota units per user per second
- 1,000,000,000 quota units per day (project-wide)
- Sending: 100 recipients/message, 500 emails/day (personal), 2000/day (Workspace)

**Push Notifications:**
- Uses Google Cloud Pub/Sub
- Webhook receives notification of new messages
- Must re-watch every 7 days (or use `expiration` field)

**Gmail-Specific Behavior:**
- Messages encoded as base64url RFC 2822 format
- Threading via `threadId` (all messages share same thread ID)
- Uses labels instead of folders (`INBOX`, `SENT`, `DRAFT`, custom labels)
- Search uses Gmail query syntax: `from:`, `to:`, `subject:`, `is:`, `has:`, etc.
- Attachments accessed separately via `attachmentId`

**Service Implementation:** `GmailService` (see Section 6.3)

---

#### Outlook / Microsoft 365

**Provider Slug:** `outlook_mail`

**Use Cases:**
- Microsoft 365 (business)
- Outlook.com (personal)
- Hotmail / Live.com accounts
- On-premises Exchange (via hybrid)

**OAuth Configuration:**

| Field | Value |
|-------|-------|
| Authorization URL | `https://login.microsoftonline.com/common/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/common/oauth2/v2.0/token` |
| Scopes | `Mail.Read`, `Mail.Send`, `Mail.ReadWrite` |

**OAuth Scopes Required:**
- `Mail.Read` - Read user's mail
- `Mail.Send` - Send mail as the user
- `Mail.ReadWrite` - Full access to mailbox
- `offline_access` - Refresh tokens

**API Endpoints (Microsoft Graph):**

| Operation | Method | Endpoint |
|-----------|--------|----------|
| List messages | GET | `/v1.0/me/messages` |
| Get message | GET | `/v1.0/me/messages/{id}` |
| Send message | POST | `/v1.0/me/sendMail` |
| Search | GET | `/v1.0/me/messages?$search="{query}"` |
| List folders | GET | `/v1.0/me/mailFolders` |
| Get thread | GET | `/v1.0/me/messages?$filter=conversationId eq '{id}'` |
| Create subscription | POST | `/v1.0/subscriptions` |

**Rate Limits:**
- 10,000 requests per 10 minutes per app per mailbox
- Throttling returns 429 with `Retry-After` header
- Batch requests supported (up to 20 requests per batch)

**Push Notifications:**
- Uses Graph Webhooks (subscriptions)
- Subscription expires after max 4230 minutes (~3 days)
- Must renew subscription before expiry
- Webhook receives `changeType: created` for new messages

**Outlook-Specific Behavior:**
- Messages returned as JSON (no base64 encoding needed)
- Threading via `conversationId` (filter messages by conversation)
- Uses folders: `inbox`, `sentitems`, `drafts`, `deleteditems`
- Search uses OData `$search` or `$filter` syntax
- Rich HTML body in `body.content` with `body.contentType`
- Attachments inline in message or via `/attachments` endpoint

**Service Implementation:**

```python
class OutlookService(EmailProviderService):
    """Microsoft Graph API implementation for Outlook/M365."""

    provider_slug = "outlook_mail"
    base_url = "https://graph.microsoft.com/v1.0"

    def __init__(self, integration: Integration):
        self.integration = integration
        self._client = None

    def _get_client(self):
        """Get authenticated Graph client."""
        if self._client is None:
            creds = get_valid_credentials(self.integration)
            self._client = GraphClient(creds['access_token'])
        return self._client

    def send_email(self, to, subject, body, cc=None, reply_to=None, **kwargs):
        """Send email via Graph API."""
        client = self._get_client()

        message = {
            "message": {
                "subject": subject,
                "body": {
                    "contentType": "HTML",
                    "content": body
                },
                "toRecipients": [
                    {"emailAddress": {"address": addr}} for addr in to
                ],
            },
            "saveToSentItems": True
        }

        if cc:
            message["message"]["ccRecipients"] = [
                {"emailAddress": {"address": addr}} for addr in cc
            ]

        if reply_to:
            # Get original message for threading
            original = client.get(f"/me/messages/{reply_to}")
            message["message"]["conversationId"] = original["conversationId"]

        result = client.post("/me/sendMail", json=message)
        return {
            "message_id": result.get("id"),
            "status": "sent"
        }

    def search_emails(self, query, max_results=10, folder="inbox", **kwargs):
        """
        Search emails using OData.

        Results returned in date descending order (newest first).
        Token efficiency: Only metadata + truncated snippets by default.
        """
        client = self._get_client()

        # Cap max_results to limit token usage
        max_results = min(max_results, 25)

        # Map folder names
        folder_map = {
            "inbox": "inbox",
            "sent": "sentitems",
            "drafts": "drafts",
            "trash": "deleteditems"
        }
        folder_id = folder_map.get(folder, folder)

        params = {
            "$search": f'"{query}"',
            "$top": max_results,
            "$orderby": "receivedDateTime desc",  # Newest first
            "$select": "id,conversationId,from,toRecipients,subject,bodyPreview,receivedDateTime,hasAttachments"
        }

        result = client.get(f"/me/mailFolders/{folder_id}/messages", params=params)
        return {
            "messages": [self._format_message(m) for m in result.get("value", [])],
            "result_count": len(result.get("value", [])),
            "has_more": result.get("@odata.nextLink") is not None
        }

    def setup_push_notifications(self, webhook_url):
        """Create Graph webhook subscription."""
        client = self._get_client()

        subscription = {
            "changeType": "created",
            "notificationUrl": webhook_url,
            "resource": "/me/mailFolders/inbox/messages",
            "expirationDateTime": (datetime.utcnow() + timedelta(days=2)).isoformat() + "Z",
            "clientState": str(self.integration.id)
        }

        result = client.post("/subscriptions", json=subscription)
        return {
            "subscription_id": result["id"],
            "expires_at": result["expirationDateTime"]
        }
```

---

#### iCloud Mail

**Provider Slug:** `icloud_mail`

**Use Cases:**
- Apple iCloud Mail (@icloud.com, @me.com, @mac.com)
- Users in Apple ecosystem
- Integration with Apple Calendar

**Authentication:**
- **No OAuth available** - Apple does not provide OAuth for iCloud Mail
- Uses **App-Specific Passwords** generated from Apple ID settings
- Requires user to enable 2FA and create app password

**Connection Details:**

| Protocol | Server | Port | Security |
|----------|--------|------|----------|
| IMAP | `imap.mail.me.com` | 993 | SSL/TLS |
| SMTP | `smtp.mail.me.com` | 587 | STARTTLS |

**Credentials Required:**
- Apple ID email address
- App-specific password (16 characters, no spaces)

**Rate Limits:**
- Apple doesn't publish official limits
- Estimated: ~200 emails/day for personal accounts
- Aggressive rate limiting may trigger account lock

**iCloud-Specific Behavior:**
- Uses standard IMAP/SMTP protocols (see IMAP/SMTP section)
- Folders: `INBOX`, `Sent Messages`, `Drafts`, `Deleted Messages`, `Junk`
- No push notifications - must use IMAP IDLE or polling
- Limited search compared to Gmail/Outlook
- HTML emails supported but some formatting may differ

**Service Implementation:**

```python
class ICloudService(EmailProviderService):
    """iCloud Mail implementation via IMAP/SMTP."""

    provider_slug = "icloud_mail"

    IMAP_HOST = "imap.mail.me.com"
    IMAP_PORT = 993
    SMTP_HOST = "smtp.mail.me.com"
    SMTP_PORT = 587

    def __init__(self, integration: Integration):
        self.integration = integration
        self._imap = None
        self._smtp = None

    def _get_credentials(self):
        """Get decrypted credentials."""
        return {
            "email": self.integration.metadata.get("email"),
            "password": decrypt(self.integration.access_token),  # App-specific password
        }

    def _get_imap(self):
        """Get IMAP connection."""
        if self._imap is None:
            creds = self._get_credentials()
            self._imap = imaplib.IMAP4_SSL(self.IMAP_HOST, self.IMAP_PORT)
            self._imap.login(creds["email"], creds["password"])
        return self._imap

    def _get_smtp(self):
        """Get SMTP connection."""
        if self._smtp is None:
            creds = self._get_credentials()
            self._smtp = smtplib.SMTP(self.SMTP_HOST, self.SMTP_PORT)
            self._smtp.starttls()
            self._smtp.login(creds["email"], creds["password"])
        return self._smtp

    # Implementation follows IMAP/SMTP pattern below...
```

**Setup Flow:**
1. User goes to appleid.apple.com → Security → App-Specific Passwords
2. Generate new password with name "EchoForge"
3. Enter email + app password in EchoForge connection dialog
4. EchoForge encrypts and stores credentials
5. Connection tested via IMAP login

---

#### IMAP/SMTP (Generic)

**Provider Slug:** `imap_smtp`

**Use Cases:**
- Custom domains (company email on own server)
- GoDaddy, Zoho, cPanel hosted email
- Self-hosted email (Postfix, Exchange on-prem)
- Any provider not directly supported
- Fallback when OAuth isn't available

**Authentication:**
- Username + Password (basic auth)
- Some servers support OAuth2 SASL (rare)
- Credentials stored encrypted

**Connection Details (User-Provided):**

| Field | Example | Notes |
|-------|---------|-------|
| IMAP Host | `imap.example.com` | Required |
| IMAP Port | `993` | Default: 993 (SSL) or 143 (STARTTLS) |
| SMTP Host | `smtp.example.com` | Required |
| SMTP Port | `587` | Default: 587 (STARTTLS) or 465 (SSL) |
| Username | `user@example.com` | Usually email address |
| Password | `********` | Encrypted storage |
| Security | `SSL` or `STARTTLS` | Required |

**Common Provider Presets:**

| Provider | IMAP Host | SMTP Host | Ports |
|----------|-----------|-----------|-------|
| GoDaddy | `imap.secureserver.net` | `smtpout.secureserver.net` | 993/465 |
| Zoho | `imap.zoho.com` | `smtp.zoho.com` | 993/587 |
| Yahoo | `imap.mail.yahoo.com` | `smtp.mail.yahoo.com` | 993/587 |
| FastMail | `imap.fastmail.com` | `smtp.fastmail.com` | 993/587 |
| ProtonMail | Via ProtonMail Bridge | Via Bridge | Local |

**IMAP Commands Used:**

| Operation | Command |
|-----------|---------|
| Select folder | `SELECT INBOX` |
| Search | `SEARCH FROM "john" SINCE 1-Jan-2026` |
| Fetch message | `FETCH 1 (RFC822)` |
| Fetch headers | `FETCH 1 (BODY[HEADER])` |
| List folders | `LIST "" "*"` |
| Mark read | `STORE 1 +FLAGS (\Seen)` |
| IDLE (push) | `IDLE` (if supported) |

**SMTP Process:**
1. Connect and STARTTLS/SSL
2. AUTH LOGIN or AUTH PLAIN
3. MAIL FROM, RCPT TO
4. DATA with RFC 2822 message
5. QUIT

**Rate Limits:**
- Varies by provider
- GoDaddy: 250 recipients/day
- Most providers: 100-500/day
- Should implement exponential backoff on 4xx/5xx

**Push Notifications:**
- IMAP IDLE provides real-time push (if server supports)
- Falls back to polling (every 5 minutes recommended)
- IDLE connection may drop - reconnect handling required

**Service Implementation:**

```python
class IMAPSMTPService(EmailProviderService):
    """Generic IMAP/SMTP implementation."""

    provider_slug = "imap_smtp"

    def __init__(self, integration: Integration):
        self.integration = integration
        self._imap = None
        self._smtp = None

        # Get server config from integration metadata
        self.imap_host = integration.metadata.get("imap_host")
        self.imap_port = integration.metadata.get("imap_port", 993)
        self.smtp_host = integration.metadata.get("smtp_host")
        self.smtp_port = integration.metadata.get("smtp_port", 587)
        self.use_ssl = integration.metadata.get("use_ssl", True)

    def _get_imap(self):
        """Get authenticated IMAP connection."""
        if self._imap is None:
            email = self.integration.metadata.get("email")
            password = decrypt(self.integration.access_token)

            if self.use_ssl:
                self._imap = imaplib.IMAP4_SSL(self.imap_host, self.imap_port)
            else:
                self._imap = imaplib.IMAP4(self.imap_host, self.imap_port)
                self._imap.starttls()

            self._imap.login(email, password)
        return self._imap

    def _get_smtp(self):
        """Get authenticated SMTP connection."""
        if self._smtp is None:
            email = self.integration.metadata.get("email")
            password = decrypt(self.integration.access_token)

            if self.smtp_port == 465:
                self._smtp = smtplib.SMTP_SSL(self.smtp_host, self.smtp_port)
            else:
                self._smtp = smtplib.SMTP(self.smtp_host, self.smtp_port)
                self._smtp.starttls()

            self._smtp.login(email, password)
        return self._smtp

    def send_email(self, to, subject, body, cc=None, reply_to=None, **kwargs):
        """Send email via SMTP."""
        smtp = self._get_smtp()
        email_addr = self.integration.metadata.get("email")

        # Build message
        msg = MIMEMultipart('alternative')
        msg['From'] = email_addr
        msg['To'] = ', '.join(to)
        msg['Subject'] = subject
        msg['Date'] = formatdate(localtime=True)
        msg['Message-ID'] = make_msgid()

        if cc:
            msg['Cc'] = ', '.join(cc)

        if reply_to:
            # Fetch original message for threading
            original = self.read_email(reply_to)
            if original.get('headers', {}).get('message_id'):
                msg['In-Reply-To'] = original['headers']['message_id']
                msg['References'] = original['headers']['message_id']

        msg.attach(MIMEText(body, 'html'))

        # Send
        all_recipients = to + (cc or [])
        smtp.sendmail(email_addr, all_recipients, msg.as_string())

        return {
            "message_id": msg['Message-ID'],
            "status": "sent",
            "to": to,
            "subject": subject,
        }

    def search_emails(self, query, max_results=10, folder="inbox", **kwargs):
        """
        Search emails via IMAP SEARCH.

        Results returned in date descending order (newest first).
        Token efficiency: Only fetches headers + truncated body preview.
        """
        imap = self._get_imap()

        # Cap max_results to limit token usage
        max_results = min(max_results, 25)

        # Map folder names
        folder_map = {
            "inbox": "INBOX",
            "sent": "Sent",
            "drafts": "Drafts",
            "trash": "Trash"
        }
        imap.select(folder_map.get(folder, folder))

        # Build IMAP search criteria from query
        criteria = self._parse_query_to_imap(query)

        _, message_ids = imap.search(None, criteria)
        all_ids = message_ids[0].split()

        # Take latest N (IMAP returns oldest first, so take from end)
        ids = all_ids[-max_results:] if len(all_ids) > max_results else all_ids

        messages = []
        for msg_id in reversed(ids):  # Reverse to get newest first
            # Fetch only headers + first 500 bytes of body for snippet
            _, data = imap.fetch(msg_id, '(RFC822.HEADER BODY[TEXT]<0.500>)')
            messages.append(self._parse_imap_message(msg_id.decode(), data))

        return {
            "messages": messages,
            "result_count": len(messages),
            "has_more": len(all_ids) > max_results
        }

    def read_email(self, message_id):
        """Read full email by IMAP UID."""
        imap = self._get_imap()
        imap.select("INBOX")

        _, data = imap.fetch(message_id.encode(), '(RFC822)')
        return self._parse_imap_message(message_id, data, full=True)

    def setup_push_notifications(self, webhook_url):
        """Set up IMAP IDLE for push (or return polling config)."""
        imap = self._get_imap()

        # Check if server supports IDLE
        _, capabilities = imap.capability()
        supports_idle = b'IDLE' in capabilities[0].split()

        if supports_idle:
            return {
                "method": "idle",
                "requires_persistent_connection": True
            }
        else:
            return {
                "method": "polling",
                "recommended_interval_seconds": 300
            }

    def _parse_query_to_imap(self, query: str) -> str:
        """Convert search query to IMAP SEARCH format."""
        # Simple conversion - production would be more robust
        if query.startswith("from:"):
            return f'FROM "{query[5:]}"'
        elif query.startswith("subject:"):
            return f'SUBJECT "{query[8:]}"'
        else:
            return f'TEXT "{query}"'

    def _parse_imap_message(self, msg_id, data, full=False):
        """Parse IMAP response to standard format."""
        import email
        raw = data[0][1] if data and data[0] else b''
        msg = email.message_from_bytes(raw)

        result = {
            "message_id": msg_id,
            "from": msg.get("From", ""),
            "to": msg.get("To", "").split(", "),
            "subject": msg.get("Subject", ""),
            "date": msg.get("Date", ""),
        }

        if full:
            # Extract body
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        body = part.get_payload(decode=True).decode()
                        break
            else:
                body = msg.get_payload(decode=True).decode()
            result["body_text"] = body

        return result
```

**Setup Flow:**
1. User selects "Other email provider" or specific preset
2. Enter IMAP/SMTP server details (or auto-fill from preset)
3. Enter email address and password
4. Test connection (IMAP login + SMTP auth)
5. Save encrypted credentials

---

### 3.4 Provider Selection Logic

When executing email tools, Hub determines which provider to use:

```python
def get_email_service(customer: Customer) -> EmailProviderService:
    """Get the email service for a customer."""

    # Find active email integration
    integration = Integration.objects.filter(
        customer=customer,
        provider__tool_category__slug='email',
        is_active=True,
    ).first()

    if not integration:
        raise NoEmailIntegrationError("No email integration connected")

    # Instantiate correct service
    service_map = {
        'gmail': GmailService,
        'outlook_mail': OutlookService,
        'icloud_mail': ICloudService,
        'imap_smtp': IMAPSMTPService,
    }

    service_class = service_map.get(integration.provider.slug)
    if not service_class:
        raise UnsupportedProviderError(f"Unknown provider: {integration.provider.slug}")

    return service_class(integration)
```

---

## 4. Logic Flows

### 4.1 Send with Reply Tracking

```
email_send(to=[john], expect_reply=true)
                    │
                    ▼
┌─────────────────────────────────────┐
│ 1. Create SentEmailTracking record  │
│    - tracking_id = uuid             │
│    - message_id = sent msg id       │
│    - status = awaiting_reply        │
│    - expires_at = now + 7 days      │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ 2. Send email via Gmail API         │
│    - Include tracking header        │
│    - Store thread_id                │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ 3. Return to agent                  │
│    - message_id, tracking_id        │
└─────────────────────────────────────┘
```

### 4.2 Reply Detection Flow

```
┌─────────────────────────────────────┐
│ Gmail Pub/Sub Webhook               │
│ (new message in inbox)              │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Check if reply to tracked email     │
│ - Match thread_id                   │
│ - Match In-Reply-To header          │
└─────────────────┬───────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌───────────────┐   ┌───────────────────┐
│ Not tracked   │   │ Is tracked reply  │
│ (ignore)      │   │                   │
└───────────────┘   └─────────┬─────────┘
                              │
                              ▼
                ┌─────────────────────────────┐
                │ Update SentEmailTracking    │
                │ - status = reply_received   │
                │ - reply_message_id = new id │
                │ - reply_received_at = now   │
                └─────────────────┬───────────┘
                                  │
                                  ▼
                ┌─────────────────────────────┐
                │ If mission waiting:         │
                │ - Trigger mission resume    │
                │ - Pass reply content        │
                └─────────────────────────────┘
```

### 4.3 Approval Flow for Unknown Recipients

```
email_send(to=[unknown@example.com])
                    │
                    ▼
┌─────────────────────────────────────┐
│ Check if recipient is known         │
│ - In contacts?                      │
│ - Previous correspondence?          │
│ - Same domain as user?              │
└─────────────────┬───────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌───────────────┐   ┌───────────────────┐
│ Known         │   │ Unknown           │
│ → Auto-send   │   │ → Require approval│
└───────────────┘   └─────────┬─────────┘
                              │
                              ▼
                ┌─────────────────────────────┐
                │ Return approval_required    │
                │ with email preview          │
                └─────────────────┬───────────┘
                                  │
                                  ▼
                ┌─────────────────────────────┐
                │ User approves in chat/dash  │
                └─────────────────┬───────────┘
                                  │
                                  ▼
                ┌─────────────────────────────┐
                │ Send email                  │
                │ Add to known contacts       │
                └─────────────────────────────┘
```

---

## 5. UI/UX

### 5.1 Chat Interface

**Email Sent Card:**
```
┌─────────────────────────────────────────────────────────┐
│ ✉️ Email Sent                                           │
│                                                         │
│ To: john@example.com                                    │
│ Subject: Meeting availability?                          │
│                                                         │
│ "Hi John, I'm reaching out to find a time for us to    │
│ meet next week regarding the Q1 budget..."             │
│                                                         │
│ 📬 Tracking reply                                       │
└─────────────────────────────────────────────────────────┘
```

**Approval Request Card:**
```
┌─────────────────────────────────────────────────────────┐
│ 🔔 Email Approval Required                              │
│                                                         │
│ I'd like to send an email to an address I don't        │
│ recognize:                                              │
│                                                         │
│ To: unknown.person@external.com                         │
│ Subject: Meeting request                                │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Preview:                                            │ │
│ │ "Hello, I'm reaching out on behalf of [User] to    │ │
│ │ schedule a meeting regarding..."                    │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ [Approve & Send] [Edit] [Cancel]                        │
└─────────────────────────────────────────────────────────┘
```

**Reply Received Card:**
```
┌─────────────────────────────────────────────────────────┐
│ 📬 Reply Received                                       │
│                                                         │
│ From: john@example.com                                  │
│ Subject: Re: Meeting availability?                      │
│                                                         │
│ "Hi! Tuesday at 2pm or Wednesday at 10am works for     │
│ me. Let me know which is better for you."              │
│                                                         │
│ I've extracted his availability:                        │
│ • Tuesday 2:00 PM - 3:00 PM                            │
│ • Wednesday 10:00 AM - 11:00 AM                        │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Dashboard Components

Email integration is managed in **Settings > Integrations**:

```
┌──────────────────────────────────────────────────────────────────┐
│ ✉️ Email                                                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ ✅ Gmail                                        Connected  │   │
│ │    user@gmail.com                                          │   │
│ │    Permissions: Read, Send, Modify                         │   │
│ │                                                            │   │
│ │    [Disconnect] [Test Connection]                          │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ ⬚ Outlook                                   Not Connected │   │
│ │                                                            │   │
│ │    [Connect with Microsoft]                                │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
│ Email Preferences:                                               │
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ ☑️ Require approval for unknown recipients                 │   │
│ │ ☐ Require approval for all emails                          │   │
│ │ ☑️ Track replies automatically                              │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.3 Notifications

| Event | Chat | Dashboard | Email | Push |
|-------|------|-----------|-------|------|
| Email sent | Confirmation | - | - | - |
| Approval required | Card | Badge | If idle >1h | If enabled |
| Reply received | Card | Badge | If in mission | - |
| Tracking expired | Message | - | - | - |

---

## 6. Hub Implementation

### 6.1 Models

```python
# apps/integrations/models.py (or apps/email/models.py)

class SentEmailTracking(CustomerScopedModel):
    """Track sent emails awaiting replies."""

    class Status(models.TextChoices):
        AWAITING_REPLY = 'awaiting_reply', 'Awaiting Reply'
        REPLY_RECEIVED = 'reply_received', 'Reply Received'
        FOLLOWUP_SENT = 'followup_sent', 'Follow-up Sent'
        EXPIRED = 'expired', 'Expired'
        CANCELLED = 'cancelled', 'Cancelled'

    # Identifiers
    tracking_id = models.UUIDField(default=uuid.uuid4, unique=True, db_index=True)
    message_id = models.CharField(max_length=255)  # Gmail message ID
    thread_id = models.CharField(max_length=255)   # Gmail thread ID

    # Original email details
    to_addresses = models.JSONField()  # List of recipients
    subject = models.CharField(max_length=500)
    sent_at = models.DateTimeField()

    # Tracking state
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.AWAITING_REPLY
    )
    expires_at = models.DateTimeField()

    # Reply info (populated when reply received)
    reply_message_id = models.CharField(max_length=255, blank=True)
    reply_received_at = models.DateTimeField(null=True, blank=True)
    reply_from = models.EmailField(blank=True)
    reply_snippet = models.TextField(blank=True)

    # Mission integration
    mission_task = models.ForeignKey(
        'agents.MissionTask',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='email_tracking'
    )

    # Follow-up tracking
    followup_count = models.IntegerField(default=0)
    last_followup_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=['thread_id']),
            models.Index(fields=['status', 'expires_at']),
        ]


class KnownContact(CustomerScopedModel):
    """Contacts that don't require approval for emails."""

    email = models.EmailField()
    name = models.CharField(max_length=200, blank=True)
    source = models.CharField(max_length=50)  # 'manual', 'correspondence', 'contacts_sync'
    last_contact_at = models.DateTimeField(null=True)

    class Meta:
        unique_together = ['customer', 'email']
```

### 6.2 API Endpoints

**Tool Execution (Internal API):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/internal/tools/execute` | Execute email tool |

**Webhook (Gmail Push):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/webhooks/gmail/push` | Gmail Pub/Sub notification |

**Integration Management:**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/integrations/` | List integrations |
| `POST` | `/api/v1/integrations/gmail/connect/` | Initiate Gmail OAuth |
| `POST` | `/api/v1/integrations/{id}/disconnect/` | Disconnect |

### 6.3 Services

```python
# apps/integrations/services/gmail.py

import base64
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, List, Optional
from datetime import datetime, timedelta

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from apps.integrations.models import Integration, SentEmailTracking, KnownContact
from apps.integrations.oauth import get_valid_credentials


class GmailError(Exception):
    """Exception raised when a Gmail operation fails."""
    def __init__(self, code: str, message: str, details: dict = None):
        self.code = code
        self.message = message
        self.details = details or {}
        super().__init__(message)


class GmailService:
    """Service for Gmail API operations."""

    def __init__(self, integration: Integration):
        self.integration = integration
        self._service = None

    def _get_service(self):
        """Get or create the Gmail service instance."""
        if self._service is None:
            creds_data = get_valid_credentials(self.integration)
            if not creds_data:
                raise GmailError(
                    code='CREDENTIALS_INVALID',
                    message='Unable to obtain valid credentials.'
                )
            creds = Credentials(
                token=creds_data['access_token'],
                refresh_token=self.integration.refresh_token,
                token_uri='https://oauth2.googleapis.com/token',
                client_id=settings.GOOGLE_CLIENT_ID,
                client_secret=settings.GOOGLE_CLIENT_SECRET,
            )
            self._service = build('gmail', 'v1', credentials=creds)
        return self._service

    def send_email(
        self,
        to: List[str],
        subject: str,
        body: str,
        cc: List[str] = None,
        bcc: List[str] = None,
        reply_to_message_id: str = None,
        expect_reply: bool = False,
    ) -> Dict:
        """
        Send an email via Gmail.

        Args:
            to: List of recipient addresses
            subject: Email subject
            body: Email body (HTML supported)
            cc: CC recipients
            bcc: BCC recipients
            reply_to_message_id: Message ID to reply to (for threading)
            expect_reply: Whether to track for reply

        Returns:
            Dict with message_id, thread_id, tracking_id (if tracking)
        """
        service = self._get_service()

        # Build message
        message = MIMEMultipart('alternative')
        message['to'] = ', '.join(to)
        message['subject'] = subject

        if cc:
            message['cc'] = ', '.join(cc)

        # Add threading headers if reply
        thread_id = None
        if reply_to_message_id:
            # Get original message for headers
            original = service.users().messages().get(
                userId='me',
                id=reply_to_message_id,
                format='metadata',
                metadataHeaders=['Message-ID']
            ).execute()

            original_msg_id = self._get_header(original, 'Message-ID')
            if original_msg_id:
                message['In-Reply-To'] = original_msg_id
                message['References'] = original_msg_id
            thread_id = original.get('threadId')

        # Add body
        message.attach(MIMEText(body, 'html'))

        # Encode and send
        raw = base64.urlsafe_b64encode(message.as_bytes()).decode()

        send_body = {'raw': raw}
        if thread_id:
            send_body['threadId'] = thread_id

        try:
            result = service.users().messages().send(
                userId='me',
                body=send_body
            ).execute()

            response = {
                'message_id': result['id'],
                'thread_id': result.get('threadId'),
                'to': to,
                'subject': subject,
                'status': 'sent',
                'sent_at': datetime.utcnow().isoformat() + 'Z',
            }

            # Create tracking record if needed
            if expect_reply:
                tracking = SentEmailTracking.objects.create(
                    customer=self.integration.customer,
                    message_id=result['id'],
                    thread_id=result.get('threadId'),
                    to_addresses=to,
                    subject=subject,
                    sent_at=datetime.utcnow(),
                    expires_at=datetime.utcnow() + timedelta(days=7),
                )
                response['tracking_id'] = str(tracking.tracking_id)

            return response

        except HttpError as e:
            raise self._handle_api_error(e, 'send_email')

    def search_emails(
        self,
        query: str,
        max_results: int = 10,
        include_body: bool = False,
        folder: str = 'inbox',
    ) -> Dict:
        """
        Search emails using Gmail query syntax.

        Results are returned in date descending order (newest first).
        Token efficiency: Only metadata + truncated snippets by default.

        Args:
            query: Gmail search query
            max_results: Max emails to return (capped at 25)
            include_body: Include full body text (increases token usage)
            folder: Which folder to search

        Returns:
            Dict with messages list, ordered by date descending
        """
        service = self._get_service()

        # Cap max_results to limit token usage
        max_results = min(max_results, 25)

        # Add folder to query
        if folder == 'inbox':
            query = f'in:inbox {query}'
        elif folder == 'sent':
            query = f'in:sent {query}'
        elif folder == 'drafts':
            query = f'in:drafts {query}'

        try:
            # Gmail API returns newest first by default
            result = service.users().messages().list(
                userId='me',
                q=query,
                maxResults=max_results,
            ).execute()

            messages = []
            for msg_ref in result.get('messages', []):
                msg = service.users().messages().get(
                    userId='me',
                    id=msg_ref['id'],
                    format='metadata' if not include_body else 'full',
                    metadataHeaders=['From', 'To', 'Subject', 'Date']
                ).execute()

                messages.append(self._format_message(msg, include_body))

            return {
                'messages': messages,
                'result_count': len(messages),
                'has_more': result.get('nextPageToken') is not None,
            }

        except HttpError as e:
            raise self._handle_api_error(e, 'search_emails')

    def read_email(self, message_id: str, format: str = 'full') -> Dict:
        """Read a specific email by ID."""
        service = self._get_service()

        try:
            msg = service.users().messages().get(
                userId='me',
                id=message_id,
                format=format,
            ).execute()

            return self._format_message(msg, include_body=True)

        except HttpError as e:
            raise self._handle_api_error(e, 'read_email')

    def check_replies(
        self,
        tracking_ids: List[str] = None,
        max_age_hours: int = 168,
    ) -> Dict:
        """Check for replies to tracked emails."""
        customer = self.integration.customer

        # Get tracked emails
        query = SentEmailTracking.objects.filter(
            customer=customer,
            status=SentEmailTracking.Status.AWAITING_REPLY,
            expires_at__gt=datetime.utcnow(),
        )

        if tracking_ids:
            query = query.filter(tracking_id__in=tracking_ids)
        else:
            cutoff = datetime.utcnow() - timedelta(hours=max_age_hours)
            query = query.filter(sent_at__gte=cutoff)

        replies = []
        pending = []
        service = self._get_service()

        for tracking in query:
            # Search for replies in thread
            thread = service.users().threads().get(
                userId='me',
                id=tracking.thread_id,
                format='metadata',
            ).execute()

            # Check for new messages after our sent message
            found_reply = False
            for msg in thread.get('messages', []):
                if msg['id'] == tracking.message_id:
                    continue  # Skip our sent message

                # Check if this is a reply (has our message in thread)
                internal_date = int(msg.get('internalDate', 0)) / 1000
                msg_date = datetime.fromtimestamp(internal_date)

                if msg_date > tracking.sent_at:
                    # Get full message for reply
                    full_msg = service.users().messages().get(
                        userId='me',
                        id=msg['id'],
                        format='full',
                    ).execute()

                    # Update tracking
                    tracking.status = SentEmailTracking.Status.REPLY_RECEIVED
                    tracking.reply_message_id = msg['id']
                    tracking.reply_received_at = msg_date
                    tracking.reply_from = self._get_header(full_msg, 'From')
                    tracking.reply_snippet = full_msg.get('snippet', '')
                    tracking.save()

                    replies.append({
                        'tracking_id': str(tracking.tracking_id),
                        'original_message_id': tracking.message_id,
                        'original_subject': tracking.subject,
                        'original_to': tracking.to_addresses,
                        'reply': self._format_message(full_msg, include_body=True),
                    })
                    found_reply = True
                    break

            if not found_reply:
                hours_waiting = (datetime.utcnow() - tracking.sent_at).total_seconds() / 3600
                pending.append({
                    'tracking_id': str(tracking.tracking_id),
                    'original_message_id': tracking.message_id,
                    'original_subject': tracking.subject,
                    'original_to': tracking.to_addresses,
                    'sent_at': tracking.sent_at.isoformat() + 'Z',
                    'hours_waiting': round(hours_waiting, 1),
                })

        return {'replies': replies, 'pending': pending}

    def send_followup(
        self,
        tracking_id: str,
        followup_message: str = None,
        urgency: str = 'normal',
    ) -> Dict:
        """Send follow-up for tracked email."""
        tracking = SentEmailTracking.objects.get(
            tracking_id=tracking_id,
            customer=self.integration.customer,
        )

        if tracking.status == SentEmailTracking.Status.REPLY_RECEIVED:
            raise GmailError(
                code='ALREADY_REPLIED',
                message='This email already received a reply',
            )

        # Generate follow-up message if not provided
        if not followup_message:
            followup_message = self._generate_followup_message(
                tracking.subject,
                urgency,
                tracking.followup_count,
            )

        # Send as reply to original
        result = self.send_email(
            to=tracking.to_addresses,
            subject=f"Re: {tracking.subject}",
            body=followup_message,
            reply_to_message_id=tracking.message_id,
            expect_reply=True,  # Continue tracking
        )

        # Update tracking
        tracking.followup_count += 1
        tracking.last_followup_at = datetime.utcnow()
        tracking.status = SentEmailTracking.Status.FOLLOWUP_SENT
        tracking.save()

        result['followup_number'] = tracking.followup_count
        return result

    def is_known_contact(self, email: str) -> bool:
        """Check if email is a known contact."""
        return KnownContact.objects.filter(
            customer=self.integration.customer,
            email__iexact=email,
        ).exists()

    def _format_message(self, msg: dict, include_body: bool = False) -> dict:
        """Format Gmail message to standard structure."""
        headers = {h['name']: h['value'] for h in msg.get('payload', {}).get('headers', [])}

        result = {
            'message_id': msg['id'],
            'thread_id': msg.get('threadId'),
            'from': headers.get('From', ''),
            'to': headers.get('To', '').split(', '),
            'subject': headers.get('Subject', ''),
            'date': headers.get('Date', ''),
            'snippet': msg.get('snippet', ''),
            'labels': msg.get('labelIds', []),
        }

        if include_body:
            result['body_text'] = self._extract_body(msg, 'text/plain')
            result['body_html'] = self._extract_body(msg, 'text/html')

        return result

    def _extract_body(self, msg: dict, mime_type: str) -> str:
        """Extract body of specific MIME type from message."""
        payload = msg.get('payload', {})

        # Simple message
        if payload.get('mimeType') == mime_type:
            data = payload.get('body', {}).get('data', '')
            return base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')

        # Multipart message
        for part in payload.get('parts', []):
            if part.get('mimeType') == mime_type:
                data = part.get('body', {}).get('data', '')
                return base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')

        return ''

    def _get_header(self, msg: dict, header_name: str) -> str:
        """Get header value from message."""
        for header in msg.get('payload', {}).get('headers', []):
            if header['name'].lower() == header_name.lower():
                return header['value']
        return ''

    def _handle_api_error(self, error: HttpError, operation: str) -> GmailError:
        """Convert Gmail API error to GmailError."""
        status = error.resp.status
        reason = error._get_reason() if hasattr(error, '_get_reason') else str(error)

        error_map = {
            401: ('AUTH_ERROR', 'Authentication failed.'),
            403: ('PERMISSION_DENIED', 'Permission denied.'),
            404: ('NOT_FOUND', 'Message not found.'),
            429: ('RATE_LIMITED', 'Too many requests.'),
        }

        code, message = error_map.get(status, ('API_ERROR', f'Gmail API error: {reason}'))
        return GmailError(code=code, message=message, details={'operation': operation})

    def _generate_followup_message(
        self,
        subject: str,
        urgency: str,
        followup_count: int,
    ) -> str:
        """Generate a follow-up message."""
        if urgency == 'high':
            tone = "I wanted to follow up urgently on my previous email"
        elif urgency == 'low':
            tone = "Just a gentle reminder about my previous email"
        else:
            tone = "I wanted to follow up on my previous email"

        ordinal = {1: 'first', 2: 'second', 3: 'third'}.get(followup_count, f'{followup_count}th')

        return f"""<p>{tone} regarding "{subject}".</p>
<p>I understand you may be busy, but I would appreciate your response when you have a moment.</p>
<p>This is my {ordinal} follow-up on this matter.</p>
<p>Thank you!</p>"""
```

---

## 7. Agent Implementation

### 7.1 Tool Classes

Already implemented in `src/services/tools/email_tools.py`:
- `EmailSendTool`
- `EmailSearchTool`
- `EmailReadTool`
- `EmailCheckRepliesTool`
- `EmailParseReplyTool`
- `EmailSendFollowupTool`

All tools use the Hub-proxied pattern via `call_hub_tool()`.

### 7.2 Integration with Handler

```python
# In PersonalAssistantHandler

# Email tools are included in enabled_actions from Hub config
# Agent validates against config.actions_enabled before executing
# Hub handles OAuth, API calls, and tracking
```

---

## 8. Testing

### 8.1 Unit Tests

- [ ] GmailService initialization with valid credentials
- [ ] Token refresh when access token expires
- [ ] send_email creates correct MIME structure
- [ ] send_email with reply_to_message_id adds threading headers
- [ ] search_emails with various query formats
- [ ] read_email returns full message details
- [ ] check_replies detects new replies in thread
- [ ] send_followup increments followup_count
- [ ] is_known_contact checks database correctly
- [ ] Error handling for auth failures
- [ ] Error handling for rate limiting

### 8.2 Integration Tests

- [ ] Full OAuth flow (connect → use → refresh → disconnect)
- [ ] Send email and verify in Gmail
- [ ] Search emails and verify results
- [ ] Reply tracking end-to-end
- [ ] Webhook receives push notification
- [ ] Approval flow for unknown recipients

### 8.3 E2E Scenarios

- [ ] "Email John to ask about his availability" → send with tracking
- [ ] "Did Sarah reply to my email?" → check_replies
- [ ] "Search for emails from the marketing team" → search
- [ ] "Send a follow-up to John" → send_followup
- [ ] Mission: Send email → wait for reply → use reply data

---

## 9. Implementation Roadmap

### Phase 1: Base Infrastructure
1. Create `EmailProviderService` abstract base class
2. Create `SentEmailTracking` model + migrations
3. Create `KnownContact` model + migrations
4. Create provider selection logic (`get_email_service()`)
5. Wire up Hub internal API tool execution router

### Phase 2: Gmail Provider (Priority 1)
1. Create `GmailService` class with OAuth handling
2. Implement `send_email()` with tracking support
3. Implement `search_emails()` with Gmail query syntax
4. Implement `read_email()` with full message parsing
5. Set up Gmail Pub/Sub webhook for push notifications
6. Implement `check_replies()` via thread monitoring
7. Test end-to-end with agent

### Phase 3: Outlook Provider (Priority 2)
1. Create `OutlookService` class with Graph API client
2. Implement OAuth flow for Microsoft identity
3. Implement `send_email()` with Graph API
4. Implement `search_emails()` with OData syntax
5. Implement `read_email()`
6. Set up Graph webhook subscription
7. Implement `check_replies()` via conversationId
8. Test end-to-end with agent

### Phase 4: iCloud Provider (Priority 3)
1. Create `ICloudService` class extending IMAP/SMTP base
2. Implement app-specific password setup flow in UI
3. Implement IMAP connection with Apple servers
4. Implement SMTP sending
5. Test end-to-end with agent

### Phase 5: IMAP/SMTP Generic Provider (Priority 4)
1. Create `IMAPSMTPService` class
2. Implement provider presets (GoDaddy, Zoho, Yahoo, etc.)
3. Implement custom server configuration UI
4. Implement IMAP IDLE for push (where supported)
5. Implement polling fallback
6. Test with multiple providers

### Phase 6: Advanced Features
1. Implement `send_followup()` across all providers
2. Implement `email_parse_reply` (LLM-based parsing)
3. Add approval flow for unknown recipients
4. Link `SentEmailTracking` to `MissionTask`
5. Trigger mission resume on reply received
6. Test full mission flow with email coordination

### Phase 7: Polish & Monitoring
1. Add connection health monitoring
2. Implement token refresh for OAuth providers
3. Add rate limit tracking and backoff
4. Create admin dashboard for email integration status
5. Add metrics and alerting

---

## 10. Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-01-02 | Initial spec with full implementation design | Claude |
| 2026-01-02 | Added Outlook, iCloud, IMAP/SMTP providers | Claude |
| 2026-01-02 | Updated email_search for token efficiency: max 25 results, date desc order, truncated snippets | Claude |
