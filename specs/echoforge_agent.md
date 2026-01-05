---
title: EchoForge Agent
version: "1.0"
status: testing
project: EchoForge Agent
created: 2025-12-29
updated: 2025-12-31
---

# 1. Executive Summary

EchoForge Agent is a FastAPI-based AI runtime engine that powers all EchoForge agent instances. It handles chat conversations, LLM interactions, knowledge base searches, and action execution. The service is stateless and horizontally scalable, fetching configuration from EchoForge Hub on each request.

---

# 2. System Architecture

## 2.1 Position in EchoForge Platform

```
┌─────────────────────────────────────────────────────────────────┐
│                      EchoForge Hub (Django)                     │
│  Configuration, Onboarding, Knowledge, Integrations, Billing    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    Config API (fetch on request)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                 EchoForge Agent (FastAPI)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────────┐ │
│  │ Chat API │  │   LLM    │  │ Actions  │  │ Vector Search   │ │
│  │Endpoints │  │ Clients  │  │ Executor │  │    Client       │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │Streaming │  │ Context  │  │  Cache   │                      │
│  │  Server  │  │ Manager  │  │  Layer   │                      │
│  └──────────┘  └──────────┘  └──────────┘                      │
└─────────────────────────────────────────────────────────────────┘
        │                              │                    │
        ▼                              ▼                    ▼
┌───────────────┐            ┌─────────────────┐   ┌──────────────┐
│  LLM APIs     │            │  External APIs  │   │  Vector DB   │
│ Claude/OpenAI │            │ CRM, Calendar   │   │   Pinecone   │
└───────────────┘            └─────────────────┘   └──────────────┘
```

## 2.2 Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | FastAPI 0.100+ |
| Python | 3.11+ |
| Async Runtime | uvicorn + asyncio |
| Cache | Redis 7+ |
| Vector DB | Pinecone or Weaviate |
| LLM | Anthropic Claude API, OpenAI API |
| HTTP Client | httpx (async) |
| Validation | Pydantic v2 |
| Streaming | Server-Sent Events (SSE) |

## 2.3 Design Principles

1. **Stateless**: No persistent state in the service; all config fetched from Hub
2. **Async-First**: All I/O operations are async for maximum concurrency
3. **Horizontally Scalable**: Multiple instances behind load balancer
4. **Fault Tolerant**: Graceful degradation when external services fail
5. **Observable**: Structured logging, metrics, tracing

---

# 3. API Specification

## 3.1 Authentication

All endpoints require authentication via API key in header:

```
Authorization: Bearer {agent_api_key}
```

The API key is validated against Hub and identifies the agent instance.

## 3.2 Chat Endpoint

### POST /v1/chat

Send a message and receive a response.

**Request:**
```json
{
    "message": "How do I reset my password?",
    "conversation_id": "conv_123",  // Optional, creates new if omitted
    "context": {                     // Optional additional context
        "user_id": "user_456",
        "user_name": "John",
        "metadata": {}
    }
}
```

**Response:**
```json
{
    "conversation_id": "conv_123",
    "message_id": "msg_789",
    "response": "To reset your password, follow these steps:\n\n1. Click on 'Forgot Password'...",
    "sources": [
        {
            "title": "Password Reset Guide",
            "url": "https://docs.example.com/password-reset",
            "relevance": 0.94
        }
    ],
    "actions_taken": [
        {
            "action": "knowledge_search",
            "status": "success"
        }
    ],
    "tokens_used": {
        "input": 234,
        "output": 156
    }
}
```

### POST /v1/chat/stream

Send a message and receive streaming response via SSE.

**Request:** Same as `/v1/chat`

**Response:** Server-Sent Events stream
```
event: message_start
data: {"conversation_id": "conv_123", "message_id": "msg_789"}

event: content_delta
data: {"delta": "To reset "}

event: content_delta
data: {"delta": "your password, "}

event: content_delta
data: {"delta": "follow these steps:"}

event: source
data: {"title": "Password Reset Guide", "url": "...", "relevance": 0.94}

event: message_end
data: {"tokens_used": {"input": 234, "output": 156}}
```

