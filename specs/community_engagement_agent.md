# Community Engagement Agent Specification

**Version:** 1.0
**Status:** in-development
**Issue:** #32
**Date:** January 2026
**Updated:** 2026-01-04

---

## Overview

The Community Engagement Agent monitors configured online communities (Reddit, LinkedIn, Dev.to, Hacker News) for relevant discussions and suggests contextual responses. It helps users build brand presence, generate leads, and establish thought leadership through authentic, value-adding engagement.

### Goals

1. **Save time** - Automate discovery of engagement opportunities
2. **Improve quality** - AI-drafted responses that match community norms
3. **Generate leads** - Track engaged users through CRM integration
4. **Learn & adapt** - Get smarter over time based on user feedback

### Non-Goals

- Fully automated posting without human oversight (except opt-in high-confidence)
- Aggressive marketing or promotional spam
- Astroturfing or fake persona management
- Mass engagement that violates platform TOS

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Community Engagement Agent                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐            │
│  │   Scanner   │───▶│  Analyzer   │───▶│   Drafter   │            │
│  │             │    │             │    │             │            │
│  │ - Fetch new │    │ - Relevance │    │ - Generate  │            │
│  │   posts     │    │ - Confidence│    │   response  │            │
│  │ - Keywords  │    │ - Rules     │    │ - Persona   │            │
│  │ - Threads   │    │   check     │    │ - Disclosure│            │
│  └─────────────┘    └─────────────┘    └─────────────┘            │
│         │                  │                  │                    │
│         ▼                  ▼                  ▼                    │
│  ┌─────────────────────────────────────────────────┐              │
│  │              Opportunity Queue                   │              │
│  │  - Post + Context                               │              │
│  │  - Draft response                               │              │
│  │  - Confidence score                             │              │
│  │  - Suggested action                             │              │
│  └─────────────────────────────────────────────────┘              │
│                            │                                       │
│         ┌──────────────────┼──────────────────┐                   │
│         ▼                  ▼                  ▼                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐           │
│  │   Manual    │    │  Auto-Post  │    │    Skip     │           │
│  │  Approval   │    │  (95%+)     │    │  /Archive   │           │
│  └─────────────┘    └─────────────┘    └─────────────┘           │
│         │                  │                                      │
│         ▼                  ▼                                      │
│  ┌─────────────────────────────────────────────────┐              │
│  │              Learning Engine                     │              │
│  │  - Confidence calibration                       │              │
│  │  - Style adaptation                             │              │
│  │  - Rule violation tracking                      │              │
│  └─────────────────────────────────────────────────┘              │
│                                                                    │
└─────────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
  │  Knowledge  │      │     CRM     │      │  Analytics  │
  │    Base     │      │ Integration │      │  Dashboard  │
  └─────────────┘      └─────────────┘      └─────────────┘
```

---

## Data Models

### CommunityEngagementAgent

```python
class CommunityEngagementAgent(AgentInstance):
    """Community Engagement Agent instance configuration."""

    # Platform credentials (encrypted)
    reddit_credentials = EncryptedJSONField(null=True)
    linkedin_credentials = EncryptedJSONField(null=True)
    devto_api_key = EncryptedTextField(null=True)

    # Global settings
    confidence_threshold = models.FloatField(default=0.7)
    auto_post_threshold = models.FloatField(default=0.95)
    auto_post_enabled = models.BooleanField(default=False)
    daily_digest_time = models.TimeField(default="09:00")

    # Learning
    learning_enabled = models.BooleanField(default=True)

    # Rate limits (per day)
    global_daily_limit = models.IntegerField(default=20)
