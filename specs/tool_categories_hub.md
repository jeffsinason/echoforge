---
title: Tool Categories Architecture - Hub Specification
version: "1.0"
status: draft
project: EchoForge Hub
created: 2026-01-01
updated: 2026-01-01
related:
  - tool_categories_agent.md
  - internal_api_contract.md
  - integration_framework.md
---

# 1. Executive Summary

This specification defines the Hub's responsibility for managing **Tool Categories** - a system that organizes agent tools into logical groups tied to integrations or platform capabilities. The Hub serves as the single source of truth for which tools are available to each agent instance, based on:

1. **Agent Type** - What categories are possible for this type of agent
2. **Customer Configuration** - Which categories the customer has enabled
3. **Connected Integrations** - Which providers fulfill integration categories
4. **Plan & Add-ons** - Billing constraints on category access

The Agent runtime receives a computed list of enabled tools and executes them; it does not maintain its own tool configuration.

---

# 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HUB (Source of Truth)                          │
│                                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  ToolCategory   │    │ IntegrationProv │    │  AgentInstance  │         │
│  │  - email        │◄───│ - gmail         │    │  - enabled_cats │         │
│  │  - calendar     │    │ - google_cal    │    │  - enabled_addons│        │
│  │  - missions     │    │ - outlook       │    │                 │         │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘         │
│           │                      │                      │                   │
│           └──────────────────────┴──────────────────────┘                   │
│                                  │                                          │
│                                  ▼                                          │
│                    ┌─────────────────────────┐                              │
│                    │  get_effective_tools()  │                              │
│                    │  Computes enabled tools │                              │
│                    │  for agent instance     │                              │
│                    └─────────────────────────┘                              │
│                                  │                                          │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────┐
                    │  GET /api/internal/     │
                    │  agent/{id}/config      │
                    │                         │
                    │  Returns:               │
                    │  - enabled_actions: []  │
                    │  - integrations: {}     │
                    └─────────────────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────┐
                    │         AGENT           │
                    │  (Receives & executes)  │
                    └─────────────────────────┘
```

---

# 3. Abstraction Layers and Tool Routing

This section clarifies the relationship between tools, categories, providers, integrations, and services.

## 3.1 The Five Abstraction Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 1: TOOLS/ACTIONS (Abstract - what LLM calls)                          │
│                                                                             │
│   email_send, email_search, calendar_list_events, calendar_create_event    │
│                                                                             │
│   These are ABSTRACT - same name regardless of provider                     │
│   The LLM never knows about Gmail vs Outlook                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 2: CATEGORIES (Grouping)                                              │
│                                                                             │
│   email: [email_send, email_search, email_read, ...]                        │
│   calendar: [calendar_list_events, calendar_create_event, ...]              │
│                                                                             │
│   Maps tools to a capability domain                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 3: PROVIDERS (Implementations available)                              │
│                                                                             │
│   email category:     gmail, outlook_mail, sendgrid                         │
│   calendar category:  google_calendar, outlook_calendar                     │
│                                                                             │
│   Each provider implements the category's tools                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 4: INTEGRATIONS (Customer's connection)                               │
│                                                                             │
│   Customer "Acme Corp" has:                                                 │
│     - gmail integration (OAuth tokens, account info)                        │
│     - google_calendar integration                                           │
│                                                                             │
│   This is the BINDING - determines which provider handles the tool          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 5: SERVICES (Concrete implementation code)                            │
│                                                                             │
│   GmailService.send_email() - calls Gmail API                               │
│   OutlookService.send_email() - calls Microsoft Graph API                   │
│                                                                             │
│   Same interface, different implementation                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Data Model Relationships

```
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│  ToolCategory    │       │IntegrationProvider│      │   Integration    │
├──────────────────┤       ├──────────────────┤       ├──────────────────┤
│ slug: "email"    │◄──────│ slug: "gmail"    │◄──────│ customer: Acme   │
│ tools: [         │   FK  │ name: "Gmail"    │   FK  │ provider: gmail  │
│   "email_send",  │       │ category: email  │───────│ access_token:... │
│   "email_search",│       │ oauth_config:... │       │ is_active: true  │
│   ...            │       └──────────────────┘       └──────────────────┘
│ ]                │
└──────────────────┘       ┌──────────────────┐       ┌──────────────────┐
                           │IntegrationProvider│      │   Integration    │
                           ├──────────────────┤       ├──────────────────┤
                           │ slug: "outlook"  │◄──────│ customer: Bob    │
                           │ name: "Outlook"  │   FK  │ provider: outlook│
                           │ category: email  │───────│ access_token:... │
                           └──────────────────┘       └──────────────────┘