## 3.3 Conversation Management

### GET /v1/conversations/{conversation_id}

Retrieve conversation history.

**Response:**
```json
{
    "conversation_id": "conv_123",
    "created_at": "2025-01-15T10:00:00Z",
    "messages": [
        {
            "id": "msg_001",
            "role": "user",
            "content": "How do I reset my password?",
            "timestamp": "2025-01-15T10:00:00Z"
        },
        {
            "id": "msg_002",
            "role": "assistant",
            "content": "To reset your password...",
            "timestamp": "2025-01-15T10:00:01Z",
            "sources": [...]
        }
    ],
    "context": {
        "user_id": "user_456"
    }
}
```

### DELETE /v1/conversations/{conversation_id}

Delete a conversation and its history.

## 3.4 Action Endpoints

### POST /v1/actions/execute

Manually trigger an action (for testing or direct integrations).

**Request:**
```json
{
    "action": "create_ticket",
    "parameters": {
        "subject": "Password reset issue",
        "description": "User unable to reset password",
        "priority": "normal"
    }
}
```

**Response:**
```json
{
    "action": "create_ticket",
    "status": "success",
    "result": {
        "ticket_id": "TICKET-1234",
        "url": "https://zendesk.com/tickets/1234"
    }
}
```

## 3.5 Health & Status

### GET /health

Basic health check.

```json
{
    "status": "healthy",
    "version": "1.0.0",
    "uptime_seconds": 3600
}
```

### GET /health/ready

Readiness check (all dependencies available).

```json
{
    "status": "ready",
    "dependencies": {
        "hub_api": "healthy",
        "redis": "healthy",
        "llm_api": "healthy",
        "vector_db": "healthy"
    }
}
```

---

# 4. Core Components

## 4.1 Request Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Request Flow                            │
└─────────────────────────────────────────────────────────────────┘

1. Request arrives at /v1/chat
   │
2. Auth middleware validates API key
   │
3. Fetch agent config from Hub (cached)
   │
4. Load/create conversation context
   │
5. Build prompt:
   │  ├─ System prompt (from config)
   │  ├─ Conversation history
   │  ├─ Knowledge base search results
   │  └─ User message
   │
6. Call LLM API (stream or batch)
   │
7. Parse response for action triggers
   │  └─ Execute actions if needed
   │
8. Store message in conversation
   │
9. Return response (stream or JSON)
```

## 4.2 Config Manager

Fetches and caches agent configuration from Hub.

```python
class ConfigManager:
    def __init__(self, hub_client: HubClient, cache: Redis):
        self.hub_client = hub_client
        self.cache = cache
        self.cache_ttl = 300  # 5 minutes

    async def get_agent_config(self, agent_id: str) -> AgentConfig:
        """Get agent config, using cache when available."""
        cache_key = f"agent_config:{agent_id}"

        # Try cache first
        cached = await self.cache.get(cache_key)
        if cached:
            return AgentConfig.model_validate_json(cached)

        # Fetch from Hub
        config = await self.hub_client.get_agent_config(agent_id)

        # Cache for future requests
        await self.cache.setex(
            cache_key,
            self.cache_ttl,
            config.model_dump_json()
        )

        return config

    async def invalidate_config(self, agent_id: str) -> None:
        """Invalidate cached config (called via webhook from Hub)."""
        await self.cache.delete(f"agent_config:{agent_id}")
