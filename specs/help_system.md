---
title: Help System & Documentation
version: "1.0"
status: deployed
project: SignShield
created: 2025-12-23
updated: 2026-01-02
---

# 1. Executive Summary

Define and implement a comprehensive help system for SignShield that provides contextual in-app assistance, a searchable knowledge base, and getting-started guides. The help system supports both tenant users (business owners/staff) and signers (public waiver participants) with appropriate content for each audience.

# 2. Current System State

## 2.1 Existing Help Infrastructure

| Component | Status |
|-----------|--------|
| In-app tooltips | None |
| Help center | None |
| Contextual help links | None |
| Getting started guide | None (onboarding wizard provides guided setup) |
| API documentation | None |
| Admin documentation | None |

## 2.2 Current Gaps

- No help text on form fields
- No explanation of features for new users
- No searchable documentation
- No troubleshooting guides
- No FAQ system
- No contextual "Learn more" links
- Signers have no help during waiver signing

# 3. Help System Architecture

## 3.1 Help Content Types

| Type | Audience | Location | Purpose |
|------|----------|----------|---------|
| **Field Hints** | Tenant users | Form fields | Explain what to enter |
| **Tooltips** | Tenant users | UI elements | Explain features |
| **Contextual Help** | Tenant users | Help sidebar/modal | Deeper explanation |
| **Knowledge Base** | Tenant users | /help/ pages | Searchable articles |
| **Getting Started** | New tenants | Dashboard + /help/ | Guided orientation |
| **Signer Help** | Public signers | Signing page | Signing assistance |
| **API Docs** | Developers | /docs/api/ | API reference |

## 3.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HELP SYSTEM ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        IN-APP HELP LAYER                             │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │   │
│  │  │ Field Hints  │  │   Tooltips   │  │   Help Sidebar/Modal     │  │   │
│  │  │              │  │              │  │                          │  │   │
│  │  │ "Maximum 30  │  │ [?] icon     │  │  Context-aware help      │  │   │
│  │  │  seconds"    │  │ on hover     │  │  panel with "Learn more" │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    │ Links to                               │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       KNOWLEDGE BASE (/help/)                        │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │   │
│  │  │Getting Started│  │   Guides    │  │    Troubleshooting       │  │   │
│  │  │              │  │              │  │                          │  │   │
│  │  │ • Quick start│  │ • Waivers   │  │ • Common issues          │  │   │
│  │  │ • First event│  │ • Events    │  │ • Video problems         │  │   │
│  │  │ • First waiver│ │ • Kiosks    │  │ • Email delivery         │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │   │
│  │                                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │   │
│  │  │     FAQ      │  │   Billing   │  │      API Docs            │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      SIGNER HELP (Public)                            │   │
│  │                                                                      │   │
│  │  Minimal, focused help for waiver signing:                          │   │
│  │  • "What is video verification?"                                    │   │
│  │  • "How do I sign?"                                                 │   │
│  │  • "Having trouble with your camera?"                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

# 4. Feature Requirements

## 4.1 In-App Help Components

### 4.1.1 Field Hints

Small helper text below form fields.

```html
<!-- Template pattern -->
<div class="form-group">
    <label for="video_max_seconds">Maximum Video Length</label>
    <input type="number" id="video_max_seconds" name="video_max_seconds" value="30">
    <small class="form-hint">
        How long signers can record their consent video (5-60 seconds).
    </small>
</div>
```

**Implementation:** Add `help_text` to Django model fields and render in templates.

```python
# Example: apps/waivers/models.py
video_max_seconds = models.PositiveIntegerField(
    default=30,
    help_text="How long signers can record their consent video (5-60 seconds)."
)
```

### 4.1.2 Tooltips

Icon-triggered help for UI elements.

```html
<!-- Template pattern -->
<div class="feature-header">
    <h3>Video Verification</h3>
    <button class="help-tooltip"
            data-tooltip="Video verification adds legal weight to waivers by recording signers stating their name and consent.">
        <span class="icon-help">?</span>
    </button>
</div>
```

