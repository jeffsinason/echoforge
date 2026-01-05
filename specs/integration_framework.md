---
title: EchoForge Hub Integration Framework
version: "1.0"
status: draft
project: EchoForge Hub
created: 2025-12-29
updated: 2025-12-29
---

# 1. Executive Summary

This specification defines the integration framework for EchoForge Hub — the architecture, patterns, and processes for connecting agents to external communication channels and services. It includes detailed design sheets for the initial five integrations: Gmail, Outlook, Apple Mail (IMAP/SMTP), Telegram, and Slack.

**Purpose of Integrations:**
- **Communication Channels** — Allow agents to interact with users via email, messaging apps, chat platforms
- **Service Integrations** — Connect to CRMs, ticketing systems, calendars (future)

**This Spec Covers:**
1. Integration architecture and data model (extends Hub spec)
2. Authentication patterns (OAuth2, API keys, IMAP credentials)
3. Message routing and channel abstraction
4. Integration design sheet template
5. Initial integrations: Gmail, Outlook, Apple Mail, Telegram, Slack

---

# 2. Integration Architecture

## 2.1 Integration Types

| Type | Description | Examples |
|------|-------------|----------|
| **Channel** | Two-way communication with end users | Gmail, Slack, Telegram |
| **Service** | Backend system integration | Zendesk, HubSpot, Calendly |
| **Notification** | One-way outbound notifications | SMS, Push notifications |

This spec focuses on **Channel** integrations — enabling agents to communicate across platforms.

## 2.2 Message Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              End User                                    │
│         (sends email, Slack message, Telegram message, etc.)            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         External Platform                                │
│              (Gmail, Outlook, Telegram, Slack, etc.)                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                          Webhook / Poll / Push
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          EchoForge Hub                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Integration Gateway                           │   │
│  │  • Receives inbound messages (webhooks, polling)                │   │
│  │  • Normalizes to standard ChannelMessage format                 │   │
│  │  • Routes to appropriate AgentInstance                          │   │
│  │  • Sends outbound messages via platform APIs                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Channel Message Queue                         │   │
│  │  • Celery tasks for async processing                            │   │
│  │  • Retry logic for failed deliveries                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                          Internal API
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        EchoForge Agent                                   │
│  • Receives normalized message                                          │
│  • Processes with AI                                                    │
│  • Returns response                                                     │
│  • Hub sends response via appropriate channel                           │
└─────────────────────────────────────────────────────────────────────────┘
```

## 2.3 Channel Abstraction

All channel integrations implement a common interface:

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional, List
from datetime import datetime

@dataclass
class ChannelMessage:
    """Normalized message format across all channels."""
    id: str                          # Platform-specific message ID
    channel_type: str                # "email", "slack", "telegram"
    direction: str                   # "inbound" or "outbound"

    # Sender/recipient
    sender_id: str                   # Platform user ID
    sender_name: Optional[str]
    sender_email: Optional[str]
    recipient_id: str                # Our channel identifier

    # Content
    subject: Optional[str]           # For email
    body_text: str                   # Plain text content
    body_html: Optional[str]         # HTML content (email)
    attachments: List[dict]          # [{name, url, mime_type, size}]

    # Threading
    thread_id: Optional[str]         # Conversation thread
    reply_to_id: Optional[str]       # Message being replied to

    # Metadata
    timestamp: datetime
    raw_payload: dict                # Original platform payload
    metadata: dict                   # Channel-specific data


class ChannelProvider(ABC):
    """Base class for all channel integrations."""

    @property
    @abstractmethod
    def channel_type(self) -> str:
        """Return channel type identifier (e.g., 'email', 'slack')."""
        pass

    @abstractmethod
    async def send_message(
        self,
        integration: 'Integration',
        message: ChannelMessage,
    ) -> str:
        """Send a message, return platform message ID."""
        pass

    @abstractmethod
    async def process_webhook(
        self,
        integration: 'Integration',
        payload: dict,
    ) -> Optional[ChannelMessage]:
        """Process incoming webhook, return normalized message."""
        pass

    @abstractmethod
    async def validate_credentials(
        self,
        integration: 'Integration',
    ) -> tuple[bool, Optional[str]]:
        """Validate integration credentials, return (valid, error_message)."""
        pass

    def normalize_message(self, raw: dict) -> ChannelMessage:
        """Convert platform-specific message to ChannelMessage."""
        raise NotImplementedError
```

---

# 3. Data Model Extensions

## 3.1 IntegrationProvider (Enhanced)

Extends the Hub spec model with channel-specific fields.

| Field | Type | Description |
|-------|------|-------------|
| slug | SlugField | Unique ID ("gmail", "slack", "telegram") |
| name | CharField(100) | Display name ("Gmail", "Slack") |
| category | CharField(50) | "email", "messaging", "chat" |
| integration_type | CharField(20) | "channel", "service", "notification" |
| auth_type | CharField(20) | "oauth2", "api_key", "credentials" |
| oauth_config | JSONField | OAuth URLs, scopes (if OAuth) |
| credentials_schema | JSONField | Required credential fields (if credentials auth) |
| webhook_supported | BooleanField | Supports inbound webhooks |
| polling_supported | BooleanField | Supports polling for messages |
| polling_interval_seconds | IntegerField | Default poll interval |
| logo_url | URLField | Provider logo |
| setup_instructions | TextField | User-facing setup guide |
| is_active | BooleanField | Available for use |

## 3.2 ChannelIntegration

Links an Integration to an AgentInstance as a communication channel.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| agent_instance | FK(AgentInstance) | Agent using this channel |
| integration | FK(Integration) | Connected account |
| channel_identifier | CharField(200) | Channel-specific ID (email address, channel ID) |
| channel_name | CharField(200) | Display name ("support@acme.com") |
| is_primary | BooleanField | Primary channel for this agent |
| is_active | BooleanField | Channel enabled |
| config | JSONField | Channel-specific settings |
| last_message_at | DateTimeField | Last message sent/received |
| created_at | DateTimeField | When connected |

## 3.3 Conversation

Tracks ongoing conversations across channels.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| agent_instance | FK(AgentInstance) | Handling agent |
| channel_integration | FK(ChannelIntegration) | Communication channel |
| external_thread_id | CharField(200) | Platform thread/conversation ID |
| contact_identifier | CharField(200) | End user identifier (email, user ID) |
| contact_name | CharField(200) | End user name |
| subject | CharField(500) | Conversation subject (email) |
| status | CharField(20) | "active", "resolved", "archived" |
| started_at | DateTimeField | First message |
| last_message_at | DateTimeField | Most recent message |
| message_count | IntegerField | Total messages |
| metadata | JSONField | Additional context |