```

## 4.3 Conversation Manager

Manages conversation state and history.

```python
class ConversationManager:
    def __init__(self, cache: Redis):
        self.cache = cache
        self.history_ttl = 86400  # 24 hours
        self.max_history_messages = 50

    async def get_or_create(
        self,
        agent_id: str,
        conversation_id: str | None,
        context: dict | None
    ) -> Conversation:
        """Get existing conversation or create new one."""
        if conversation_id:
            conversation = await self.get(conversation_id)
            if conversation and conversation.agent_id == agent_id:
                return conversation

        # Create new conversation
        return Conversation(
            id=generate_conversation_id(),
            agent_id=agent_id,
            messages=[],
            context=context or {},
            created_at=datetime.utcnow()
        )

    async def add_message(
        self,
        conversation: Conversation,
        role: str,
        content: str,
        metadata: dict | None = None
    ) -> Message:
        """Add message to conversation history."""
        message = Message(
            id=generate_message_id(),
            role=role,
            content=content,
            timestamp=datetime.utcnow(),
            metadata=metadata or {}
        )

        conversation.messages.append(message)

        # Trim to max history
        if len(conversation.messages) > self.max_history_messages:
            conversation.messages = conversation.messages[-self.max_history_messages:]

        # Persist to cache
        await self.save(conversation)

        return message

    async def save(self, conversation: Conversation) -> None:
        """Persist conversation to cache."""
        key = f"conversation:{conversation.id}"
        await self.cache.setex(
            key,
            self.history_ttl,
            conversation.model_dump_json()
        )

    async def get(self, conversation_id: str) -> Conversation | None:
        """Retrieve conversation from cache."""
        key = f"conversation:{conversation_id}"
        data = await self.cache.get(key)
        if data:
            return Conversation.model_validate_json(data)
        return None
```

## 4.4 LLM Client

Abstraction layer for multiple LLM providers.

```python
from abc import ABC, abstractmethod
from typing import AsyncIterator

class LLMClient(ABC):
    @abstractmethod
    async def complete(self, messages: list[dict], **kwargs) -> str:
        """Generate a complete response."""
        pass

    @abstractmethod
    async def stream(self, messages: list[dict], **kwargs) -> AsyncIterator[str]:
        """Stream response chunks."""
        pass

class ClaudeClient(LLMClient):
    def __init__(self, api_key: str, model: str = "claude-sonnet-4-20250514"):
        self.client = anthropic.AsyncAnthropic(api_key=api_key)
        self.model = model

    async def complete(self, messages: list[dict], **kwargs) -> str:
        response = await self.client.messages.create(
            model=self.model,
            max_tokens=kwargs.get("max_tokens", 1024),
            system=kwargs.get("system"),
            messages=messages
        )
        return response.content[0].text

    async def stream(self, messages: list[dict], **kwargs) -> AsyncIterator[str]:
        async with self.client.messages.stream(
            model=self.model,
            max_tokens=kwargs.get("max_tokens", 1024),
            system=kwargs.get("system"),
            messages=messages
        ) as stream:
            async for text in stream.text_stream:
                yield text

class OpenAIClient(LLMClient):
    def __init__(self, api_key: str, model: str = "gpt-4"):
        self.client = openai.AsyncOpenAI(api_key=api_key)
        self.model = model

    async def complete(self, messages: list[dict], **kwargs) -> str:
        # Prepend system message if provided
        if kwargs.get("system"):
            messages = [{"role": "system", "content": kwargs["system"]}] + messages

        response = await self.client.chat.completions.create(
            model=self.model,
            max_tokens=kwargs.get("max_tokens", 1024),
            messages=messages
        )
        return response.choices[0].message.content

    async def stream(self, messages: list[dict], **kwargs) -> AsyncIterator[str]:
        if kwargs.get("system"):
            messages = [{"role": "system", "content": kwargs["system"]}] + messages

        stream = await self.client.chat.completions.create(
            model=self.model,
            max_tokens=kwargs.get("max_tokens", 1024),
            messages=messages,
            stream=True
        )
        async for chunk in stream:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

class LLMFactory:
    @staticmethod
    def create(provider: str, **kwargs) -> LLMClient:
        if provider == "claude":
            return ClaudeClient(**kwargs)
        elif provider == "openai":
            return OpenAIClient(**kwargs)
        else:
            raise ValueError(f"Unknown LLM provider: {provider}")
