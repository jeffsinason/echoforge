---
title: "Agent Behavior Framework"
version: "1.0"
status: ready-for-development
project: EchoForge
created: 2026-01-03
updated: 2026-01-03
github_issue: 26
---

# Agent Behavior Framework

## Executive Summary

This spec defines a structured framework for configuring agent behaviors without hardcoding them in source code. Behaviors are stored in the Hub database and editable via Django Admin, allowing EchoForge administrators to tune agent behavior without code deployments.

### Key Principles

1. **Not customer-editable** - Prevents prompt injection and ensures quality
2. **Structured options** - Predefined choices, not free-form text
3. **Admin-editable** - Changes via Django Admin, no code deployment
4. **Cached at startup** - Agent loads config once, effective on restart
5. **Extensible** - New categories added as agent types evolve

---

## 1. Architecture

### 1.1 Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CONFIGURATION FLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │ Django Admin │───►│ Hub Database │───►│ Agent Runtime        │  │
│  │ (Edit JSON)  │    │ (AgentType)  │    │ (Fetch at startup)   │  │
│  └──────────────┘    └──────────────┘    └──────────────────────┘  │
│                                                   │                  │
│                                                   ▼                  │
│                                          ┌──────────────────────┐   │
│                                          │ Build System Prompt  │   │
│                                          │ from behavior_config │   │
│                                          └──────────────────────┘   │
│                                                   │                  │
│                                                   ▼                  │
│                                          ┌──────────────────────┐   │
│                                          │ Claude API Request   │   │
│                                          │ with dynamic prompt  │   │
│                                          └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Configuration Hierarchy

```
AgentType (e.g., "personal_assistant")
    ├── behavior_config (JSON)
    │   ├── scheduling
    │   ├── approval
    │   ├── communication
    │   └── proactivity
    │
    └── system_prompt_template (Text with {placeholders})
```

---

## 2. Database Schema

### 2.1 AgentType Model Updates

```python
# backend/apps/agents/models.py

class AgentType(BaseModel):
    """
    Defines a type of agent with its capabilities and behaviors.
    """
    slug = models.SlugField(unique=True)
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)

    # Existing fields...
    onboarding_schema = models.JSONField(default=dict)
    default_actions = models.JSONField(default=list)

    # NEW: Behavioral configuration
    behavior_config = models.JSONField(
        default=dict,
        help_text="Structured behavior policies (scheduling, approval, etc.)"
    )

    # NEW: Editable system prompt template
    system_prompt_template = models.TextField(
        blank=True,
        help_text="System prompt template with {placeholders} for dynamic values"
    )

    # NEW: Behavior schema for validation
    behavior_schema_version = models.CharField(
        max_length=10,
        default="1.0",
        help_text="Version of behavior schema for compatibility"
    )

    class Meta:
        ordering = ['name']

    def get_behavior(self, category: str, key: str, default=None):
        """Get a specific behavior setting."""
        return self.behavior_config.get(category, {}).get(key, default)

    def get_system_prompt(self, context: dict) -> str:
        """Build system prompt from template with context."""
        if self.system_prompt_template:
            return self.system_prompt_template.format(**context)
        return ""
```

### 2.2 Migration

