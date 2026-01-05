---
title: EchoForge Hub
version: "1.1"
status: in-development
project: EchoForge Hub
created: 2025-12-29
updated: 2025-12-30
---

# 1. Executive Summary

EchoForge Hub is a Django-based customer portal for managing AI agents. It provides customer account management, an agent type registry, dynamic onboarding wizards, knowledge base management, integration credential storage, and billing. Hub serves as the configuration and management layer for EchoForge Agent (the runtime engine).

---

# 2. System Architecture

## 2.1 Relationship to EchoForge Agent

```
┌─────────────────────────────────────────────────────────────────┐
│                      EchoForge Hub (Django)                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────────┐ │
│  │ Customer │  │  Agent   │  │Onboarding│  │   Knowledge     │ │
│  │ Accounts │  │ Registry │  │  Engine  │  │     Bases       │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │Integra-  │  │ Billing  │  │  Admin   │                      │
│  │  tions   │  │          │  │Dashboard │                      │
│  └──────────┘  └──────────┘  └──────────┘                      │
│                           │                                     │
│               Internal Config API                               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                 EchoForge Agent (FastAPI)                       │
│  Stateless runtime - fetches config from Hub per request        │
└─────────────────────────────────────────────────────────────────┘
```

## 2.2 Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Django 5.2 |
| Database | PostgreSQL 15+ |
| Cache | Redis 7+ |
| Task Queue | Celery |
| API | Django REST Framework |
| Auth | Django built-in + API keys |
| Payments | Stripe |
| File Storage | S3-compatible (knowledge base docs) |

---

# 3. Data Model

## 3.1 Customer Management

### Customer

Represents a business or individual using EchoForge agents.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| name | CharField(200) | Company/customer name |
| email | EmailField | Primary contact email |
| phone | CharField(20) | Contact phone (optional) |
| industry | CharField(100) | Industry category (optional) |
| website | URLField | Company website (optional) |
| logo | ImageField | Company logo (optional) |
| created_at | DateTimeField | Account creation date |
| is_active | BooleanField | Account status |

### CustomerUser

Users who can access a customer's Hub account.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Parent customer |
| user | OneToOne(User) | Django auth user |
| role | CharField(20) | "owner", "admin", "member" |
| invited_by | FK(CustomerUser) | Who invited this user |
| joined_at | DateTimeField | When user joined |
| is_active | BooleanField | User status |

### CustomerInvite

Pending invitations to join a customer account.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Target customer |
| email | EmailField | Invitee email |
| role | CharField(20) | Role to assign |
| token | CharField(64) | Unique invite token |
| invited_by | FK(CustomerUser) | Who sent invite |
| expires_at | DateTimeField | Expiration (7 days) |
| accepted_at | DateTimeField | When accepted (null if pending) |

---

## 3.2 Agent Registry

### AgentType

Defines a category of agent (created by EchoForgeX admins).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| slug | SlugField | Unique identifier ("support_agent") |
| name | CharField(100) | Display name ("Support Agent") |
| description | TextField | Marketing description |
| icon | CharField(50) | Icon identifier |
| category | CharField(50) | "support", "sales", "intake", etc. |
| system_prompt_template | TextField | Default prompt with {{variables}} |
| available_actions | JSONField | List of action slugs this type can use |
| onboarding_schema | JSONField | Dynamic form configuration |
| default_config | JSONField | Default settings |
| pricing_tier | CharField(20) | Required plan tier |
| is_active | BooleanField | Available for new instances |
| is_featured | BooleanField | Show in featured section |
| created_at | DateTimeField | Creation date |
| updated_at | DateTimeField | Last update |

### AgentInstance

