---
title: Tenant Self-Registration
version: "1.2"
status: deployed
project: SignShield
created: 2025-01-17
updated: 2025-12-25
---

# 1. Executive Summary

Enable businesses to self-register for SignShield without admin intervention. New users complete a registration form, verify their email, and gain immediate access to a Free plan account. The flow creates both a Tenant and the initial owner TenantUser in a single transaction.

# 2. Current System State

## 2.1 Existing Data Structures

| Entity | Key Fields | Current Usage |
|--------|------------|---------------|
| Tenant | name, slug, company_name, owner_email, plan, is_active | Created via Django admin only |
| TenantUser | user, tenant, role, is_active, accepted_at | Links Django users to tenants |
| User (Django) | username, email, password, first_name, last_name | Standard Django auth |

## 2.2 Existing Workflows

- Tenants created manually in Django admin
- Users created manually and linked to tenants
- No public registration flow

## 2.3 Current Gaps

- No self-service registration
- No email verification system
- No duplicate slug checking UI
- No welcome email system

# 3. Feature Requirements

## 3.1 Email Verification Token Model

### Data Changes

```python
# apps/core/models.py (add to existing file)

class EmailVerificationToken(models.Model):
    """Token for verifying email during registration"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField()
    token = models.CharField(max_length=64, unique=True, db_index=True)

    # Registration data (stored until verified)
    registration_data = models.JSONField()
    # Contains: first_name, last_name, company_name, tenant_name, slug, password_hash

    # Tracking
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    verified_at = models.DateTimeField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.email} - {self.created_at.date()}"

    @property
    def is_expired(self):
        from django.utils import timezone
        return timezone.now() > self.expires_at

    @property
    def is_used(self):
        return self.verified_at is not None

    @classmethod
    def create_for_registration(cls, email, registration_data, ip_address=None):
        """Create a new verification token"""
        import secrets
        from django.utils import timezone
        from datetime import timedelta

        token = secrets.token_urlsafe(48)  # 64 chars
        expires_at = timezone.now() + timedelta(hours=24)

        return cls.objects.create(
            email=email,
            token=token,
            registration_data=registration_data,
            expires_at=expires_at,
            ip_address=ip_address,
        )
```

| Field | Type | Description |
|-------|------|-------------|
| id | UUIDField | Primary key |
| email | EmailField | Email being verified |
| token | CharField(64) | URL-safe verification token |
| registration_data | JSONField | Encrypted registration form data |
| created_at | DateTimeField | When token was created |
| expires_at | DateTimeField | When token expires (24 hours) |
| verified_at | DateTimeField | When email was verified (null if pending) |
| ip_address | GenericIPAddressField | IP that requested registration |

### Business Rules

- Tokens expire after 24 hours
- Old unverified tokens for same email are deleted when new one is created
- Token can only be used once (verified_at set on use)
- Password is hashed before storing in registration_data

## 3.2 Registration Form

### Form Fields