```

## 3.3 Tool Routing Flow

When a user says "send an email to John":

```
1. LLM decides: "I need to call email_send"

2. Agent sends to Hub:
   POST /api/internal/tools/execute/
   {
     "tool": "email_send",           ← Abstract tool name
     "agent_id": "...",
     "customer_id": "...",
     "inputs": {
       "to": "john@example.com",
       "subject": "Hello",
       "body": "..."
     }
   }

3. Hub looks up category:
   ToolCategory.objects.filter(tools__contains=["email_send"])
   → Returns: email category

4. Hub finds customer's integration for this category:
   Integration.objects.get(
     customer=customer,
     provider__category=email_category,
     is_active=True
   )
   → Returns: Integration(provider="gmail", access_token="...")

5. Hub routes to provider's service:
   service = get_service_for_provider("gmail")  # → GmailService
   result = service.execute_tool("email_send", inputs, integration)

6. GmailService calls Gmail API:
   gmail_api.users().messages().send(...)

7. Result returned to Agent → LLM
```

## 3.4 Terminology Reference

| Concept | What It Is | Example |
|---------|------------|---------|
| **Tool/Action** | Abstract operation LLM calls | `email_send` |
| **Category** | Groups related tools | `email` contains `[email_send, email_search, ...]` |
| **Provider** | Service that implements a category | `gmail`, `outlook` both implement `email` |
| **Integration** | Customer's connection to a provider | Acme's Gmail OAuth tokens |
| **Service** | Code that calls the actual API | `GmailService._send_email()` |

---

# 4. Data Models

## 4.1 ToolCategory

Defines a category of related tools.

```python
# apps/agents/models.py

class ToolCategory(BaseModel):
    """
    A logical grouping of related tools.

    Categories are either:
    - Integration categories: Require an OAuth provider (email, calendar, documents)
    - Capability categories: Platform-provided features (research, missions)
    """

    CATEGORY_TYPES = [
        ('integration', 'Requires Integration'),
        ('capability', 'Platform Capability'),
    ]

    BILLING_TYPES = [
        ('included', 'Included in Plan'),
        ('metered', 'Usage Metered'),
        ('addon', 'Premium Add-on'),
    ]

    # Identity
    slug = models.SlugField(unique=True, max_length=50)
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    icon = models.CharField(max_length=50, blank=True)

    # Classification
    category_type = models.CharField(
        max_length=20,
        choices=CATEGORY_TYPES,
        default='integration',
    )

    # Tools in this category
    tools = models.JSONField(
        default=list,
        help_text="List of tool slugs: ['email_send', 'email_search']"
    )

    # Billing configuration
    billing_type = models.CharField(
        max_length=20,
        choices=BILLING_TYPES,
        default='included',
    )
    meter_name = models.CharField(
        max_length=50,
        blank=True,
        help_text="Usage meter slug for metered categories"
    )

    # Plan requirements
    min_plan_tier = models.CharField(
        max_length=20,
        default='starter',
        help_text="Minimum plan tier to enable this category"
    )

    # Display
    display_order = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['display_order', 'name']
        verbose_name = 'Tool Category'
        verbose_name_plural = 'Tool Categories'

    def __str__(self):
        return f"{self.name} ({self.category_type})"
```

## 4.2 IntegrationProvider Updates

Update to link providers to categories.

```python
# apps/integrations/models.py

