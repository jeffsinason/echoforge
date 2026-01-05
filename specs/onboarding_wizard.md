---
title: Onboarding Wizard
version: "1.1"
status: deployed
project: SignShield
created: 2025-01-17
updated: 2025-12-22
---

# 1. Executive Summary

Guide new tenants through initial setup with a step-by-step onboarding wizard. The wizard helps users complete essential configuration: company profile, first waiver template, first event, team invitations, and a test signing flow. Progress is tracked and users can skip steps or return later.

# 2. Current System State

## 2.1 Existing Data Structures

| Entity | Key Fields | Relevance |
|--------|------------|-----------|
| Tenant | logo_url, primary_color, company_name | Company profile step |
| WaiverTemplate | name, content, tenant | Create template step |
| Event | name, date, tenant | Create event step |
| TenantUser | user, tenant, role | Team invite step |
| SigningLink | token, signer, event | Test signing step |

## 2.2 Current Gaps

- No onboarding flow
- No progress tracking for new users
- No guidance for first-time setup
- New users land on empty dashboard

# 3. Feature Requirements

## 3.1 Onboarding Progress Model

### Data Changes

```python
# apps/core/models.py (add to existing)

class TenantOnboarding(models.Model):
    """Tracks onboarding progress for a tenant"""

    tenant = models.OneToOneField(
        'Tenant',
        on_delete=models.CASCADE,
        related_name='onboarding'
    )

    # Step completion
    company_profile_completed = models.BooleanField(default=False)
    first_template_completed = models.BooleanField(default=False)
    first_event_completed = models.BooleanField(default=False)
    team_invite_completed = models.BooleanField(default=False)  # Can be skipped
    test_signing_completed = models.BooleanField(default=False)

    # Tracking
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    skipped_at = models.DateTimeField(null=True, blank=True)

    # References to created items (for display)
    first_template_id = models.UUIDField(null=True, blank=True)
    first_event_id = models.UUIDField(null=True, blank=True)

    class Meta:
        verbose_name = 'Tenant Onboarding'
        verbose_name_plural = 'Tenant Onboardings'

    def __str__(self):
        return f"Onboarding: {self.tenant.name}"

    @property
    def current_step(self):
        """Return the current step number (1-5) or None if complete"""
        if not self.company_profile_completed:
            return 1
        if not self.first_template_completed:
            return 2
        if not self.first_event_completed:
            return 3
        if not self.team_invite_completed:
            return 4
        if not self.test_signing_completed:
            return 5
        return None  # All complete

    @property
    def progress_percent(self):
        """Calculate completion percentage"""
        steps = [
            self.company_profile_completed,
            self.first_template_completed,
            self.first_event_completed,
            self.team_invite_completed,
            self.test_signing_completed,
        ]
        return int((sum(steps) / len(steps)) * 100)

    @property
    def is_complete(self):
        return self.completed_at is not None or self.skipped_at is not None

    def mark_complete(self):
        from django.utils import timezone
        if not self.completed_at:
            self.completed_at = timezone.now()
            self.save()

    def mark_skipped(self):
        from django.utils import timezone
        if not self.skipped_at:
            self.skipped_at = timezone.now()
            self.save()
```

| Field | Type | Description |
|-------|------|-------------|
| tenant | OneToOneField | Link to tenant |
| company_profile_completed | BooleanField | Step 1 complete |
| first_template_completed | BooleanField | Step 2 complete |
| first_event_completed | BooleanField | Step 3 complete |
| team_invite_completed | BooleanField | Step 4 complete (skippable) |
| test_signing_completed | BooleanField | Step 5 complete |
| started_at | DateTimeField | When onboarding began |
| completed_at | DateTimeField | When all steps finished |
| skipped_at | DateTimeField | When user chose to skip |

### Business Rules

- TenantOnboarding created automatically when tenant is created
- Steps must be completed in order (except team invite can be skipped)
- Users can skip individual steps or entire onboarding
- Skipped users can return to onboarding from dashboard
- Once all steps complete OR skipped, redirect to dashboard