**CSS:**
```css
.help-tooltip {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--color-gray-200);
    color: var(--color-gray-600);
    font-size: 12px;
    cursor: help;
    border: none;
}

.help-tooltip:hover {
    background: var(--color-primary);
    color: white;
}

.help-tooltip[data-tooltip]:hover::after {
    content: attr(data-tooltip);
    position: absolute;
    /* tooltip styling */
}
```

### 4.1.3 Contextual Help Sidebar

Slide-out panel with context-aware help content.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Dashboard                                              [?] Help  [×] Close │
├────────────────────────────────────────────────┬────────────────────────────┤
│                                                │                            │
│  [Main content area]                           │  HELP                      │
│                                                │  ────                      │
│                                                │                            │
│                                                │  📖 Events                 │
│                                                │                            │
│                                                │  Events help you organize  │
│                                                │  participants and track    │
│                                                │  waiver status.            │
│                                                │                            │
│                                                │  Quick Tips:               │
│                                                │  • Create an event for     │
│                                                │    each activity or date   │
│                                                │  • Import participants     │
│                                                │    via CSV                 │
│                                                │  • Send bulk signing links │
│                                                │                            │
│                                                │  [📚 Full Guide →]         │
│                                                │  [❓ FAQs →]               │
│                                                │                            │
└────────────────────────────────────────────────┴────────────────────────────┘
```

**Implementation:**

```python
# apps/help/models.py

class ContextualHelp(models.Model):
    """Context-aware help content for specific pages/features."""

    # Context matching
    page_key = models.CharField(
        max_length=100,
        unique=True,
        help_text="Matches URL path or feature key (e.g., 'events.list', 'templates.create')"
    )

    # Content
    title = models.CharField(max_length=100)
    summary = models.TextField(help_text="Brief explanation (2-3 sentences)")
    tips = models.JSONField(
        default=list,
        help_text="List of quick tips as strings"
    )

    # Links
    guide_article = models.ForeignKey(
        'HelpArticle',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='contextual_guide'
    )
    faq_category = models.CharField(max_length=50, blank=True)

    # Visibility
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "Contextual Help"
        verbose_name_plural = "Contextual Help"

    def __str__(self):
        return f"{self.page_key}: {self.title}"
```

### 4.1.4 Help Trigger Button

Persistent help button in dashboard header.

```html
<!-- In base_dashboard.html -->
<header class="dashboard-header">
    <nav>...</nav>
    <div class="header-actions">
        <button id="help-trigger" class="btn-help" aria-label="Open help">
            <span class="icon-help">?</span>
            <span class="btn-text">Help</span>
        </button>
    </div>
</header>
```

```javascript
// help.js
document.getElementById('help-trigger').addEventListener('click', () => {
    const pageKey = document.body.dataset.helpContext || 'dashboard';
    openHelpSidebar(pageKey);
});

async function openHelpSidebar(pageKey) {
    const response = await fetch(`/api/v1/help/context/${pageKey}/`);
    const helpData = await response.json();
    renderHelpSidebar(helpData);
}
```

## 4.2 Knowledge Base

### 4.2.1 Data Model

```python
# apps/help/models.py

class HelpCategory(models.Model):
    """Categories for organizing help articles."""

    name = models.CharField(max_length=100)
    slug = models.SlugField(unique=True)
    description = models.TextField(blank=True)
    icon = models.CharField(max_length=50, blank=True, help_text="Icon class name")
    order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['order', 'name']
        verbose_name_plural = "Help Categories"

    def __str__(self):
        return self.name