## 3.4 Message

Individual messages within a conversation.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| conversation | FK(Conversation) | Parent conversation |
| direction | CharField(10) | "inbound" or "outbound" |
| external_id | CharField(200) | Platform message ID |
| sender_type | CharField(20) | "user", "agent", "system" |
| body_text | TextField | Plain text content |
| body_html | TextField | HTML content (optional) |
| attachments | JSONField | List of attachments |
| status | CharField(20) | "pending", "sent", "delivered", "failed" |
| failure_reason | TextField | Error details if failed |
| sent_at | DateTimeField | When sent |
| delivered_at | DateTimeField | Delivery confirmation |
| created_at | DateTimeField | Record creation |

## 3.5 WebhookEvent

Logs all incoming webhook events for debugging.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| provider | FK(IntegrationProvider) | Source provider |
| integration | FK(Integration) | Target integration (if identified) |
| event_type | CharField(100) | Platform event type |
| payload | JSONField | Raw webhook payload |
| processed | BooleanField | Successfully processed |
| error_message | TextField | Processing error (if any) |
| received_at | DateTimeField | When received |
| processed_at | DateTimeField | When processed |

---

# 4. Authentication Patterns

## 4.1 OAuth2 (Gmail, Outlook, Slack)

```python
class OAuth2Flow:
    """Standard OAuth2 flow for integrations."""

    def initiate(self, provider: IntegrationProvider, customer: Customer) -> str:
        """Generate OAuth authorization URL."""
        state = generate_secure_state(customer.id, provider.slug)

        params = {
            'client_id': settings.OAUTH_CLIENTS[provider.slug]['client_id'],
            'redirect_uri': f"{settings.HUB_URL}/integrations/oauth/callback",
            'response_type': 'code',
            'scope': ' '.join(provider.oauth_config['scopes']),
            'state': state,
            'access_type': 'offline',  # For refresh token
            'prompt': 'consent',
        }

        return f"{provider.oauth_config['auth_url']}?{urlencode(params)}"

    def complete(self, code: str, state: str) -> Integration:
        """Exchange code for tokens and create Integration."""
        customer_id, provider_slug = verify_state(state)
        provider = IntegrationProvider.objects.get(slug=provider_slug)

        # Exchange code for tokens
        response = requests.post(
            provider.oauth_config['token_url'],
            data={
                'client_id': settings.OAUTH_CLIENTS[provider_slug]['client_id'],
                'client_secret': settings.OAUTH_CLIENTS[provider_slug]['client_secret'],
                'code': code,
                'grant_type': 'authorization_code',
                'redirect_uri': f"{settings.HUB_URL}/integrations/oauth/callback",
            }
        )

        tokens = response.json()

        # Get account info
        account_info = self.fetch_account_info(provider, tokens['access_token'])

        # Create integration
        integration = Integration.objects.create(
            customer_id=customer_id,
            provider=provider,
            account_id=account_info['id'],
            account_name=account_info['name'],
            access_token=encrypt(tokens['access_token']),
            refresh_token=encrypt(tokens.get('refresh_token')),
            token_expires_at=timezone.now() + timedelta(seconds=tokens['expires_in']),
            scopes=provider.oauth_config['scopes'],
            status='active',
        )

        return integration
```

## 4.2 Bot Token (Telegram)

```python
class BotTokenAuth:
    """Authentication via bot token (Telegram)."""

    def connect(self, customer: Customer, bot_token: str) -> Integration:
        """Validate bot token and create Integration."""
        provider = IntegrationProvider.objects.get(slug='telegram')

        # Validate token with Telegram API
        response = requests.get(
            f"https://api.telegram.org/bot{bot_token}/getMe"
        )

        if not response.ok:
            raise ValueError("Invalid bot token")

        bot_info = response.json()['result']

        integration = Integration.objects.create(
            customer=customer,
            provider=provider,
            account_id=str(bot_info['id']),
            account_name=bot_info['username'],
            access_token=encrypt(bot_token),
            status='active',
            metadata={'bot_info': bot_info},
        )

        # Set up webhook
        self.configure_webhook(integration, bot_token)

        return integration

    def configure_webhook(self, integration: Integration, bot_token: str):
        """Configure Telegram webhook for this bot."""
        webhook_url = f"{settings.HUB_URL}/webhooks/telegram/{integration.id}"

        requests.post(
            f"https://api.telegram.org/bot{bot_token}/setWebhook",
            json={'url': webhook_url}
        )
```

## 4.3 IMAP/SMTP Credentials (Apple Mail)

```python
class IMAPCredentialsAuth:
    """Authentication via IMAP/SMTP credentials."""

    def connect(
        self,
        customer: Customer,
        email: str,
        imap_server: str,
        imap_port: int,
        smtp_server: str,
        smtp_port: int,
        username: str,
        password: str,
    ) -> Integration:
        """Validate credentials and create Integration."""
        provider = IntegrationProvider.objects.get(slug='imap_email')

        # Test IMAP connection
        import imaplib
        try:
            imap = imaplib.IMAP4_SSL(imap_server, imap_port)
            imap.login(username, password)
            imap.logout()
        except Exception as e:
            raise ValueError(f"IMAP connection failed: {e}")

        # Test SMTP connection
        import smtplib
        try:
            smtp = smtplib.SMTP_SSL(smtp_server, smtp_port)
            smtp.login(username, password)
            smtp.quit()
        except Exception as e:
            raise ValueError(f"SMTP connection failed: {e}")

        integration = Integration.objects.create(
            customer=customer,
            provider=provider,
            account_id=email,
            account_name=email,
            access_token=encrypt(password),  # Store password encrypted
            status='active',
            metadata={
                'email': email,
                'imap_server': imap_server,
                'imap_port': imap_port,
                'smtp_server': smtp_server,
                'smtp_port': smtp_port,
                'username': username,
            },
        )

        return integration
```

---

# 5. Webhook & Polling Infrastructure

## 5.1 Webhook Endpoints

```python
# urls.py
urlpatterns = [
    path('webhooks/gmail/', GmailWebhookView.as_view()),
    path('webhooks/outlook/', OutlookWebhookView.as_view()),
    path('webhooks/telegram/<uuid:integration_id>/', TelegramWebhookView.as_view()),
    path('webhooks/slack/', SlackWebhookView.as_view()),
]
```

## 5.2 Webhook Processing