```

## 4.5 Knowledge Search

Query vector database for relevant context.

```python
class KnowledgeSearchClient:
    def __init__(self, hub_client: HubClient):
        self.hub_client = hub_client

    async def search(
        self,
        knowledge_base_id: str,
        query: str,
        top_k: int = 5,
        min_score: float = 0.7
    ) -> list[SearchResult]:
        """Search knowledge base via Hub API."""
        results = await self.hub_client.search_knowledge(
            knowledge_base_id=knowledge_base_id,
            query=query,
            top_k=top_k,
            min_score=min_score
        )

        return [
            SearchResult(
                content=r["content"],
                score=r["score"],
                metadata=r["metadata"]
            )
            for r in results
        ]

    def format_for_prompt(self, results: list[SearchResult]) -> str:
        """Format search results for inclusion in prompt."""
        if not results:
            return ""

        formatted = "Relevant information from knowledge base:\n\n"
        for i, result in enumerate(results, 1):
            formatted += f"[{i}] {result.content}\n"
            if result.metadata.get("source_url"):
                formatted += f"    Source: {result.metadata['source_url']}\n"
            formatted += "\n"

        return formatted
```

## 4.6 Action Executor

Execute actions triggered by LLM responses.

```python
class ActionExecutor:
    def __init__(self, hub_client: HubClient):
        self.hub_client = hub_client
        self.actions: dict[str, ActionHandler] = {}
        self._register_actions()

    def _register_actions(self):
        """Register all available action handlers."""
        self.actions = {
            "create_ticket": CreateTicketAction(),
            "update_ticket": UpdateTicketAction(),
            "escalate_to_human": EscalateAction(),
            "send_email": SendEmailAction(),
            "create_crm_contact": CreateCRMContactAction(),
            "book_meeting": BookMeetingAction(),
            "search_knowledge": SearchKnowledgeAction(),
            "http_webhook": WebhookAction(),
        }

    async def execute(
        self,
        action_name: str,
        agent_config: AgentConfig,
        parameters: dict
    ) -> ActionResult:
        """Execute an action with the given parameters."""
        # Check action is enabled for this agent
        if action_name not in agent_config.actions_enabled:
            return ActionResult(
                action=action_name,
                status="error",
                error="Action not enabled for this agent"
            )

        # Get handler
        handler = self.actions.get(action_name)
        if not handler:
            return ActionResult(
                action=action_name,
                status="error",
                error=f"Unknown action: {action_name}"
            )

        # Get integration credentials if needed
        credentials = None
        if handler.requires_integration:
            integration_config = agent_config.integrations.get(handler.integration_type)
            if integration_config:
                credentials = await self.hub_client.get_integration_credentials(
                    integration_config["credentials_ref"]
                )

        # Execute action
        try:
            result = await handler.execute(parameters, credentials)
            return ActionResult(
                action=action_name,
                status="success",
                result=result
            )
        except Exception as e:
            return ActionResult(
                action=action_name,
                status="error",
                error=str(e)
            )


class ActionHandler(ABC):
    requires_integration: bool = False
    integration_type: str | None = None

    @abstractmethod
    async def execute(self, parameters: dict, credentials: dict | None) -> dict:
        pass