class IntegrationProvider(BaseModel):
    """
    A third-party service provider (Gmail, Google Calendar, etc.)

    Each provider fulfills one tool category.
    """

    # Existing fields...
    slug = models.SlugField(unique=True)
    name = models.CharField(max_length=100)

    # NEW: Link to category
    category = models.ForeignKey(
        'agents.ToolCategory',
        on_delete=models.PROTECT,
        related_name='providers',
        limit_choices_to={'category_type': 'integration'},
        help_text="Which tool category this provider fulfills"
    )

    # OAuth configuration
    oauth_config = models.JSONField(default=dict)

    # ... rest of existing fields
```

## 4.3 AgentType Updates

Update to reference categories instead of individual tools.

```python
# apps/agents/models.py

class AgentType(BaseModel):
    """
    Template defining a type of agent.

    Available categories define what tools this agent type CAN use.
    Actual enabled tools depend on customer configuration and integrations.
    """

    # Existing fields...
    slug = models.SlugField(unique=True)
    name = models.CharField(max_length=100)

    # CHANGE: From available_actions (list of tools) to available_categories
    available_categories = models.ManyToManyField(
        ToolCategory,
        related_name='agent_types',
        blank=True,
        help_text="Tool categories this agent type can use"
    )

    # Keep for backwards compatibility during migration
    # Remove after migration complete
    available_actions = models.JSONField(
        default=list,
        help_text="DEPRECATED: Use available_categories"
    )

    # ... rest of existing fields
```

## 4.4 AgentInstance Updates

Update to store category preferences and add-ons.

```python
# apps/agents/models.py

class AgentInstance(CustomerScopedModel):
    """
    A customer's configured agent.
    """

    # Existing fields...

    # CHANGE: From enabled_actions to enabled_categories
    enabled_categories = models.ManyToManyField(
        ToolCategory,
        related_name='enabled_instances',
        blank=True,
        help_text="Categories enabled for this instance"
    )

    # NEW: Premium add-ons
    enabled_addons = models.ManyToManyField(
        ToolCategory,
        related_name='addon_instances',
        blank=True,
        limit_choices_to={'billing_type': 'addon'},
        help_text="Premium capability add-ons"
    )

    # Keep for backwards compatibility during migration
    enabled_actions = models.JSONField(
        default=list,
        help_text="DEPRECATED: Computed from categories"
    )

    def get_effective_tools(self) -> List[str]:
        """
        Compute the list of tools available to this agent instance.

        Considers:
        - Agent type's available categories
        - Instance's enabled categories
        - Customer's connected integrations
        - Premium add-ons
        - Plan tier restrictions
        """
        from apps.integrations.models import Integration

        tools = []
        customer = self.customer
        available_cats = set(self.agent_type.available_categories.values_list('id', flat=True))

        # 1. Integration categories
        for category in self.enabled_categories.filter(category_type='integration'):
            # Must be in agent type's available categories
            if category.id not in available_cats:
                continue

            # Must have plan tier
            if not customer.has_plan_tier(category.min_plan_tier):
                continue

            # Must have active integration for this category
            has_integration = Integration.objects.filter(
                customer=customer,
                provider__category=category,
                is_active=True,
            ).exists()

            if has_integration:
                tools.extend(category.tools)

        # 2. Capability categories (non-addon)
        for category in self.enabled_categories.filter(
            category_type='capability',
        ).exclude(billing_type='addon'):
            if category.id not in available_cats:
                continue
            if customer.has_plan_tier(category.min_plan_tier):
                tools.extend(category.tools)

        # 3. Premium add-ons
        for category in self.enabled_addons.all():
            if customer.has_addon(category.slug):
                tools.extend(category.tools)

        return list(set(tools))
```

---

# 5. API Changes

## 5.1 Agent Config Endpoint Update

Update the config response to include computed tools.

```python
# api/internal/views.py

