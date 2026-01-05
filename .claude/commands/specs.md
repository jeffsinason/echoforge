# /specs - Feature Specification Manager

Manage feature specifications stored in `specs/` for the EchoForge Platform.

## Arguments
- No arguments: List all specs grouped by status
- `show <filename>`: Display a spec's contents in formatted view
- `work <filename>`: Start working on an approved spec
- `complete <filename>`: Mark a spec as testing/deployed
- `dashboard`: Show Kanban-style board
- `create <filename>`: Create new spec from template

---

## IMPORTANT: Use the specs.py CLI Tool

**All spec operations use the shared `specs.py` CLI tool:**

```bash
# List all specs
python3 ../tools/specs.py list

# List specs filtered by status
python3 ../tools/specs.py list --status approved

# Show spec details
python3 ../tools/specs.py show <filename>

# Change spec status
python3 ../tools/specs.py status <filename> <new_status>

# Show Kanban dashboard
python3 ../tools/specs.py dashboard

# Create new spec from template
python3 ../tools/specs.py create <filename>
```

**DO NOT write inline Python code to parse specs.** Always use the tool.

---

## Show Mode: `/specs show <filename>`

Run:
```bash
python3 ../tools/specs.py show <filename>
```

The tool handles partial filename matching automatically.

---

## List Mode (default)

When run without arguments, execute:
```bash
python3 ../tools/specs.py list
```

Or for the dashboard view:
```bash
python3 ../tools/specs.py dashboard
```

---

## Work Mode: `/specs work [filename]`

**If filename is NOT provided:**

1. List approved specs using:
   ```bash
   python3 ../tools/specs.py list --status approved
   ```
2. If no approved specs exist: Inform user "No approved specs available. Use `/specs` to see all specs and their statuses."
3. If approved specs exist: Use the AskUserQuestion tool to let the user select which spec to work on
4. Once user selects, continue with steps below using the selected filename

**If filename IS provided:**

1. Show the spec details:
   ```bash
   python3 ../tools/specs.py show <filename>
   ```
2. Verify the status is `approved`. If not, inform user.

3. Update the status to in-development:
   ```bash
   python3 ../tools/specs.py status <filename> in_development
   ```

4. Display the spec summary:
   - Title
   - Version
   - Key requirements (bullet summary)

5. **Codebase Research Phase**

   Use the Task tool with subagent_type=Explore to understand the current system state:
   - For hub-related work: explore `hub/` directory
   - For agent-related work: explore `agent/` directory
   - For cross-component work: explore both

   Wait for research to complete before proceeding.
   Summarize the research findings briefly (3-5 bullet points).

6. **Create Implementation Plan**

   Create a todo list based on:
   - The spec requirements (from the document)
   - The codebase research findings
   - Logical implementation order
   - Dependencies between components

7. **Begin Implementation**

   Work through todo items systematically:
   - Implement each component according to the spec
   - Run tests after completing major components
   - Update todo status as you progress
   - If blocked, note the blocker and continue with other items

8. **Pre-Completion Verification**

   Before reporting complete:
   - Run full test suite for affected components
   - Review each acceptance criterion from the spec
   - Confirm all are met
   - Note any deviations or decisions made during implementation

---

## Complete Mode: `/specs complete <filename>`

1. Show current spec status:
   ```bash
   python3 ../tools/specs.py show <filename>
   ```

2. Verify the status is `in_development` or `testing`. If not, inform user.

3. Run final verification:
   - Run full test suite for affected apps
   - If tests fail, report and do not complete

4. Ask the user which status to set:
   - If current status is `in_development`: "Mark this spec as 'testing' or 'deployed'?"
   - If current status is `testing`: "Mark this spec as 'deployed'?"

5. Update the status using the tool:
   ```bash
   python3 ../tools/specs.py status <filename> <new_status>
   ```

6. Provide completion summary:
   - What was implemented (brief)
   - Files created/modified
   - Tests added/updated
   - Any notes for testing or deployment

---

## Status Values Reference

| Status | Meaning | Claude Action |
|--------|---------|---------------|
| `draft` | Initial creation | Ignore - not ready |
| `review` | Under stakeholder review | Ignore - not ready |
| `approved` | Ready for development | Can start with `/specs work` |
| `in_development` | Currently being implemented | Continue working |
| `testing` | Implementation complete, being tested | Can complete |
| `blocked` | Paused due to blocker | Ignore |
| `on_hold` | Deliberately paused | Ignore |
| `deployed` | Complete and in production | Ignore - done |

---

## Frontmatter Format

Specs use YAML frontmatter:

```yaml
---
title: Feature Name
version: "1.0"
status: draft
project: EchoForge Platform
created: 2025-01-05
updated: 2025-01-05
---
```

When updating status, preserve all other frontmatter fields.