class CreateTicketAction(ActionHandler):
    requires_integration = True
    integration_type = "ticketing"

    async def execute(self, parameters: dict, credentials: dict | None) -> dict:
        if not credentials:
            raise ValueError("Ticketing integration not configured")

        provider = credentials["provider"]

        if provider == "zendesk":
            return await self._create_zendesk_ticket(parameters, credentials)
        elif provider == "freshdesk":
            return await self._create_freshdesk_ticket(parameters, credentials)
        else:
            raise ValueError(f"Unsupported ticketing provider: {provider}")

    async def _create_zendesk_ticket(self, params: dict, creds: dict) -> dict:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"https://{creds['account_id']}.zendesk.com/api/v2/tickets",
                headers={"Authorization": f"Bearer {creds['access_token']}"},
                json={
                    "ticket": {
                        "subject": params["subject"],
                        "description": params["description"],
                        "priority": params.get("priority", "normal")
                    }
                }
            )
            response.raise_for_status()
            data = response.json()
            return {
                "ticket_id": data["ticket"]["id"],
                "url": f"https://{creds['account_id']}.zendesk.com/tickets/{data['ticket']['id']}"
            }
```

## 4.7 Prompt Builder

Construct prompts from components.

```python
class PromptBuilder:
    def __init__(self, knowledge_search: KnowledgeSearchClient):
        self.knowledge_search = knowledge_search

    async def build(
        self,
        agent_config: AgentConfig,
        conversation: Conversation,
        user_message: str
    ) -> tuple[str, list[dict], list[SearchResult]]:
        """
        Build system prompt and messages for LLM.
        Returns: (system_prompt, messages, sources)
        """
        # Start with agent's system prompt
        system_prompt = agent_config.system_prompt

        # Add user context if available
        if conversation.context:
            context_str = self._format_context(conversation.context)
            system_prompt += f"\n\nCurrent user context:\n{context_str}"

        # Search knowledge base if configured
        sources = []
        if agent_config.knowledge_base:
            sources = await self.knowledge_search.search(
                knowledge_base_id=agent_config.knowledge_base["id"],
                query=user_message,
                top_k=5
            )
            if sources:
                knowledge_context = self.knowledge_search.format_for_prompt(sources)
                system_prompt += f"\n\n{knowledge_context}"

        # Add action instructions if actions are enabled
        if agent_config.actions_enabled:
            action_instructions = self._build_action_instructions(
                agent_config.actions_enabled
            )
            system_prompt += f"\n\n{action_instructions}"

        # Build message history
        messages = []
        for msg in conversation.messages:
            messages.append({
                "role": msg.role,
                "content": msg.content
            })

        # Add current user message
        messages.append({
            "role": "user",
            "content": user_message
        })

        return system_prompt, messages, sources

    def _format_context(self, context: dict) -> str:
        """Format user context for prompt."""
        lines = []
        if context.get("user_name"):
            lines.append(f"User name: {context['user_name']}")
        if context.get("user_id"):
            lines.append(f"User ID: {context['user_id']}")
        for key, value in context.get("metadata", {}).items():
            lines.append(f"{key}: {value}")
        return "\n".join(lines)

    def _build_action_instructions(self, actions: list[str]) -> str:
        """Build action trigger instructions for LLM."""
        return """
When appropriate, you can trigger actions by including them in your response using this format:
[ACTION: action_name]
{"parameter": "value"}
[/ACTION]

Available actions:
""" + "\n".join(f"- {action}" for action in actions)
```

---

# 5. Token Optimization

## 5.1 Strategies

### Context Window Management

```python
class ContextOptimizer:
    def __init__(self, max_tokens: int = 8000):
        self.max_tokens = max_tokens

    def optimize_messages(
        self,
        messages: list[dict],
        system_prompt: str,
        reserved_for_response: int = 1024
    ) -> list[dict]:
        """Trim message history to fit context window."""
        system_tokens = self._count_tokens(system_prompt)
        available = self.max_tokens - system_tokens - reserved_for_response

        # Always keep the last (current) message
        current_message = messages[-1]
        current_tokens = self._count_tokens(current_message["content"])
        available -= current_tokens

        # Add messages from most recent, going backwards
        optimized = []
        for msg in reversed(messages[:-1]):
            msg_tokens = self._count_tokens(msg["content"])
            if msg_tokens <= available:
                optimized.insert(0, msg)
                available -= msg_tokens
            else:
                # Summarize older messages if significant
                if len(optimized) == 0:
                    summary = self._summarize_history(messages[:-1])
                    optimized.insert(0, {
                        "role": "system",
                        "content": f"Earlier conversation summary: {summary}"
                    })
                break

        optimized.append(current_message)
        return optimized

    def _count_tokens(self, text: str) -> int:
        """Approximate token count (4 chars ≈ 1 token)."""
        return len(text) // 4

    def _summarize_history(self, messages: list[dict]) -> str:
        """Create brief summary of message history."""
        # In production, could use LLM for better summaries
        topics = set()
        for msg in messages:
            # Extract key topics (simplified)
            words = msg["content"].lower().split()
            topics.update(word for word in words if len(word) > 5)

        return f"Discussion covered: {', '.join(list(topics)[:10])}"