```

### MonitoredCommunity

```python
class MonitoredCommunity(CustomerScopedModel):
    """A community being monitored by the agent."""

    class Platform(models.TextChoices):
        REDDIT = 'reddit', 'Reddit'
        LINKEDIN = 'linkedin', 'LinkedIn'
        DEVTO = 'devto', 'Dev.to'
        HACKERNEWS = 'hackernews', 'Hacker News'

    agent = models.ForeignKey(CommunityEngagementAgent, on_delete=models.CASCADE)
    platform = models.CharField(max_length=20, choices=Platform.choices)
    community_id = models.CharField(max_length=255)  # subreddit name, group ID, etc.
    display_name = models.CharField(max_length=255)

    # Filtering
    keywords = models.JSONField(default=list)  # Must-see keywords
    excluded_keywords = models.JSONField(default=list)

    # Persona configuration
    persona_name = models.CharField(max_length=100, blank=True)
    persona_description = models.TextField(blank=True)
    response_tone = models.CharField(max_length=50, default='helpful_expert')

    # Disclosure
    disclosure_required = models.BooleanField(default=False)
    disclosure_text = models.TextField(blank=True)

    # Rate limits (per community per day)
    daily_post_limit = models.IntegerField(default=3)

    # Rule awareness
    parsed_rules = models.JSONField(default=dict)
    rules_last_parsed = models.DateTimeField(null=True)

    # Status
    is_active = models.BooleanField(default=True)
    last_scanned = models.DateTimeField(null=True)

    class Meta:
        unique_together = ['agent', 'platform', 'community_id']
```

### EngagementOpportunity

```python
class EngagementOpportunity(CustomerScopedModel):
    """A discovered opportunity for engagement."""

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending Review'
        APPROVED = 'approved', 'Approved'
        POSTED = 'posted', 'Posted'
        SKIPPED = 'skipped', 'Skipped'
        AUTO_POSTED = 'auto_posted', 'Auto-Posted'
        FAILED = 'failed', 'Failed'

    class OpportunityType(models.TextChoices):
        ORIGINAL_POST = 'original', 'Original Post'
        COMMENT_REPLY = 'comment', 'Comment Reply'
        THREAD_FOLLOWUP = 'followup', 'Thread Follow-up'

    agent = models.ForeignKey(CommunityEngagementAgent, on_delete=models.CASCADE)
    community = models.ForeignKey(MonitoredCommunity, on_delete=models.CASCADE)

    # Source content
    opportunity_type = models.CharField(max_length=20, choices=OpportunityType.choices)
    platform_post_id = models.CharField(max_length=255)
    platform_url = models.URLField()
    post_title = models.TextField()
    post_content = models.TextField()
    post_author = models.CharField(max_length=255)
    post_created_at = models.DateTimeField()
    parent_comment_id = models.CharField(max_length=255, null=True)  # For replies

    # Analysis
    relevance_score = models.FloatField()
    confidence_score = models.FloatField()
    confidence_reasoning = models.TextField()
    matched_keywords = models.JSONField(default=list)

    # Draft response
    draft_response = models.TextField()
    final_response = models.TextField(blank=True)  # After user edits

    # Status tracking
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    reviewed_at = models.DateTimeField(null=True)
    posted_at = models.DateTimeField(null=True)
    platform_response_id = models.CharField(max_length=255, null=True)

    # Engagement tracking
    upvotes = models.IntegerField(default=0)
    replies_received = models.IntegerField(default=0)
    last_engagement_check = models.DateTimeField(null=True)

    # Learning feedback
    user_feedback = models.CharField(max_length=20, null=True)  # approved, edited, skipped
    edit_distance = models.FloatField(null=True)  # How much user changed draft

    created_at = models.DateTimeField(auto_now_add=True)
```

### CompetitorMention

```python
class CompetitorMention(CustomerScopedModel):
    """Tracked competitor mentions for alerting."""

    agent = models.ForeignKey(CommunityEngagementAgent, on_delete=models.CASCADE)
    community = models.ForeignKey(MonitoredCommunity, on_delete=models.CASCADE)

    competitor_name = models.CharField(max_length=255)
    platform_post_id = models.CharField(max_length=255)
    platform_url = models.URLField()
    post_title = models.TextField()
    post_content = models.TextField()
    mention_context = models.TextField()  # Snippet around mention
    sentiment = models.CharField(max_length=20)  # positive, negative, neutral

    created_at = models.DateTimeField(auto_now_add=True)
    reviewed = models.BooleanField(default=False)