## 3.2 Onboarding Flow Overview

### Steps

| Step | Name | Required | Description |
|------|------|----------|-------------|
| 1 | Company Profile | Yes | Upload logo, set colors, verify company info |
| 2 | Create Template | Yes | Create first waiver template (guided) |
| 3 | Create Event | Yes | Create first event |
| 4 | Invite Team | No | Invite additional team members (skippable) |
| 5 | Test Signing | Yes | Send yourself a test waiver to experience the flow |

### Navigation Rules

- Progress bar shows all 5 steps
- Current step is highlighted
- Completed steps show checkmark
- Can go back to completed steps
- Cannot skip ahead (except team invite)
- "Skip for now" always available
- "Skip onboarding" available to exit entirely

## 3.3 URL Structure

```python
# urls.py additions

urlpatterns = [
    path('onboarding/', OnboardingStartView.as_view(), name='onboarding_start'),
    path('onboarding/profile/', OnboardingProfileView.as_view(), name='onboarding_profile'),
    path('onboarding/template/', OnboardingTemplateView.as_view(), name='onboarding_template'),
    path('onboarding/event/', OnboardingEventView.as_view(), name='onboarding_event'),
    path('onboarding/team/', OnboardingTeamView.as_view(), name='onboarding_team'),
    path('onboarding/test/', OnboardingTestView.as_view(), name='onboarding_test'),
    path('onboarding/complete/', OnboardingCompleteView.as_view(), name='onboarding_complete'),
    path('onboarding/skip/', OnboardingSkipView.as_view(), name='onboarding_skip'),
]
```

## 3.4 Step 1: Company Profile

### UI Components

```
[Progress Bar: Step 1 of 5 - Company Profile]

[FORM CARD]
Headline: "Let's set up your company profile"
Subheadline: "This information appears on your waivers and emails"

[Logo Upload]
- Drag & drop or click to upload
- Preview of current logo (or placeholder)
- Accepts: PNG, JPG, SVG (max 2MB)

[Company Name]
- Pre-filled from registration
- Editable text field

[Brand Color]
- Color picker
- Hex input
- Preview of color in button/header

[Timezone]
- Dropdown of common timezones
- Auto-detect suggestion

[ACTIONS]
[Continue →] (primary)
[Skip for now] (secondary link)
```

### Form

```python
class OnboardingProfileForm(forms.ModelForm):
    class Meta:
        model = Tenant
        fields = ['company_name', 'logo_url', 'primary_color', 'timezone']
        widgets = {
            'company_name': forms.TextInput(attrs={'class': 'input'}),
            'primary_color': forms.TextInput(attrs={
                'class': 'input color-picker',
                'type': 'color',
            }),
            'timezone': forms.Select(attrs={'class': 'input'}),
        }

    logo_file = forms.ImageField(
        required=False,
        widget=forms.FileInput(attrs={'accept': 'image/*'}),
    )

    def clean_logo_file(self):
        logo = self.cleaned_data.get('logo_file')
        if logo:
            if logo.size > 2 * 1024 * 1024:  # 2MB
                raise forms.ValidationError('Logo must be less than 2MB')
        return logo
```

### View Logic

```python
class OnboardingProfileView(TenantRequiredMixin, UpdateView):
    template_name = 'onboarding/profile.html'
    form_class = OnboardingProfileForm
    success_url = '/onboarding/template/'

    def get_object(self):
        return self.request.tenant

    def form_valid(self, form):
        # Handle logo upload
        logo_file = form.cleaned_data.get('logo_file')
        if logo_file:
            # Save to storage and update logo_url
            pass

        # Mark step complete
        onboarding = self.request.tenant.onboarding
        onboarding.company_profile_completed = True
        onboarding.save()

        return super().form_valid(form)
```

## 3.5 Step 2: Create Waiver Template

### UI Components