```python
# backend/apps/agents/migrations/XXXX_add_behavior_config.py

from django.db import migrations, models

def populate_default_behaviors(apps, schema_editor):
    """Set default behaviors for existing agent types."""
    AgentType = apps.get_model('agents', 'AgentType')

    personal_assistant_defaults = {
        "scheduling": {
            "ambiguous_time": "email_options",
            "missing_subject": "ask_user",
            "missing_duration": "default_1_hour",
            "external_attendees": "email_first",
            "propose_options_count": 3,
        },
        "approval": {
            "unknown_contacts": "require_approval",
            "financial_actions": "require_approval",
            "calendar_changes": "proceed",
            "email_send": "proceed",
            "document_share": "require_approval",
        },
        "communication": {
            "verbosity": "concise",
            "formatting": "markdown",
            "error_handling": "explain",
            "confirmation_style": "summary",
        },
        "proactivity": {
            "suggestions": "offer",
            "follow_ups": "automatic",
            "status_updates": "minimal",
            "reminders": "enabled",
        },
    }

    AgentType.objects.filter(slug='personal_assistant').update(
        behavior_config=personal_assistant_defaults
    )

class Migration(migrations.Migration):
    dependencies = [
        ('agents', 'previous_migration'),
    ]

    operations = [
        migrations.AddField(
            model_name='agenttype',
            name='behavior_config',
            field=models.JSONField(default=dict),
        ),
        migrations.AddField(
            model_name='agenttype',
            name='system_prompt_template',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='agenttype',
            name='behavior_schema_version',
            field=models.CharField(default='1.0', max_length=10),
        ),
        migrations.RunPython(populate_default_behaviors),
    ]
```

---

## 3. Behavior Categories

### 3.1 Scheduling Behavior

Controls how the agent handles meeting/event scheduling requests.

| Key | Options | Default | Description |
|-----|---------|---------|-------------|
| `ambiguous_time` | `email_options`, `ask_user` | `email_options` | What to do when time is vague ("next week") |
| `missing_subject` | `ask_user`, `generate_default` | `ask_user` | What to do when meeting subject is missing |
| `missing_duration` | `default_1_hour`, `default_30_min`, `ask_user` | `default_1_hour` | What to do when duration not specified |
| `external_attendees` | `email_first`, `calendar_direct` | `email_first` | How to handle external attendees |
| `propose_options_count` | `2`, `3`, `4`, `5` | `3` | Number of time options to propose |
| `check_conflicts` | `always`, `external_only`, `never` | `always` | When to check calendar conflicts |

**Generated Prompt Section:**
```
SCHEDULING BEHAVIOR:
- When time is ambiguous (e.g., "next week", "sometime"): {ambiguous_time_text}
- When meeting subject is missing: {missing_subject_text}
- Default meeting duration: {duration_text}
- For external attendees: {external_attendees_text}
- Propose {propose_options_count} time options when asking for preferences
```

### 3.2 Approval Behavior

Controls when the agent requires explicit user approval before acting.

| Key | Options | Default | Description |
|-----|---------|---------|-------------|
| `unknown_contacts` | `require_approval`, `proceed`, `warn_and_proceed` | `require_approval` | Emailing/scheduling with unknown contacts |
| `financial_actions` | `require_approval`, `proceed` | `require_approval` | Any action involving money |
| `calendar_changes` | `require_approval`, `proceed` | `proceed` | Creating/modifying calendar events |
| `email_send` | `require_approval`, `proceed` | `proceed` | Sending emails |
| `document_share` | `require_approval`, `proceed` | `require_approval` | Sharing documents externally |
| `bulk_actions` | `require_approval`, `proceed` | `require_approval` | Actions affecting multiple items |

**Generated Prompt Section:**
```
APPROVAL REQUIREMENTS:
- Unknown/new contacts: {unknown_contacts_text}
- Financial actions (bookings, purchases): {financial_text}
- Calendar changes: {calendar_text}
- Sending emails: {email_text}
- Document sharing: {document_text}
- Bulk operations: {bulk_text}
```

### 3.3 Communication Style

Controls how the agent communicates with the user.

| Key | Options | Default | Description |
|-----|---------|---------|-------------|
| `verbosity` | `concise`, `detailed`, `minimal` | `concise` | How much detail in responses |
| `formatting` | `markdown`, `plain`, `rich` | `markdown` | Response formatting style |
| `error_handling` | `explain`, `retry_silently`, `ask_for_guidance` | `explain` | How to handle errors |
| `confirmation_style` | `summary`, `detailed`, `minimal` | `summary` | How to confirm completed actions |
| `progress_updates` | `every_step`, `milestones`, `completion_only` | `milestones` | When to update on progress |

