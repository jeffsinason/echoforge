# Category: {Category Name}

> **Status:** Draft | Review | Approved
> **Last Updated:** YYYY-MM-DD
> **Owner:** {Team/Person}

## 1. Overview

### 1.1 Purpose

{Brief description of what this category enables users to do}

### 1.2 Classification

| Attribute | Value |
|-----------|-------|
| **Type** | `integration` / `capability` |
| **Billing** | `included` / `metered` / `addon` |
| **Min Plan** | `starter` / `professional` / `enterprise` |
| **Meter Name** | {If metered: e.g., `research_queries`} |

### 1.3 Dependencies

- {List any dependencies on other categories or systems}

---

## 2. Tools

### 2.1 Tool Summary

| Tool Name | Description | Async | Approval |
|-----------|-------------|-------|----------|
| `{category}_{action}` | {What it does} | Yes/No | Required/Optional/No |

### 2.2 Tool Definitions

#### `{category}_{action}`

**Description:** {Detailed description}

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "param1": {
      "type": "string",
      "description": "Description of param1"
    }
  },
  "required": ["param1"]
}
```

**Output Schema:**
```json
{
  "success": true,
  "data": {
    "field1": "value"
  }
}
```

**Error Cases:**
- `{error_code}`: {When this occurs}

---

## 3. Providers

> *Skip this section for `capability` type categories*

### 3.1 Provider Summary

| Provider | Slug | Status | Notes |
|----------|------|--------|-------|
| {Provider Name} | `{slug}` | Implemented / Planned | {Any limitations} |

### 3.2 Provider Details

#### {Provider Name}

**OAuth Scopes Required:**
- `scope.one` - {Why needed}
- `scope.two` - {Why needed}

**API Endpoints Used:**
- `POST /api/endpoint` - {Purpose}

**Rate Limits:**
- {Limit details}

**Provider-Specific Behavior:**
- {Any differences from abstract tool behavior}

---

## 4. Logic Flows

### 4.1 State Machine

> *For categories with complex state (e.g., missions, async operations)*

```
┌─────────┐
│ State A │
└────┬────┘
     │ event
     ▼
┌─────────┐
│ State B │
└─────────┘
```

### 4.2 Approval Workflows

> *For categories requiring human-in-the-loop*

**When Approval Required:**
- {Condition 1}
- {Condition 2}

**Approval Flow:**
```
{Flow diagram}
```

### 4.3 Async Patterns

> *For operations that wait for external events*

**Wait Conditions:**
- {What triggers wait}

**Resume Triggers:**
- {What resumes execution}

**Timeout Handling:**
- {What happens on timeout}

---

## 5. UI/UX

### 5.1 Chat Interface

**Inline Components:**
- {Component 1}: {When shown, what it does}

**Message Formats:**
- {Message type}: {Format/template}

### 5.2 Dashboard Components

**Widget/Page:** {Name}

```
┌─────────────────────────────────────┐
│ {Wireframe or description}          │
└─────────────────────────────────────┘
```

**User Actions:**
- {Action 1}: {What it does}

### 5.3 Notifications

| Event | Chat | Dashboard | Email | Push |
|-------|------|-----------|-------|------|
| {Event} | {Yes/No} | {Yes/No} | {Condition} | {Condition} |

---

## 6. Hub Implementation

### 6.1 Models

```python
# apps/{app}/models.py

class {ModelName}(BaseModel):
    """Description"""
    field = models.Field()
```

### 6.2 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/{resource}/` | {Description} |

### 6.3 Services

```python
# apps/{app}/services/{service}.py

class {ServiceName}:
    """Description"""

    def method(self):
        pass
```

---

## 7. Agent Implementation

### 7.1 Tool Classes

```python
# src/services/tools/{category}_tools.py

class {ToolName}Tool(BaseTool):
    """Description"""

    name = "{category}_{action}"
    description = "..."

    async def execute(self, inputs: Dict) -> ToolResult:
        pass
```

### 7.2 Integration with Handler

{How the agent type handler uses these tools}

---

## 8. Testing

### 8.1 Unit Tests

- [ ] {Test case 1}
- [ ] {Test case 2}

### 8.2 Integration Tests

- [ ] {Test case 1}

### 8.3 E2E Scenarios

- [ ] {Scenario 1}

---

## 9. Future Considerations

- {Planned enhancement 1}
- {Planned enhancement 2}

---

## 10. Changelog

| Date | Change | Author |
|------|--------|--------|
| YYYY-MM-DD | Initial draft | {Name} |