```

### EngagementContext

```python
class EngagementContext(CustomerScopedModel):
    """Engagement-specific context documents separate from main KB."""

    agent = models.ForeignKey(CommunityEngagementAgent, on_delete=models.CASCADE)

    title = models.CharField(max_length=255)
    content = models.TextField()
    context_type = models.CharField(max_length=50)  # talking_points, faq, product_info

    # Scoping
    communities = models.ManyToManyField(MonitoredCommunity, blank=True)  # Empty = all

    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

### LearningFeedback

```python
class LearningFeedback(CustomerScopedModel):
    """Aggregated learning data for improving suggestions."""

    agent = models.ForeignKey(CommunityEngagementAgent, on_delete=models.CASCADE)
    community = models.ForeignKey(MonitoredCommunity, on_delete=models.CASCADE, null=True)

    # Confidence calibration
    predicted_confidence = models.FloatField()
    actual_outcome = models.CharField(max_length=20)  # approved, edited, skipped, removed

    # Style patterns
    original_draft = models.TextField()
    final_version = models.TextField()
    edit_patterns = models.JSONField(default=dict)  # Learned edits

    # Rule violations
    was_removed = models.BooleanField(default=False)
    removal_reason = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
```

---

## Core Workflows

### 1. Daily Scan Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Daily Scan (Scheduled)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. For each active MonitoredCommunity:                         │
│     │                                                           │
│     ├─► Fetch new posts since last_scanned                      │
│     │   - Reddit: /r/{subreddit}/new                            │
│     │   - LinkedIn: Group feed API                              │
│     │   - Dev.to: /articles?tag={tag}                           │
│     │                                                           │
│     ├─► Pre-filter with keywords                                │
│     │   - Must-see: Always analyze if keyword matches           │
│     │   - Excluded: Skip if excluded keyword present            │
│     │                                                           │
│     ├─► AI pre-filter remaining posts                           │
│     │   - Quick relevance check (low-cost model)                │
│     │   - Pass threshold: 0.5 relevance                         │
│     │                                                           │
│     ├─► Deep analysis on filtered posts                         │
│     │   - Full relevance scoring                                │
│     │   - Confidence calculation                                │
│     │   - Rule compliance check                                 │
│     │                                                           │
│     ├─► Analyze existing comments for reply opportunities       │
│     │   - Find questions without good answers                   │
│     │   - Identify threads worth joining                        │
│     │                                                           │
│     └─► Create EngagementOpportunity for each qualifying post   │
│                                                                 │
│  2. Check previously engaged threads for follow-up              │
│     - New replies to our comments                               │
│     - Thread developments worth responding to                   │
│                                                                 │
│  3. Scan for competitor mentions                                │
│     - Create CompetitorMention records                          │
│     - Flag for daily digest                                     │
│                                                                 │
│  4. Update last_scanned timestamps                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Confidence Scoring

```python
def calculate_confidence(post, community, agent):
    """
    Calculate confidence score for responding to a post.

    Returns:
        float: 0.0 - 1.0 confidence score
        str: Reasoning explanation
    """

    factors = {
        # Positive factors
        'topic_relevance': 0.0,      # How relevant to our expertise
        'question_clarity': 0.0,     # Is there a clear question to answer
        'value_opportunity': 0.0,    # Can we add genuine value
        'engagement_potential': 0.0, # Likely to get positive engagement

        # Negative factors (reduce confidence)
        'rule_violation_risk': 0.0,  # Might violate community rules
        'spam_perception_risk': 0.0, # Might appear promotional
        'existing_answers': 0.0,     # Already well-answered
        'post_age_penalty': 0.0,     # Too old for engagement
        'author_history': 0.0,       # Troll/spam account
    }

    # Calculate each factor using LLM analysis
    # ...

    # Weight and combine
    positive = (
        factors['topic_relevance'] * 0.3 +
        factors['question_clarity'] * 0.2 +
        factors['value_opportunity'] * 0.3 +
        factors['engagement_potential'] * 0.2
    )

    negative = (
        factors['rule_violation_risk'] * 0.3 +
        factors['spam_perception_risk'] * 0.3 +
        factors['existing_answers'] * 0.2 +
        factors['post_age_penalty'] * 0.1 +
        factors['author_history'] * 0.1
    )

    confidence = max(0, positive - negative)

    # Apply learned calibration from historical feedback
    calibration = get_confidence_calibration(agent, community)
    confidence = apply_calibration(confidence, calibration)

    return confidence, generate_reasoning(factors)
```