```
[Progress Bar: Step 2 of 5 - Create Template]

[FORM CARD]
Headline: "Create your first waiver template"
Subheadline: "This is the document your participants will sign"

[Template Name]
- Text input
- Placeholder: "e.g., General Liability Waiver"

[Waiver Content]
- Rich text editor (TinyMCE or similar)
- Pre-filled with sample waiver text
- User can edit or replace entirely

[Video Requirement]
- Toggle: "Require video consent recording"
- Default: ON
- Help text: "Signers will record a video stating their name and consent"

[SAMPLE TEMPLATES]
"Or start from a template:"
- General Liability Waiver
- Activity Release Form
- Photo/Video Release
- Equipment Rental Agreement

[PREVIEW PANEL]
Live preview of how the waiver will appear to signers

[ACTIONS]
[Create Template & Continue →] (primary)
[Skip for now] (secondary link)
```

### Sample Template Content

```python
SAMPLE_WAIVER_TEMPLATES = {
    'general_liability': {
        'name': 'General Liability Waiver',
        'content': '''
<h2>Release and Waiver of Liability</h2>

<p>I, the undersigned participant, acknowledge that I am voluntarily participating
in activities provided by {company_name}.</p>

<p><strong>Assumption of Risk:</strong> I understand that participation involves
inherent risks including, but not limited to, physical injury. I knowingly and
freely assume all such risks and accept personal responsibility for any injury
or damages.</p>

<p><strong>Release of Liability:</strong> I hereby release, waive, and forever
discharge {company_name}, its officers, employees, agents, and representatives
from any and all liability, claims, demands, or causes of action that I may
have arising out of my participation.</p>

<p><strong>Medical Authorization:</strong> I authorize {company_name} to secure
emergency medical treatment if necessary.</p>

<p><strong>Acknowledgment:</strong> I have read this agreement, understand its
contents, and agree to its terms voluntarily.</p>
        ''',
    },
    # ... other templates
}
```

### View Logic

```python
class OnboardingTemplateView(TenantRequiredMixin, CreateView):
    template_name = 'onboarding/template.html'
    model = WaiverTemplate
    fields = ['name', 'content', 'require_video', 'video_max_seconds']
    success_url = '/onboarding/event/'

    def get_initial(self):
        # Pre-fill with sample template
        return {
            'name': 'General Liability Waiver',
            'content': SAMPLE_WAIVER_TEMPLATES['general_liability']['content'].format(
                company_name=self.request.tenant.company_name
            ),
            'require_video': True,
            'video_max_seconds': 30,
        }

    def form_valid(self, form):
        form.instance.tenant = self.request.tenant
        response = super().form_valid(form)

        # Mark step complete and save template reference
        onboarding = self.request.tenant.onboarding
        onboarding.first_template_completed = True
        onboarding.first_template_id = self.object.id
        onboarding.save()

        return response
```

## 3.6 Step 3: Create Event

### UI Components

```
[Progress Bar: Step 3 of 5 - Create Event]

[FORM CARD]
Headline: "Create your first event"
Subheadline: "Events help you organize waivers by date, class, or activity"

[Event Name]
- Text input
- Placeholder: "e.g., Saturday Morning Yoga Class"

[Event Date]
- Date picker
- Default: Tomorrow's date

[Waiver Template]
- Dropdown (pre-selects the one just created)
- Shows: "General Liability Waiver (just created)"

[Description] (optional)
- Textarea
- Placeholder: "Add any notes about this event"

[USE CASE EXAMPLES]
"Not sure what to call it? Here are examples:"
- Recurring class: "Tuesday 6pm CrossFit"
- One-time event: "Summer 5K Race 2024"
- Ongoing: "General Drop-in Participants"

[ACTIONS]
[Create Event & Continue →] (primary)
[Skip for now] (secondary link)
```

### View Logic

