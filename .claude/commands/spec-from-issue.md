---
description: Create a spec from a GitHub issue marked "Need Spec"
---

# /spec-from-issue - Create Specification from GitHub Issue

Fetch GitHub issues labeled "Need Spec" from the EchoForge Platform repository, select one, and create a specification.

## Configuration

```
REPO: jeffsinason/echoforge
```

---

## Step 1: Fetch Issues Needing Specs

```bash
gh issue list --repo jeffsinason/echoforge \
  --label "Need Spec" \
  --json number,title,body \
  --jq '.[] | "#\(.number) - \(.title)"'
```

If no issues are found, inform the user:
> "No issues with 'Need Spec' label found. Create an issue with `/new-issue` first."

---

## Step 2: User Selection

Use AskUserQuestion to let the user choose which issue to work on.

Present each issue as an option:
- Label: "#5 - Add user invitation workflow"
- Description: First 100 chars of issue body

---

## Step 3: Fetch Full Issue Details

Once issue is selected, fetch complete details:

```bash
gh issue view <number> --repo jeffsinason/echoforge \
  --json number,title,body,labels,comments,author,createdAt
```

---

## Step 4: Begin Architect Session

1. Read `docs/prompts/system_architect.md` for the architect instructions
2. Present the issue context to the user
3. Begin the collaborative design process as described in the architect prompt
4. Ask clarifying questions grouped by topic
5. Iterate on the design
6. Write the spec to `specs/<feature_name>.md`

---

## Step 5: After Spec is Written

Once the spec is complete, offer to update the GitHub issue:

### Present to User

```
Spec written to: specs/<filename>.md

Would you like me to update the GitHub issue?
- Add comment linking to the spec
- Change label from "Need Spec" to "Has Spec"
```

### If User Confirms

Run these commands:

```bash
gh issue comment <number> --repo jeffsinason/echoforge \
  --body "Spec created: specs/<filename>.md"

gh issue edit <number> --repo jeffsinason/echoforge \
  --remove-label "Need Spec" --add-label "Has Spec"
```

### Report Result

```
Issue #<number> updated:
- Comment added with spec link
- Labels: "Need Spec" → "Has Spec"

Next step: Run `/specs work <filename>.md` to begin implementation
```

---

## Complete Example Flow

```
User: /spec-from-issue

Claude: I'll fetch issues needing specs from echoforge...

Found 2 issues:
1. #5 - Add user invitation workflow
2. #6 - Implement webhook retry logic

[Uses AskUserQuestion for selection]

User selects: #5

Claude: [Fetches full issue details]

---
## Issue #5: Add user invitation workflow

**Labels:** enhancement, Need Spec, component:hub
**Author:** jeffsinason
**Created:** 2026-01-02

### Description
Allow admins to invite new users via email...
---

I'll now act as System Architect for this feature.

Let me gather some information before proposing a design:

**Current System:**
1. How is user authentication currently handled?
...

[Collaborative design process continues]
[Spec is written to specs/user_invitation.md]

Claude: Spec written to specs/user_invitation.md

Would you like me to update GitHub issue #5?

User: yes

Claude: [Runs gh commands]

Issue #5 updated:
- Comment added with spec link
- Labels: "Need Spec" → "Has Spec"

Next step: Run `/specs work user_invitation.md` to begin implementation
```