**Generated Prompt Section:**
```
COMMUNICATION STYLE:
- Response length: {verbosity_text}
- Use {formatting} formatting in responses
- When errors occur: {error_handling_text}
- After completing actions: {confirmation_text}
- Progress updates: {progress_text}
```

### 3.4 Proactivity

Controls how proactive the agent is in offering help and following up.

| Key | Options | Default | Description |
|-----|---------|---------|-------------|
| `suggestions` | `offer`, `wait_for_ask`, `aggressive` | `offer` | Whether to suggest related actions |
| `follow_ups` | `automatic`, `ask_first`, `manual` | `automatic` | How to handle follow-up tasks |
| `status_updates` | `verbose`, `minimal`, `none` | `minimal` | Unsolicited status updates |
| `reminders` | `enabled`, `disabled`, `ask_first` | `enabled` | Whether to send reminders |
| `anticipate_needs` | `enabled`, `disabled` | `enabled` | Anticipate user needs based on context |

**Generated Prompt Section:**
```
PROACTIVITY LEVEL:
- Suggestions: {suggestions_text}
- Follow-up tasks: {follow_ups_text}
- Status updates: {status_text}
- Reminders: {reminders_text}
- Anticipate needs: {anticipate_text}
```

---

## 4. System Prompt Generation

### 4.1 Prompt Builder

```python
# echoforge-agent/src/services/prompt_builder.py

class BehaviorPromptBuilder:
    """Builds system prompt sections from behavior configuration."""

    # Text mappings for behavior options
    BEHAVIOR_TEXT = {
        "scheduling": {
            "ambiguous_time": {
                "email_options": "Email the attendees with 2-3 time options and wait for their preference",
                "ask_user": "Ask the user to specify a preferred time",
            },
            "missing_subject": {
                "ask_user": "Always ask the user for the meeting subject/title",
                "generate_default": "Generate a sensible default subject based on context",
            },
            "missing_duration": {
                "default_1_hour": "Default to 1 hour if duration not specified",
                "default_30_min": "Default to 30 minutes if duration not specified",
                "ask_user": "Ask the user for the meeting duration",
            },
            "external_attendees": {
                "email_first": "Email external attendees to check availability before scheduling",
                "calendar_direct": "Create calendar invite directly (assumes availability)",
            },
        },
        "approval": {
            "unknown_contacts": {
                "require_approval": "Request explicit approval before contacting",
                "proceed": "Proceed without approval",
                "warn_and_proceed": "Warn the user but proceed",
            },
            "financial_actions": {
                "require_approval": "Always request explicit approval",
                "proceed": "Proceed without approval",
            },
            # ... more mappings
        },
        # ... more categories
    }

    def build_scheduling_section(self, config: dict) -> str:
        """Build the scheduling behavior section of the prompt."""
        scheduling = config.get("scheduling", {})

        lines = ["SCHEDULING BEHAVIOR:"]

        ambiguous = scheduling.get("ambiguous_time", "email_options")
        lines.append(f"- When time is ambiguous (e.g., 'next week'): {self.BEHAVIOR_TEXT['scheduling']['ambiguous_time'][ambiguous]}")

        subject = scheduling.get("missing_subject", "ask_user")
        lines.append(f"- When meeting subject is missing: {self.BEHAVIOR_TEXT['scheduling']['missing_subject'][subject]}")

        duration = scheduling.get("missing_duration", "default_1_hour")
        lines.append(f"- Duration: {self.BEHAVIOR_TEXT['scheduling']['missing_duration'][duration]}")

        external = scheduling.get("external_attendees", "email_first")
        lines.append(f"- External attendees: {self.BEHAVIOR_TEXT['scheduling']['external_attendees'][external]}")

        options_count = scheduling.get("propose_options_count", 3)
        lines.append(f"- When proposing times, offer {options_count} options")

        return "\n".join(lines)

    def build_approval_section(self, config: dict) -> str:
        """Build the approval behavior section of the prompt."""
        approval = config.get("approval", {})

        lines = ["APPROVAL REQUIREMENTS:"]

        for key, default in [
            ("unknown_contacts", "require_approval"),
            ("financial_actions", "require_approval"),
            ("calendar_changes", "proceed"),
            ("email_send", "proceed"),
            ("document_share", "require_approval"),
        ]:
            value = approval.get(key, default)
            text = self.BEHAVIOR_TEXT["approval"].get(key, {}).get(value, value)
            lines.append(f"- {key.replace('_', ' ').title()}: {text}")

        return "\n".join(lines)

    def build_communication_section(self, config: dict) -> str:
        """Build the communication style section of the prompt."""
        comm = config.get("communication", {})

        verbosity = comm.get("verbosity", "concise")
        formatting = comm.get("formatting", "markdown")
        error_handling = comm.get("error_handling", "explain")

        lines = [
            "COMMUNICATION STYLE:",
            f"- Be {verbosity} in responses",
            f"- Use {formatting} formatting",
            f"- On errors: {error_handling} what went wrong and suggest alternatives",
        ]

        return "\n".join(lines)

    def build_proactivity_section(self, config: dict) -> str:
        """Build the proactivity section of the prompt."""
        proactive = config.get("proactivity", {})

        suggestions = proactive.get("suggestions", "offer")
        follow_ups = proactive.get("follow_ups", "automatic")

        lines = ["PROACTIVITY:"]

        if suggestions == "offer":
            lines.append("- Offer relevant suggestions when appropriate")
        elif suggestions == "wait_for_ask":
            lines.append("- Only provide suggestions when explicitly asked")

        if follow_ups == "automatic":
            lines.append("- Automatically handle follow-up tasks when possible")
        elif follow_ups == "ask_first":
            lines.append("- Ask before initiating follow-up tasks")

        return "\n".join(lines)

    def build_full_behavior_prompt(self, config: dict) -> str:
        """Build the complete behavior section of the system prompt."""
        sections = [
            self.build_scheduling_section(config),
            self.build_approval_section(config),
            self.build_communication_section(config),
            self.build_proactivity_section(config),
        ]

        return "\n\n".join(sections)
```