A customer's configured agent (created during onboarding).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner customer |
| agent_type | FK(AgentType) | Base agent type |
| name | CharField(100) | Customer-given name ("Acme Support Bot") |
| slug | SlugField | URL-safe identifier |
| system_prompt | TextField | Customized prompt (from template) |
| identity_config | JSONField | Name, avatar, greeting, etc. |
| knowledge_base | FK(KnowledgeBase) | Associated knowledge base (optional) |
| enabled_actions | JSONField | Subset of available_actions |
| custom_config | JSONField | Instance-specific settings |
| api_key | CharField(64) | Runtime API key (hashed) |
| api_key_prefix | CharField(8) | Visible prefix for identification |
| embed_domains | ArrayField | Allowed embed domains |
| is_active | BooleanField | Instance status |
| created_at | DateTimeField | Creation date |
| updated_at | DateTimeField | Last config update |

---

## 3.3 Onboarding System

### OnboardingSession

Tracks a customer's progress through agent onboarding.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Customer creating agent |
| agent_type | FK(AgentType) | Agent type being configured |
| agent_instance | FK(AgentInstance) | Created instance (null until complete) |
| current_step | CharField(50) | Current step ID |
| completed_steps | JSONField | List of completed step IDs |
| step_data | JSONField | Collected data per step |
| started_at | DateTimeField | Session start |
| completed_at | DateTimeField | Session completion (null if in progress) |
| abandoned_at | DateTimeField | Marked abandoned (null if active) |

### Onboarding Schema Format

Each AgentType defines its onboarding via `onboarding_schema`:

```json
{
  "version": "1.0",
  "knowledge_base": {
    "enabled": true,
    "required": false,
    "recommended": true,
    "allow_existing": true,
    "allow_create_new": true,
    "allow_url_import": true,
    "help_text": "Help your agent answer questions accurately with your documentation"
  },
  "steps": [
    {
      "id": "basics",
      "title": "Basic Setup",
      "description": "Configure your agent's identity",
      "required": true,
      "sections": [
        {
          "id": "identity",
          "title": "Agent Identity",
          "fields": [
            {
              "name": "agent_name",
              "type": "text",
              "label": "Agent Name",
              "placeholder": "e.g., Support Bot",
              "required": true,
              "validation": {
                "min_length": 2,
                "max_length": 50
              }
            },
            {
              "name": "avatar",
              "type": "image_upload",
              "label": "Avatar",
              "required": false,
              "validation": {
                "max_size_mb": 2,
                "formats": ["jpg", "png", "webp"]
              }
            },
            {
              "name": "greeting",
              "type": "textarea",
              "label": "Welcome Message",
              "placeholder": "Hi! How can I help you today?",
              "required": true
            }
          ]
        }
      ]
    },
    {
      "id": "knowledge",
      "title": "Knowledge Base",
      "required": false,
      "sections": [
        {
          "id": "documents",
          "title": "Upload Documents",
          "fields": [
            {
              "name": "documents",
              "type": "file_upload_multi",
              "label": "Documentation",
              "accept": ".pdf,.docx,.md,.txt",
              "help": "Upload product docs, FAQs, help articles"
            },
            {
              "name": "website_urls",
              "type": "url_list",
              "label": "Website Pages to Crawl",
              "help": "We'll extract content from these pages"
            }
          ]
        }
      ]
    },
    {
      "id": "integrations",
      "title": "Integrations",
      "required": false,
      "sections": [
        {
          "id": "ticketing",
          "title": "Ticket System",
          "fields": [
            {
              "name": "ticket_integration",
              "type": "oauth_connect",
              "label": "Connect Ticket System",
              "providers": ["zendesk", "freshdesk", "jira", "linear"],
              "help": "Allow agent to create and update tickets"
            },
            {
              "name": "escalation_email",
              "type": "email",
              "label": "Escalation Email",
              "show_if": {"ticket_integration": null},
              "help": "Fallback when no ticket system connected"
            }
          ]
        }
      ]
    }
  ]
}
```

### Supported Field Types