class HelpArticle(models.Model):
    """Knowledge base articles."""

    AUDIENCE_CHOICES = [
        ('tenant', 'Tenant Users'),
        ('signer', 'Signers'),
        ('developer', 'Developers'),
        ('all', 'All Audiences'),
    ]

    # Identification
    title = models.CharField(max_length=200)
    slug = models.SlugField(unique=True)
    category = models.ForeignKey(
        HelpCategory,
        on_delete=models.CASCADE,
        related_name='articles'
    )

    # Content
    summary = models.TextField(help_text="Brief summary shown in search results")
    content = models.TextField(help_text="Full article content (Markdown supported)")

    # Metadata
    audience = models.CharField(max_length=20, choices=AUDIENCE_CHOICES, default='tenant')
    related_feature = models.CharField(
        max_length=50,
        blank=True,
        help_text="Feature key for contextual linking (e.g., 'events', 'kiosk')"
    )

    # SEO
    meta_description = models.CharField(max_length=160, blank=True)

    # Ordering & Status
    order = models.PositiveIntegerField(default=0)
    is_featured = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['category', 'order', 'title']

    def __str__(self):
        return self.title


class FAQ(models.Model):
    """Frequently asked questions."""

    question = models.CharField(max_length=300)
    answer = models.TextField()
    category = models.ForeignKey(
        HelpCategory,
        on_delete=models.CASCADE,
        related_name='faqs'
    )

    # Linking
    related_article = models.ForeignKey(
        HelpArticle,
        on_delete=models.SET_NULL,
        null=True, blank=True
    )

    # Ordering & Status
    order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['category', 'order']
        verbose_name = "FAQ"
        verbose_name_plural = "FAQs"

    def __str__(self):
        return self.question[:50]
```

### 4.2.2 Knowledge Base Categories

| Category | Slug | Icon | Description |
|----------|------|------|-------------|
| Getting Started | `getting-started` | 🚀 | New user orientation |
| Waiver Templates | `templates` | 📝 | Creating and managing templates |
| Events | `events` | 📅 | Event management and participants |
| Signing & Collection | `signing` | ✍️ | How signing works, sending links |
| Kiosk Mode | `kiosk` | 📱 | Setting up and using kiosks |
| Team & Permissions | `team` | 👥 | Managing team members |
| Billing & Plans | `billing` | 💳 | Plans, payments, invoices |
| Account Settings | `settings` | ⚙️ | Account and tenant configuration |
| Troubleshooting | `troubleshooting` | 🔧 | Common issues and solutions |
| API & Integrations | `api` | 🔌 | Developer documentation |

### 4.2.3 Knowledge Base URLs

```python
# apps/help/urls.py