```python
class OnboardingEventView(TenantRequiredMixin, CreateView):
    template_name = 'onboarding/event.html'
    model = Event
    fields = ['name', 'date', 'waiver_template', 'description']
    success_url = '/onboarding/team/'

    def get_form(self, form_class=None):
        form = super().get_form(form_class)
        # Limit waiver_template choices to tenant's templates
        form.fields['waiver_template'].queryset = WaiverTemplate.objects.filter(
            tenant=self.request.tenant
        )
        # Pre-select the template created in previous step
        onboarding = self.request.tenant.onboarding
        if onboarding.first_template_id:
            form.fields['waiver_template'].initial = onboarding.first_template_id
        return form

    def get_initial(self):
        from datetime import date, timedelta
        return {
            'date': date.today() + timedelta(days=1),
        }

    def form_valid(self, form):
        form.instance.tenant = self.request.tenant
        response = super().form_valid(form)

        # Mark step complete
        onboarding = self.request.tenant.onboarding
        onboarding.first_event_completed = True
        onboarding.first_event_id = self.object.id
        onboarding.save()

        return response
```

## 3.7 Step 4: Invite Team (Skippable)

### UI Components

```
[Progress Bar: Step 4 of 5 - Invite Team]

[FORM CARD]
Headline: "Invite your team"
Subheadline: "Add colleagues who need access to manage waivers"

[INVITE FORM]
[Email input] [Role dropdown] [+ Add]

Roles:
- Admin: Full access, can manage team
- Staff: View and manage waivers, no team management

[PENDING INVITES LIST]
(Shows any emails added before clicking Continue)
- jeff@company.com (Admin) [Remove]
- sarah@company.com (Staff) [Remove]

[INFO BOX]
"Team members will receive an email invitation to join your account.
You can always add more team members later from Settings."

[ACTIONS]
[Send Invites & Continue →] (primary)
[Skip for now] (secondary) — marks step complete without inviting
[I'll do this later] (link)
```

### View Logic

```python
class OnboardingTeamView(TenantRequiredMixin, FormView):
    template_name = 'onboarding/team.html'
    form_class = TeamInviteForm
    success_url = '/onboarding/test/'

    def form_valid(self, form):
        # Send invites
        invites = form.cleaned_data.get('invites', [])
        for invite in invites:
            self.send_team_invite(invite['email'], invite['role'])

        # Mark step complete
        onboarding = self.request.tenant.onboarding
        onboarding.team_invite_completed = True
        onboarding.save()

        return super().form_valid(form)

    def post(self, request, *args, **kwargs):
        # Handle "Skip" button
        if 'skip' in request.POST:
            onboarding = request.tenant.onboarding
            onboarding.team_invite_completed = True
            onboarding.save()
            return redirect(self.success_url)
        return super().post(request, *args, **kwargs)

    def send_team_invite(self, email, role):
        # Create pending TenantUser and send invite email
        # (Implementation in separate team invite feature)
        pass
```

## 3.8 Step 5: Test Signing Flow

### UI Components

```
[Progress Bar: Step 5 of 5 - Test Signing]

[FORM CARD]
Headline: "Experience the signing flow"
Subheadline: "Send yourself a test waiver to see exactly what your participants will see"

[INFO BOX - How it works]
1. We'll create a test participant with your email
2. You'll receive a signing link via email
3. Complete the signing process (including video if enabled)
4. See the completed waiver in your dashboard

[YOUR EMAIL]
- Shows: jeff@company.com (your email)
- Checkbox: "Send to a different email instead"
- If checked, show email input

[TEST EVENT]
- Shows: "Saturday Morning Yoga Class" (the event just created)
- Read-only, for display

[PREVIEW]
"Here's what your signing email will look like:"
[Email preview mockup]

[ACTIONS]
[Send Test Waiver →] (primary)
[Skip & Finish] (secondary)
```

### View Logic