### 4.2 Integration with Agent Type Handler

```python
# echoforge-agent/src/services/agent_types/personal_assistant.py

class PersonalAssistantHandler(AgentTypeHandler):

    def get_orchestrator_prompt(self) -> str:
        """
        Get the orchestrator system prompt with behavior configuration.
        """
        from src.services.prompt_builder import BehaviorPromptBuilder

        try:
            tz = ZoneInfo(self.user_timezone)
        except Exception:
            tz = ZoneInfo("UTC")

        current_time = datetime.now(tz).strftime("%Y-%m-%d %H:%M %Z")

        # Get base template from config (from Hub)
        base_template = self.config.system_prompt_template or DEFAULT_PROMPT_TEMPLATE

        # Build behavior sections
        behavior_builder = BehaviorPromptBuilder()
        behavior_prompt = behavior_builder.build_full_behavior_prompt(
            self.config.behavior_config or {}
        )

        # Combine base template with behaviors
        full_prompt = base_template.format(
            user_name=self.user_name,
            current_time=current_time,
            user_timezone=self.user_timezone,
        )

        # Append behavior sections
        full_prompt += "\n\n" + behavior_prompt

        return full_prompt
```

---

## 5. Django Admin Interface

### 5.1 Admin Configuration

```python
# backend/apps/agents/admin.py

from django.contrib import admin
from django import forms
from django.utils.html import format_html
import json

class BehaviorConfigWidget(forms.Textarea):
    """Custom widget for editing behavior config with validation."""

    def __init__(self, *args, **kwargs):
        kwargs['attrs'] = {
            'rows': 30,
            'cols': 80,
            'style': 'font-family: monospace;',
        }
        super().__init__(*args, **kwargs)

class AgentTypeAdminForm(forms.ModelForm):
    class Meta:
        model = AgentType
        fields = '__all__'
        widgets = {
            'behavior_config': BehaviorConfigWidget(),
            'system_prompt_template': forms.Textarea(attrs={
                'rows': 20,
                'cols': 100,
                'style': 'font-family: monospace;',
            }),
        }

    def clean_behavior_config(self):
        """Validate behavior config JSON."""
        config = self.cleaned_data.get('behavior_config', {})

        # Validate structure
        valid_categories = ['scheduling', 'approval', 'communication', 'proactivity']
        for key in config.keys():
            if key not in valid_categories:
                raise forms.ValidationError(f"Unknown behavior category: {key}")

        # Validate scheduling options
        if 'scheduling' in config:
            valid_scheduling = {
                'ambiguous_time': ['email_options', 'ask_user'],
                'missing_subject': ['ask_user', 'generate_default'],
                'missing_duration': ['default_1_hour', 'default_30_min', 'ask_user'],
                'external_attendees': ['email_first', 'calendar_direct'],
            }
            for key, value in config['scheduling'].items():
                if key in valid_scheduling and value not in valid_scheduling[key]:
                    raise forms.ValidationError(
                        f"Invalid value '{value}' for scheduling.{key}. "
                        f"Valid options: {valid_scheduling[key]}"
                    )

        return config

@admin.register(AgentType)
class AgentTypeAdmin(admin.ModelAdmin):
    form = AgentTypeAdminForm

    list_display = ['name', 'slug', 'behavior_summary', 'updated_at']
    readonly_fields = ['created_at', 'updated_at', 'behavior_preview']

    fieldsets = (
        ('Basic Info', {
            'fields': ('name', 'slug', 'description'),
        }),
        ('Capabilities', {
            'fields': ('onboarding_schema', 'default_actions'),
        }),
        ('Behavior Configuration', {
            'fields': ('behavior_config', 'behavior_preview'),
            'description': 'Configure agent behavioral policies. Changes take effect on agent restart.',
        }),
        ('System Prompt', {
            'fields': ('system_prompt_template',),
            'classes': ('collapse',),
            'description': 'Base system prompt template. Use {user_name}, {current_time}, {user_timezone} placeholders.',
        }),
        ('Metadata', {
            'fields': ('behavior_schema_version', 'created_at', 'updated_at'),
        }),
    )

    def behavior_summary(self, obj):
        """Show quick summary of behavior settings."""
        config = obj.behavior_config or {}
        scheduling = config.get('scheduling', {}).get('ambiguous_time', 'N/A')
        approval = config.get('approval', {}).get('unknown_contacts', 'N/A')
        return f"Scheduling: {scheduling}, Approval: {approval}"
    behavior_summary.short_description = 'Key Behaviors'

    def behavior_preview(self, obj):
        """Show formatted preview of behavior config."""
        if not obj.behavior_config:
            return "No behavior config set"

        formatted = json.dumps(obj.behavior_config, indent=2)
        return format_html('<pre style="background: #f5f5f5; padding: 10px;">{}</pre>', formatted)
    behavior_preview.short_description = 'Behavior Preview'
```