```

### Response Caching

```python
class ResponseCache:
    def __init__(self, cache: Redis):
        self.cache = cache
        self.ttl = 3600  # 1 hour

    def _make_key(self, agent_id: str, query: str) -> str:
        """Create cache key from agent and normalized query."""
        normalized = query.lower().strip()
        query_hash = hashlib.sha256(normalized.encode()).hexdigest()[:16]
        return f"response_cache:{agent_id}:{query_hash}"

    async def get(self, agent_id: str, query: str) -> str | None:
        """Get cached response if available."""
        key = self._make_key(agent_id, query)
        return await self.cache.get(key)

    async def set(
        self,
        agent_id: str,
        query: str,
        response: str,
        cache_if_simple: bool = True
    ) -> None:
        """Cache response for simple/common queries."""
        if not cache_if_simple:
            return

        # Only cache responses that seem cacheable
        # (no personalization, no actions taken)
        key = self._make_key(agent_id, query)
        await self.cache.setex(key, self.ttl, response)
```

### Embedding Cache

```python
class EmbeddingCache:
    """Cache embeddings to avoid recomputing for repeated queries."""

    def __init__(self, cache: Redis):
        self.cache = cache
        self.ttl = 86400  # 24 hours

    async def get_or_compute(
        self,
        text: str,
        compute_fn: Callable[[str], Awaitable[list[float]]]
    ) -> list[float]:
        """Get cached embedding or compute and cache."""
        key = f"embedding:{hashlib.sha256(text.encode()).hexdigest()}"

        cached = await self.cache.get(key)
        if cached:
            return json.loads(cached)

        embedding = await compute_fn(text)
        await self.cache.setex(key, self.ttl, json.dumps(embedding))
        return embedding
```

---

# 6. Multi-Tenant Data Isolation

## 6.1 Request Scoping

Every request is scoped to a single agent instance:

```python
@app.middleware("http")
async def tenant_scope_middleware(request: Request, call_next):
    """Ensure all requests are scoped to a valid agent."""
    # Extract API key
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JSONResponse({"error": "Missing authorization"}, status_code=401)

    api_key = auth_header[7:]

    # Validate with Hub
    agent_info = await hub_client.validate_api_key(api_key)
    if not agent_info:
        return JSONResponse({"error": "Invalid API key"}, status_code=401)

    # Attach to request state
    request.state.agent_id = agent_info["agent_id"]
    request.state.customer_id = agent_info["customer_id"]

    response = await call_next(request)
    return response
```

## 6.2 Cache Namespacing

All cache keys include agent/customer identifiers:

```python
def make_cache_key(prefix: str, agent_id: str, *parts: str) -> str:
    """Create namespaced cache key."""
    return f"{prefix}:{agent_id}:{':'.join(parts)}"

# Examples:
# conversation:agent_123:conv_456
# config:agent_123
# response_cache:agent_123:abc123hash
```

## 6.3 Vector DB Namespacing

Knowledge base queries are scoped by namespace:

```python
async def search_vectors(
    knowledge_base_id: str,
    query_embedding: list[float],
    top_k: int
) -> list[dict]:
    """Search vectors within knowledge base namespace."""
    return await pinecone_client.query(
        namespace=knowledge_base_id,  # Isolates by KB
        vector=query_embedding,
        top_k=top_k,
        include_metadata=True
    )