```python
# apps/core/forms.py

from django import forms
from django.contrib.auth.password_validation import validate_password
from django.core.validators import RegexValidator
from .models import Tenant

slug_validator = RegexValidator(
    regex=r'^[a-z][a-z0-9-]*[a-z0-9]$',
    message='Must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number.'
)

class TenantRegistrationForm(forms.Form):
    # Personal Info
    first_name = forms.CharField(
        max_length=30,
        widget=forms.TextInput(attrs={
            'placeholder': 'First name',
            'class': 'input',
            'autocomplete': 'given-name',
        })
    )
    last_name = forms.CharField(
        max_length=30,
        widget=forms.TextInput(attrs={
            'placeholder': 'Last name',
            'class': 'input',
            'autocomplete': 'family-name',
        })
    )
    email = forms.EmailField(
        widget=forms.EmailInput(attrs={
            'placeholder': 'you@company.com',
            'class': 'input',
            'autocomplete': 'email',
        })
    )

    # Company Info
    company_name = forms.CharField(
        max_length=200,
        widget=forms.TextInput(attrs={
            'placeholder': 'Your company name',
            'class': 'input',
            'autocomplete': 'organization',
        })
    )
    slug = forms.CharField(
        max_length=50,
        min_length=3,
        validators=[slug_validator],
        widget=forms.TextInput(attrs={
            'placeholder': 'yourcompany',
            'class': 'input slug-input',
            'autocomplete': 'off',
        }),
        help_text='This will be your subdomain: yourcompany.signshield.io'
    )

    # Password
    password = forms.CharField(
        min_length=8,
        widget=forms.PasswordInput(attrs={
            'placeholder': 'Create a password',
            'class': 'input',
            'autocomplete': 'new-password',
        })
    )
    password_confirm = forms.CharField(
        widget=forms.PasswordInput(attrs={
            'placeholder': 'Confirm password',
            'class': 'input',
            'autocomplete': 'new-password',
        })
    )

    # Terms
    accept_terms = forms.BooleanField(
        required=True,
        widget=forms.CheckboxInput(attrs={'class': 'checkbox'}),
        label='I agree to the Terms of Service and Privacy Policy'
    )

    def clean_email(self):
        email = self.cleaned_data['email'].lower()
        # Check if email already exists
        from django.contrib.auth import get_user_model
        User = get_user_model()
        if User.objects.filter(email=email).exists():
            raise forms.ValidationError('An account with this email already exists.')
        return email

    def clean_slug(self):
        slug = self.cleaned_data['slug'].lower()
        # Check if slug is taken
        if Tenant.objects.filter(slug=slug).exists():
            raise forms.ValidationError('This subdomain is already taken.')
        # Check reserved slugs
        reserved = ['www', 'app', 'api', 'admin', 'mail', 'support', 'help', 'blog', 'status']
        if slug in reserved:
            raise forms.ValidationError('This subdomain is reserved.')
        return slug

    def clean(self):
        cleaned_data = super().clean()
        password = cleaned_data.get('password')
        password_confirm = cleaned_data.get('password_confirm')

        if password and password_confirm:
            if password != password_confirm:
                raise forms.ValidationError({'password_confirm': 'Passwords do not match.'})
            # Validate password strength
            validate_password(password)

        return cleaned_data
```

### UI Flow

1. User navigates to `/signup/`
2. Form displays with all fields
3. Slug field has real-time availability check (AJAX)
4. On submit:
   - Validate all fields
   - Check email not already registered
   - Check slug availability
   - Create EmailVerificationToken with hashed password
   - Send verification email
   - Redirect to `/signup/verify-email/`

## 3.3 Slug Availability Check (AJAX)

### Endpoint

```python
# apps/core/views.py

from django.http import JsonResponse
from django.views import View
from .models import Tenant

class CheckSlugAvailabilityView(View):
    """AJAX endpoint for real-time slug checking"""

    def get(self, request):
        slug = request.GET.get('slug', '').lower().strip()

        if not slug:
            return JsonResponse({'available': False, 'error': 'Slug is required'})

        if len(slug) < 3:
            return JsonResponse({'available': False, 'error': 'Must be at least 3 characters'})

        if len(slug) > 50:
            return JsonResponse({'available': False, 'error': 'Must be 50 characters or less'})

        # Check format
        import re
        if not re.match(r'^[a-z][a-z0-9-]*[a-z0-9]$', slug):
            return JsonResponse({
                'available': False,
                'error': 'Must start with a letter and contain only lowercase letters, numbers, and hyphens'
            })

        # Check reserved
        reserved = ['www', 'app', 'api', 'admin', 'mail', 'support', 'help', 'blog', 'status']
        if slug in reserved:
            return JsonResponse({'available': False, 'error': 'This subdomain is reserved'})

        # Check database
        exists = Tenant.objects.filter(slug=slug).exists()

        return JsonResponse({
            'available': not exists,
            'error': 'This subdomain is already taken' if exists else None,
            'preview': f'{slug}.signshield.io'
        })
```

### URL

```python
# urls.py
path('api/check-slug/', CheckSlugAvailabilityView.as_view(), name='check_slug'),
```

### JavaScript