class AgentConfigView(APIView):
    """
    GET /api/internal/agent/{agent_id}/config

    Returns agent configuration including computed enabled_actions.
    """

    def get(self, request, agent_id):
        agent = get_object_or_404(AgentInstance, id=agent_id, is_active=True)

        # Compute effective tools from categories
        enabled_actions = agent.get_effective_tools()

        # Get integration details for enabled categories
        integrations = self._get_integration_config(agent)

        return Response({
            'id': str(agent.id),
            'agent_type_slug': agent.agent_type.slug,
            'customer_id': str(agent.customer_id),
            'customer_name': agent.customer.name,
            'name': agent.name,
            'slug': agent.slug,
            'system_prompt': agent.system_prompt,
            'identity_config': agent.identity_config,

            # Computed from categories + integrations
            'enabled_actions': enabled_actions,

            # Integration routing info
            'integrations': integrations,

            'custom_config': agent.custom_config,
            'embed_domains': agent.embed_domains,
            'knowledge_base': self._get_kb_config(agent),
            'limits': self._get_limits(agent),
            'billing': self._get_billing_status(agent),
            'plan': agent.customer.subscription.plan.slug if hasattr(agent.customer, 'subscription') else None,
        })

    def _get_integration_config(self, agent) -> Dict:
        """
        Build integration config mapping categories to providers.

        Returns:
            {
                "email": {
                    "provider": "gmail",
                    "integration_id": "uuid"
                },
                "calendar": {
                    "provider": "google_calendar",
                    "integration_id": "uuid"
                }
            }
        """
        from apps.integrations.models import Integration

        integrations = {}

        for integration in Integration.objects.filter(
            customer=agent.customer,
            is_active=True,
        ).select_related('provider__category'):
            category_slug = integration.provider.category.slug
            integrations[category_slug] = {
                'provider': integration.provider.slug,
                'integration_id': str(integration.id),
            }

        return integrations
```

## 5.2 Tool Execution Routing

Update tool execution to route based on category → integration.

```python
# api/internal/views.py

class ToolExecutionView(APIView):
    """
    POST /api/internal/tools/execute/

    Executes a tool, routing to the correct provider based on
    the customer's integration for that tool's category.
    """

    def post(self, request):
        tool_name = request.data['tool']
        agent_id = request.data['agent_id']
        inputs = request.data['inputs']
        context = request.data.get('context', {})

        agent = get_object_or_404(AgentInstance, id=agent_id)

        # Find which category this tool belongs to
        category = ToolCategory.objects.filter(
            tools__contains=[tool_name]
        ).first()

        if not category:
            return Response({
                'success': False,
                'error': {'message': f"Unknown tool: {tool_name}"}
            }, status=400)

        # For integration categories, find the customer's provider
        if category.category_type == 'integration':
            integration = Integration.objects.filter(
                customer=agent.customer,
                provider__category=category,
                is_active=True,
            ).select_related('provider').first()

            if not integration:
                return Response({
                    'success': False,
                    'error': {'message': f"No integration configured for {category.name}"}
                }, status=400)

            # Route to provider-specific service
            result = self._execute_integration_tool(
                tool_name=tool_name,
                provider=integration.provider,
                integration=integration,
                inputs=inputs,
                context=context,
            )
        else:
            # Capability tools (research, missions) - platform provided
            result = self._execute_capability_tool(
                tool_name=tool_name,
                category=category,
                agent=agent,
                inputs=inputs,
                context=context,
            )

        return Response(result)

    def _execute_integration_tool(self, tool_name, provider, integration, inputs, context):
        """Route to provider-specific implementation."""
        from apps.integrations.services import get_service_for_provider

        service = get_service_for_provider(provider.slug)
        return service.execute_tool(
            tool_name=tool_name,
            integration=integration,
            inputs=inputs,
            context=context,
        )

    def _execute_capability_tool(self, tool_name, category, agent, inputs, context):
        """Execute platform-provided capability tools."""
        # Research tools, mission tools, etc.
        # These don't need integration routing
        from apps.agents.services import execute_capability_tool

        return execute_capability_tool(
            tool_name=tool_name,
            agent=agent,
            inputs=inputs,
            context=context,
        )