```

---

# 7. Error Handling

## 7.1 Error Categories

| Category | HTTP Status | Retry | Example |
|----------|-------------|-------|---------|
| Authentication | 401 | No | Invalid API key |
| Authorization | 403 | No | Action not enabled |
| Validation | 400 | No | Missing required field |
| Rate Limit | 429 | Yes (with backoff) | Too many requests |
| LLM Error | 502 | Yes | Claude API timeout |
| Integration Error | 502 | Depends | Zendesk API error |
| Internal Error | 500 | Yes | Unexpected exception |

## 7.2 Graceful Degradation

```python
async def handle_chat_with_fallbacks(
    agent_config: AgentConfig,
    conversation: Conversation,
    user_message: str
) -> ChatResponse:
    """Handle chat with graceful degradation on failures."""

    # Try knowledge search (non-critical)
    sources = []
    try:
        if agent_config.knowledge_base:
            sources = await knowledge_search.search(
                agent_config.knowledge_base["id"],
                user_message
            )
    except Exception as e:
        logger.warning(f"Knowledge search failed: {e}")
        # Continue without knowledge context

    # Build prompt
    system_prompt, messages, _ = await prompt_builder.build(
        agent_config, conversation, user_message
    )

    # Try primary LLM
    try:
        response = await llm_client.complete(messages, system=system_prompt)
    except Exception as e:
        logger.error(f"Primary LLM failed: {e}")

        # Try fallback LLM if configured
        if fallback_llm:
            try:
                response = await fallback_llm.complete(messages, system=system_prompt)
            except Exception as e2:
                logger.error(f"Fallback LLM also failed: {e2}")
                return ChatResponse(
                    response="I'm sorry, I'm having trouble responding right now. Please try again in a moment.",
                    error="LLM service unavailable"
                )

    # Try to execute any actions (non-critical)
    actions_taken = []
    for action in parse_actions(response):
        try:
            result = await action_executor.execute(
                action.name,
                agent_config,
                action.parameters
            )
            actions_taken.append(result)
        except Exception as e:
            logger.warning(f"Action {action.name} failed: {e}")
            actions_taken.append(ActionResult(
                action=action.name,
                status="error",
                error=str(e)
            ))

    return ChatResponse(
        response=response,
        sources=sources,
        actions_taken=actions_taken
    )
```

---

# 8. Observability

## 8.1 Logging

```python
import structlog

logger = structlog.get_logger()

@app.middleware("http")
async def logging_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())

    # Bind context for all log messages in this request
    structlog.contextvars.bind_contextvars(
        request_id=request_id,
        agent_id=getattr(request.state, "agent_id", None),
        path=request.url.path
    )

    start_time = time.time()
    response = await call_next(request)
    duration_ms = (time.time() - start_time) * 1000

    logger.info(
        "request_completed",
        status_code=response.status_code,
        duration_ms=duration_ms
    )

    response.headers["X-Request-ID"] = request_id
    return response
```

## 8.2 Metrics

Key metrics to track:

| Metric | Type | Labels |
|--------|------|--------|
| `chat_requests_total` | Counter | agent_id, status |
| `chat_request_duration_seconds` | Histogram | agent_id |
| `llm_tokens_used` | Counter | agent_id, direction (in/out) |
| `llm_request_duration_seconds` | Histogram | provider |
| `action_executions_total` | Counter | action, status |
| `knowledge_search_duration_seconds` | Histogram | agent_id |
| `cache_hits_total` | Counter | cache_type |
| `cache_misses_total` | Counter | cache_type |

## 8.3 Tracing

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

async def handle_chat(request: ChatRequest) -> ChatResponse:
    with tracer.start_as_current_span("chat_request") as span:
        span.set_attribute("agent_id", request.state.agent_id)

        with tracer.start_span("fetch_config"):
            config = await config_manager.get_agent_config(...)

        with tracer.start_span("knowledge_search"):
            sources = await knowledge_search.search(...)

        with tracer.start_span("llm_completion"):
            response = await llm_client.complete(...)

        return ChatResponse(response=response, sources=sources)
```