```javascript
// Debounced slug check
const slugInput = document.querySelector('.slug-input');
const slugFeedback = document.querySelector('.slug-feedback');
let debounceTimer;

slugInput.addEventListener('input', function() {
    const slug = this.value.toLowerCase().trim();
    clearTimeout(debounceTimer);

    if (slug.length < 3) {
        slugFeedback.innerHTML = '';
        return;
    }

    debounceTimer = setTimeout(async () => {
        const response = await fetch(`/api/check-slug/?slug=${encodeURIComponent(slug)}`);
        const data = await response.json();

        if (data.available) {
            slugFeedback.innerHTML = `<span class="text-success">✓ ${data.preview} is available</span>`;
        } else {
            slugFeedback.innerHTML = `<span class="text-error">✗ ${data.error}</span>`;
        }
    }, 300);
});
```

## 3.4 Registration View

### Pseudo Code

```python
# apps/core/views.py

from django.views.generic import FormView
from django.contrib.auth.hashers import make_password
from .forms import TenantRegistrationForm
from .models import EmailVerificationToken

class RegisterView(FormView):
    template_name = 'registration/signup.html'
    form_class = TenantRegistrationForm
    success_url = '/signup/verify-email/'

    def dispatch(self, request, *args, **kwargs):
        # Redirect logged-in users
        if request.user.is_authenticated:
            return redirect('/dashboard/')
        return super().dispatch(request, *args, **kwargs)

    def form_valid(self, form):
        data = form.cleaned_data

        # Hash password before storing
        registration_data = {
            'first_name': data['first_name'],
            'last_name': data['last_name'],
            'company_name': data['company_name'],
            'tenant_name': data['company_name'],  # Default tenant name to company name
            'slug': data['slug'],
            'password_hash': make_password(data['password']),
        }

        # Delete any existing unverified tokens for this email
        EmailVerificationToken.objects.filter(
            email=data['email'],
            verified_at__isnull=True
        ).delete()

        # Create verification token
        token = EmailVerificationToken.create_for_registration(
            email=data['email'],
            registration_data=registration_data,
            ip_address=self.get_client_ip(),
        )

        # Send verification email
        self.send_verification_email(data['email'], token)

        # Store email in session for display on verify page
        self.request.session['pending_verification_email'] = data['email']

        return super().form_valid(form)

    def get_client_ip(self):
        x_forwarded_for = self.request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            return x_forwarded_for.split(',')[0]
        return self.request.META.get('REMOTE_ADDR')

    def send_verification_email(self, email, token):
        from django.core.mail import send_mail
        from django.conf import settings

        verify_url = self.request.build_absolute_uri(f'/signup/verify/{token.token}/')

        send_mail(
            subject='Verify your SignShield account',
            message=f'''
Welcome to SignShield!

Please verify your email by clicking the link below:

{verify_url}

This link expires in 24 hours.

If you didn't create a SignShield account, you can ignore this email.

- The SignShield Team
            ''',
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            html_message=render_to_string('emails/verification.html', {
                'verify_url': verify_url,
            }),
        )
```

## 3.5 Email Verification View

### Pseudo Code