```

---

# 6. Provider Services

Provider services implement the actual API calls for each integration provider. Each service class implements the same interface but uses provider-specific APIs.

## 6.1 Base Service Interface

```python
# apps/integrations/services/base.py

from abc import ABC, abstractmethod
from typing import Any, Dict
from apps.integrations.models import Integration


class BaseIntegrationService(ABC):
    """
    Base class for provider services.

    Each provider (Gmail, Outlook, etc.) implements this interface
    to execute tools using their specific API.
    """

    # Provider slug this service handles
    provider_slug: str = ""

    @abstractmethod
    def execute_tool(
        self,
        tool_name: str,
        integration: Integration,
        inputs: Dict[str, Any],
        context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Execute a tool using this provider.

        Args:
            tool_name: The abstract tool name (e.g., "email_send")
            integration: Customer's integration with OAuth tokens
            inputs: Tool input parameters from LLM
            context: Additional context (conversation_id, etc.)

        Returns:
            Dict with 'success', 'result' or 'error' keys
        """
        pass

    def _get_credentials(self, integration: Integration):
        """Get decrypted OAuth credentials from integration."""
        return {
            'access_token': integration.get_access_token(),
            'refresh_token': integration.get_refresh_token(),
        }
```

## 6.2 Gmail Service Example

```python
# apps/integrations/services/gmail.py

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

from .base import BaseIntegrationService


class GmailService(BaseIntegrationService):
    """Gmail implementation of email tools."""

    provider_slug = "gmail"

    def execute_tool(self, tool_name, integration, inputs, context):
        credentials = self._get_google_credentials(integration)

        # Route to specific method based on tool name
        tool_methods = {
            'email_send': self._send_email,
            'email_search': self._search_emails,
            'email_read': self._read_email,
            'email_check_replies': self._check_replies,
        }

        method = tool_methods.get(tool_name)
        if not method:
            return {
                'success': False,
                'error': {'message': f"Tool {tool_name} not implemented for Gmail"}
            }

        return method(inputs, credentials, context)

    def _send_email(self, inputs, credentials, context):
        """Send email via Gmail API."""
        service = build('gmail', 'v1', credentials=credentials)

        message = self._create_message(
            to=inputs['to'],
            subject=inputs['subject'],
            body=inputs.get('body', ''),
        )

        result = service.users().messages().send(
            userId='me',
            body=message
        ).execute()

        return {
            'success': True,
            'result': {
                'message_id': result['id'],
                'thread_id': result['threadId'],
            }
        }
```

## 6.3 Outlook Service Example

```python
# apps/integrations/services/outlook.py

import httpx
from .base import BaseIntegrationService


class OutlookService(BaseIntegrationService):
    """Outlook/Microsoft 365 implementation of email tools."""

    provider_slug = "outlook_mail"
    GRAPH_API_URL = "https://graph.microsoft.com/v1.0"

    def execute_tool(self, tool_name, integration, inputs, context):
        # Same interface, different implementation
        tool_methods = {
            'email_send': self._send_email,
            'email_search': self._search_emails,
            'email_read': self._read_email,
        }

        method = tool_methods.get(tool_name)
        if not method:
            return {
                'success': False,
                'error': {'message': f"Tool {tool_name} not implemented for Outlook"}
            }

        return method(inputs, integration, context)

    def _send_email(self, inputs, integration, context):
        """Send email via Microsoft Graph API."""
        headers = {
            'Authorization': f'Bearer {integration.get_access_token()}',
            'Content-Type': 'application/json',
        }

        message = {
            'message': {
                'subject': inputs['subject'],
                'body': {'contentType': 'HTML', 'content': inputs.get('body', '')},
                'toRecipients': [{'emailAddress': {'address': inputs['to']}}],
            }
        }

        response = httpx.post(
            f'{self.GRAPH_API_URL}/me/sendMail',
            headers=headers,
            json=message,
        )

        if response.status_code == 202:
            return {'success': True, 'result': {'sent': True}}
        else:
            return {'success': False, 'error': {'message': response.text}}
```

## 6.4 Service Registry

```python
# apps/integrations/services/__init__.py

from typing import Type
from .base import BaseIntegrationService
from .gmail import GmailService
from .outlook import OutlookService
from .google_calendar import GoogleCalendarService
from .outlook_calendar import OutlookCalendarService


# Registry mapping provider slugs to service classes
SERVICE_REGISTRY: dict[str, Type[BaseIntegrationService]] = {
    'gmail': GmailService,
    'outlook_mail': OutlookService,
    'google_calendar': GoogleCalendarService,
    'outlook_calendar': OutlookCalendarService,
}


def get_service_for_provider(provider_slug: str) -> BaseIntegrationService:
    """
    Get the service instance for a provider.

    Args:
        provider_slug: The provider's slug (e.g., "gmail")

    Returns:
        Service instance for executing tools

    Raises:
        ValueError: If no service exists for the provider
    """
    service_class = SERVICE_REGISTRY.get(provider_slug)
    if not service_class:
        raise ValueError(f"No service registered for provider: {provider_slug}")
    return service_class()
```

## 6.5 Capability Services (Non-Integration)

For capability categories like research and missions that don't require OAuth:

```python
# apps/agents/services/capability_tools.py

from typing import Any, Dict


def execute_capability_tool(
    tool_name: str,
    agent: 'AgentInstance',
    inputs: Dict[str, Any],
    context: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Execute platform-provided capability tools.

    These tools don't route through integrations - they're
    provided directly by the platform.
    """
    tool_handlers = {
        # Research tools
        'research_web_search': execute_web_search,
        'research_fetch_page': execute_fetch_page,
        'research_summarize': execute_summarize,
        # Mission tools
        'mission_create_task': execute_create_task,
        'mission_ask_user': execute_ask_user,
        'mission_complete': execute_complete_mission,
    }

    handler = tool_handlers.get(tool_name)
    if not handler:
        return {
            'success': False,
            'error': {'message': f"Unknown capability tool: {tool_name}"}
        }

    return handler(agent, inputs, context)
```

---

# 7. Admin Interface

## 7.1 ToolCategory Admin

```python
# apps/agents/admin.py

@admin.register(ToolCategory)
class ToolCategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'category_type', 'billing_type', 'min_plan_tier', 'tool_count', 'is_active']
    list_filter = ['category_type', 'billing_type', 'min_plan_tier', 'is_active']
    search_fields = ['name', 'slug']
    ordering = ['display_order', 'name']

    fieldsets = [
        ('Identity', {
            'fields': ['slug', 'name', 'description', 'icon']
        }),
        ('Classification', {
            'fields': ['category_type', 'tools']
        }),
        ('Billing', {
            'fields': ['billing_type', 'meter_name', 'min_plan_tier']
        }),
        ('Display', {
            'fields': ['display_order', 'is_active']
        }),
    ]

    def tool_count(self, obj):
        return len(obj.tools)
    tool_count.short_description = 'Tools'