---

## 6. API Updates

### 6.1 Agent Config Response

Update the internal API to include behavior config:

```python
# backend/api/internal/views.py

class AgentConfigView(APIView):
    def get(self, request, agent_id):
        # ... existing code ...

        return Response({
            'id': agent.id,
            'name': agent.name,
            # ... existing fields ...

            # NEW: Include behavior configuration
            'behavior_config': agent.agent_type.behavior_config,
            'system_prompt_template': agent.agent_type.system_prompt_template,
        })
```

### 6.2 Agent Config Model Update

```python
# echoforge-agent/src/models/config.py

@dataclass
class AgentConfig:
    agent_id: str
    agent_type: str
    # ... existing fields ...

    # NEW
    behavior_config: Dict[str, Any] = field(default_factory=dict)
    system_prompt_template: str = ""
```

---

## 7. Default Configurations

### 7.1 Personal Assistant Defaults

```json
{
  "scheduling": {
    "ambiguous_time": "email_options",
    "missing_subject": "ask_user",
    "missing_duration": "default_1_hour",
    "external_attendees": "email_first",
    "propose_options_count": 3,
    "check_conflicts": "always"
  },
  "approval": {
    "unknown_contacts": "require_approval",
    "financial_actions": "require_approval",
    "calendar_changes": "proceed",
    "email_send": "proceed",
    "document_share": "require_approval",
    "bulk_actions": "require_approval"
  },
  "communication": {
    "verbosity": "concise",
    "formatting": "markdown",
    "error_handling": "explain",
    "confirmation_style": "summary",
    "progress_updates": "milestones"
  },
  "proactivity": {
    "suggestions": "offer",
    "follow_ups": "automatic",
    "status_updates": "minimal",
    "reminders": "enabled",
    "anticipate_needs": "enabled"
  }
}
```

