# /new-issue - Create New Issue

Create a new issue in the EchoForge Platform repository with proper formatting and labels.

## Configuration

```
REPO: jeffsinason/echoforge
```

## Step 1: Gather Information

Use AskUserQuestion to collect issue details:

### Question 1: Issue Type
- Header: "Type"
- Options:
  - `bug` - "Something isn't working correctly"
  - `enhancement` - "New feature or improvement"

### Question 2: Component
- Header: "Component"
- Options:
  - `hub` - "Customer portal (Django)"
  - `agent` - "Runtime engine (FastAPI)"
  - `both` - "Cross-component issue"

### Question 3: Issue Title
- Ask: "What is a brief title for this issue?"

### Question 4: Issue Description
- Ask: "Describe the issue in detail"
- For bugs: steps to reproduce, expected vs actual behavior
- For enhancements: problem/motivation, proposed solution

### Question 5: Needs Specification?
- Header: "Needs Spec"
- Options:
  - `Yes` - "This needs a design specification before implementation" (default for enhancement)
  - `No` - "Can proceed directly to development" (default for bug)

## Step 2: Create Issue

Run the GitHub CLI command to create the issue:

```bash
gh issue create --repo jeffsinason/echoforge \
  --title "TITLE" \
  --body "DESCRIPTION" \
  --label "needs-triage,TYPE,component:COMPONENT"
```

If "Needs Spec" is Yes, add the `Need Spec` label:
```bash
gh issue create --repo jeffsinason/echoforge \
  --title "TITLE" \
  --body "DESCRIPTION" \
  --label "needs-triage,TYPE,component:COMPONENT,Need Spec"
```

## Step 3: Report Result

Display the created issue URL and summary:

```
Issue created: https://github.com/jeffsinason/echoforge/issues/XX

Title: Your title
Type: enhancement
Component: hub
Labels: needs-triage, enhancement, component:hub, Need Spec

Next steps:
- If spec needed: Run /spec-from-issue to create the specification
- If no spec: Update label to 'in-development' when ready to start
```

## Example Flow

```
User: /new-issue

Claude: I'll help you create a new issue. Let me gather some information.

[Asks questions via AskUserQuestion]

User answers:
- Type: enhancement
- Component: hub
- Title: Add user invitation workflow
- Description: Allow admins to invite new users via email...
- Needs Spec: Yes

Claude: Creating issue in jeffsinason/echoforge...

[Runs gh issue create command]

Issue created: https://github.com/jeffsinason/echoforge/issues/5

Title: Add user invitation workflow
Type: enhancement
Component: hub
Labels: needs-triage, enhancement, component:hub, Need Spec

Next steps:
- Run /spec-from-issue to create the specification
```

## Label Reference

| Label | Description |
|-------|-------------|
| `needs-triage` | Initial state for all new issues |
| `bug` | Something isn't working |
| `enhancement` | New feature or improvement |
| `component:hub` | Affects Hub (Django) |
| `component:agent` | Affects Agent (FastAPI) |
| `component:both` | Cross-component issue |
| `Need Spec` | Requires specification before development |