```python
# apps/core/views.py

from django.db import transaction
from django.contrib.auth import login, get_user_model
from django.utils import timezone

User = get_user_model()

class VerifyEmailView(View):
    """Handle email verification link clicks"""

    def get(self, request, token):
        try:
            verification = EmailVerificationToken.objects.get(token=token)
        except EmailVerificationToken.DoesNotExist:
            return render(request, 'registration/verify_error.html', {
                'error': 'Invalid verification link.'
            })

        if verification.is_used:
            return render(request, 'registration/verify_error.html', {
                'error': 'This link has already been used. Try logging in.'
            })

        if verification.is_expired:
            return render(request, 'registration/verify_error.html', {
                'error': 'This link has expired. Please register again.'
            })

        # Create account in a transaction
        try:
            with transaction.atomic():
                user, tenant = self.create_account(verification)

                # Mark token as used
                verification.verified_at = timezone.now()
                verification.save()

            # Log the user in
            login(request, user)

            # Send welcome email
            self.send_welcome_email(user, tenant)

            # Redirect to onboarding
            return redirect(f'/onboarding/?tenant={tenant.slug}')

        except Exception as e:
            return render(request, 'registration/verify_error.html', {
                'error': 'An error occurred creating your account. Please try again.'
            })

    def create_account(self, verification):
        """Create User, Tenant, and TenantUser atomically"""
        data = verification.registration_data

        # Create Django User
        user = User.objects.create(
            username=verification.email,  # Use email as username
            email=verification.email,
            first_name=data['first_name'],
            last_name=data['last_name'],
            password=data['password_hash'],  # Already hashed
        )

        # Create Tenant
        tenant = Tenant.objects.create(
            name=data['tenant_name'],
            slug=data['slug'],
            company_name=data['company_name'],
            owner_email=verification.email,
            plan='free',  # Start on Free plan
            is_active=True,
        )

        # Create TenantUser as owner
        tenant_user = TenantUser.objects.create(
            user=user,
            tenant=tenant,
            role='owner',
            is_active=True,
            accepted_at=timezone.now(),
        )

        # Record legal acceptance (ToS + Privacy Policy)
        # See terms_of_service.md Section 3.5 for model fields
        tenant_user.record_legal_acceptance(
            ip_address=verification.ip_address,
            tos_version='2025.1',
            privacy_version='2025.1',
        )

        return user, tenant

    def send_welcome_email(self, user, tenant):
        from django.core.mail import send_mail
        from django.conf import settings

        dashboard_url = f'https://{tenant.slug}.signshield.io/dashboard/'

        send_mail(
            subject='Welcome to SignShield!',
            message=f'''
Hi {user.first_name},

Your SignShield account is ready!

Your dashboard: {dashboard_url}

Here are some things to get started:
1. Create your first waiver template
2. Set up an event
3. Send your first waiver link

Need help? Reply to this email or visit our help center.

- The SignShield Team
            ''',
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
            html_message=render_to_string('emails/welcome.html', {
                'user': user,
                'tenant': tenant,
                'dashboard_url': dashboard_url,
            }),
        )
```

## 3.6 URL Configuration

```python
# signshield/urls.py (add to existing)

from apps.core.views import (
    RegisterView,
    VerifyEmailPendingView,
    VerifyEmailView,
    CheckSlugAvailabilityView,
)

urlpatterns = [
    # ... existing urls ...

    # Registration
    path('signup/', RegisterView.as_view(), name='signup'),
    path('signup/verify-email/', VerifyEmailPendingView.as_view(), name='verify_email_pending'),
    path('signup/verify/<str:token>/', VerifyEmailView.as_view(), name='verify_email'),

    # API
    path('api/check-slug/', CheckSlugAvailabilityView.as_view(), name='check_slug'),
]
```

## 3.7 Email Templates

### Verification Email Template

```html
<!-- templates/emails/verification.html -->
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #374151; max-width: 600px; margin: 0 auto; padding: 20px;">

    <div style="text-align: center; margin-bottom: 32px;">
        <img src="{{ logo_url }}" alt="SignShield" height="48">
    </div>

    <h1 style="color: #1E2A3B; font-size: 24px; margin-bottom: 16px;">
        Verify your email
    </h1>

    <p>Welcome to SignShield! Click the button below to verify your email and activate your account.</p>

    <div style="text-align: center; margin: 32px 0;">
        <a href="{{ verify_url }}"
           style="display: inline-block; background: #2D7DD2; color: white; padding: 14px 32px; border-radius: 6px; text-decoration: none; font-weight: 600;">
            Verify Email Address
        </a>
    </div>

    <p style="color: #6B7280; font-size: 14px;">
        This link expires in 24 hours. If you didn't create a SignShield account, you can safely ignore this email.
    </p>

    <hr style="border: none; border-top: 1px solid #E5E7EB; margin: 32px 0;">

    <p style="color: #9CA3AF; font-size: 12px; text-align: center;">
        SignShield - Video-Verified Waivers<br>
        <a href="https://signshield.io" style="color: #9CA3AF;">signshield.io</a>
    </p>

</body>
</html>
```