### 3. Response Generation

```python
def generate_response(opportunity, community, agent):
    """
    Generate a draft response for an engagement opportunity.
    """

    # Gather context
    context = {
        'post': {
            'title': opportunity.post_title,
            'content': opportunity.post_content,
            'author': opportunity.post_author,
            'existing_comments': fetch_comments(opportunity),
        },
        'community': {
            'name': community.display_name,
            'rules': community.parsed_rules,
            'typical_tone': analyze_community_tone(community),
        },
        'persona': {
            'name': community.persona_name,
            'description': community.persona_description,
            'tone': community.response_tone,
        },
        'knowledge': {
            'main_kb': search_knowledge_base(opportunity.post_content, agent),
            'engagement_context': get_engagement_context(agent, community),
        },
        'learned_style': get_learned_style(agent, community),
    }

    # Build prompt
    prompt = f"""
    You are helping draft a response for a community discussion.

    COMMUNITY: {context['community']['name']}
    COMMUNITY RULES: {context['community']['rules']}
    TYPICAL TONE: {context['community']['typical_tone']}

    PERSONA: {context['persona']['description']}
    RESPONSE TONE: {context['persona']['tone']}

    POST TITLE: {context['post']['title']}
    POST CONTENT: {context['post']['content']}

    EXISTING COMMENTS:
    {format_comments(context['post']['existing_comments'])}

    RELEVANT KNOWLEDGE:
    {context['knowledge']}

    LEARNED STYLE PATTERNS:
    {context['learned_style']}

    Generate a response that:
    1. Adds genuine value to the discussion
    2. Matches the community's typical tone
    3. Follows all community rules
    4. Does NOT appear promotional or spammy
    5. Is concise but helpful

    {'Include disclosure: ' + community.disclosure_text if community.disclosure_required else ''}

    Response:
    """

    response = llm_service.generate(prompt)

    return response
```

### 4. Auto-Post Flow

```
┌─────────────────────────────────────────────────────────────────┐
│               Auto-Post Decision (if enabled)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  IF agent.auto_post_enabled AND                                 │
│     opportunity.confidence_score >= agent.auto_post_threshold:  │
│                                                                 │
│     1. Verify rate limits not exceeded                          │
│        - Global daily limit                                     │
│        - Community daily limit                                  │
│        - Platform API limits                                    │
│                                                                 │
│     2. Final safety checks                                      │
│        - Re-verify rule compliance                              │
│        - Check for recent removals in community                 │
│        - Verify account not rate-limited                        │
│                                                                 │
│     3. Post response via platform API                           │
│        - Reddit: POST /api/comment                              │
│        - LinkedIn: POST /comments                               │
│                                                                 │
│     4. Update opportunity status = AUTO_POSTED                  │
│                                                                 │
│     5. Schedule engagement check (1hr, 24hr)                    │
│                                                                 │
│  ELSE:                                                          │
│     Add to pending queue for manual review                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Learning Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Learning from Feedback                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  On user action (approve/edit/skip):                            │
│                                                                 │
│  1. CONFIDENCE CALIBRATION                                      │
│     │                                                           │
│     ├─► Record: predicted_confidence vs actual_outcome          │
│     │   - approved = good prediction                            │
│     │   - edited = partial miss                                 │
│     │   - skipped = bad prediction                              │
│     │                                                           │
│     └─► Adjust calibration curve for future predictions         │
│         - If consistently skipping 0.8+ confidence → lower      │
│         - If consistently approving 0.6 confidence → raise      │
│                                                                 │
│  2. STYLE LEARNING (on edit or approve)                         │
│     │                                                           │
│     ├─► Compare draft_response to final_response                │
│     │                                                           │
│     ├─► Extract patterns:                                       │
│     │   - Length adjustments (shorter/longer)                   │
│     │   - Tone shifts (more/less formal)                        │
│     │   - Structure changes (paragraphs, bullets)               │
│     │   - Common additions (greetings, sign-offs)               │
│     │   - Common removals (hedging, filler)                     │
│     │                                                           │
│     └─► Store patterns per community for future drafts          │
│                                                                 │
│  3. RULE VIOLATION LEARNING                                     │
│     │                                                           │
│     ├─► Monitor posted responses for removal                    │
│     │                                                           │
│     ├─► If removed:                                             │
│     │   - Fetch removal reason if available                     │
│     │   - Analyze what triggered violation                      │
│     │   - Update rule understanding                             │
│     │                                                           │
│     └─► Increase rule_violation_risk for similar posts          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## User Interface

### Daily Digest Email

```
Subject: 📬 Community Engagement - 12 opportunities found

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DAILY SUMMARY - January 4, 2026