```

## 7.2 AgentInstance Admin Updates

```python
# apps/agents/admin.py

@admin.register(AgentInstance)
class AgentInstanceAdmin(admin.ModelAdmin):
    # ... existing config ...

    fieldsets = [
        # ... existing fieldsets ...
        ('Tool Categories', {
            'fields': ['enabled_categories', 'enabled_addons'],
            'description': 'Select which tool categories are enabled for this agent.'
        }),
    ]

    filter_horizontal = ['enabled_categories', 'enabled_addons']

    def get_queryset(self, request):
        return super().get_queryset(request).prefetch_related(
            'enabled_categories', 'enabled_addons'
        )
```

---

# 8. Seed Data

## 8.1 Initial Categories

```python
# apps/agents/management/commands/setup_tool_categories.py

from django.core.management.base import BaseCommand
from apps.agents.models import ToolCategory

CATEGORIES = [
    # Integration categories
    {
        'slug': 'email',
        'name': 'Email',
        'description': 'Send, search, and manage emails',
        'category_type': 'integration',
        'billing_type': 'included',
        'tools': [
            'email_send',
            'email_search',
            'email_read',
            'email_check_replies',
            'email_parse_reply',
            'email_send_followup',
        ],
        'display_order': 10,
    },
    {
        'slug': 'calendar',
        'name': 'Calendar',
        'description': 'View and manage calendar events',
        'category_type': 'integration',
        'billing_type': 'included',
        'tools': [
            'calendar_list_events',
            'calendar_get_availability',
            'calendar_find_optimal_times',
            'calendar_create_event',
            'calendar_update_event',
            'calendar_delete_event',
        ],
        'display_order': 20,
    },
    {
        'slug': 'documents',
        'name': 'Documents',
        'description': 'Create and edit documents',
        'category_type': 'integration',
        'billing_type': 'included',
        'tools': [
            'document_create',
            'document_edit',
            'document_get',
        ],
        'display_order': 30,
    },
    # Capability categories
    {
        'slug': 'research',
        'name': 'Web Research',
        'description': 'Search the web and fetch page content',
        'category_type': 'capability',
        'billing_type': 'metered',
        'meter_name': 'research_queries',
        'tools': [
            'research_web_search',
            'research_fetch_page',
            'research_summarize',
        ],
        'display_order': 40,
    },
    {
        'slug': 'missions',
        'name': 'Mission Orchestration',
        'description': 'Complex multi-step task management with human approvals',
        'category_type': 'capability',
        'billing_type': 'addon',
        'min_plan_tier': 'pro',
        'tools': [
            'mission_create_task',
            'mission_ask_user',
            'mission_complete',
        ],
        'display_order': 50,
    },
]