| Type | Description | Renderer |
|------|-------------|----------|
| text | Single-line text input | TextInput |
| textarea | Multi-line text | Textarea |
| richtext | WYSIWYG editor | RichTextEditor |
| email | Email with validation | EmailInput |
| url | URL with validation | URLInput |
| url_list | Multiple URLs | URLListInput |
| phone | Phone number | PhoneInput |
| number | Numeric input | NumberInput |
| select | Dropdown selection | Select |
| multi_select | Multiple selection | MultiSelect |
| radio | Radio buttons | RadioGroup |
| checkbox | Single checkbox | Checkbox |
| file_upload | Single file | FileUpload |
| file_upload_multi | Multiple files | MultiFileUpload |
| image_upload | Image with preview | ImageUpload |
| oauth_connect | OAuth integration | OAuthConnect |
| api_key_input | Secure API key | APIKeyInput |
| webhook_config | Webhook URL + secret | WebhookConfig |
| field_mapper | Map fields between systems | FieldMapper |
| crm_user_select | Select CRM user (dynamic) | CRMUserSelect |

### Conditional Logic

Fields support conditional display:

```json
{
  "name": "custom_url",
  "type": "url",
  "label": "Custom Booking URL",
  "show_if": {"booking_provider": "custom"}
}
```

Supported conditions:
- `show_if`: Show field if condition met
- `hide_if`: Hide field if condition met
- `required_if`: Make required if condition met

Condition operators:
- `{"field": "value"}` — equals
- `{"field": ["val1", "val2"]}` — in list
- `{"field": null}` — is empty/null
- `{"field": {"not": "value"}}` — not equals

### Knowledge Base Configuration

The `knowledge_base` object in `onboarding_schema` controls KB behavior per agent type:

| Field | Type | Description |
|-------|------|-------------|
| enabled | boolean | Show KB step in onboarding |
| required | boolean | Must configure KB to complete setup |
| recommended | boolean | Show "Recommended" badge |
| allow_existing | boolean | Can select from existing KBs |
| allow_create_new | boolean | Can create new KB inline |
| allow_url_import | boolean | Can add URLs for crawling |
| help_text | string | Guidance shown to user |

**Agent Type Examples:**

| Agent Type | enabled | required | recommended | Notes |
|------------|---------|----------|-------------|-------|
| Support Agent | true | false | true | Encouraged for FAQs |
| Knowledge Assistant | true | true | true | Core functionality |
| Sales Agent | true | false | false | Optional product info |
| Generic Chat | false | false | false | No KB needed |

**Post-Creation Configuration:**

KB can also be configured after agent creation via Agent Settings:
- Agent → Configuration → Knowledge Base
- Same options as wizard: select existing, create new, add URLs
- Can change or remove KB at any time

---

## 3.4 Knowledge Base

### KnowledgeBase

A collection of documents for an agent to reference.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| name | CharField(100) | Knowledge base name |
| description | TextField | Description (optional) |
| vector_index_id | CharField(100) | Vector store index ID (pgvector namespace) |
| embedding_model | CharField(50) | Model used (default: text-embedding-3-small) |
| total_documents | IntegerField | Document count |
| total_chunks | IntegerField | Chunk count |
| last_indexed_at | DateTimeField | Last indexing run |
| created_at | DateTimeField | Creation date |

### KnowledgeDocument

Individual documents in a knowledge base.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| knowledge_base | FK(KnowledgeBase) | Parent KB |
| source_type | CharField(20) | "upload", "url", "api" |
| source_url | URLField | Source URL (if crawled) |
| file | FileField | Uploaded file (if uploaded) |
| title | CharField(200) | Document title |
| content_hash | CharField(64) | SHA256 of content (dedup) |
| chunk_count | IntegerField | Number of chunks |
| status | CharField(20) | "pending", "processing", "indexed", "failed" |
| error_message | TextField | Error details (if failed) |
| indexed_at | DateTimeField | When indexed |
| created_at | DateTimeField | Upload/crawl date |

---

## 3.5 Integrations

### IntegrationProvider

Registry of supported integration providers (seeded data).