```python
class BaseWebhookView(View):
    """Base webhook handler."""

    def post(self, request, **kwargs):
        provider = self.get_provider()

        # Log raw event
        event = WebhookEvent.objects.create(
            provider=provider,
            event_type=self.get_event_type(request),
            payload=json.loads(request.body),
            received_at=timezone.now(),
        )

        # Process async
        process_webhook_event.delay(event.id)

        return JsonResponse({'status': 'ok'})


@shared_task
def process_webhook_event(event_id: str):
    """Process webhook event asynchronously."""
    event = WebhookEvent.objects.get(id=event_id)

    try:
        # Get appropriate provider handler
        handler = get_channel_provider(event.provider.slug)

        # Identify integration from payload
        integration = handler.identify_integration(event.payload)
        event.integration = integration

        # Process and normalize message
        message = handler.process_webhook(integration, event.payload)

        if message and message.direction == 'inbound':
            # Route to agent
            route_inbound_message.delay(
                integration_id=str(integration.id),
                message=asdict(message),
            )

        event.processed = True
        event.processed_at = timezone.now()
        event.save()

    except Exception as e:
        event.error_message = str(e)
        event.save()
        raise
```

## 5.3 Email Polling (IMAP)

```python
@shared_task
def poll_imap_integrations():
    """Poll all IMAP integrations for new messages."""
    integrations = Integration.objects.filter(
        provider__slug='imap_email',
        status='active',
    )

    for integration in integrations:
        poll_imap_mailbox.delay(str(integration.id))


@shared_task
def poll_imap_mailbox(integration_id: str):
    """Poll a single IMAP mailbox for new messages."""
    integration = Integration.objects.get(id=integration_id)
    handler = IMAPEmailProvider()

    messages = handler.fetch_new_messages(integration)

    for message in messages:
        route_inbound_message.delay(
            integration_id=integration_id,
            message=asdict(message),
        )


# Celery beat schedule
CELERYBEAT_SCHEDULE = {
    'poll-imap-integrations': {
        'task': 'integrations.tasks.poll_imap_integrations',
        'schedule': 60.0,  # Every 60 seconds
    },
}
```

## 5.4 Message Routing

```python
@shared_task
def route_inbound_message(integration_id: str, message: dict):
    """Route inbound message to appropriate agent."""
    integration = Integration.objects.get(id=integration_id)
    message = ChannelMessage(**message)

    # Find channel integration (which agent handles this?)
    channel_integration = ChannelIntegration.objects.filter(
        integration=integration,
        is_active=True,
    ).first()

    if not channel_integration:
        logger.warning(f"No active channel for integration {integration_id}")
        return

    agent_instance = channel_integration.agent_instance

    # Find or create conversation
    conversation, created = Conversation.objects.get_or_create(
        agent_instance=agent_instance,
        channel_integration=channel_integration,
        external_thread_id=message.thread_id or message.id,
        defaults={
            'customer': integration.customer,
            'contact_identifier': message.sender_id,
            'contact_name': message.sender_name,
            'subject': message.subject,
            'status': 'active',
            'started_at': message.timestamp,
        }
    )

    # Create message record
    msg_record = Message.objects.create(
        conversation=conversation,
        direction='inbound',
        external_id=message.id,
        sender_type='user',
        body_text=message.body_text,
        body_html=message.body_html,
        attachments=message.attachments,
        status='delivered',
        sent_at=message.timestamp,
    )

    # Update conversation
    conversation.last_message_at = message.timestamp
    conversation.message_count = F('message_count') + 1
    conversation.save()

    # Send to Agent runtime for processing
    send_to_agent.delay(
        agent_instance_id=str(agent_instance.id),
        conversation_id=str(conversation.id),
        message_id=str(msg_record.id),
    )
```

---

# 6. Integration Design Sheet Template

Use this template when adding new integrations:

```markdown
# Integration: [Provider Name]

## Overview
- **Slug:** [lowercase_identifier]
- **Category:** [email/messaging/chat]
- **Auth Type:** [oauth2/api_key/credentials]
- **Webhook Support:** [Yes/No]
- **Polling Required:** [Yes/No]
- **Priority:** [P1/P2/P3]

## Authentication

### [OAuth2 / API Key / Credentials]
- [Auth-specific details]
- [Required scopes/permissions]
- [Token refresh notes]

## Capabilities
- [ ] Send message
- [ ] Receive message (webhook)
- [ ] Receive message (polling)
- [ ] Attachments
- [ ] Threading/replies
- [ ] Read receipts
- [ ] Typing indicators

## API Details

### Send Message
- **Endpoint:** [URL]
- **Method:** [POST/etc]
- **Rate Limit:** [X/min]

### Webhook Events
| Event | Description | Payload Key Fields |
|-------|-------------|-------------------|
| [event_name] | [description] | [fields] |

## Message Mapping

### Inbound (Platform → ChannelMessage)
| Platform Field | ChannelMessage Field | Transform |
|---------------|---------------------|-----------|
| [field] | [field] | [notes] |

### Outbound (ChannelMessage → Platform)
| ChannelMessage Field | Platform Field | Transform |
|---------------------|---------------|-----------|
| [field] | [field] | [notes] |

## Setup Instructions (User-Facing)
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Testing Notes
- Sandbox/test environment: [details]
- Test credentials: [how to obtain]

## Known Limitations
- [Limitation 1]
- [Limitation 2]
```

---

# 7. Initial Integrations

## 7.1 Gmail

### Overview
- **Slug:** gmail
- **Category:** email
- **Auth Type:** oauth2
- **Webhook Support:** Yes (Google Pub/Sub push)
- **Polling Required:** No (but fallback available)
- **Priority:** P1

### Authentication

**OAuth2 Configuration:**
```json
{
  "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
  "token_url": "https://oauth2.googleapis.com/token",
  "scopes": [
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.modify"
  ]
}
```

**Required Google Cloud Setup:**
- Enable Gmail API in Google Cloud Console
- Create OAuth2 credentials (Web application)
- Configure authorized redirect URIs
- Set up Pub/Sub topic for push notifications

### Capabilities
- [x] Send message
- [x] Receive message (webhook via Pub/Sub)
- [x] Receive message (polling fallback)
- [x] Attachments (up to 25MB)
- [x] Threading/replies
- [ ] Read receipts (not supported)
- [ ] Typing indicators (not applicable)

### API Details

**Send Message:**
```
POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send
Content-Type: application/json
Authorization: Bearer {access_token}

{
  "raw": "{base64_encoded_email}"
}
```

**Watch for Changes (Pub/Sub):**
```
POST https://gmail.googleapis.com/gmail/v1/users/me/watch
{
  "topicName": "projects/{project}/topics/{topic}",
  "labelIds": ["INBOX"]
}
```

**Rate Limits:**
- 250 quota units per user per second
- Sending: 100 emails/day (unverified), 2000/day (verified)

### Webhook Events

Push notifications via Google Pub/Sub:

