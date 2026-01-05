---
title: Tool Categories Architecture - Agent Specification
version: "1.0"
status: draft
project: EchoForge Agent
created: 2026-01-01
updated: 2026-01-01
related:
  - tool_categories_hub.md
  - internal_api_contract.md
  - echoforge_agent.md
---

# 1. Executive Summary

This specification defines the Agent's responsibility in the Tool Categories architecture. The Agent is a **tool execution engine** that:

1. Receives configuration from Hub (including computed `enabled_actions`)
2. Exposes enabled tools to the LLM
3. Executes tool calls by routing to Hub
4. Does **not** maintain its own tool configuration

The Hub is the single source of truth for which tools are available. The Agent's role is to register all possible tools, expose the Hub-configured subset to Claude, and execute them.

---

# 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AGENT (Execution Engine)                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ToolRegistry                                                         │   │
│  │                                                                      │   │
│  │ Registers ALL tools the Agent can execute:                           │   │
│  │ - email_send, email_search, email_read, ...                          │   │
│  │ - calendar_list_events, calendar_create_event, ...                   │   │
│  │ - mission_create_task, mission_ask_user, ...                         │   │
│  │ - research_web_search, research_fetch_page, ...                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ AgentTypeHandler                                                     │   │
│  │                                                                      │   │
│  │ get_tool_definitions():                                              │   │
│  │   - Uses config.actions_enabled (from Hub)                           │   │
│  │   - NOT hardcoded list                                               │   │
│  │                                                                      │   │
│  │ execute_tool():                                                      │   │
│  │   - Validates tool is in config.actions_enabled                      │   │
│  │   - Routes to Hub for execution                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
                      ┌─────────────────────────────────────┐
                      │            HUB                       │
                      │                                      │
                      │ GET /api/internal/agent/{id}/config  │
                      │   → enabled_actions: [...]           │
                      │   → integrations: {...}              │
                      │                                      │
                      │ POST /api/internal/tools/execute/    │
                      │   → Routes to correct provider       │
                      └─────────────────────────────────────┘
```

---

# 3. Key Principle: Hub as Source of Truth

**Current Problem:**
```python
# personal_assistant.py - CURRENT (BAD)
PERSONAL_ASSISTANT_TOOLS = [
    "calendar_list_events",
    "calendar_create_event",
    # ... hardcoded list
]

class PersonalAssistantHandler:
    tools_enabled = PERSONAL_ASSISTANT_TOOLS  # Hardcoded!

    def get_tool_definitions(self):
        for tool in self.tools_enabled:  # Uses hardcoded list
            ...
```

**New Approach:**
```python
# personal_assistant.py - NEW (GOOD)
class PersonalAssistantHandler:
    # NO hardcoded tools_enabled list

    def get_tool_definitions(self):
        # Use Hub config - this is the source of truth
        for tool in self.config.actions_enabled:
            ...
```

---

# 4. Code Changes

## 4.1 Remove Hardcoded Tool Lists

```python
# src/services/agent_types/personal_assistant.py

# REMOVE this constant entirely:
# PERSONAL_ASSISTANT_TOOLS = [...]