| Field | Type | Description |
|-------|------|-------------|
| slug | SlugField | Unique ID ("hubspot", "zendesk") |
| name | CharField(100) | Display name |
| category | CharField(50) | "crm", "ticketing", "calendar", etc. |
| auth_type | CharField(20) | "oauth2", "api_key", "basic" |
| oauth_config | JSONField | OAuth URLs, scopes |
| logo_url | URLField | Provider logo |
| capabilities | JSONField | List of supported actions |
| field_schema_endpoint | CharField(200) | API to fetch custom fields |
| is_active | BooleanField | Available for use |

### Integration

A customer's connected integration account.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| provider | FK(IntegrationProvider) | Provider type |
| account_id | CharField(100) | Provider account ID |
| account_name | CharField(200) | Account display name |
| access_token | EncryptedTextField | OAuth access token |
| refresh_token | EncryptedTextField | OAuth refresh token |
| token_expires_at | DateTimeField | Token expiration |
| scopes | JSONField | Granted scopes |
| metadata | JSONField | Provider-specific data |
| status | CharField(20) | "active", "expired", "revoked" |
| last_used_at | DateTimeField | Last API call |
| last_error | TextField | Last error (if any) |
| connected_at | DateTimeField | Connection date |

### AgentIntegration

Links an agent instance to a customer integration with config.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| agent_instance | FK(AgentInstance) | Agent using this |
| integration | FK(Integration) | Connected account |
| purpose | CharField(50) | "crm", "ticketing", "calendar" |
| config | JSONField | Field mappings, settings |
| is_active | BooleanField | Enabled for this agent |

---

## 3.6 Billing

### Subscription

Customer subscription (Stripe-backed).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | OneToOne(Customer) | Owner |
| stripe_customer_id | CharField(100) | Stripe customer ID |
| stripe_subscription_id | CharField(100) | Stripe subscription ID |
| plan | CharField(50) | "starter", "pro", "enterprise" |
| status | CharField(20) | "active", "past_due", "canceled" |
| current_period_start | DateTimeField | Billing period start |
| current_period_end | DateTimeField | Billing period end |
| cancel_at_period_end | BooleanField | Scheduled cancellation |

### UsageRecord

Tracks metered usage for billing.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| agent_instance | FK(AgentInstance) | Agent (optional) |
| metric | CharField(50) | "messages", "tokens", "api_calls" |
| quantity | IntegerField | Usage count |
| period_start | DateField | Usage period start |
| period_end | DateField | Usage period end |
| reported_to_stripe | BooleanField | Sent to Stripe |

### PlanLimit

Defines limits per subscription plan.

| Field | Type | Description |
|-------|------|-------------|
| plan | CharField(50) | Plan slug |
| limit_type | CharField(50) | Limit name |
| limit_value | IntegerField | Limit amount (-1 = unlimited) |

**Default Plan Limits:**

| Plan | Agents | Messages/mo | Knowledge Docs | Integrations |
|------|--------|-------------|----------------|--------------|
| starter | 1 | 1,000 | 10 | 2 |
| pro | 5 | 10,000 | 100 | 10 |
| enterprise | -1 | -1 | -1 | -1 |

---

# 4. Feature Requirements

## 4.1 Customer Registration

### Flow

1. User visits hub.echoforge.ai/register
2. Enters: email, password, company name
3. Receives verification email
4. Clicks verification link
5. Completes profile (optional: phone, industry, logo)
6. Lands on dashboard with agent catalog

### Business Rules

- Email must be unique across all customers
- Password: minimum 8 chars, 1 uppercase, 1 number
- Email verification required before dashboard access
- Verification link expires in 24 hours
- Customer created with "starter" plan (free tier or trial)

---

## 4.2 Agent Catalog & Provisioning

### Catalog View

- Grid display of available agent types
- Filter by category (support, sales, etc.)
- Show: icon, name, description, pricing tier
- "Featured" badge for promoted agents
- Disable unavailable agents (wrong plan tier)

### Provisioning Flow

1. Customer clicks "Add Agent" on desired type
2. System checks plan limits (max agents)
3. If allowed, creates OnboardingSession
4. Redirects to onboarding wizard
5. On completion, creates AgentInstance
6. Shows embed code and API key