| Event | Description | Action |
|-------|-------------|--------|
| historyId change | New message or change | Fetch history to get new messages |

**Webhook Payload:**
```json
{
  "message": {
    "data": "eyJlbWFpbEFkZHJlc3MiOiJ1c2VyQGV4YW1wbGUuY29tIiwiaGlzdG9yeUlkIjoiMTIzNDU2In0=",
    "messageId": "...",
    "publishTime": "..."
  }
}
```

**Decoded data:**
```json
{
  "emailAddress": "user@example.com",
  "historyId": "123456"
}
```

### Message Mapping

**Inbound:**
| Gmail Field | ChannelMessage Field | Transform |
|------------|---------------------|-----------|
| id | id | Direct |
| threadId | thread_id | Direct |
| payload.headers[From] | sender_email, sender_name | Parse "Name <email>" |
| payload.headers[To] | recipient_id | Email address |
| payload.headers[Subject] | subject | Direct |
| snippet / payload.body | body_text | Decode base64, strip HTML |
| payload.body (text/html) | body_html | Decode base64 |
| payload.parts[attachments] | attachments | Extract metadata |
| internalDate | timestamp | Unix ms → datetime |

**Outbound:**
| ChannelMessage Field | Gmail Field | Transform |
|---------------------|------------|-----------|
| recipient_id | To header | Direct |
| subject | Subject header | Direct |
| body_text | Body (text/plain) | Direct |
| body_html | Body (text/html) | Direct |
| thread_id | threadId | For replies |
| reply_to_id | In-Reply-To header | Message-ID format |
| attachments | MIME parts | Base64 encode |

### Implementation

```python
class GmailProvider(ChannelProvider):
    channel_type = 'email'

    async def send_message(self, integration: Integration, message: ChannelMessage) -> str:
        credentials = self.get_credentials(integration)

        # Build MIME message
        mime_msg = MIMEMultipart('alternative')
        mime_msg['To'] = message.recipient_id
        mime_msg['Subject'] = message.subject or ''

        if message.reply_to_id:
            mime_msg['In-Reply-To'] = message.reply_to_id
            mime_msg['References'] = message.reply_to_id

        # Add body
        if message.body_text:
            mime_msg.attach(MIMEText(message.body_text, 'plain'))
        if message.body_html:
            mime_msg.attach(MIMEText(message.body_html, 'html'))

        # Add attachments
        for attachment in message.attachments:
            # ... attachment handling
            pass

        # Encode and send
        raw = base64.urlsafe_b64encode(mime_msg.as_bytes()).decode()

        async with aiohttp.ClientSession() as session:
            body = {'raw': raw}
            if message.thread_id:
                body['threadId'] = message.thread_id

            async with session.post(
                'https://gmail.googleapis.com/gmail/v1/users/me/messages/send',
                headers={'Authorization': f'Bearer {credentials.access_token}'},
                json=body,
            ) as resp:
                result = await resp.json()
                return result['id']

    async def process_webhook(self, integration: Integration, payload: dict) -> Optional[ChannelMessage]:
        # Decode Pub/Sub message
        data = json.loads(base64.b64decode(payload['message']['data']))
        history_id = data['historyId']

        # Fetch new messages since last history ID
        messages = await self.fetch_history(integration, history_id)

        # Return first new inbound message (others queued separately)
        for msg in messages:
            if self.is_inbound(msg, integration):
                return self.normalize_message(msg)

        return None
```

### Setup Instructions (User-Facing)

1. Click "Connect Gmail"
2. Sign in with your Google account
3. Review and approve the requested permissions:
   - Read your emails
   - Send emails on your behalf
   - Modify email labels
4. Select which email address to use with your agent
5. Done! Your agent can now send and receive emails

### Known Limitations

- Gmail API quota limits (250 units/user/second)
- Sending limits for unverified apps (100/day)
- Push notifications require Google Cloud Pub/Sub setup
- Watch expires after 7 days (must renew)
- 25MB attachment limit

---

## 7.2 Outlook (Microsoft 365)

### Overview
- **Slug:** outlook
- **Category:** email
- **Auth Type:** oauth2
- **Webhook Support:** Yes (Microsoft Graph subscriptions)
- **Polling Required:** No (webhook preferred)
- **Priority:** P1

### Authentication

**OAuth2 Configuration:**
```json
{
  "auth_url": "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
  "token_url": "https://login.microsoftonline.com/common/oauth2/v2.0/token",
  "scopes": [
    "https://graph.microsoft.com/Mail.ReadWrite",
    "https://graph.microsoft.com/Mail.Send",
    "offline_access"
  ]
}
```

**Required Azure Setup:**
- Register application in Azure AD
- Add Microsoft Graph API permissions
- Configure redirect URIs
- Create client secret

### Capabilities
- [x] Send message
- [x] Receive message (webhook)
- [x] Receive message (polling fallback)
- [x] Attachments (up to 150MB with upload sessions)
- [x] Threading/replies
- [ ] Read receipts (via message flags)
- [ ] Typing indicators (not applicable)

### API Details

**Send Message:**
```
POST https://graph.microsoft.com/v1.0/me/sendMail
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "message": {
    "subject": "Subject",
    "body": {
      "contentType": "HTML",
      "content": "<p>Body</p>"
    },
    "toRecipients": [
      {"emailAddress": {"address": "recipient@example.com"}}
    ]
  }
}
```

**Create Subscription (Webhook):**
```
POST https://graph.microsoft.com/v1.0/subscriptions
{
  "changeType": "created",
  "notificationUrl": "https://hub.echoforge.ai/webhooks/outlook",
  "resource": "me/mailFolders/inbox/messages",
  "expirationDateTime": "2025-01-01T00:00:00Z",
  "clientState": "{secret}"
}
```

**Rate Limits:**
- 10,000 requests per 10 minutes per app
- 4 concurrent requests per mailbox

### Webhook Events

| Event | changeType | Resource |
|-------|------------|----------|
| New message | created | me/mailFolders/inbox/messages |
| Message updated | updated | me/messages/{id} |

**Webhook Payload:**
```json
{
  "value": [
    {
      "changeType": "created",
      "clientState": "{secret}",
      "resource": "me/messages/{message_id}",
      "resourceData": {
        "id": "{message_id}"
      }
    }
  ]
}
```

### Message Mapping

**Inbound:**
| Graph Field | ChannelMessage Field | Transform |
|-------------|---------------------|-----------|
| id | id | Direct |
| conversationId | thread_id | Direct |
| from.emailAddress | sender_email, sender_name | Extract |
| toRecipients[0] | recipient_id | Email address |
| subject | subject | Direct |
| body.content | body_text/body_html | Based on contentType |
| attachments | attachments | Fetch separately |
| receivedDateTime | timestamp | ISO → datetime |

