---
title: Issues Command - Interactive GitHub Issue Browser
version: "1.0"
status: draft
project: EchoForge Platform
created: 2026-01-07
updated: 2026-01-07
components:
  - tooling
issue: 22
---

# 1. Executive Summary

A slash command (`/issues`) for interactively browsing, filtering, and searching GitHub issues directly from Claude Code sessions. Uses `gh` CLI for data access with minimal AI processing, providing fast, lightweight issue management for architect and developer workflows.

# 2. Current System State

## 2.1 Existing Workflows

| Method | Description | Limitations |
|--------|-------------|-------------|
| `gh issue list` | CLI command | Raw output, no interactivity |
| GitHub web UI | Browser-based | Context switch from terminal |
| Manual search | Ask Claude to search | Uses AI tokens, slower |

## 2.2 Current Gaps

- No quick way to browse issues from within Claude Code session
- No integration between issue browsing and spec workflow
- Context switching to browser breaks flow
- No unified view across org repos

# 3. Feature Requirements

## 3.1 Command Syntax

**Description:** Flexible command syntax supporting filters, search, and help.

**Component:** Tooling (Claude Code Skill)

### Basic Usage

```bash
/issues                           # List all open issues (current repo)
/issues bug                       # Filter by label
/issues --status=closed           # Filter by status
/issues --status=all              # All issues regardless of status
/issues "contact"                 # Substring search in title
/issues bug "contact"             # Combined: label + search
/issues --help                    # Show available labels, statuses, usage
/issues --repo=echoforge          # Explicit repo (from org level)
```

### Argument Parsing

| Argument | Format | Description |
|----------|--------|-------------|
| label | bare word | Filter by label name (case-insensitive) |
| --status | `--status=open\|closed\|all` | Filter by issue state (default: open) |
| search | `"quoted string"` | Substring match on issue title |
| --repo | `--repo=name` | Explicit repo (org-level only) |
| --help | flag | Show help with live labels |

### Business Rules

- Arguments can appear in any order
- Label matching is case-insensitive
- Search is substring match on title only
- Multiple labels not supported in v1 (use GitHub web for complex queries)
- Default status is `open`

---

## 3.2 Context Detection

**Description:** Automatically detect which repo(s) to query based on current directory.

**Component:** Tooling

### Detection Logic

```python
def detect_context(cwd: str) -> Context:
    """
    Determine repo context from current working directory.

    Returns:
        Context with repo info or prompt requirement
    """
    # Check if in a project directory
    if is_git_repo(cwd):
        remote = get_git_remote(cwd)  # e.g., "jeffsinason/echoforge"
        return Context(type="project", repo=remote)

    # Check if in org root (EchoForgeX)
    if is_org_root(cwd):
        return Context(type="org", repos=get_org_repos())

    # Fallback: try to find nearest git repo
    return Context(type="unknown")
```

### Org-Level Behavior

When running from org root (`/EchoForgeX/`):

```
Which repository?
  [1] echoforge
  [2] signshield
  [3] echoforgex-website
  [a] All repositories

>
```

If "All" selected, results grouped by repo.

### Repository Detection

```bash
# Get remote repo from git
git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/'

# Get org repos (from CLAUDE.md or gh)
gh repo list jeffsinason --json name --limit 20
```

---

## 3.3 Issue List Display

**Description:** Formatted table display of issues with key metadata.

**Component:** Tooling

### Display Format

```
Issues for jeffsinason/echoforge (23 open)
══════════════════════════════════════════════════════════════════════════

  #  │ Title                                          │ Labels              │ Updated
─────┼────────────────────────────────────────────────┼─────────────────────┼─────────
  21 │ [Hub] Actions dropdown not showing             │ bug                 │ 2d ago
  20 │ [Agents] Implementation of personas in chat    │ enhancement, Need.. │ 2d ago
  17 │ [Mobile] Cross-Platform App Implementation     │ enhancement, Has S..│ 2d ago
  11 │ [Feature] Contact Management                   │ enhancement, Has S..│ 1h ago

[↑↓] Navigate  [Enter] Select  [o] Open in browser  [q] Quit  [/] Search
```

### Multi-Repo Display (Org Level)