---

## 4.3 Dynamic Onboarding Wizard

### Wizard Engine

The onboarding wizard dynamically renders based on `AgentType.onboarding_schema`:

```python
class OnboardingWizard:
    def __init__(self, session: OnboardingSession):
        self.session = session
        self.schema = session.agent_type.onboarding_schema

    def get_current_step(self) -> dict:
        """Return current step definition with field values"""
        step_id = self.session.current_step
        step = self.find_step(step_id)
        return self.hydrate_step(step)

    def validate_step(self, data: dict) -> tuple[bool, dict]:
        """Validate submitted step data, return (valid, errors)"""
        step = self.get_current_step()
        errors = {}
        for section in step['sections']:
            for field in section['fields']:
                if self.should_show_field(field, data):
                    field_errors = self.validate_field(field, data.get(field['name']))
                    if field_errors:
                        errors[field['name']] = field_errors
        return len(errors) == 0, errors

    def save_step(self, data: dict) -> None:
        """Save step data and advance to next step"""
        self.session.step_data[self.session.current_step] = data
        self.session.completed_steps.append(self.session.current_step)
        self.session.current_step = self.get_next_step_id()
        self.session.save()

    def complete(self) -> AgentInstance:
        """Finalize onboarding and create agent instance"""
        # Compile all step data
        config = self.compile_config()

        # Create agent instance
        instance = AgentInstance.objects.create(
            customer=self.session.customer,
            agent_type=self.session.agent_type,
            name=config['identity']['agent_name'],
            system_prompt=self.render_system_prompt(config),
            identity_config=config['identity'],
            knowledge_base=config.get('knowledge_base'),
            enabled_actions=config.get('actions', []),
            custom_config=config,
            api_key=generate_api_key(),
        )

        # Link integrations
        for integration_config in config.get('integrations', []):
            AgentIntegration.objects.create(
                agent_instance=instance,
                integration_id=integration_config['integration_id'],
                purpose=integration_config['purpose'],
                config=integration_config['config'],
            )

        # Mark session complete
        self.session.agent_instance = instance
        self.session.completed_at = timezone.now()
        self.session.save()

        return instance
```

### Step Persistence

- Each step saves immediately on "Next"
- User can navigate back to previous steps
- Abandoning session preserves progress
- Resume from last completed step

---

## 4.4 Knowledge Base Management

### Document Upload

1. Customer uploads files (PDF, DOCX, MD, TXT)
2. System queues processing task
3. Celery worker:
   - Extracts text content
   - Chunks into segments (500 tokens, 50 overlap)
   - Generates embeddings (OpenAI ada-002 or similar)
   - Stores in vector DB (Pinecone/Weaviate)
4. Updates document status to "indexed"

### Website Crawling

1. Customer provides URLs to crawl
2. System queues crawl task
3. Celery worker:
   - Fetches page content
   - Extracts main content (removes nav, footer, etc.)
   - Follows internal links (configurable depth)
   - Processes like uploaded documents

### Knowledge Base API

```python
# Internal API for Agent runtime
GET /api/internal/knowledge/{kb_id}/search
{
    "query": "how do I reset my password",
    "top_k": 5,
    "min_score": 0.7
}

Response:
{
    "results": [
        {
            "chunk_id": "doc_123_chunk_5",
            "content": "To reset your password, click...",
            "score": 0.92,
            "metadata": {
                "document_id": "doc_123",
                "document_title": "User Guide",
                "source_url": "https://..."
            }
        }
    ]
}
```

---

## 4.5 Integration Management

### OAuth Connection Flow

1. Customer clicks "Connect" for a provider
2. System redirects to provider OAuth
3. Customer authorizes
4. Provider redirects back with auth code
5. System exchanges for tokens
6. Creates Integration record (encrypted tokens)
7. Fetches account info (name, ID)
8. Returns to Hub with success message

### Token Refresh