**Outbound:**
| ChannelMessage Field | Graph Field | Transform |
|---------------------|-------------|-----------|
| recipient_id | toRecipients[].emailAddress.address | Direct |
| subject | subject | Direct |
| body_text | body.content (Text) | contentType: "Text" |
| body_html | body.content (HTML) | contentType: "HTML" |
| thread_id | conversationId | For replies |
| attachments | attachments | Upload first if >3MB |

### Implementation

```python
class OutlookProvider(ChannelProvider):
    channel_type = 'email'

    async def send_message(self, integration: Integration, message: ChannelMessage) -> str:
        credentials = self.get_credentials(integration)

        mail_body = {
            'message': {
                'subject': message.subject or '',
                'body': {
                    'contentType': 'HTML' if message.body_html else 'Text',
                    'content': message.body_html or message.body_text,
                },
                'toRecipients': [
                    {'emailAddress': {'address': message.recipient_id}}
                ],
            }
        }

        # Handle reply
        if message.reply_to_id:
            # Reply to existing message
            url = f'https://graph.microsoft.com/v1.0/me/messages/{message.reply_to_id}/reply'
            mail_body = {'comment': message.body_html or message.body_text}
        else:
            url = 'https://graph.microsoft.com/v1.0/me/sendMail'

        async with aiohttp.ClientSession() as session:
            async with session.post(
                url,
                headers={'Authorization': f'Bearer {credentials.access_token}'},
                json=mail_body,
            ) as resp:
                if message.reply_to_id:
                    return message.reply_to_id  # Reply doesn't return new ID
                result = await resp.json()
                return result.get('id', '')

    async def process_webhook(self, integration: Integration, payload: dict) -> Optional[ChannelMessage]:
        for notification in payload.get('value', []):
            if notification['changeType'] == 'created':
                message_id = notification['resourceData']['id']
                message = await self.fetch_message(integration, message_id)
                return self.normalize_message(message)
        return None
```

### Setup Instructions (User-Facing)

1. Click "Connect Outlook"
2. Sign in with your Microsoft account (personal or work/school)
3. Review and approve permissions:
   - Read and write your mail
   - Send mail as you
4. Select which mailbox to connect
5. Done! Your agent can now send and receive Outlook emails

### Known Limitations

- Subscriptions expire (max 3 days for mail), must renew
- Webhook validation required (respond to validation request)
- Large attachments require upload sessions
- Personal vs Work accounts have different limits

---

## 7.3 Apple Mail (IMAP/SMTP)

### Overview
- **Slug:** imap_email
- **Display Name:** Email (IMAP/SMTP)
- **Category:** email
- **Auth Type:** credentials
- **Webhook Support:** No
- **Polling Required:** Yes
- **Priority:** P1

*Note: Apple Mail is an email client, not a service. This integration uses standard IMAP/SMTP protocols, supporting iCloud Mail, Apple Mail users, and any IMAP-compatible email provider.*

### Authentication

**Credentials Schema:**
```json
{
  "fields": [
    {"name": "email", "type": "email", "label": "Email Address", "required": true},
    {"name": "imap_server", "type": "text", "label": "IMAP Server", "required": true, "placeholder": "imap.mail.me.com"},
    {"name": "imap_port", "type": "number", "label": "IMAP Port", "default": 993, "required": true},
    {"name": "smtp_server", "type": "text", "label": "SMTP Server", "required": true, "placeholder": "smtp.mail.me.com"},
    {"name": "smtp_port", "type": "number", "label": "SMTP Port", "default": 587, "required": true},
    {"name": "username", "type": "text", "label": "Username", "required": true},
    {"name": "password", "type": "password", "label": "Password/App Password", "required": true}
  ],
  "presets": {
    "icloud": {
      "imap_server": "imap.mail.me.com",
      "imap_port": 993,
      "smtp_server": "smtp.mail.me.com",
      "smtp_port": 587
    },
    "gmail": {
      "imap_server": "imap.gmail.com",
      "imap_port": 993,
      "smtp_server": "smtp.gmail.com",
      "smtp_port": 587
    },
    "outlook": {
      "imap_server": "outlook.office365.com",
      "imap_port": 993,
      "smtp_server": "smtp.office365.com",
      "smtp_port": 587
    }
  }
}
```

**iCloud-Specific Requirements:**
- Must use app-specific password (not regular password)
- Two-factor authentication must be enabled on Apple ID
- Generate app password at appleid.apple.com