urlpatterns = [
    # Main help center
    path('help/', views.HelpHomeView.as_view(), name='help_home'),

    # Category pages
    path('help/<slug:category_slug>/', views.HelpCategoryView.as_view(), name='help_category'),

    # Article pages
    path('help/<slug:category_slug>/<slug:article_slug>/', views.HelpArticleView.as_view(), name='help_article'),

    # Search
    path('help/search/', views.HelpSearchView.as_view(), name='help_search'),

    # FAQ
    path('help/faq/', views.FAQView.as_view(), name='help_faq'),

    # API for contextual help
    path('api/v1/help/context/<str:page_key>/', views.ContextualHelpAPIView.as_view(), name='help_context_api'),
    path('api/v1/help/search/', views.HelpSearchAPIView.as_view(), name='help_search_api'),
]
```

### 4.2.4 Knowledge Base UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SignShield Help Center                                    [🔍 Search help] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  🚀 GETTING STARTED                                                   │ │
│  │  New to SignShield? Start here.                                       │ │
│  │  [Quick Start Guide] [Create Your First Waiver] [Send Signing Links] │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  BROWSE BY TOPIC                                                            │
│  ─────────────────                                                          │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ 📝 Templates │  │ 📅 Events   │  │ ✍️ Signing  │  │ 📱 Kiosk    │       │
│  │             │  │             │  │             │  │             │       │
│  │ 5 articles  │  │ 8 articles  │  │ 6 articles  │  │ 4 articles  │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ 👥 Team     │  │ 💳 Billing  │  │ ⚙️ Settings │  │ 🔧 Trouble- │       │
│  │             │  │             │  │             │  │    shooting │       │
│  │ 3 articles  │  │ 7 articles  │  │ 4 articles  │  │ 10 articles │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│  FREQUENTLY ASKED QUESTIONS                                                 │
│  ──────────────────────────────                                             │
│                                                                             │
│  ▶ How do I add video verification to my waivers?                          │
│  ▶ Can signers use their phone to sign?                                    │
│  ▶ How do I export signed waivers as PDFs?                                 │
│  ▶ What happens when I exceed my plan limits?                              │
│  [View all FAQs →]                                                         │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Can't find what you're looking for? [Contact Support]                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4.3 Signer Help

Minimal help for public waiver signing pages.

### 4.3.1 Signer Help Modal

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Need Help Signing?                                                    [×]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ▼ What is video verification?                                             │
│    Video verification records you stating your name and that you agree     │
│    to the waiver terms. This provides additional legal protection for      │
│    both you and the business.                                              │
│                                                                             │
│  ▼ How do I record my video?                                               │
│    1. Click "Start Recording"                                              │
│    2. State your full name                                                 │
│    3. Say "I have read and agree to this waiver"                          │
│    4. Click "Stop Recording"                                               │
│                                                                             │
│  ▼ My camera isn't working                                                 │
│    • Make sure you've allowed camera access in your browser                │
│    • Try refreshing the page                                               │
│    • Check that no other app is using your camera                          │
│    • Try a different browser (Chrome works best)                           │
│                                                                             │
│  ▼ How do I sign on the signature pad?                                     │
│    Use your finger (on touch screens) or mouse to draw your signature.     │
│    Click "Clear" to start over if needed.                                  │
│                                                                             │
│  ▼ I'm signing for a minor                                                 │
│    If you're a parent or guardian signing for someone under 18, make       │
│    sure to select "I am signing as a guardian" and enter the minor's       │
│    information.                                                             │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Still having trouble? Contact {business_name}: {support_email}            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.3.2 Signer Help Implementation

```python
# Static content, no database needed
# apps/waivers/templates/waivers/partials/signer_help_modal.html

SIGNER_HELP_ITEMS = [
    {
        'question': 'What is video verification?',
        'answer': 'Video verification records you stating your name and that you agree...',
    },
    {
        'question': 'How do I record my video?',
        'answer': '1. Click "Start Recording"\n2. State your full name...',
    },
    # ... etc
]
```

## 4.4 Search Functionality

### 4.4.1 Search Implementation

```python
# apps/help/views.py

from django.contrib.postgres.search import SearchVector, SearchQuery, SearchRank

class HelpSearchView(View):
    def get(self, request):
        query = request.GET.get('q', '').strip()

        if not query or len(query) < 2:
            return render(request, 'help/search.html', {'results': [], 'query': query})

        # Search articles
        search_vector = SearchVector('title', weight='A') + \
                        SearchVector('summary', weight='B') + \
                        SearchVector('content', weight='C')
        search_query = SearchQuery(query)

        articles = HelpArticle.objects.annotate(
            rank=SearchRank(search_vector, search_query)
        ).filter(
            rank__gte=0.1,
            is_active=True
        ).order_by('-rank')[:20]

        # Search FAQs
        faqs = FAQ.objects.filter(
            Q(question__icontains=query) | Q(answer__icontains=query),
            is_active=True
        )[:10]

        return render(request, 'help/search.html', {
            'query': query,
            'articles': articles,
            'faqs': faqs,
        })
```

### 4.4.2 Search UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Search: "video not working"                               [🔍 Search]     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  5 results for "video not working"                                          │
│                                                                             │
│  📄 Troubleshooting Video Recording Issues                                  │
│     Common solutions for video problems during waiver signing...            │
│     Category: Troubleshooting                                               │
│                                                                             │
│  📄 Video Verification Requirements                                         │
│     Learn about browser and device requirements for video...                │
│     Category: Signing & Collection                                          │
│                                                                             │
│  ❓ FAQ: My camera isn't working, what should I do?                         │
│     First, check that you've allowed camera permissions...                  │
│                                                                             │
│  ❓ FAQ: Can signers skip video if their camera doesn't work?               │
│     Video requirements are set per template. If required...                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4.5 Help Content from Feature Specs

Each feature spec should include a "Help Content" section defining:

```markdown
# X. Help Content Requirements