### Welcome Email Template

```html
<!-- templates/emails/welcome.html -->
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #374151; max-width: 600px; margin: 0 auto; padding: 20px;">

    <div style="text-align: center; margin-bottom: 32px;">
        <img src="{{ logo_url }}" alt="SignShield" height="48">
    </div>

    <h1 style="color: #1E2A3B; font-size: 24px; margin-bottom: 16px;">
        Welcome to SignShield, {{ user.first_name }}!
    </h1>

    <p>Your account is ready. Here's how to get started:</p>

    <div style="background: #F5F9FC; border-radius: 8px; padding: 24px; margin: 24px 0;">
        <h3 style="color: #1E2A3B; margin-top: 0;">Quick Start Checklist</h3>
        <ol style="margin: 0; padding-left: 20px;">
            <li style="margin-bottom: 8px;"><strong>Create a waiver template</strong> — Set up your first waiver document</li>
            <li style="margin-bottom: 8px;"><strong>Create an event</strong> — Organize participants by event or class</li>
            <li style="margin-bottom: 8px;"><strong>Send your first waiver</strong> — Test the signing experience yourself</li>
        </ol>
    </div>

    <div style="text-align: center; margin: 32px 0;">
        <a href="{{ dashboard_url }}"
           style="display: inline-block; background: #2D7DD2; color: white; padding: 14px 32px; border-radius: 6px; text-decoration: none; font-weight: 600;">
            Go to Dashboard
        </a>
    </div>

    <p>Your SignShield URL: <a href="{{ dashboard_url }}" style="color: #2D7DD2;">{{ tenant.slug }}.signshield.io</a></p>

    <p style="color: #6B7280;">
        Questions? Just reply to this email — we're here to help.
    </p>

    <hr style="border: none; border-top: 1px solid #E5E7EB; margin: 32px 0;">

    <p style="color: #9CA3AF; font-size: 12px; text-align: center;">
        SignShield - Video-Verified Waivers<br>
        <a href="https://signshield.io" style="color: #9CA3AF;">signshield.io</a>
    </p>

</body>
</html>
```

## 3.8 Registration Templates

### Signup Page

```html
<!-- templates/registration/signup.html -->
{% extends 'marketing/base_marketing.html' %}

{% block title %}Sign Up{% endblock %}

{% block content %}
<div class="auth-container">
    <div class="auth-card">
        <div class="auth-header">
            <h1>Create your account</h1>
            <p>Start collecting video-verified waivers today</p>
        </div>

        <form method="post" class="auth-form" novalidate>
            {% csrf_token %}

            {% if form.non_field_errors %}
            <div class="alert alert-error">
                {{ form.non_field_errors }}
            </div>
            {% endif %}

            <div class="form-row">
                <div class="form-group">
                    <label for="id_first_name">First name</label>
                    {{ form.first_name }}
                    {% if form.first_name.errors %}
                    <span class="error-text">{{ form.first_name.errors.0 }}</span>
                    {% endif %}
                </div>
                <div class="form-group">
                    <label for="id_last_name">Last name</label>
                    {{ form.last_name }}
                    {% if form.last_name.errors %}
                    <span class="error-text">{{ form.last_name.errors.0 }}</span>
                    {% endif %}
                </div>
            </div>

            <div class="form-group">
                <label for="id_email">Work email</label>
                {{ form.email }}
                {% if form.email.errors %}
                <span class="error-text">{{ form.email.errors.0 }}</span>
                {% endif %}
            </div>

            <div class="form-group">
                <label for="id_company_name">Company name</label>
                {{ form.company_name }}
                {% if form.company_name.errors %}
                <span class="error-text">{{ form.company_name.errors.0 }}</span>
                {% endif %}
            </div>

            <div class="form-group">
                <label for="id_slug">Choose your subdomain</label>
                <div class="slug-input-wrapper">
                    {{ form.slug }}
                    <span class="slug-suffix">.signshield.io</span>
                </div>
                <div class="slug-feedback"></div>
                {% if form.slug.errors %}
                <span class="error-text">{{ form.slug.errors.0 }}</span>
                {% endif %}
            </div>

            <div class="form-group">
                <label for="id_password">Password</label>
                {{ form.password }}
                <span class="help-text">At least 8 characters</span>
                {% if form.password.errors %}
                <span class="error-text">{{ form.password.errors.0 }}</span>
                {% endif %}
            </div>

            <div class="form-group">
                <label for="id_password_confirm">Confirm password</label>
                {{ form.password_confirm }}
                {% if form.password_confirm.errors %}
                <span class="error-text">{{ form.password_confirm.errors.0 }}</span>
                {% endif %}
            </div>

            <div class="form-group checkbox-group">
                {{ form.accept_terms }}
                <label for="id_accept_terms">
                    I agree to the <a href="/terms/" target="_blank">Terms of Service</a>
                    and <a href="/privacy/" target="_blank">Privacy Policy</a>
                </label>
                {% if form.accept_terms.errors %}
                <span class="error-text">{{ form.accept_terms.errors.0 }}</span>
                {% endif %}
            </div>

            <button type="submit" class="btn btn-primary btn-block">
                Create Account
            </button>
        </form>

        <div class="auth-footer">
            <p>Already have an account? <a href="/login/">Log in</a></p>
        </div>
    </div>
</div>
{% endblock %}
```