Found 12 engagement opportunities across 5 communities
3 auto-posted (95%+ confidence)
9 awaiting your review

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🤖 AUTO-POSTED (3)

r/programming • "Best practices for error handling?"
Confidence: 97% • Posted 6 hours ago
👍 12 upvotes • 💬 3 replies
[View Thread]

r/webdev • "How do you structure large React apps?"
Confidence: 96% • Posted 4 hours ago
👍 8 upvotes • 💬 1 reply
[View Thread]

r/devops • "Terraform state management tips?"
Confidence: 95% • Posted 2 hours ago
👍 5 upvotes • 💬 0 replies
[View Thread]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 AWAITING REVIEW (9)

[Review All in Dashboard →]

Top opportunity:
r/ExperiencedDevs • "Senior devs, how do you use AI tools?"
Confidence: 89% • 45 comments • Highly relevant
[Review →]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔔 COMPETITOR MENTIONS (2)

"Copilot" mentioned in r/programming (neutral)
"Cursor" mentioned in r/webdev (positive)
[View Details →]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 THIS WEEK'S STATS

Opportunities found: 67
Responses posted: 23
Total upvotes: 156
Leads captured: 4
Avg confidence accuracy: 87%

[View Full Analytics →]
```

### Review Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│ Community Engagement Dashboard                    [Settings ⚙️]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Filter: [All Communities ▼] [All Types ▼] [Pending ▼]          │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ r/programming • 2 hours ago                    Confidence   │ │
│ │                                                    89%      │ │
│ │ "What's your biggest frustration with AI coding tools?"     │ │
│ │                                                             │ │
│ │ The "almost right but not quite" problem. I spend more      │ │
│ │ time debugging AI suggestions than I saved generating...    │ │
│ │ [Show full post]                                            │ │
│ │                                                             │ │
│ │ 💬 45 comments • 👍 127 upvotes • 🔥 Trending               │ │
│ │                                                             │ │
│ │ ─────────────────────────────────────────────────────────── │ │
│ │                                                             │ │
│ │ SUGGESTED RESPONSE:                                         │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ This resonates. The core issue is confidence            │ │
│ │ │ calibration - AI tools don't know what they don't       │ │
│ │ │ know. They generate plausible-looking code with equal   │ │
│ │ │ confidence whether it's correct or subtly broken.       │ │
│ │ │                                                         │ │
│ │ │ What's helped me:                                       │ │
│ │ │ 1. Use AI for boilerplate, never for business logic    │ │
│ │ │ 2. Treat every suggestion as a first draft             │ │
│ │ │ 3. Test immediately - don't let AI code accumulate     │ │
│ │ │                                                         │ │
│ │ │ The productivity gain is real but only if you're       │ │
│ │ │ ruthless about verification.                           │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ │                                                             │ │
│ │ WHY THIS SCORE:                                             │ │
│ │ ✓ High relevance to configured expertise                   │ │
│ │ ✓ Clear question with room for valuable answer             │ │
│ │ ✓ Active discussion, high visibility                       │ │
│ │ ⚠ Many existing comments (but none comprehensive)          │ │
│ │                                                             │ │
│ │ [✓ Approve] [✏️ Edit] [Skip] [🚫 Block Thread]              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ r/devops • 5 hours ago                         Confidence   │ │
│ │                                                    76%      │ │
│ │ "Anyone using AI for Terraform modules?"                    │ │
│ │ ...                                                         │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Community Settings

```
┌─────────────────────────────────────────────────────────────────┐
│ Community Settings: r/programming                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ STATUS: [● Active]                                              │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ FILTERING                                                       │
│                                                                 │
│ Must-see keywords:                                              │
│ [AI coding] [code assistant] [Copilot] [productivity] [+Add]   │
│                                                                 │
│ Excluded keywords:                                              │
│ [hiring] [job post] [resume] [+Add]                            │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ PERSONA                                                         │
│                                                                 │
│ Name: [Jeff - Developer                    ]                    │
│                                                                 │
│ Description:                                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Senior developer with 15+ years experience. Interested in  │ │
│ │ developer productivity, AI tools, and building great       │ │
│ │ software. Founder working on developer tools.              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ Tone: [Helpful Expert ▼]                                        │
│       Options: Helpful Expert, Casual Peer, Technical Deep,     │
│                Friendly Mentor, Brief & Direct                  │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ DISCLOSURE                                                      │
│                                                                 │
│ [✓] Require disclosure in responses                             │
│                                                                 │
│ Disclosure text:                                                │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ (Disclosure: I'm building tools in this space)             │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ RATE LIMITS                                                     │
│                                                                 │
│ Max posts per day: [3      ]                                    │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ PARSED RULES                                     [🔄 Re-parse]  │
│                                                                 │
│ Last parsed: 2 days ago                                         │
│                                                                 │
│ • No self-promotion or blogspam                                 │
│ • Must be about programming                                     │
│ • No surveys without moderator approval                         │
│ • Be civil and constructive                                     │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│                                    [Cancel] [Save Changes]      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Integrations

### Platform APIs

#### Reddit

```python
class RedditIntegration:
    """Reddit API integration using OAuth."""

    SCOPES = ['read', 'submit', 'identity', 'history']

    async def fetch_new_posts(self, subreddit: str, since: datetime) -> list:
        """Fetch new posts from subreddit."""
        # GET /r/{subreddit}/new

    async def fetch_post_comments(self, post_id: str) -> list:
        """Fetch all comments on a post."""
        # GET /comments/{post_id}

    async def submit_comment(self, parent_id: str, text: str) -> dict:
        """Submit a comment."""
        # POST /api/comment

    async def get_subreddit_rules(self, subreddit: str) -> dict:
        """Fetch subreddit rules."""
        # GET /r/{subreddit}/about/rules

    async def check_rate_limits(self) -> dict:
        """Check current rate limit status."""
        # From response headers
```

#### LinkedIn (Phase 2)

```python
class LinkedInIntegration:
    """LinkedIn API integration."""

    async def fetch_group_posts(self, group_id: str, since: datetime) -> list:
        """Fetch new posts from LinkedIn group."""

    async def submit_comment(self, post_urn: str, text: str) -> dict:
        """Submit a comment on a post."""
```

#### Dev.to (Phase 2)

```python
class DevToIntegration:
    """Dev.to API integration."""

    async def fetch_articles(self, tag: str, since: datetime) -> list:
        """Fetch articles by tag."""
        # GET /articles?tag={tag}

    async def fetch_comments(self, article_id: str) -> list:
        """Fetch comments on article."""
        # GET /comments?a_id={article_id}
```

#### Hacker News (Phase 2)

```python
class HackerNewsIntegration:
    """Hacker News API integration (read-only, no official comment API)."""

    async def fetch_new_stories(self, since: datetime) -> list:
        """Fetch new stories."""
        # GET /newstories

    async def fetch_item(self, item_id: str) -> dict:
        """Fetch story or comment."""
        # GET /item/{id}
```

### CRM Integration

```python
class CRMIntegration:
    """Abstract CRM integration for lead tracking."""

    providers = {
        'hubspot': HubSpotProvider,
        'salesforce': SalesforceProvider,
        'pipedrive': PipedriveProvider,
        'zoho': ZohoCRMProvider,
    }

    async def create_lead(self, agent, user_data: dict) -> str:
        """Create lead from engaged user."""
        provider = self.get_provider(agent)
        return await provider.create_contact({
            'source': 'community_engagement',
            'platform': user_data['platform'],
            'username': user_data['username'],
            'profile_url': user_data['profile_url'],
            'engagement_thread': user_data['thread_url'],
            'engagement_date': user_data['engaged_at'],
            'notes': user_data.get('notes', ''),
        })

    async def update_lead_engagement(self, lead_id: str, engagement: dict):
        """Update lead with new engagement data."""
        provider = self.get_provider(agent)
        return await provider.add_activity(lead_id, engagement)
```

### Knowledge Base Integration

```python
async def search_knowledge_base(query: str, agent) -> list:
    """Search main KB for relevant context."""

    # Use existing KB search from EchoForge
    results = await knowledge_service.search(
        agent_id=agent.id,
        query=query,
        limit=5,
    )

    return results

async def get_engagement_context(agent, community=None) -> list:
    """Get engagement-specific context documents."""

    contexts = EngagementContext.objects.filter(
        agent=agent,
        is_active=True,
    )

    if community:
        contexts = contexts.filter(
            Q(communities=community) | Q(communities__isnull=True)
        )

    return list(contexts.values('title', 'content', 'context_type'))
```

---

## Analytics

### Metrics Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│ Analytics - Last 30 Days                         [Export CSV]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ENGAGEMENT METRICS                                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Posts Found    Approved    Posted    Upvotes    Replies    │ │
│ │    287           89          76        523        147       │ │
│ │                                                             │ │
│ │ [Chart: Engagement over time]                               │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ EFFICIENCY METRICS                                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Approval Rate    Edit Rate    Skip Rate    Confidence Acc  │ │
│ │     31%            18%          51%            84%          │ │
│ │                                                             │ │
│ │ Avg time saved per response: ~12 minutes                    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ CONVERSION METRICS                                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Leads Generated    DMs Received    Site Clicks (est)       │ │
│ │       12                8               ~45                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ BY COMMUNITY                                                    │
│ ┌──────────────────┬────────┬────────┬─────────┬─────────────┐ │
│ │ Community        │ Posts  │ Posted │ Upvotes │ Conf. Acc   │ │
│ ├──────────────────┼────────┼────────┼─────────┼─────────────┤ │
│ │ r/programming    │   89   │   23   │   234   │    87%      │ │
│ │ r/webdev         │   67   │   19   │   156   │    82%      │ │
│ │ r/devops         │   45   │   12   │    78   │    89%      │ │
│ │ r/ExperiencedDev │   42   │   14   │    45   │    91%      │ │
│ │ r/startups       │   44   │    8   │    10   │    72%      │ │
│ └──────────────────┴────────┴────────┴─────────┴─────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## MVP Scope

### Phase 1: Scan + Approve + Post (MVP)

**Included:**
- Reddit OAuth integration (read + write)
- Daily scan of configured subreddits
- Keyword + AI pre-filtering
- Confidence scoring
- Response drafting with persona support
- Daily digest email with opportunities
- Simple web UI to review suggestions
- Post to Reddit on user approval (approve/edit → post)
- Basic analytics (opportunities found, approval rate, engagement)

**Not Included (Phase 2+):**
- Auto-posting (95%+ confidence)
- Thread tracking / follow-ups
- CRM integration
- Learning engine
- Additional platforms (LinkedIn, Dev.to, HN)
- Competitor monitoring

### MVP Data Model (Simplified)

```python
# MVP Models

class CommunityEngagementAgent(AgentInstance):
    # Reddit OAuth credentials (encrypted)
    reddit_credentials = EncryptedJSONField(null=True)

    confidence_threshold = models.FloatField(default=0.7)
    daily_digest_time = models.TimeField(default="09:00")

class MonitoredSubreddit(CustomerScopedModel):
    agent = models.ForeignKey(CommunityEngagementAgent)
    subreddit_name = models.CharField(max_length=255)
    keywords = models.JSONField(default=list)
    persona_description = models.TextField(blank=True)
    response_tone = models.CharField(max_length=50, default='helpful_expert')
    disclosure_text = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    last_scanned = models.DateTimeField(null=True)

class EngagementSuggestion(CustomerScopedModel):
    agent = models.ForeignKey(CommunityEngagementAgent)
    subreddit = models.ForeignKey(MonitoredSubreddit)

    # Post info
    reddit_post_id = models.CharField(max_length=255)
    post_url = models.URLField()
    post_title = models.TextField()
    post_content = models.TextField()
    post_author = models.CharField(max_length=255)

    # Analysis
    confidence_score = models.FloatField()
    confidence_reasoning = models.TextField()

    # Draft
    draft_response = models.TextField()

    # Status
    status = models.CharField(max_length=20)  # pending, approved, skipped
    reviewed_at = models.DateTimeField(null=True)

    created_at = models.DateTimeField(auto_now_add=True)
```

---

## Implementation Phases

### Phase 1: MVP (Scan + Approve + Post)
- Reddit OAuth integration (read + write)
- Basic subreddit monitoring
- Confidence scoring
- Response drafting
- Daily digest email
- Simple review UI
- Post to Reddit on user approval

### Phase 2: Full Reddit
- Auto-post for high confidence (95%+)
- Thread tracking
- Learning engine (confidence + style)
- Rule parsing and violation learning
- Competitor mention alerts
- Enhanced analytics

### Phase 3: Multi-Platform
- LinkedIn integration
- Dev.to integration
- Hacker News integration
- CRM integration
- Cross-platform analytics

### Phase 4: Advanced
- Full thread analysis
- Sentiment analysis
- Advanced learning (response performance)
- A/B testing of response styles
- Team collaboration features

---

## Security & Compliance

### Data Handling

- Platform credentials encrypted at rest
- No storage of other users' personal data beyond public usernames
- Responses reviewed before posting (except opt-in auto-post)
- Audit log of all posts made

### Platform Compliance

- Respect all platform rate limits
- No automation that violates TOS
- Disclosure options for transparency
- No astroturfing or fake personas

### User Privacy

- Clear consent for CRM tracking
- User can delete all data
- No selling of engagement data

---

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| Auto-posting? | Optional for 95%+ confidence |
| Persona approach? | Configurable per subreddit |
| Disclosure? | Configurable per subreddit |
| Post filtering? | Hybrid (keywords + AI pre-filter) |
| Engagement depth? | Full thread analysis |
| Rate limiting? | Platform limits + conservative caps |
| Competitor monitoring? | Alert only |
| Learning? | Full (confidence + style) |
| Notifications? | Daily digest |
| Lead capture? | CRM integration (multi-provider) |
| Multi-account? | Separate agent per account |
| Knowledge base? | Main KB + engagement context |
| Analytics? | Comprehensive |
| Platform priority? | Reddit → LinkedIn → Dev.to → HN |
| Rule awareness? | Parse, learn, adapt |
| MVP scope? | Scan + Approve + Post |

---

## References

- Reddit API: https://www.reddit.com/dev/api/
- Reddit OAuth: https://github.com/reddit-archive/reddit/wiki/OAuth2
- LinkedIn API: https://docs.microsoft.com/en-us/linkedin/
- Dev.to API: https://developers.forem.com/api
- Hacker News API: https://github.com/HackerNews/API