```python
class OnboardingTestView(TenantRequiredMixin, FormView):
    template_name = 'onboarding/test.html'
    form_class = TestSigningForm
    success_url = '/onboarding/complete/'

    def get_initial(self):
        return {
            'email': self.request.user.email,
        }

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        onboarding = self.request.tenant.onboarding

        # Get the event and template created earlier
        if onboarding.first_event_id:
            context['event'] = Event.objects.get(id=onboarding.first_event_id)
        if onboarding.first_template_id:
            context['template'] = WaiverTemplate.objects.get(id=onboarding.first_template_id)

        return context

    def form_valid(self, form):
        email = form.cleaned_data['email']
        onboarding = self.request.tenant.onboarding

        # Create or get Signer
        signer, _ = Signer.objects.get_or_create(
            tenant=self.request.tenant,
            email=email,
            defaults={
                'first_name': self.request.user.first_name,
                'last_name': self.request.user.last_name,
            }
        )

        # Get the event
        event = Event.objects.get(id=onboarding.first_event_id)

        # Create EventParticipant
        participant, _ = EventParticipant.objects.get_or_create(
            event=event,
            signer=signer,
        )

        # Create SigningLink
        signing_link = SigningLink.objects.create(
            tenant=self.request.tenant,
            event_participant=participant,
            signer=signer,
        )

        # Send signing email
        signing_link.send_email()

        # Mark step complete
        onboarding.test_signing_completed = True
        onboarding.save()

        # Store signing link for display on complete page
        self.request.session['test_signing_link_id'] = str(signing_link.id)

        return super().form_valid(form)
```

## 3.9 Completion Page

### UI Components

```
[SUCCESS ILLUSTRATION]

Headline: "You're all set!"
Subheadline: "Your SignShield account is ready to collect waivers"

[CHECKLIST - completed items]
✓ Company profile configured
✓ Waiver template created
✓ First event created
✓ Team invites sent (or: Skipped)
✓ Test waiver sent to jeff@company.com

[NEXT STEPS CARD]
"What's next?"

1. Check your email for the test waiver
   Complete the signing process to see the full experience

2. Add participants to your event
   Import from CSV or add manually

3. Explore your dashboard
   Track waivers, download PDFs, and manage events

[ACTIONS]
[Go to Dashboard →] (primary)
[View Test Waiver] (secondary - opens signing link in new tab)
```

### View Logic

```python
class OnboardingCompleteView(TenantRequiredMixin, TemplateView):
    template_name = 'onboarding/complete.html'

    def get(self, request, *args, **kwargs):
        # Mark onboarding as complete
        onboarding = request.tenant.onboarding
        onboarding.mark_complete()
        return super().get(request, *args, **kwargs)

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context['onboarding'] = self.request.tenant.onboarding

        # Get test signing link if available
        link_id = self.request.session.get('test_signing_link_id')
        if link_id:
            try:
                context['test_link'] = SigningLink.objects.get(id=link_id)
            except SigningLink.DoesNotExist:
                pass

        return context
```

## 3.10 Skip Onboarding

### Skip Options

1. **Skip individual step**: Marks step complete, moves to next
2. **Skip entire onboarding**: Marks all steps skipped, goes to dashboard

### UI Element

```
[In header or footer of each step]
"Skip this step" (link) — skips current step only
"Skip onboarding & go to dashboard" (link) — skips everything
```

### View

```python
class OnboardingSkipView(TenantRequiredMixin, View):
    def post(self, request):
        onboarding = request.tenant.onboarding
        skip_type = request.POST.get('skip_type', 'all')

        if skip_type == 'all':
            onboarding.mark_skipped()
            return redirect('/dashboard/')

        elif skip_type == 'step':
            step = request.POST.get('step')
            # Mark specific step as complete (skipped)
            if step == 'profile':
                onboarding.company_profile_completed = True
            elif step == 'template':
                onboarding.first_template_completed = True
            elif step == 'event':
                onboarding.first_event_completed = True
            elif step == 'team':
                onboarding.team_invite_completed = True
            elif step == 'test':
                onboarding.test_signing_completed = True
            onboarding.save()

            # Redirect to next step
            return redirect(self.get_next_step_url(onboarding))

    def get_next_step_url(self, onboarding):
        step = onboarding.current_step
        urls = {
            1: '/onboarding/profile/',
            2: '/onboarding/template/',
            3: '/onboarding/event/',
            4: '/onboarding/team/',
            5: '/onboarding/test/',
            None: '/onboarding/complete/',
        }
        return urls.get(step, '/dashboard/')
```