### Verify Email Pending Page

```html
<!-- templates/registration/verify_email_pending.html -->
{% extends 'marketing/base_marketing.html' %}

{% block title %}Verify Your Email{% endblock %}

{% block content %}
<div class="auth-container">
    <div class="auth-card text-center">
        <div class="icon-circle icon-success">
            <svg><!-- Email icon --></svg>
        </div>

        <h1>Check your email</h1>

        <p>
            We've sent a verification link to<br>
            <strong>{{ pending_email }}</strong>
        </p>

        <p class="text-secondary">
            Click the link in the email to activate your account.
            The link expires in 24 hours.
        </p>

        <hr>

        <p class="text-small text-secondary">
            Didn't receive the email?
            <a href="/signup/resend-verification/">Resend verification email</a>
        </p>
    </div>
</div>
{% endblock %}
```

### Verification Error Page

```html
<!-- templates/registration/verify_error.html -->
{% extends 'marketing/base_marketing.html' %}

{% block title %}Verification Error{% endblock %}

{% block content %}
<div class="auth-container">
    <div class="auth-card text-center">
        <div class="icon-circle icon-error">
            <svg><!-- Error icon --></svg>
        </div>

        <h1>Verification Failed</h1>

        <p>{{ error }}</p>

        <div class="auth-actions">
            <a href="/signup/" class="btn btn-primary">Try Again</a>
            <a href="/login/" class="btn btn-secondary">Log In</a>
        </div>
    </div>
</div>
{% endblock %}
```

# 4. Future Considerations (Out of Scope)

- Social login (Google, Microsoft)
- Magic link login (passwordless)
- Phone number verification
- Custom plan selection during signup
- Team invite during signup
- SSO/SAML integration

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Data Model**
1. Create EmailVerificationToken model
2. Run migrations
3. Add to Django admin

**Phase 2: Registration Form**
1. Create TenantRegistrationForm
2. Create RegisterView
3. Create signup template
4. Implement slug availability AJAX endpoint

**Phase 3: Email Verification**
1. Create verification email template
2. Implement VerifyEmailView
3. Create verification success/error templates
4. Test full flow

**Phase 4: Welcome Flow**
1. Create welcome email template
2. Wire up post-verification redirect to onboarding
3. Test end-to-end flow

## 5.2 Spec Dependencies

This spec has dependencies on other specs that must be implemented first.

### Dependency Chain