### Capabilities
- [x] Send message
- [ ] Receive message (webhook) — not supported
- [x] Receive message (polling)
- [x] Attachments
- [x] Threading/replies (via In-Reply-To header)
- [ ] Read receipts (protocol doesn't support)
- [ ] Typing indicators (not applicable)

### Polling Implementation

```python
class IMAPEmailProvider(ChannelProvider):
    channel_type = 'email'

    def fetch_new_messages(self, integration: Integration) -> List[ChannelMessage]:
        """Poll IMAP for new messages since last check."""
        config = integration.metadata
        password = decrypt(integration.access_token)

        messages = []

        with imaplib.IMAP4_SSL(config['imap_server'], config['imap_port']) as imap:
            imap.login(config['username'], password)
            imap.select('INBOX')

            # Search for unseen messages
            _, message_ids = imap.search(None, 'UNSEEN')

            for msg_id in message_ids[0].split():
                _, msg_data = imap.fetch(msg_id, '(RFC822)')
                email_msg = email.message_from_bytes(msg_data[0][1])

                messages.append(self.parse_email(email_msg, msg_id.decode()))

                # Mark as seen
                imap.store(msg_id, '+FLAGS', '\\Seen')

        return messages

    def parse_email(self, email_msg: email.message.Message, msg_id: str) -> ChannelMessage:
        """Parse email message to ChannelMessage."""
        # Extract sender
        from_header = email_msg['From']
        sender_name, sender_email = email.utils.parseaddr(from_header)

        # Extract body
        body_text = ''
        body_html = ''
        attachments = []

        if email_msg.is_multipart():
            for part in email_msg.walk():
                content_type = part.get_content_type()
                disposition = str(part.get('Content-Disposition', ''))

                if 'attachment' in disposition:
                    attachments.append({
                        'name': part.get_filename(),
                        'mime_type': content_type,
                        'size': len(part.get_payload(decode=True)),
                        'data': base64.b64encode(part.get_payload(decode=True)).decode(),
                    })
                elif content_type == 'text/plain':
                    body_text = part.get_payload(decode=True).decode()
                elif content_type == 'text/html':
                    body_html = part.get_payload(decode=True).decode()
        else:
            body_text = email_msg.get_payload(decode=True).decode()

        return ChannelMessage(
            id=msg_id,
            channel_type='email',
            direction='inbound',
            sender_id=sender_email,
            sender_name=sender_name,
            sender_email=sender_email,
            recipient_id=email_msg['To'],
            subject=email_msg['Subject'],
            body_text=body_text,
            body_html=body_html,
            attachments=attachments,
            thread_id=email_msg.get('References', '').split()[0] if email_msg.get('References') else None,
            reply_to_id=email_msg.get('In-Reply-To'),
            timestamp=email.utils.parsedate_to_datetime(email_msg['Date']),
            raw_payload={},
            metadata={},
        )

    async def send_message(self, integration: Integration, message: ChannelMessage) -> str:
        """Send email via SMTP."""
        config = integration.metadata
        password = decrypt(integration.access_token)

        # Build MIME message
        mime_msg = MIMEMultipart('alternative')
        mime_msg['From'] = config['email']
        mime_msg['To'] = message.recipient_id
        mime_msg['Subject'] = message.subject or ''
        mime_msg['Date'] = email.utils.formatdate(localtime=True)
        mime_msg['Message-ID'] = email.utils.make_msgid()

        if message.reply_to_id:
            mime_msg['In-Reply-To'] = message.reply_to_id
            mime_msg['References'] = message.reply_to_id

        if message.body_text:
            mime_msg.attach(MIMEText(message.body_text, 'plain'))
        if message.body_html:
            mime_msg.attach(MIMEText(message.body_html, 'html'))

        # Send via SMTP
        with smtplib.SMTP(config['smtp_server'], config['smtp_port']) as smtp:
            smtp.starttls()
            smtp.login(config['username'], password)
            smtp.send_message(mime_msg)

        return mime_msg['Message-ID']
```

### Setup Instructions (User-Facing)

**For iCloud Mail:**
1. Go to appleid.apple.com and sign in
2. Under "Sign-In and Security", select "App-Specific Passwords"
3. Generate a new password for "EchoForge"
4. Return to EchoForge and enter:
   - Email: your iCloud email address
   - Select preset: "iCloud"
   - Username: your full iCloud email
   - Password: the app-specific password you generated
5. Click "Test Connection" to verify
6. Done!

**For Other Providers:**
1. Enter your email address
2. Enter IMAP and SMTP server details (or select a preset)
3. Enter your username and password
   - Note: Many providers require app-specific passwords
4. Click "Test Connection" to verify
5. Done!

### Known Limitations

- No real-time notifications (polling only)
- Default polling interval: 60 seconds (configurable)
- iCloud requires app-specific passwords
- Some email providers may block IMAP access
- Connection must be re-established for each poll

---

## 7.4 Telegram

### Overview
- **Slug:** telegram
- **Category:** messaging
- **Auth Type:** api_key (bot token)
- **Webhook Support:** Yes
- **Polling Required:** No
- **Priority:** P1

### Authentication

**Bot Token Setup:**
1. Message @BotFather on Telegram
2. Send `/newbot` and follow prompts
3. Receive bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

**Credentials Schema:**
```json
{
  "fields": [
    {"name": "bot_token", "type": "password", "label": "Bot Token", "required": true, "help": "Get this from @BotFather on Telegram"}
  ]
}
```

### Capabilities
- [x] Send message
- [x] Receive message (webhook)
- [ ] Receive message (polling available but not used)
- [x] Attachments (photos, documents, etc.)
- [x] Threading/replies
- [ ] Read receipts (not available)
- [x] Typing indicators (can send)

### API Details

**Send Message:**
```
POST https://api.telegram.org/bot{token}/sendMessage
{
  "chat_id": 123456789,
  "text": "Hello!",
  "parse_mode": "HTML",
  "reply_to_message_id": 42  // optional, for replies
}
```

**Send Photo:**
```
POST https://api.telegram.org/bot{token}/sendPhoto
{
  "chat_id": 123456789,
  "photo": "https://example.com/image.jpg",
  "caption": "Check this out!"
}
```

**Set Webhook:**
```
POST https://api.telegram.org/bot{token}/setWebhook
{
  "url": "https://hub.echoforge.ai/webhooks/telegram/{integration_id}",
  "allowed_updates": ["message", "edited_message", "callback_query"]
}
```

**Rate Limits:**
- 30 messages/second to same chat
- 20 messages/minute to same group
- Bulk: 30 messages/second overall

### Webhook Events

| Update Type | Description |
|-------------|-------------|
| message | New incoming message |
| edited_message | Message was edited |
| callback_query | Inline button pressed |

**Webhook Payload (message):**
```json
{
  "update_id": 123456789,
  "message": {
    "message_id": 42,
    "from": {
      "id": 123456789,
      "first_name": "John",
      "last_name": "Doe",
      "username": "johndoe"
    },
    "chat": {
      "id": 123456789,
      "type": "private"
    },
    "date": 1234567890,
    "text": "Hello bot!"
  }
}
```

### Message Mapping

**Inbound:**
| Telegram Field | ChannelMessage Field | Transform |
|---------------|---------------------|-----------|
| message.message_id | id | String |
| message.chat.id | thread_id | String (use chat as thread) |
| message.from.id | sender_id | String |
| message.from.first_name + last_name | sender_name | Concatenate |
| message.chat.id | recipient_id | String |
| message.text | body_text | Direct |
| message.photo/document/etc | attachments | Extract file_id, fetch URL |
| message.date | timestamp | Unix → datetime |
| message.reply_to_message.message_id | reply_to_id | String |

**Outbound:**
| ChannelMessage Field | Telegram Field | Transform |
|---------------------|---------------|-----------|
| thread_id | chat_id | Integer |
| body_text | text | Direct |
| body_html | text + parse_mode=HTML | Strip unsupported tags |
| reply_to_id | reply_to_message_id | Integer |
| attachments | Separate API calls | sendPhoto, sendDocument, etc. |

### Implementation

```python
class TelegramProvider(ChannelProvider):
    channel_type = 'messaging'

    def __init__(self):
        self.base_url = "https://api.telegram.org/bot"

    async def send_message(self, integration: Integration, message: ChannelMessage) -> str:
        token = decrypt(integration.access_token)
        chat_id = int(message.thread_id or message.recipient_id)

        # Send typing indicator
        await self._send_typing(token, chat_id)

        # Handle attachments first
        for attachment in message.attachments:
            await self._send_attachment(token, chat_id, attachment)

        # Send text message
        payload = {
            'chat_id': chat_id,
            'text': message.body_text,
            'parse_mode': 'HTML',
        }

        if message.reply_to_id:
            payload['reply_to_message_id'] = int(message.reply_to_id)

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.base_url}{token}/sendMessage",
                json=payload,
            ) as resp:
                result = await resp.json()
                return str(result['result']['message_id'])

    async def _send_typing(self, token: str, chat_id: int):
        async with aiohttp.ClientSession() as session:
            await session.post(
                f"{self.base_url}{token}/sendChatAction",
                json={'chat_id': chat_id, 'action': 'typing'},
            )

    async def process_webhook(self, integration: Integration, payload: dict) -> Optional[ChannelMessage]:
        message = payload.get('message') or payload.get('edited_message')
        if not message:
            return None

        # Skip if from bot itself
        if message.get('from', {}).get('is_bot'):
            return None

        sender = message['from']

        return ChannelMessage(
            id=str(message['message_id']),
            channel_type='messaging',
            direction='inbound',
            sender_id=str(sender['id']),
            sender_name=f"{sender.get('first_name', '')} {sender.get('last_name', '')}".strip(),
            sender_email=None,
            recipient_id=str(message['chat']['id']),
            subject=None,
            body_text=message.get('text', ''),
            body_html=None,
            attachments=self._extract_attachments(message),
            thread_id=str(message['chat']['id']),
            reply_to_id=str(message['reply_to_message']['message_id']) if message.get('reply_to_message') else None,
            timestamp=datetime.fromtimestamp(message['date'], tz=timezone.utc),
            raw_payload=payload,
            metadata={'chat_type': message['chat']['type']},
        )

    def _extract_attachments(self, message: dict) -> List[dict]:
        attachments = []

        if 'photo' in message:
            # Get largest photo
            photo = max(message['photo'], key=lambda p: p['file_size'])
            attachments.append({
                'type': 'photo',
                'file_id': photo['file_id'],
                'mime_type': 'image/jpeg',
                'size': photo.get('file_size'),
            })

        if 'document' in message:
            doc = message['document']
            attachments.append({
                'type': 'document',
                'file_id': doc['file_id'],
                'name': doc.get('file_name'),
                'mime_type': doc.get('mime_type'),
                'size': doc.get('file_size'),
            })

        # Similar for voice, video, audio, etc.

        return attachments
```

### Setup Instructions (User-Facing)

1. Open Telegram and search for @BotFather
2. Send `/newbot` command
3. Follow the prompts:
   - Enter a name for your bot (e.g., "Acme Support")
   - Enter a username ending in "bot" (e.g., "AcmeSupportBot")
4. BotFather will give you a bot token — copy it
5. Paste the token in EchoForge
6. Click "Connect"
7. Your bot is ready! Share the link (t.me/YourBotUsername) with users

**Optional Bot Customization:**
- `/setdescription` — Set bot description
- `/setabouttext` — Set "About" text
- `/setuserpic` — Set bot profile picture

### Known Limitations

- Bots can't initiate conversations (user must message first)
- File downloads require separate API call
- Max message length: 4096 characters
- Webhook URL must be HTTPS
- Can't access message history before bot was added

---

## 7.5 Slack

### Overview
- **Slug:** slack
- **Category:** chat
- **Auth Type:** oauth2
- **Webhook Support:** Yes (Events API)
- **Polling Required:** No
- **Priority:** P1

### Authentication

**OAuth2 Configuration:**
```json
{
  "auth_url": "https://slack.com/oauth/v2/authorize",
  "token_url": "https://slack.com/api/oauth.v2.access",
  "scopes": {
    "bot": [
      "chat:write",
      "channels:history",
      "channels:read",
      "groups:history",
      "groups:read",
      "im:history",
      "im:read",
      "im:write",
      "users:read"
    ]
  }
}
```

**Required Slack App Setup:**
- Create app at api.slack.com/apps
- Add Bot Token Scopes
- Install to workspace
- Configure Event Subscriptions
- Set Request URL for events

### Capabilities
- [x] Send message
- [x] Receive message (Events API webhook)
- [ ] Receive message (polling available via conversations.history)
- [x] Attachments (files)
- [x] Threading/replies
- [ ] Read receipts (not available)
- [x] Typing indicators (not typically used for bots)

### API Details

**Send Message:**
```
POST https://slack.com/api/chat.postMessage
Authorization: Bearer {bot_token}
Content-Type: application/json

{
  "channel": "C1234567890",
  "text": "Hello!",
  "thread_ts": "1234567890.123456"  // for threaded reply
}
```

**Send with Blocks (Rich Formatting):**
```json
{
  "channel": "C1234567890",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Hello!* How can I help you today?"
      }
    }
  ]
}
```

**Upload File:**
```
POST https://slack.com/api/files.upload
Content-Type: multipart/form-data

channels=C1234567890
file=@document.pdf
title=Document
```

**Rate Limits:**
- Tier 1: 1 request/second
- Tier 2: 20 requests/minute
- Tier 3: 50 requests/minute
- Most message methods are Tier 3

### Event Subscriptions

Subscribe to these events:

| Event | Description |
|-------|-------------|
| message.channels | Message in public channel |
| message.groups | Message in private channel |
| message.im | Direct message |
| message.mpim | Group DM |
| app_mention | Bot was @mentioned |

**Event Payload:**
```json
{
  "type": "event_callback",
  "event": {
    "type": "message",
    "channel": "C1234567890",
    "user": "U1234567890",
    "text": "Hello bot!",
    "ts": "1234567890.123456",
    "thread_ts": "1234567890.000000"
  }
}
```

### Message Mapping

**Inbound:**
| Slack Field | ChannelMessage Field | Transform |
|-------------|---------------------|-----------|
| event.ts | id | Direct |
| event.thread_ts or event.channel | thread_id | Use thread_ts if threaded |
| event.user | sender_id | Direct |
| (fetch from users.info) | sender_name | API call |
| event.channel | recipient_id | Direct |
| event.text | body_text | Direct |
| event.blocks | body_html | Convert blocks to HTML |
| event.files | attachments | Extract metadata |
| event.ts | timestamp | Unix ts → datetime |

**Outbound:**
| ChannelMessage Field | Slack Field | Transform |
|---------------------|-------------|-----------|
| recipient_id | channel | Direct |
| body_text | text | Direct |
| body_html | blocks | Convert to Block Kit |
| thread_id | thread_ts | For threaded replies |
| attachments | files.upload | Separate API call |

### Implementation

```python
class SlackProvider(ChannelProvider):
    channel_type = 'chat'

    async def send_message(self, integration: Integration, message: ChannelMessage) -> str:
        token = decrypt(integration.access_token)

        payload = {
            'channel': message.recipient_id,
            'text': message.body_text,
        }

        # Add threading
        if message.thread_id and message.thread_id != message.recipient_id:
            payload['thread_ts'] = message.thread_id

        # Convert HTML to blocks if present
        if message.body_html:
            payload['blocks'] = self._html_to_blocks(message.body_html)

        async with aiohttp.ClientSession() as session:
            async with session.post(
                'https://slack.com/api/chat.postMessage',
                headers={'Authorization': f'Bearer {token}'},
                json=payload,
            ) as resp:
                result = await resp.json()

                if not result['ok']:
                    raise Exception(f"Slack error: {result['error']}")

                return result['ts']

    async def process_webhook(self, integration: Integration, payload: dict) -> Optional[ChannelMessage]:
        # Handle URL verification challenge
        if payload.get('type') == 'url_verification':
            return None  # Handled separately

        event = payload.get('event', {})

        # Skip bot messages
        if event.get('bot_id'):
            return None

        # Skip message subtypes (joins, leaves, etc.)
        if event.get('subtype'):
            return None

        # Get user info for name
        sender_name = await self._get_user_name(integration, event['user'])

        return ChannelMessage(
            id=event['ts'],
            channel_type='chat',
            direction='inbound',
            sender_id=event['user'],
            sender_name=sender_name,
            sender_email=None,
            recipient_id=event['channel'],
            subject=None,
            body_text=event.get('text', ''),
            body_html=None,
            attachments=self._extract_attachments(event),
            thread_id=event.get('thread_ts', event['channel']),
            reply_to_id=None,
            timestamp=datetime.fromtimestamp(float(event['ts']), tz=timezone.utc),
            raw_payload=payload,
            metadata={
                'channel_type': event.get('channel_type'),
                'team': payload.get('team_id'),
            },
        )

    async def _get_user_name(self, integration: Integration, user_id: str) -> str:
        """Fetch user display name from Slack."""
        token = decrypt(integration.access_token)

        async with aiohttp.ClientSession() as session:
            async with session.get(
                'https://slack.com/api/users.info',
                headers={'Authorization': f'Bearer {token}'},
                params={'user': user_id},
            ) as resp:
                result = await resp.json()
                if result['ok']:
                    user = result['user']
                    return user.get('real_name') or user.get('name', user_id)
                return user_id

    def _extract_attachments(self, event: dict) -> List[dict]:
        attachments = []
        for file in event.get('files', []):
            attachments.append({
                'file_id': file['id'],
                'name': file.get('name'),
                'mime_type': file.get('mimetype'),
                'size': file.get('size'),
                'url': file.get('url_private'),
            })
        return attachments

    def _html_to_blocks(self, html: str) -> List[dict]:
        """Convert simple HTML to Slack Block Kit."""
        # Basic conversion - could be enhanced
        text = html_to_mrkdwn(html)
        return [
            {
                'type': 'section',
                'text': {'type': 'mrkdwn', 'text': text}
            }
        ]
```

### Setup Instructions (User-Facing)

1. Click "Connect Slack"
2. Select the Slack workspace to connect
3. Review permissions and click "Allow"
4. Choose how the agent should interact:
   - **Channel:** Select a channel for the agent to monitor
   - **Direct Messages:** Enable DMs with the bot
   - **Mentions:** Respond when @mentioned
5. Done! Your agent is now active in Slack

**Adding to a Channel:**
After connecting, invite the bot to channels:
```
/invite @YourBotName
```

### Known Limitations

- Bot must be invited to channels to see messages
- Can't access messages from before bot was added
- File access requires additional scopes
- Rate limits vary by API tier
- Events API requires public URL (can use ngrok for dev)
- URL verification required on setup

---

# 8. Implementation Approach

## 8.1 Recommended Phases

**Phase 1: Framework Foundation (1 week)**
1. ChannelMessage data class
2. ChannelProvider base class
3. IntegrationProvider model enhancements
4. ChannelIntegration model
5. Conversation and Message models
6. WebhookEvent logging

**Phase 2: Email - Gmail (1 week)**
1. Gmail OAuth flow
2. Gmail provider implementation
3. Google Pub/Sub webhook setup
4. Send/receive testing

**Phase 3: Email - Outlook (1 week)**
1. Microsoft OAuth flow
2. Outlook provider implementation
3. Graph API subscription setup
4. Send/receive testing

**Phase 4: Email - IMAP/SMTP (1 week)**
1. Credentials auth flow
2. IMAP polling implementation
3. SMTP send implementation
4. iCloud preset and testing

**Phase 5: Messaging - Telegram (1 week)**
1. Bot token auth
2. Telegram provider implementation
3. Webhook configuration
4. Send/receive testing

**Phase 6: Chat - Slack (1 week)**
1. Slack OAuth flow
2. Slack provider implementation
3. Events API webhook
4. Send/receive testing

**Phase 7: Agent Integration (1 week)**
1. Message routing to Agent runtime
2. Response handling
3. Conversation context
4. End-to-end testing

## 8.2 Dependencies

| Dependency | Notes |
|------------|-------|
| Hub Foundation | Customer, AgentInstance models |
| Google Cloud | Pub/Sub for Gmail push |
| Azure AD | App registration for Outlook |
| Celery | Async task processing |
| Redis | Message queue, polling coordination |

---

# 9. Acceptance Criteria

## 9.1 Framework

- [ ] ChannelMessage normalizes all platforms
- [ ] Providers implement common interface
- [ ] Webhook events logged for debugging
- [ ] Message routing to correct agent

## 9.2 Gmail

- [ ] OAuth connection works
- [ ] Pub/Sub webhook receives notifications
- [ ] Inbound emails create conversations
- [ ] Outbound emails sent successfully
- [ ] Threading preserved in replies
- [ ] Attachments handled

## 9.3 Outlook

- [ ] OAuth connection works
- [ ] Graph subscriptions created
- [ ] Webhook receives notifications
- [ ] Inbound/outbound emails work
- [ ] Threading preserved

## 9.4 IMAP/SMTP (Apple Mail)

- [ ] Credential validation works
- [ ] Polling fetches new messages
- [ ] SMTP sends successfully
- [ ] iCloud preset works with app password
- [ ] Threading via headers works

## 9.5 Telegram

- [ ] Bot token validation works
- [ ] Webhook configured automatically
- [ ] Messages received and processed
- [ ] Replies sent with typing indicator
- [ ] Attachments handled

## 9.6 Slack

- [ ] OAuth connection works
- [ ] Events API webhook configured
- [ ] Messages in channels received
- [ ] DMs received
- [ ] Threaded replies work
- [ ] Bot can be invited to channels

---

*End of Specification*