## X.1 Field Hints

| Field | Help Text |
|-------|-----------|
| `field_name` | "Help text to display below field" |

## X.2 Tooltips

| Element | Tooltip Text |
|---------|--------------|
| Feature name | "Explanation of what this feature does" |

## X.3 Knowledge Base Articles

| Article Title | Category | Key Points |
|---------------|----------|------------|
| "How to [do thing]" | category-slug | • Point 1 • Point 2 |

## X.4 FAQs

| Question | Answer Summary |
|----------|----------------|
| "How do I...?" | Brief answer pointing to article if needed |
```

# 5. Initial Content Structure

## 5.1 Getting Started Articles

| # | Article | Summary |
|---|---------|---------|
| 1 | Quick Start Guide | 5-minute overview of SignShield |
| 2 | Creating Your First Waiver Template | Step-by-step template creation |
| 3 | Setting Up Your First Event | Creating and configuring events |
| 4 | Sending Signing Links | How to invite participants to sign |
| 5 | Understanding Your Dashboard | Dashboard overview and metrics |

## 5.2 Core Feature Articles

| Category | Articles |
|----------|----------|
| **Templates** | Creating templates, Video settings, Template variables, Cloning templates, Archive templates |
| **Events** | Create events, Import participants (CSV), Event status tracking, Bulk actions, Archive events |
| **Signing** | How signing works, Email invitations, Signing link expiration, Reminder emails, PDF generation |
| **Kiosk** | Setting up kiosk mode, Device registration, Offline mode, Minor participant flow, Kiosk best practices |
| **Team** | Inviting team members, Roles and permissions, Removing members |
| **Billing** | Understanding plans, Upgrading/downgrading, Payment methods, Invoices, Plan limits |

## 5.3 Essential FAQs

| Question | Category |
|----------|----------|
| How do I add video verification to my waivers? | Templates |
| Can signers use their phone to sign? | Signing |
| How do I export signed waivers as PDFs? | Signing |
| What happens when I exceed my plan limits? | Billing |
| Can I customize the signing page with my branding? | Templates |
| How long are signing links valid? | Signing |
| Can I use SignShield offline at events? | Kiosk |
| How do I cancel my subscription? | Billing |
| Is SignShield HIPAA compliant? | Settings |
| How do I transfer ownership of my account? | Settings |

# 6. Implementation Approach

## 6.1 Recommended Phases

**Phase 1: Infrastructure**
1. Create `apps/help` Django app
2. Create HelpCategory, HelpArticle, FAQ, ContextualHelp models
3. Run migrations
4. Set up admin interface for content management
5. Create base help templates

**Phase 2: In-App Help**
1. Add help button to dashboard header
2. Implement contextual help sidebar
3. Add tooltip component (CSS + JS)
4. Ensure all form fields have help_text
5. Add `data-help-context` attributes to pages

**Phase 3: Knowledge Base**
1. Create help center home page
2. Create category and article templates
3. Implement search functionality
4. Create FAQ accordion component
5. Add breadcrumb navigation

**Phase 4: Content**
1. Write Getting Started articles
2. Write core feature articles
3. Create FAQs
4. Add contextual help entries for all dashboard pages
5. Review and audit field hints across all forms

**Phase 5: Signer Help**
1. Create signer help modal component
2. Add help trigger to signing page
3. Write signer-focused help content
4. Test on mobile devices

## 6.2 Spec Dependencies

This spec has no hard dependencies on other specs, but help content should be written **after** features are implemented.

### Content Timing

| Feature Spec | Help Content Timing |
|--------------|---------------------|
| brand_guidelines | After - document branding options |
| marketing_website | N/A - public pages, not user help |
| tenant_self_registration | After - document signup process |
| onboarding_wizard | After - document onboarding steps |
| kiosk_mode | After - document kiosk setup |
| waiver_email_notifications | After - document notification settings |
| plan_enforcement | After - document plan limits and overages |
| waiver_archival | After - document archive access |

### Recommendation

Add "Help Content Requirements" section to each feature spec during design. Implement help content as part of feature completion, not as a separate phase.

## 6.3 Infrastructure Dependencies

| Dependency | Notes |
|------------|-------|
| PostgreSQL full-text search | For article/FAQ search |
| Markdown renderer | For article content (e.g., `markdown` package) |
| Django admin | For content management |

# 7. Admin Interface

## 7.1 Content Management

```python
# apps/help/admin.py