```python
class IntegrationService:
    def get_valid_token(self, integration: Integration) -> str:
        """Get a valid access token, refreshing if needed"""
        if integration.token_expires_at > timezone.now() + timedelta(minutes=5):
            return integration.access_token

        # Refresh token
        provider = integration.provider
        response = requests.post(
            provider.oauth_config['token_url'],
            data={
                'grant_type': 'refresh_token',
                'refresh_token': integration.refresh_token,
                'client_id': settings.OAUTH_CLIENTS[provider.slug]['client_id'],
                'client_secret': settings.OAUTH_CLIENTS[provider.slug]['client_secret'],
            }
        )

        if response.status_code != 200:
            integration.status = 'expired'
            integration.last_error = response.text
            integration.save()
            raise IntegrationExpiredError(integration)

        data = response.json()
        integration.access_token = data['access_token']
        integration.refresh_token = data.get('refresh_token', integration.refresh_token)
        integration.token_expires_at = timezone.now() + timedelta(seconds=data['expires_in'])
        integration.save()

        return integration.access_token
```

### Integration Disconnect

1. Customer clicks "Disconnect"
2. System calls provider's revoke endpoint (if available)
3. Deletes Integration record
4. Updates AgentIntegrations to remove references
5. Notifies affected agents (graceful degradation)

---

## 4.6 Internal Config API

API for EchoForge Agent runtime to fetch configuration.

### Authentication

- Service-to-service auth via shared secret
- Agent instance auth via API key

### Endpoints

```
GET /api/internal/agent/{agent_id}/config
Authorization: Bearer {service_secret}

Response:
{
    "agent_id": "inst_abc123",
    "agent_type": "support_agent",
    "customer_id": "cust_xyz",

    "identity": {
        "name": "Acme Support Bot",
        "avatar_url": "https://...",
        "greeting": "Hi! How can I help you today?"
    },

    "system_prompt": "You are a support assistant for Acme Corp...",

    "knowledge_base": {
        "id": "kb_456",
        "search_endpoint": "https://hub.echoforge.ai/api/internal/knowledge/kb_456/search"
    },

    "integrations": {
        "ticketing": {
            "provider": "zendesk",
            "credentials_endpoint": "https://hub.echoforge.ai/api/internal/integration/int_789/credentials",
            "config": {
                "default_priority": "normal",
                "default_group_id": "group_123"
            }
        }
    },

    "actions_enabled": [
        "create_ticket",
        "escalate_to_human"
    ],

    "rate_limits": {
        "messages_per_minute": 20,
        "tokens_per_minute": 10000
    }
}
```

```
GET /api/internal/integration/{integration_id}/credentials
Authorization: Bearer {service_secret}

Response:
{
    "provider": "zendesk",
    "access_token": "eyJ...",  // Decrypted
    "account_id": "acme",
    "expires_at": "2025-01-15T12:00:00Z"
}
```

---

# 5. User Interface

## 5.1 Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│  EchoForge Hub                              [Acme Corp ▼]       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Your Agents                                   [+ Add Agent]    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ 💬 Support Bot  │  │ 💼 Sales Bot    │  │ ➕ Add Agent    │ │
│  │ ✓ Active        │  │ ✓ Active        │  │                 │ │
│  │ 1,234 messages  │  │ 567 messages    │  │                 │ │
│  │ [Configure]     │  │ [Configure]     │  │                 │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Quick Stats (This Month)                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Messages     │  │ Conversations│  │ Satisfaction │          │
│  │ 1,801        │  │ 423          │  │ 94%          │          │
│  │ ↑ 12%        │  │ ↑ 8%         │  │ ↑ 2%         │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Recent Activity                                                │
│  • Support Bot resolved 5 tickets today                         │
│  • Sales Bot booked 2 meetings                                  │
│  • Knowledge base updated (3 new documents)                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 5.2 Navigation