```
┌─────────────────────┐    ┌─────────────────────┐
│  marketing_website  │    │  planlimit_update   │
│  (In Development)   │    │  (In Development)   │
│                     │    │                     │
│  Provides:          │    │  Provides:          │
│  • Base templates   │    │  • Free plan config │
│  • Header/footer    │    │  • Plan assignment  │
│  • Sign-up link     │    │                     │
│  • Brand styling    │    │                     │
└──────────┬──────────┘    └──────────┬──────────┘
           │                          │
           └────────────┬─────────────┘
                        ▼
          ┌─────────────────────────────┐
          │  tenant_self_registration   │
          │  (This Spec)                │
          │                             │
          │  Uses:                      │
          │  • Marketing templates      │
          │  • Free plan from PlanLimit │
          └─────────────────────────────┘
                        │
                        ▼
          ┌─────────────────────────────┐
          │     onboarding_wizard       │
          │  (Triggered after signup)   │
          └─────────────────────────────┘
```

### Dependency Details

| Spec | Status | Required For | Specific Dependencies |
|------|--------|--------------|----------------------|
| **marketing_website.md** | In Development | Sign-up page | Base templates, header/footer, CSS styling, sign-up CTA links |
| **planlimit_update.md** | In Development | Plan assignment | Free plan configuration, `PlanLimit.get_plan('free')` |

### What This Spec Provides To Others

| Downstream Spec | What We Provide |
|-----------------|-----------------|
| **onboarding_wizard** | New tenant creation triggers onboarding flow |

### Implementation Order

```
1. planlimit_update.md     ─┐
2. brand_guidelines.md      ├──► 4. tenant_self_registration.md ──► 5. onboarding_wizard.md
3. marketing_website.md    ─┘
```

## 5.3 Infrastructure Dependencies

| Dependency | Notes |
|------------|-------|
| Email Configuration | SMTP settings for sending verification emails |
| Django authentication | User model for account creation |

# 6. Acceptance Criteria

## 6.1 Registration Form

- [ ] All form fields render correctly
- [ ] Client-side validation for required fields
- [ ] Password strength requirements enforced
- [ ] Email uniqueness check works
- [ ] Slug format validation works
- [ ] Slug availability check (AJAX) works
- [ ] Reserved slugs rejected
- [ ] Terms checkbox required
- [ ] Form submits successfully with valid data

## 6.2 Email Verification

- [ ] Verification email sent on registration
- [ ] Email contains valid verification link
- [ ] Expired tokens rejected with clear message
- [ ] Used tokens rejected with clear message
- [ ] Invalid tokens show error page
- [ ] Successful verification creates User, Tenant, TenantUser
- [ ] User auto-logged in after verification
- [ ] Redirects to onboarding after verification

## 6.3 Account Creation

- [ ] User created with correct email/name/password
- [ ] Tenant created with correct name/slug/company
- [ ] TenantUser created with role='owner'
- [ ] Tenant plan set to 'free'
- [ ] Welcome email sent

## 6.4 Security

- [ ] Password hashed before storing in token
- [ ] CSRF protection on forms
- [ ] Rate limiting on registration endpoint
- [ ] Rate limiting on slug check endpoint
- [ ] IP address logged for audit trail

## 6.5 Error Handling

- [ ] Duplicate email shows clear error
- [ ] Duplicate slug shows clear error
- [ ] Password mismatch shows clear error
- [ ] Weak password shows requirements
- [ ] Verification errors show helpful messages

## 6.6 Legal Acceptance

- [ ] Single checkbox for ToS + Privacy Policy on registration form
- [ ] `legal_accepted_at` recorded on TenantUser after verification
- [ ] `tos_version_accepted` recorded (e.g., "2025.1")
- [ ] `privacy_version_accepted` recorded (e.g., "2025.1")
- [ ] `legal_acceptance_ip` recorded from verification token

---

# Changelog

## v1.2 - 2025-12-25
- Added legal acceptance recording in create_account()
  - Calls tenant_user.record_legal_acceptance() after creating TenantUser
  - Records IP address, ToS version, and Privacy Policy version
  - References terms_of_service.md Section 3.5 for model fields
- Added Section 6.6 Legal Acceptance acceptance criteria

## v1.1 - 2025-01-17
- Initial implementation

---
*End of Specification*