```
Issues across EchoForgeX (47 total)
══════════════════════════════════════════════════════════════════════════

── jeffsinason/echoforge (23 open) ──────────────────────────────────────

  #  │ Title                                          │ Labels              │ Updated
─────┼────────────────────────────────────────────────┼─────────────────────┼─────────
  21 │ [Hub] Actions dropdown not showing             │ bug                 │ 2d ago
  ...

── jeffsinason/signshield (12 open) ─────────────────────────────────────

  #  │ Title                                          │ Labels              │ Updated
─────┼────────────────────────────────────────────────┼─────────────────────┼─────────
   8 │ [Feature] Document verification API            │ enhancement         │ 1w ago
  ...
```

### Column Specifications

| Column | Width | Truncation |
|--------|-------|------------|
| # | 4 | Right-align, no truncate |
| Title | 44 | Truncate with `...` |
| Labels | 19 | Truncate with `..` |
| Updated | 8 | Relative time |

### Relative Time Format

| Age | Display |
|-----|---------|
| < 1 hour | `Xm ago` |
| < 24 hours | `Xh ago` |
| < 7 days | `Xd ago` |
| < 30 days | `Xw ago` |
| >= 30 days | `Mon DD` |

---

## 3.4 Interactive Navigation

**Description:** Keyboard-driven navigation and selection.

**Component:** Tooling

### Key Bindings

| Key | Action |
|-----|--------|
| `↑` / `k` | Move selection up |
| `↓` / `j` | Move selection down |
| `Enter` | Select issue (show actions) |
| `o` | Open selected issue in browser |
| `/` | Enter search/filter mode |
| `q` / `Esc` | Quit/back |
| `?` | Show help |

### Selection Indicator

```
  #  │ Title                                          │ Labels              │ Updated
─────┼────────────────────────────────────────────────┼─────────────────────┼─────────
  21 │ [Hub] Actions dropdown not showing             │ bug                 │ 2d ago
► 20 │ [Agents] Implementation of personas in chat    │ enhancement, Need.. │ 2d ago
  17 │ [Mobile] Cross-Platform App Implementation     │ enhancement, Has S..│ 2d ago
```

---

## 3.5 Issue Actions Menu

**Description:** Context-sensitive actions when an issue is selected.

**Component:** Tooling

### Standard Actions

```
Issue #11: [Feature] Contact Management
───────────────────────────────────────────────────────────────
Status: Open
Labels: enhancement, Has Spec
Updated: 1 hour ago

Actions:
  [v] View full issue details
  [o] Open in browser
  [b] Back to list
  [q] Quit
```

### Spec-Aware Actions

For issues with "Has Spec" label:
```
  [s] View linked spec
```

For issues with "Need Spec" label:
```
  [c] Create spec from this issue
```

### Action Implementation

| Action | Implementation |
|--------|----------------|
| View details | `gh issue view {number} --repo {repo}` |
| Open browser | `gh issue view {number} --repo {repo} --web` |
| View spec | Read spec file, display in pager |
| Create spec | Launch `/architect` or `/spec-from-issue` skill |

### Spec Linking Logic