### 7.2 Default System Prompt Template

```
You are a personal assistant orchestrating complex tasks. You manage missions by breaking them into executable tasks, coordinating tools, and ensuring successful completion.

RESPONSIBILITIES:
1. UNDERSTAND - Parse requests, identify intent, ask clarifying questions when needed
2. PLAN - Break down into tasks with clear dependencies
3. EXECUTE - Call appropriate tools to complete each task
4. MONITOR - Track progress, detect failures, handle blocked states
5. REPLAN - Adjust strategy when tasks fail or circumstances change
6. SYNTHESIZE - Aggregate results and report back to user

AVAILABLE TOOLS:
- Mission: create, list, add_task, update_task, ask_user, complete, get_status, log_event
- Calendar: list_events, get_availability, find_optimal_times, create_event, update_event, delete_event
- Email: send, check_replies, parse_reply, search, read, send_followup
- Research: web_search, fetch_page, summarize
- Document: create, edit, get

Current user: {user_name}
Current time: {current_time}
User timezone: {user_timezone}
```

---

## 8. Implementation Phases

### Phase 1: Database & Admin
- [ ] Add `behavior_config` field to AgentType model
- [ ] Add `system_prompt_template` field to AgentType model
- [ ] Create migration with default values
- [ ] Implement Django Admin interface with validation
- [ ] Add behavior preview in admin

### Phase 2: Agent Integration
- [ ] Update AgentConfig model to include behavior fields
- [ ] Update internal API to return behavior config
- [ ] Implement BehaviorPromptBuilder class
- [ ] Update PersonalAssistantHandler to use behavior config
- [ ] Remove hardcoded ORCHESTRATOR_PROMPT_TEMPLATE

### Phase 3: Testing & Documentation
- [ ] Test behavior changes via admin
- [ ] Verify agent restart picks up new config
- [ ] Document all behavior options
- [ ] Add validation for unknown behavior keys

---

## 9. Acceptance Criteria

### Functional
- [ ] Behavior config editable via Django Admin
- [ ] Agent loads behavior config at startup
- [ ] System prompt generated from behavior config
- [ ] Changes take effect after agent restart
- [ ] Invalid behavior options rejected with helpful error

### Behavioral
- [ ] `ambiguous_time: email_options` causes agent to email attendees with options
- [ ] `missing_subject: ask_user` causes agent to ask for meeting subject
- [ ] `unknown_contacts: require_approval` causes agent to request approval
- [ ] `verbosity: concise` produces shorter responses

### Admin UX
- [ ] Behavior config displayed with syntax highlighting
- [ ] Validation errors shown clearly
- [ ] Preview of behavior settings visible
- [ ] Help text explains each option

---

## 10. Future Enhancements

1. **Behavior Versioning** - Track changes to behavior config over time
2. **A/B Testing** - Test different behavior configs for effectiveness
3. **Per-Agent Overrides** - Allow specific agents to override type defaults
4. **Behavior Analytics** - Track which behaviors lead to better outcomes
5. **Behavior Presets** - Pre-built behavior profiles (e.g., "Conservative", "Aggressive")