@register_agent_type
class PersonalAssistantHandler(AgentTypeHandler):
    agent_type = "personal_assistant"

    # REMOVE: tools_enabled = PERSONAL_ASSISTANT_TOOLS

    # Feature flags remain (these are behavioral, not tool lists)
    missions_enabled = True
    async_tasks_enabled = True
    human_approval_enabled = True

    def get_tool_definitions(self) -> List[Dict[str, Any]]:
        """
        Get Claude tool definitions for enabled tools.

        Tools are determined by Hub configuration, not hardcoded lists.
        """
        definitions = []

        # Use Hub config as source of truth
        for tool_name in self.config.actions_enabled:
            tool_class = ToolRegistry.get(tool_name)
            if tool_class:
                definitions.append({
                    "name": tool_name,
                    "description": tool_class.description,
                    "input_schema": tool_class.input_schema,
                })
            else:
                logger.warning(
                    "tool_not_in_registry",
                    tool_name=tool_name,
                    agent_type=self.agent_type,
                    hint="Hub enabled a tool that Agent doesn't have registered"
                )

        return definitions

    async def execute_tool(
        self,
        tool_name: str,
        inputs: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Execute a tool call from the LLM.
        """
        # Validate against Hub config (not hardcoded list)
        if tool_name not in self.config.actions_enabled:
            logger.warning(
                "tool_not_enabled",
                tool_name=tool_name,
                enabled_tools=self.config.actions_enabled,
            )
            return {
                "success": False,
                "error": f"Tool '{tool_name}' is not enabled for this agent",
            }

        # Validate tool exists in registry
        tool_class = ToolRegistry.get(tool_name)
        if not tool_class:
            return {
                "success": False,
                "error": f"Tool '{tool_name}' not found in registry",
            }

        # Create and execute tool
        tool = ToolRegistry.create(
            name=tool_name,
            hub_client=self.hub_client,
            user_id=self.user_id,
            mission_id=self.mission_id,
            cache_service=self.cache_service,
            conversation_id=self.conversation_id,
            agent_id=str(self.config.agent_id),
            customer_id=str(self.config.customer_id),
        )

        try:
            result = await tool.execute(inputs)
            return {
                "success": result.success,
                "data": result.data,
                "error": result.error,
                "requires_approval": result.requires_approval,
                "approval_request_id": result.approval_request_id,
            }
        except Exception as e:
            logger.error("tool_execution_error", tool_name=tool_name, error=str(e))
            return {
                "success": False,
                "error": f"Tool execution failed: {str(e)}",
            }
```

## 4.2 Update Base Handler

```python
# src/services/agent_types/base.py

class AgentTypeHandler(ABC):
    """
    Base class for agent type handlers.
    """

    agent_type: str = ""

    # REMOVE: tools_enabled: List[str] = []
    # Tools come from config.actions_enabled

    # Feature flags (behavioral, not tool lists)
    missions_enabled: bool = False
    async_tasks_enabled: bool = False
    human_approval_enabled: bool = False

    def __init__(
        self,
        config: AgentConfig,
        hub_client: Any,
        user_id: Optional[str] = None,
        mission_id: Optional[str] = None,
    ):
        self.config = config
        self.hub_client = hub_client
        self.user_id = user_id
        self.mission_id = mission_id

    @abstractmethod
    def get_orchestrator_prompt(self) -> str:
        """Get the system prompt for this agent type."""
        pass

    def get_tool_definitions(self) -> List[Dict[str, Any]]:
        """
        Get Claude tool definitions for enabled tools.

        Default implementation uses config.actions_enabled.
        Override if agent type needs custom behavior.
        """
        definitions = []

        for tool_name in self.config.actions_enabled:
            tool_class = ToolRegistry.get(tool_name)
            if tool_class:
                instance = tool_class(None, "")
                definitions.append(instance.to_claude_tool_definition())

        return definitions

    @abstractmethod
    async def execute_tool(
        self,
        tool_name: str,
        inputs: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Execute a tool call from the LLM."""
        pass
```

## 4.3 Ensure All Tools Are Registered

The ToolRegistry must have all tools registered regardless of agent type. Registration happens via the `@ToolRegistry.register` decorator.

```python
# src/services/tools/__init__.py

# All tools must be imported to trigger registration
from .calendar_tools import (
    CalendarCreateEventTool,
    CalendarDeleteEventTool,
    CalendarFindOptimalTimesTool,
    CalendarGetAvailabilityTool,
    CalendarListEventsTool,
    CalendarUpdateEventTool,
)
from .email_tools import (
    EmailCheckRepliesTool,
    EmailParseReplyTool,
    EmailReadTool,
    EmailSearchTool,
    EmailSendFollowupTool,
    EmailSendTool,
)
from .mission_tools import (
    MissionAskUserTool,
    MissionCompleteTool,
    MissionCreateTaskTool,
)
from .research_tools import (
    ResearchFetchPageTool,
    ResearchSummarizeTool,
    ResearchWebSearchTool,
)
from .document_tools import (
    DocumentCreateTool,
    DocumentEditTool,
    DocumentGetTool,
)

# Future tools will be added here
# from .crm_tools import ...
# from .ticketing_tools import ...
```

## 4.4 Update Config Model

Ensure `AgentConfig` properly maps Hub's response:

```python
# src/models/config.py

class AgentConfig(BaseModel):
    """
    Complete agent configuration from Hub.
    """
    agent_id: str = Field(alias="id")
    agent_type: str = Field(alias="agent_type_slug")
    customer_id: str

    identity: Dict[str, Any] = Field(alias="identity_config")
    system_prompt: str

    knowledge_base: Optional[Dict[str, Any]] = None
    integrations: Dict[str, Any] = Field(default_factory=dict)

    # Hub computes this from categories + integrations
    # Agent just uses it as-is
    actions_enabled: List[str] = Field(default=[], alias="enabled_actions")

    rate_limits: Dict[str, int] = Field(default={}, alias="limits")
    embed_domains: List[str] = []
    billing: Dict[str, Any] = Field(default_factory=lambda: {"can_respond": True})
    config_version: str = "1"

    # Additional fields
    name: Optional[str] = None
    slug: Optional[str] = None
    customer_name: Optional[str] = None
    custom_config: Dict[str, Any] = {}
    plan: Optional[str] = None

    class Config:
        populate_by_name = True
```

---

# 5. Dynamic Prompt Updates

The orchestrator prompt should also reflect available tools dynamically:

```python
# src/services/agent_types/personal_assistant.py

ORCHESTRATOR_PROMPT_TEMPLATE = """You are a personal assistant orchestrating complex tasks.

RESPONSIBILITIES:
1. UNDERSTAND - Parse requests, identify intent, ask clarifying questions
2. PLAN - Break down into tasks with clear dependencies
3. EXECUTE - Call appropriate tools to complete each task
4. MONITOR - Track progress, detect failures, handle blocked states
5. SYNTHESIZE - Aggregate results and report back to user

AVAILABLE TOOLS:
{available_tools}

Current user: {user_name}
Current time: {current_time}
User timezone: {user_timezone}"""


class PersonalAssistantHandler(AgentTypeHandler):
    def get_orchestrator_prompt(self) -> str:
        """
        Get the orchestrator system prompt with available tools.
        """
        # Build tools section dynamically from config
        tools_by_category = self._group_tools_by_category()
        tools_section = self._format_tools_section(tools_by_category)

        return ORCHESTRATOR_PROMPT_TEMPLATE.format(
            available_tools=tools_section,
            user_name=self.user_name,
            current_time=self._get_current_time(),
            user_timezone=self.user_timezone,
        )

    def _group_tools_by_category(self) -> Dict[str, List[str]]:
        """Group enabled tools by category prefix."""
        categories = {}
        for tool in self.config.actions_enabled:
            # Extract category from tool name (e.g., "calendar_list_events" -> "Calendar")
            prefix = tool.split('_')[0].title()
            if prefix not in categories:
                categories[prefix] = []
            # Format tool name for prompt (e.g., "list_events")
            action = '_'.join(tool.split('_')[1:])
            categories[prefix].append(action)
        return categories

    def _format_tools_section(self, categories: Dict[str, List[str]]) -> str:
        """Format tools section for prompt."""
        lines = []
        for category, actions in sorted(categories.items()):
            actions_str = ', '.join(actions)
            lines.append(f"- {category}: {actions_str}")
        return '\n'.join(lines)
```

---

# 6. Tool Execution Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 1. LLM Response                                                          │
│    Claude returns: tool_use("calendar_create_event", {...})              │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 2. Agent Validation                                                      │
│                                                                          │
│    if tool_name not in self.config.actions_enabled:                      │
│        return error("Tool not enabled")                                  │
│                                                                          │
│    if tool_name not in ToolRegistry:                                     │
│        return error("Tool not registered")                               │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 3. Tool Execution                                                        │
│                                                                          │
│    tool = ToolRegistry.create(tool_name, ...)                            │
│    result = await tool.execute(inputs)                                   │
│                                                                          │
│    Most tools call Hub:                                                  │
│    POST /api/internal/tools/execute/                                     │
│    {                                                                     │
│        "tool": "calendar_create_event",                                  │
│        "agent_id": "...",                                                │
│        "customer_id": "...",                                             │
│        "inputs": {...}                                                   │
│    }                                                                     │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 4. Hub Routes to Provider                                                │
│                                                                          │
│    Hub looks up customer's integration for "calendar" category           │
│    → Routes to GoogleCalendarService or OutlookCalendarService           │
│    → Returns result                                                      │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ 5. Result to LLM                                                         │
│                                                                          │
│    Agent returns tool_result to Claude                                   │
│    Claude continues conversation                                         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

# 7. Error Handling

## 7.1 Tool Not Enabled

When Claude tries to use a tool that's not in `config.actions_enabled`:

```python
async def execute_tool(self, tool_name: str, inputs: Dict[str, Any]):
    if tool_name not in self.config.actions_enabled:
        logger.warning(
            "llm_called_disabled_tool",
            tool_name=tool_name,
            enabled_tools=self.config.actions_enabled,
        )
        return {
            "success": False,
            "error": f"Tool '{tool_name}' is not available. Available tools: {', '.join(self.config.actions_enabled)}",
        }
```

## 7.2 Tool Not Registered

When Hub enables a tool that Agent doesn't have in its registry:

```python
def get_tool_definitions(self):
    for tool_name in self.config.actions_enabled:
        tool_class = ToolRegistry.get(tool_name)
        if not tool_class:
            logger.error(
                "hub_enabled_unknown_tool",
                tool_name=tool_name,
                hint="Hub configuration references a tool not registered in Agent. "
                     "Either add the tool to ToolRegistry or remove from Hub config."
            )
            # Skip this tool - don't expose to LLM
            continue
```

## 7.3 Hub Tool Execution Failure

```python
async def execute_tool(self, tool_name: str, inputs: Dict[str, Any]):
    try:
        result = await tool.execute(inputs)
        return result
    except HubConnectionError as e:
        logger.error("hub_unreachable", tool_name=tool_name, error=str(e))
        return {
            "success": False,
            "error": "Unable to execute tool - service temporarily unavailable. Please try again.",
        }
    except HubAuthError as e:
        logger.error("hub_auth_failed", tool_name=tool_name, error=str(e))
        return {
            "success": False,
            "error": "Authentication error. Please reconnect your integration.",
        }
```

---

# 8. Testing

## 8.1 Unit Tests

```python
# tests/test_agent_types/test_personal_assistant.py

import pytest
from unittest.mock import Mock, patch
from src.services.agent_types.personal_assistant import PersonalAssistantHandler
from src.models.config import AgentConfig


class TestPersonalAssistantHandler:
    @pytest.fixture
    def config_with_email_only(self):
        return AgentConfig(
            id="agent-123",
            agent_type_slug="personal_assistant",
            customer_id="customer-456",
            identity_config={"name": "Test Agent"},
            system_prompt="You are a test agent.",
            enabled_actions=["email_send", "email_search"],
        )

    @pytest.fixture
    def config_with_all_tools(self):
        return AgentConfig(
            id="agent-123",
            agent_type_slug="personal_assistant",
            customer_id="customer-456",
            identity_config={"name": "Test Agent"},
            system_prompt="You are a test agent.",
            enabled_actions=[
                "email_send", "email_search",
                "calendar_list_events", "calendar_create_event",
                "mission_create_task", "mission_complete",
            ],
        )

    def test_get_tool_definitions_uses_config(self, config_with_email_only):
        """Tool definitions come from config, not hardcoded list."""
        handler = PersonalAssistantHandler(
            config=config_with_email_only,
            hub_client=Mock(),
        )

        definitions = handler.get_tool_definitions()

        # Should only include email tools from config
        tool_names = [d["name"] for d in definitions]
        assert "email_send" in tool_names
        assert "email_search" in tool_names
        assert "calendar_list_events" not in tool_names

    def test_get_tool_definitions_all_tools(self, config_with_all_tools):
        """All configured tools are exposed."""
        handler = PersonalAssistantHandler(
            config=config_with_all_tools,
            hub_client=Mock(),
        )

        definitions = handler.get_tool_definitions()
        tool_names = [d["name"] for d in definitions]

        assert len(tool_names) == 6
        assert "email_send" in tool_names
        assert "calendar_list_events" in tool_names
        assert "mission_create_task" in tool_names

    async def test_execute_tool_rejects_disabled(self, config_with_email_only):
        """Disabled tools are rejected."""
        handler = PersonalAssistantHandler(
            config=config_with_email_only,
            hub_client=Mock(),
        )

        result = await handler.execute_tool(
            "calendar_list_events",
            {"start_date": "2026-01-01"},
        )

        assert result["success"] is False
        assert "not enabled" in result["error"]

    async def test_execute_tool_allows_enabled(self, config_with_email_only):
        """Enabled tools are executed."""
        mock_hub = Mock()
        mock_hub.post.return_value = {"success": True, "result": {"sent": True}}

        handler = PersonalAssistantHandler(
            config=config_with_email_only,
            hub_client=mock_hub,
        )

        with patch('src.services.tools.ToolRegistry.create') as mock_create:
            mock_tool = Mock()
            mock_tool.execute.return_value = Mock(
                success=True,
                data={"sent": True},
                error=None,
                requires_approval=False,
                approval_request_id=None,
            )
            mock_create.return_value = mock_tool

            result = await handler.execute_tool(
                "email_send",
                {"to": "test@example.com", "subject": "Test"},
            )

        assert result["success"] is True

    def test_unknown_tool_logged_but_skipped(self, caplog):
        """Unknown tools from Hub config are logged and skipped."""
        config = AgentConfig(
            id="agent-123",
            agent_type_slug="personal_assistant",
            customer_id="customer-456",
            identity_config={},
            system_prompt="Test",
            enabled_actions=["email_send", "unknown_future_tool"],
        )

        handler = PersonalAssistantHandler(config=config, hub_client=Mock())
        definitions = handler.get_tool_definitions()

        # Only known tool should be included
        tool_names = [d["name"] for d in definitions]
        assert "email_send" in tool_names
        assert "unknown_future_tool" not in tool_names

        # Warning should be logged
        assert "tool_not_in_registry" in caplog.text
```

## 8.2 Integration Tests

```python
# tests/integration/test_tool_flow.py

import pytest
from httpx import AsyncClient


@pytest.mark.integration
async def test_full_tool_execution_flow(test_client: AsyncClient, test_agent_config):
    """
    End-to-end test: Agent fetches config, exposes tools, executes via Hub.
    """
    # 1. Get config from Hub
    config_response = await test_client.get(
        f"/api/internal/agent/{test_agent_config['agent_id']}/config",
        headers={"Authorization": f"Bearer {HUB_SERVICE_SECRET}"},
    )
    assert config_response.status_code == 200
    config = config_response.json()

    # 2. Verify enabled_actions matches expected categories
    assert "calendar_list_events" in config["enabled_actions"]

    # 3. Execute a tool
    tool_response = await test_client.post(
        "/api/internal/tools/execute/",
        headers={"Authorization": f"Bearer {HUB_SERVICE_SECRET}"},
        json={
            "tool": "calendar_list_events",
            "agent_id": test_agent_config["agent_id"],
            "customer_id": test_agent_config["customer_id"],
            "inputs": {
                "start_date": "2026-01-01",
                "end_date": "2026-01-07",
            },
        },
    )
    assert tool_response.status_code == 200
    result = tool_response.json()
    assert result["success"] is True
```

---

# 9. Migration Path

## 9.1 Phase 1: Parallel Support (Non-Breaking)

Keep hardcoded list as fallback while transitioning:

```python
class PersonalAssistantHandler(AgentTypeHandler):
    # Keep for fallback during migration
    _default_tools = [
        "calendar_list_events",
        "calendar_create_event",
        # ...
    ]

    def get_tool_definitions(self):
        # Prefer Hub config, fall back to defaults
        tools = self.config.actions_enabled
        if not tools:
            logger.warning("no_tools_from_hub_using_defaults")
            tools = self._default_tools

        definitions = []
        for tool_name in tools:
            # ... build definitions
```

## 9.2 Phase 2: Hub Required

Once Hub always sends `enabled_actions`:

```python
class PersonalAssistantHandler(AgentTypeHandler):
    # REMOVE: _default_tools

    def get_tool_definitions(self):
        if not self.config.actions_enabled:
            logger.error("hub_config_missing_enabled_actions")
            return []

        # ... build definitions from config only
```

## 9.3 Phase 3: Cleanup

- Remove all hardcoded tool lists
- Remove `tools_enabled` from base class
- Update all agent type handlers

---

# 10. Implementation Checklist

## 10.1 Code Changes

- [ ] Remove `PERSONAL_ASSISTANT_TOOLS` constant
- [ ] Remove `tools_enabled` class attribute from handlers
- [ ] Update `get_tool_definitions()` to use `config.actions_enabled`
- [ ] Update `execute_tool()` to validate against `config.actions_enabled`
- [ ] Update orchestrator prompt to list tools dynamically
- [ ] Add logging for unknown tools from Hub config
- [ ] Ensure all tools are registered in `ToolRegistry`

## 10.2 Testing

- [ ] Unit tests for config-driven tool definitions
- [ ] Unit tests for tool execution validation
- [ ] Unit tests for unknown tool handling
- [ ] Integration tests for full flow
- [ ] Manual testing with different agent configurations

## 10.3 Documentation

- [ ] Update inline code documentation
- [ ] Update API documentation
- [ ] Add migration notes for developers

---

# 11. Acceptance Criteria

- [ ] Agent uses `config.actions_enabled` for tool definitions (not hardcoded list)
- [ ] Agent rejects tool calls not in `config.actions_enabled`
- [ ] Agent logs warnings for unknown tools from Hub
- [ ] Agent handles empty `actions_enabled` gracefully
- [ ] Orchestrator prompt reflects available tools dynamically
- [ ] All existing tools remain registered in ToolRegistry
- [ ] Tests pass with config-driven tool selection
- [ ] No hardcoded tool lists in agent type handlers

---

# 12. Dependency on Hub

This specification depends on Hub changes from `tool_categories_hub.md`:

1. Hub must compute `enabled_actions` from categories + integrations
2. Hub config API must return computed `enabled_actions` list
3. Hub tool execution endpoint must route by category

**Coordination required:**
- Hub deploys category-based config first
- Agent can deploy once Hub returns valid `enabled_actions`
- During transition, Agent can fall back to defaults if `enabled_actions` is empty

---

*End of Agent Specification*