## 3.11 Dashboard Integration

### Return to Onboarding

If a user skips onboarding but hasn't completed key steps, show a banner on the dashboard:

```html
{% if not tenant.onboarding.is_complete and tenant.onboarding.progress_percent < 100 %}
<div class="onboarding-banner">
    <div class="banner-content">
        <strong>Complete your setup</strong>
        <p>Finish setting up your account to get the most out of SignShield.</p>
    </div>
    <div class="banner-progress">
        <div class="progress-bar" style="width: {{ tenant.onboarding.progress_percent }}%"></div>
        <span>{{ tenant.onboarding.progress_percent }}% complete</span>
    </div>
    <a href="/onboarding/" class="btn btn-secondary btn-sm">Continue Setup</a>
    <button class="banner-dismiss" data-dismiss="onboarding-banner">×</button>
</div>
{% endif %}
```

## 3.12 Base Onboarding Template

```html
<!-- templates/onboarding/base_onboarding.html -->
{% extends 'base.html' %}

{% block body_class %}onboarding-page{% endblock %}

{% block content %}
<div class="onboarding-container">

    <!-- Progress Bar -->
    <div class="onboarding-progress">
        <div class="progress-steps">
            {% for step in steps %}
            <div class="step {% if step.number < current_step %}completed{% elif step.number == current_step %}active{% endif %}">
                <div class="step-indicator">
                    {% if step.number < current_step %}
                        <svg class="icon-check"><!-- checkmark --></svg>
                    {% else %}
                        {{ step.number }}
                    {% endif %}
                </div>
                <span class="step-label">{{ step.name }}</span>
            </div>
            {% if not forloop.last %}
            <div class="step-connector {% if step.number < current_step %}completed{% endif %}"></div>
            {% endif %}
            {% endfor %}
        </div>
    </div>

    <!-- Step Content -->
    <div class="onboarding-content">
        {% block step_content %}{% endblock %}
    </div>

    <!-- Skip Link -->
    <div class="onboarding-footer">
        <form method="post" action="{% url 'onboarding_skip' %}">
            {% csrf_token %}
            <input type="hidden" name="skip_type" value="all">
            <button type="submit" class="link-button">
                Skip onboarding & go to dashboard
            </button>
        </form>
    </div>

</div>
{% endblock %}
```

# 4. Future Considerations (Out of Scope)

- Interactive product tour (tooltips on dashboard)
- Video walkthrough option
- Industry-specific onboarding paths
- Onboarding analytics (drop-off tracking)
- A/B testing different onboarding flows
- Checklist in dashboard sidebar (persistent)

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Data Model & Infrastructure**
1. Create TenantOnboarding model
2. Run migrations
3. Create TenantOnboarding automatically on Tenant creation (signal)
4. Set up URL routing
5. Create base onboarding template with progress bar

**Phase 2: Steps 1-3 (Core Flow)**
1. Company profile step (form + logo upload)
2. Create template step (with sample content)
3. Create event step
4. Wire up step progression

**Phase 3: Steps 4-5 (Social & Test)**
1. Team invite step (basic implementation)
2. Test signing step
3. Completion page

**Phase 4: Polish & Integration**
1. Skip functionality
2. Dashboard banner for incomplete onboarding
3. Mobile responsive adjustments
4. Edge case handling

## 5.2 Spec Dependencies

This spec has dependencies on other specs that must be implemented first.

### Dependency Chain

