# Architectural Decision Records (ADR) Template

## Overview

Architectural Decision Records document significant technical decisions that affect the EchoForge platform. ADRs are embedded directly in GitHub issues to maintain traceability between decisions and implementation work.

## When to Create an ADR

Create an ADR when:
- A decision affects multiple components (Hub, Agent, Mobile)
- Multiple valid approaches exist with different trade-offs
- The decision has long-term implications
- The choice impacts privacy, security, or compliance
- Team input or stakeholder approval is needed before proceeding

## ADR Status Values

| Status | Icon | Description |
|--------|------|-------------|
| PENDING | ⏳ | Decision needed, options being evaluated |
| DECIDED | ✅ | Decision made, ready for implementation |
| IMPLEMENTED | 🚀 | Decision implemented in code |
| SUPERSEDED | 🔄 | Replaced by a newer ADR |
| REJECTED | ❌ | Decision not to proceed |

## Template

Copy and paste this template into the relevant GitHub issue:

```markdown
---

## 🏛️ Architectural Decisions Required

### ADR-XXX: [Decision Title]

| Field | Value |
|-------|-------|
| **ID** | ADR-XXX |
| **Status** | ⏳ PENDING |
| **Related Issues** | #XX, #YY |
| **Decision Required By** | [Before Phase X / Date / Milestone] |
| **Decided On** | _TBD_ |
| **Decided By** | _TBD_ |

#### Context

[Explain the background and why this decision is needed. What problem are we solving? What constraints exist?]

#### Question

[State the specific question that needs to be answered in a clear, concise way.]

#### Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A. [Name] | [Brief description] | [Benefits] | [Drawbacks] |
| B. [Name] | [Brief description] | [Benefits] | [Drawbacks] |
| C. [Name] | [Brief description] | [Benefits] | [Drawbacks] |

#### Considerations

- [Important factor 1]
- [Important factor 2]
- [Privacy/security implications]
- [Performance implications]
- [Complexity/maintenance cost]

#### Decision

**Chosen Option:** _TBD_

**Rationale:** _TBD_

**Consequences:**
- [What changes as a result]
- [What new constraints are introduced]
- [What follow-up work is needed]

---
```

## ID Naming Convention

ADR IDs should be unique within an issue. Format: `ADR-XXX`

For cross-issue ADRs that span multiple features, use a prefix:
- `ADR-CONTACTS-001` - Contact management decisions
- `ADR-MOBILE-001` - Mobile app decisions
- `ADR-AUTH-001` - Authentication/authorization decisions

## Example: Completed ADR

```markdown
### ADR-CONTACTS-002: On-Device Meta Index vs Server Storage

| Field | Value |
|-------|-------|
| **ID** | ADR-CONTACTS-002 |
| **Status** | ✅ DECIDED |
| **Related Issues** | #11, #17 |
| **Decision Required By** | Before Phase 5 |
| **Decided On** | 2026-01-15 |
| **Decided By** | @jeffsinason |

#### Context

For mobile apps, contact groups/tags can be stored either on-device only (maximum privacy) or synced to server (cross-device access). This affects GDPR compliance and user experience.

#### Question

Where should mobile contact tags/groups be stored?

#### Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A. On-Device Only | Tags in local storage, never sync | Maximum privacy, GDPR simple | No cross-device, lost on reinstall |
| B. Server Only | Tags in ContactReference on Hub | Cross-device, backup | PII concerns, requires server |
| C. Hybrid | Default on-device, optional sync | Flexibility | Complexity, UX decisions |

#### Considerations

- GDPR strongly prefers on-device storage
- Users expect cross-device sync in modern apps
- Backup/restore is important for user trust
- Hybrid adds complexity but provides choice

#### Decision

**Chosen Option:** C. Hybrid (User Choice)

**Rationale:** Provides maximum flexibility while defaulting to the privacy-preserving option. Users who want cross-device sync can explicitly opt in, making consent clear.

**Consequences:**
- Mobile app needs local storage implementation
- Hub needs optional sync endpoint
- Onboarding must explain sync choice clearly
- Two code paths to maintain
```

## Tracking ADRs Across Issues

To find all pending ADRs, search GitHub issues for:
```
"ADR-" "PENDING" in:body
```

To find all ADRs related to a topic:
```
"ADR-CONTACTS" in:body
```

## Updating ADR Status

When a decision is made:
1. Update **Status** to `✅ DECIDED`
2. Fill in **Decided On** date
3. Fill in **Decided By** username
4. Complete the **Decision** section with chosen option and rationale
5. Add any follow-up tasks to the issue checklist

When implementation is complete:
1. Update **Status** to `🚀 IMPLEMENTED`
2. Reference the PR/commit that implemented it

## Best Practices

1. **Keep options balanced** - Present each option fairly with real pros and cons
2. **Be specific** - Vague options lead to vague decisions
3. **Link related issues** - ADRs often affect multiple features
4. **Document consequences** - Future developers need to understand the "why"
5. **Update status promptly** - Stale ADRs create confusion
6. **One decision per ADR** - Split complex decisions into multiple ADRs