@admin.register(HelpCategory)
class HelpCategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'order', 'is_active', 'article_count']
    list_editable = ['order', 'is_active']
    prepopulated_fields = {'slug': ('name',)}

    def article_count(self, obj):
        return obj.articles.count()


@admin.register(HelpArticle)
class HelpArticleAdmin(admin.ModelAdmin):
    list_display = ['title', 'category', 'audience', 'is_featured', 'is_active', 'updated_at']
    list_filter = ['category', 'audience', 'is_featured', 'is_active']
    list_editable = ['is_featured', 'is_active']
    search_fields = ['title', 'summary', 'content']
    prepopulated_fields = {'slug': ('title',)}

    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'category', 'audience')
        }),
        ('Content', {
            'fields': ('summary', 'content'),
        }),
        ('Linking', {
            'fields': ('related_feature',),
        }),
        ('SEO', {
            'fields': ('meta_description',),
            'classes': ('collapse',),
        }),
        ('Status', {
            'fields': ('order', 'is_featured', 'is_active'),
        }),
    )


@admin.register(FAQ)
class FAQAdmin(admin.ModelAdmin):
    list_display = ['question_preview', 'category', 'order', 'is_active']
    list_filter = ['category', 'is_active']
    list_editable = ['order', 'is_active']
    search_fields = ['question', 'answer']

    def question_preview(self, obj):
        return obj.question[:60] + '...' if len(obj.question) > 60 else obj.question


@admin.register(ContextualHelp)
class ContextualHelpAdmin(admin.ModelAdmin):
    list_display = ['page_key', 'title', 'is_active']
    list_filter = ['is_active']
    search_fields = ['page_key', 'title']
```

# 8. Acceptance Criteria

## 8.1 Infrastructure

- [ ] `apps/help` Django app created
- [ ] HelpCategory model with admin
- [ ] HelpArticle model with admin
- [ ] FAQ model with admin
- [ ] ContextualHelp model with admin
- [ ] URL routing configured
- [ ] Base templates created

## 8.2 In-App Help

- [ ] Help button visible in dashboard header
- [ ] Contextual help sidebar opens on click
- [ ] Sidebar content changes based on current page
- [ ] "Learn more" links navigate to knowledge base
- [ ] Tooltips display on hover for [?] icons
- [ ] All form fields have help_text displayed

## 8.3 Knowledge Base

- [ ] Help center home page accessible at /help/
- [ ] Categories display with article counts
- [ ] Category pages list articles
- [ ] Article pages render Markdown content
- [ ] Search returns relevant articles and FAQs
- [ ] FAQ page with expandable answers
- [ ] Breadcrumb navigation works
- [ ] Mobile responsive layout

## 8.4 Signer Help

- [ ] Help link visible on signing page
- [ ] Signer help modal opens with FAQ-style content
- [ ] Camera troubleshooting info included
- [ ] Signature help included
- [ ] Minor/guardian signing explained
- [ ] Business contact info displayed

## 8.5 Content

- [ ] All Getting Started articles written
- [ ] Core feature articles written
- [ ] At least 10 FAQs created
- [ ] Contextual help entries for all dashboard pages
- [ ] All form fields have appropriate help_text

---

# Changelog

## v1.0 - 2025-12-23
- Initial specification
- In-app help architecture (tooltips, field hints, contextual sidebar)
- Knowledge base structure and data models
- Signer help modal design
- Search functionality
- Content management via Django admin

---
*End of Specification*