```
┌─────────────────────────────┐
│  tenant_self_registration   │
│  (Testing)                  │
│                             │
│  Provides:                  │
│  • TenantOnboarding trigger │
│  • Redirect to /onboarding/ │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐    ┌─────────────────────┐
│     onboarding_wizard       │◄───│  brand_guidelines   │
│     (This Spec)             │    │  (In Development)   │
│                             │    │                     │
│  Uses:                      │    │  Provides:          │
│  • Post-registration entry  │    │  • CSS styling      │
│  • Existing WaiverTemplate  │    │  • Component styles │
│  • Existing Event model     │    └─────────────────────┘
│  • Existing SigningLink     │
└─────────────────────────────┘
               │
               │ May resolve field issues for:
               ▼
┌─────────────────────────────┐
│  waiver_email_notifications │
│  (Draft)                    │
└─────────────────────────────┘
```

### Dependency Details

| Spec | Status | Required For | Specific Dependencies |
|------|--------|--------------|----------------------|
| **tenant_self_registration.md** | Testing | Entry point | Post-verification redirect, TenantOnboarding creation |
| **brand_guidelines.md** | In Development | UI styling | CSS variables, progress bar styling, form styles |

### What This Spec Provides To Others

| Downstream Spec | What We Provide |
|-----------------|-----------------|
| **waiver_email_notifications** | May fix Tenant field name issues (contact_email → owner_email, etc.) |

### Implementation Order

```
1. brand_guidelines.md           ─┐
2. planlimit_update.md            │
3. marketing_website.md           ├──► 5. onboarding_wizard.md
4. tenant_self_registration.md   ─┘
```

## 5.3 Infrastructure Dependencies

| Dependency | Notes |
|------------|-------|
| WaiverTemplate model | For step 2 (create template) |
| Event model | For step 3 (create event) |
| SigningLink + email | For step 5 (test signing flow) |
| File upload handling | For logo upload in step 1 |

# 6. Acceptance Criteria

## 6.1 Infrastructure

- [ ] TenantOnboarding model created and migrated
- [ ] TenantOnboarding created automatically for new tenants
- [ ] URL routing works for all steps
- [ ] Base template with progress bar renders correctly
- [ ] Progress bar updates correctly as steps complete

## 6.2 Step 1: Company Profile

- [ ] Logo upload works (drag & drop and click)
- [ ] Color picker works
- [ ] Timezone selector populated with options
- [ ] Form saves to Tenant model
- [ ] Step marked complete on success

## 6.3 Step 2: Create Template

- [ ] Sample template pre-filled
- [ ] Sample template selection works
- [ ] Rich text editor functional
- [ ] Video toggle works
- [ ] Template created and linked to tenant
- [ ] Step marked complete on success

## 6.4 Step 3: Create Event

- [ ] Date picker defaults to tomorrow
- [ ] Template dropdown shows tenant's templates
- [ ] Template from step 2 pre-selected
- [ ] Event created and linked to tenant
- [ ] Step marked complete on success

## 6.5 Step 4: Invite Team

- [ ] Can add multiple invites before submitting
- [ ] Can remove pending invites
- [ ] Role selection works
- [ ] Skip button works
- [ ] Invites sent on submit (if any)
- [ ] Step marked complete on success or skip

## 6.6 Step 5: Test Signing

- [ ] User's email pre-filled
- [ ] Can change to different email
- [ ] Test waiver created correctly
- [ ] Email sent with signing link
- [ ] Step marked complete on success

## 6.7 Completion & Skip

- [ ] Completion page shows summary of completed steps
- [ ] Link to test signing works
- [ ] Go to Dashboard button works
- [ ] Skip individual step works
- [ ] Skip entire onboarding works
- [ ] Dashboard banner shows for incomplete onboarding

## 6.8 Edge Cases

- [ ] Returning to onboarding continues from correct step
- [ ] Can go back to completed steps
- [ ] Cannot skip required steps
- [ ] Handles missing data gracefully

---
*End of Specification*