class Command(BaseCommand):
    help = 'Create initial tool categories'

    def handle(self, *args, **options):
        for cat_data in CATEGORIES:
            category, created = ToolCategory.objects.update_or_create(
                slug=cat_data['slug'],
                defaults=cat_data,
            )
            status = 'Created' if created else 'Updated'
            self.stdout.write(f"{status}: {category.name}")

        self.stdout.write(self.style.SUCCESS('Tool categories setup complete'))
```

---

# 9. Migration Strategy

## 9.1 Phase 1: Add New Models (Non-Breaking)

```python
# Migration: Add ToolCategory model and new fields

class Migration(migrations.Migration):
    dependencies = [
        ('agents', 'previous_migration'),
    ]

    operations = [
        # Create ToolCategory
        migrations.CreateModel(
            name='ToolCategory',
            fields=[
                ('id', models.UUIDField(primary_key=True)),
                ('slug', models.SlugField(unique=True)),
                ('name', models.CharField(max_length=100)),
                ('description', models.TextField(blank=True)),
                ('category_type', models.CharField(max_length=20)),
                ('tools', models.JSONField(default=list)),
                ('billing_type', models.CharField(max_length=20)),
                ('meter_name', models.CharField(max_length=50, blank=True)),
                ('min_plan_tier', models.CharField(max_length=20, default='starter')),
                ('display_order', models.IntegerField(default=0)),
                ('is_active', models.BooleanField(default=True)),
                # ... timestamps
            ],
        ),

        # Add M2M to AgentType
        migrations.AddField(
            model_name='agenttype',
            name='available_categories',
            field=models.ManyToManyField(to='agents.ToolCategory', blank=True),
        ),

        # Add M2M to AgentInstance
        migrations.AddField(
            model_name='agentinstance',
            name='enabled_categories',
            field=models.ManyToManyField(to='agents.ToolCategory', blank=True),
        ),
        migrations.AddField(
            model_name='agentinstance',
            name='enabled_addons',
            field=models.ManyToManyField(to='agents.ToolCategory', blank=True),
        ),
    ]
```

## 9.2 Phase 2: Data Migration

```python
# Migration: Populate categories from existing data