```python
def find_linked_spec(issue_number: int, repo: str) -> Optional[str]:
    """
    Find spec file linked to an issue.

    Checks:
    1. Spec frontmatter for `issue: {number}`
    2. Issue body for `Spec: specs/*.md` reference
    """
    # Search specs for issue reference
    for spec_file in glob("specs/*.md"):
        frontmatter = parse_frontmatter(spec_file)
        if frontmatter.get("issue") == issue_number:
            return spec_file

    # Check issue body for spec reference
    issue = gh_issue_view(issue_number, repo)
    match = re.search(r'Spec:\s*`?(specs/\w+\.md)`?', issue.body)
    if match:
        return match.group(1)

    return None
```

---

## 3.6 Help Command

**Description:** Dynamic help showing available labels fetched live from GitHub.

**Component:** Tooling

### Help Output

```
/issues - Interactive GitHub Issue Browser
══════════════════════════════════════════════════════════════════════════

Usage: /issues [label] [--status=STATUS] ["search term"]

Options:
  --status=open      Show open issues (default)
  --status=closed    Show closed issues
  --status=all       Show all issues
  --repo=NAME        Query specific repo (org-level only)
  --help             Show this help

Labels (jeffsinason/echoforge):
  bug                 4 open issues
  enhancement        15 open issues
  discussion          2 open issues
  Need Spec           5 open issues
  Has Spec            8 open issues
  mobile              3 open issues
  agent-type          2 open issues

Examples:
  /issues                     List all open issues
  /issues bug                 Filter by 'bug' label
  /issues --status=closed     Show closed issues
  /issues "contact"           Search titles containing 'contact'
  /issues enhancement "mobile" Filter + search combined

Navigation:
  ↑↓ or j/k    Navigate list
  Enter        Select issue
  o            Open in browser
  /            Filter/search
  q            Quit
```

### Live Label Fetching

```bash
# Get labels with issue counts
gh label list --repo jeffsinason/echoforge --json name,description --limit 50

# Get issue count per label
gh issue list --repo jeffsinason/echoforge --label "bug" --state open --json number | jq length
```

---

## 3.7 Data Fetching

**Description:** Use `gh` CLI to fetch issue data as JSON.

**Component:** Tooling

### Primary Query

```bash
gh issue list \
  --repo jeffsinason/echoforge \
  --state open \
  --label "enhancement" \
  --json number,title,labels,updatedAt,state \
  --limit 100
```

### JSON Response Format

```json
[
  {
    "number": 11,
    "title": "[Feature] Contact Management - Privacy-First Multi-Platform Strategy",
    "labels": [
      {"name": "enhancement"},
      {"name": "Has Spec"}
    ],
    "updatedAt": "2026-01-06T16:25:56Z",
    "state": "OPEN"
  }
]
```

### Filtering Logic

```python
def filter_issues(issues: list, search: str = None) -> list:
    """
    Apply client-side filters to issue list.

    Args:
        issues: List of issues from gh
        search: Optional substring to match in title

    Returns:
        Filtered list
    """
    if not search:
        return issues

    search_lower = search.lower()
    return [
        issue for issue in issues
        if search_lower in issue["title"].lower()
    ]
```

---

# 4. Future Considerations (Out of Scope)

Features not included in v1:

- Multiple label filtering (AND/OR logic)
- Fuzzy search with typo tolerance
- Issue creation from command
- Bulk operations (close, label multiple)
- Saved searches / filters
- Assignee filtering
- Milestone filtering
- Caching of issue data

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Core Command**

1. Create skill file `.claude/skills/issues.md`
2. Implement argument parsing
3. Implement `gh` data fetching
4. Implement table formatting
5. Basic list display (non-interactive)

**Phase 2: Interactivity**

1. Add navigation key handling
2. Add selection indicator
3. Implement action menu
4. Add browser opening
5. Add issue detail view

**Phase 3: Context & Help**

1. Implement repo context detection
2. Add org-level multi-repo support
3. Implement live label fetching for help
4. Add spec linking logic

**Phase 4: Integration**

1. Add "View linked spec" action
2. Add "Create spec from issue" action
3. Test integration with `/specs` workflow

## 5.2 File Structure

```
.claude/
└── skills/
    └── issues.md           # Skill definition with full prompt
```

## 5.3 Dependencies

| Dependency | Purpose |
|------------|---------|
| `gh` CLI | GitHub API access |
| Git | Repo detection |
| Terminal | Interactive display |

# 6. Acceptance Criteria

## 6.1 Command Parsing

- [ ] `/issues` lists all open issues for current repo
- [ ] `/issues bug` filters by "bug" label
- [ ] `/issues --status=closed` shows closed issues
- [ ] `/issues --status=all` shows all issues
- [ ] `/issues "search term"` filters by title substring
- [ ] `/issues bug "search"` combines label and search
- [ ] `/issues --help` shows help with live labels

## 6.2 Context Detection

- [ ] Detects repo from git remote when in project directory
- [ ] Prompts for repo selection when in org root
- [ ] "All repos" option groups results by repo
- [ ] `--repo` flag overrides detection

## 6.3 Display

- [ ] Table format with #, Title, Labels, Updated columns
- [ ] Title truncated at 44 chars with `...`
- [ ] Labels truncated at 19 chars with `..`
- [ ] Relative time display (Xm, Xh, Xd, Xw ago)
- [ ] Issue count shown in header

## 6.4 Navigation

- [ ] Arrow keys / j/k navigate selection
- [ ] Enter opens action menu
- [ ] `o` opens issue in browser
- [ ] `q` quits command
- [ ] `/` triggers search mode

## 6.5 Actions

- [ ] View full issue details via `gh issue view`
- [ ] Open in browser via `gh issue view --web`
- [ ] "View linked spec" shown for "Has Spec" issues
- [ ] "Create spec" shown for "Need Spec" issues

## 6.6 Help

- [ ] Shows usage and examples
- [ ] Fetches labels live from GitHub
- [ ] Shows issue count per label

---

*End of Specification*