```
├── Dashboard
├── Agents
│   ├── All Agents
│   ├── Add Agent (catalog)
│   └── [Agent Name]
│       ├── Overview
│       ├── Configuration
│       ├── Knowledge Base
│       ├── Integrations
│       ├── Analytics
│       └── Embed Code
├── Integrations
│   ├── Connected
│   └── Available
├── Knowledge
│   ├── All Knowledge Bases
│   └── [KB Name]
├── Analytics
├── Team
│   ├── Members
│   └── Invites
├── Billing
│   ├── Subscription
│   ├── Usage
│   └── Invoices
└── Settings
    ├── Profile
    ├── Security
    └── API Keys
```

---

# 6. Security Considerations

## 6.1 Data Isolation

- All queries scoped to customer via CustomerMiddleware
- API keys hashed (bcrypt), only prefix stored plaintext
- Integration tokens encrypted at rest (Fernet)
- Knowledge base vectors namespaced by customer

## 6.2 Authentication

- Session-based auth for web UI
- API key auth for runtime API
- Service secret for internal APIs
- OAuth for integration connections

## 6.3 Rate Limiting

- API endpoints rate-limited per customer
- Onboarding file uploads limited by size/count
- Knowledge base indexing queued (not real-time)

---

# 7. Implementation Approach

## 7.1 Recommended Phases

**Phase 1: Foundation (2 weeks)**
1. Project setup (Django, PostgreSQL, Redis)
2. Customer and CustomerUser models
3. Registration, login, email verification
4. Basic dashboard template

**Phase 2: Agent Registry (1 week)**
1. AgentType and AgentInstance models
2. Agent catalog view
3. Basic agent provisioning (no onboarding yet)
4. API key generation

**Phase 3: Onboarding Engine (2 weeks)**
1. OnboardingSession model
2. Dynamic wizard renderer
3. Field type components
4. Step persistence and navigation
5. Instance creation on completion

**Phase 4: Knowledge Base (2 weeks)**
1. KnowledgeBase and KnowledgeDocument models
2. File upload and processing
3. Vector DB integration (Pinecone)
4. Search API

**Phase 5: Integrations (2 weeks)**
1. IntegrationProvider registry
2. OAuth flow implementation
3. Token storage and refresh
4. 2-3 initial providers (Zendesk, HubSpot, Slack)

**Phase 6: Internal API (1 week)**
1. Config API for Agent runtime
2. Credentials API
3. Knowledge search API
4. Service authentication

**Phase 7: Billing (1 week)**
1. Stripe integration
2. Subscription management
3. Usage tracking
4. Plan limits enforcement

## 7.2 Dependencies

| Dependency | Notes |
|------------|-------|
| EchoForge Agent | Runtime consumes Hub APIs (can develop in parallel) |
| Vector DB | Pinecone or Weaviate account needed |
| Stripe | Account and API keys needed |
| OAuth Apps | Register apps with each integration provider |

---

# 8. Acceptance Criteria

## 8.1 Customer Management

- [ ] Customer can register with email verification
- [ ] Customer can invite team members
- [ ] Customer can manage team roles
- [ ] Customer profile editable

## 8.2 Agent Provisioning

- [ ] Agent catalog displays available types
- [ ] Plan limits enforced (agent count)
- [ ] Onboarding wizard renders from schema
- [ ] All field types functional
- [ ] Conditional logic works
- [ ] Agent instance created on completion
- [ ] API key generated and displayed once

## 8.3 Knowledge Base

- [ ] Documents uploadable (PDF, DOCX, MD, TXT)
- [ ] Documents processed and indexed
- [ ] Search returns relevant chunks
- [ ] Website crawling functional

## 8.4 Integrations

- [ ] OAuth flow works for supported providers
- [ ] Tokens stored encrypted
- [ ] Token refresh automatic
- [ ] Disconnect properly revokes access

## 8.5 Internal API

- [ ] Config API returns full agent config
- [ ] Credentials API returns decrypted tokens
- [ ] Service auth working
- [ ] Rate limiting in place

## 8.6 Billing

- [ ] Stripe checkout works
- [ ] Subscription status synced
- [ ] Usage tracked
- [ ] Plan limits enforced

---

*End of Specification*