def migrate_to_categories(apps, schema_editor):
    """
    Convert existing enabled_actions to enabled_categories.
    """
    AgentInstance = apps.get_model('agents', 'AgentInstance')
    ToolCategory = apps.get_model('agents', 'ToolCategory')

    # Build tool → category mapping
    tool_to_category = {}
    for category in ToolCategory.objects.all():
        for tool in category.tools:
            tool_to_category[tool] = category

    # Migrate each agent instance
    for agent in AgentInstance.objects.all():
        categories_to_enable = set()

        for tool in agent.enabled_actions:
            if tool in tool_to_category:
                categories_to_enable.add(tool_to_category[tool])

        agent.enabled_categories.set(categories_to_enable)
```

## 9.3 Phase 3: Update Config API

- Modify `get_effective_tools()` to use categories
- Keep `enabled_actions` field populated for backwards compatibility
- Agent continues to receive `enabled_actions` list (no Agent changes needed initially)

## 9.4 Phase 4: Remove Deprecated Fields

After Agent is updated to use category-aware config:

- Remove `AgentType.available_actions` field
- Remove `AgentInstance.enabled_actions` field

---

# 10. Customer Portal Updates

## 10.1 Agent Configuration UI

The customer portal should show categories, not individual tools:

```
┌─────────────────────────────────────────────────────────────────┐
│ Agent Settings: My Personal Assistant                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ENABLED CAPABILITIES                                            │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☑ Email                                    [Connected: Gmail]│ │
│ │   Send, search, and manage emails                           │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☑ Calendar                          [Connected: Google Cal] │ │
│ │   View and manage calendar events                           │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☐ Documents                              [Connect Provider] │ │
│ │   Create and edit documents                                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☑ Web Research                              [50/100 queries]│ │
│ │   Search the web and fetch page content                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ PREMIUM ADD-ONS                                                 │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ☐ Mission Orchestration              [Upgrade to Pro] 🔒    │ │
│ │   Complex multi-step task management                        │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

# 11. Implementation Checklist

## 11.1 Models & Migrations

- [ ] Create `ToolCategory` model
- [ ] Update `IntegrationProvider` with category FK
- [ ] Update `AgentType` with `available_categories` M2M
- [ ] Update `AgentInstance` with `enabled_categories` and `enabled_addons` M2M
- [ ] Create data migration for existing agents
- [ ] Add `get_effective_tools()` method to AgentInstance

## 11.2 API Updates

- [ ] Update `/api/internal/agent/{id}/config` to compute enabled_actions
- [ ] Update `/api/internal/tools/execute/` to route by category
- [ ] Add integration config to config response

## 11.3 Admin Interface

- [ ] Register ToolCategory admin
- [ ] Update AgentInstance admin with category fields
- [ ] Update AgentType admin with category fields

## 11.4 Seed Data

- [ ] Create `setup_tool_categories` management command
- [ ] Define initial categories (email, calendar, documents, research, missions)
- [ ] Update existing IntegrationProviders with category links

## 11.5 Customer Portal

- [ ] Update agent configuration UI to show categories
- [ ] Show integration status per category
- [ ] Show usage for metered categories
- [ ] Show upgrade prompts for addon categories

---

# 12. Acceptance Criteria

- [ ] ToolCategory model exists with all fields
- [ ] IntegrationProvider links to category
- [ ] AgentType defines available_categories
- [ ] AgentInstance stores enabled_categories and enabled_addons
- [ ] `get_effective_tools()` correctly computes tools from categories + integrations
- [ ] Config API returns computed enabled_actions
- [ ] Tool execution routes to correct provider based on category
- [ ] Admin interface allows managing categories
- [ ] Existing agents migrated without service disruption
- [ ] Customer portal shows category-based configuration

---

# 13. Open Questions

1. **Category visibility per agent type**: Should certain categories be hidden in the UI for agent types that don't support them, or always shown with "Not available for this agent type"?

2. **Multiple integrations per category**: Current design is one provider per category. If a customer has both Gmail and Outlook connected, which takes precedence? (Recommendation: First connected, or explicit selection)

3. **Category dependencies**: Should enabling "documents" require "email" to be enabled for sharing? (Recommendation: No dependencies initially, add if needed)

---

*End of Hub Specification*