---

# 9. Deployment

## 9.1 Container Configuration

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ ./app/

# Run with uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

## 9.2 Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `HUB_API_URL` | EchoForge Hub internal API URL | Yes |
| `HUB_SERVICE_SECRET` | Service-to-service auth secret | Yes |
| `REDIS_URL` | Redis connection URL | Yes |
| `ANTHROPIC_API_KEY` | Claude API key | Yes* |
| `OPENAI_API_KEY` | OpenAI API key | Yes* |
| `DEFAULT_LLM_PROVIDER` | "claude" or "openai" | No (default: claude) |
| `LOG_LEVEL` | Logging level | No (default: INFO) |
| `CORS_ORIGINS` | Allowed CORS origins | No |

*At least one LLM API key required

## 9.3 Scaling

```yaml
# Kubernetes HPA example
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: echoforge-agent
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: echoforge-agent
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"
```

---

# 10. Implementation Approach

## 10.1 Recommended Phases

**Phase 1: Foundation (1 week)**
1. Project setup (FastAPI, Redis, Docker)
2. Basic health endpoints
3. API key validation with Hub
4. Request/response models

**Phase 2: Chat Core (2 weeks)**
1. Config fetching from Hub
2. Conversation manager
3. LLM client abstraction (Claude + OpenAI)
4. Basic chat endpoint (non-streaming)
5. Prompt builder

**Phase 3: Streaming (1 week)**
1. SSE implementation
2. Streaming chat endpoint
3. Client reconnection handling

**Phase 4: Knowledge Search (1 week)**
1. Hub knowledge API client
2. Search result formatting
3. Context injection

**Phase 5: Actions (2 weeks)**
1. Action executor framework
2. Action parsing from LLM responses
3. Integration credential fetching
4. Initial actions (ticket, email, webhook)

**Phase 6: Optimization (1 week)**
1. Response caching
2. Context window optimization
3. Embedding caching

**Phase 7: Production Readiness (1 week)**
1. Comprehensive error handling
2. Structured logging
3. Metrics endpoints
4. Rate limiting
5. Load testing

## 10.2 Dependencies

| Dependency | Notes |
|------------|-------|
| EchoForge Hub | Must be running for config/credentials |
| Redis | Required for caching and conversations |
| LLM API | At least one provider needed |
| Vector DB | Pinecone/Weaviate for knowledge search |

---

# 11. Acceptance Criteria

## 11.1 Core Chat

- [ ] Chat endpoint returns valid responses
- [ ] Streaming endpoint delivers chunks correctly
- [ ] Conversation history maintained
- [ ] System prompt applied correctly

## 11.2 Configuration

- [ ] Agent config fetched from Hub
- [ ] Config cached appropriately
- [ ] Config invalidation works via webhook

## 11.3 Knowledge Search

- [ ] Queries return relevant results
- [ ] Results included in prompt
- [ ] Sources returned with response

## 11.4 Actions

- [ ] Actions parsed from LLM responses
- [ ] Actions executed with correct credentials
- [ ] Action results returned in response
- [ ] Failed actions handled gracefully

## 11.5 Performance

- [ ] Streaming latency < 200ms to first chunk
- [ ] Non-streaming response < 5s p95
- [ ] 100+ concurrent conversations supported
- [ ] Cache hit rate > 80% for config

## 11.6 Reliability

- [ ] Graceful degradation on LLM failure
- [ ] Graceful degradation on knowledge search failure
- [ ] Rate limiting enforced
- [ ] All errors return structured responses

---

*End of Specification*
