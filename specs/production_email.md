---
title: Production Email Setup
version: "1.2"
status: deployed
project: SignShield
created: 2025-12-23
updated: 2025-12-24
---

# 1. Executive Summary

Configure production email for SignShield using Hostinger SMTP. The existing email infrastructure (Celery tasks, templates, tenant configuration) is largely complete. This spec covers: production SMTP configuration, domain authentication (SPF/DKIM), missing email templates (password reset, restore complete, signing reminder), and automated reminder scheduling.

# 2. Current System State

## 2.1 What Already Exists

| Component | Status | Location |
|-----------|--------|----------|
| Django email settings | ✅ Complete | `settings/base.py`, `production.py` |
| Mailpit dev config | ✅ Complete | `settings/development.py`, docker-compose |
| Celery email tasks | ✅ Complete | `apps/waivers/tasks.py`, `apps/billing/tasks.py` |
| Tenant email config | ✅ Complete | `apps/core/models.py` (Tenant model) |
| Email verification | ✅ Complete | `apps/core/views.py` |
| PDF attachments | ✅ Complete | EmailMultiAlternatives in tasks |

### Existing Email Templates

```
templates/emails/
├── waiver_signed_notification.html    ✅ Exists
├── waiver_signed_notification.txt     ✅ Exists
├── verification.html                  ✅ Exists
└── welcome.html                       ✅ Exists
```

### Existing Celery Email Tasks

| Task | File | Purpose |
|------|------|---------|
| `send_waiver_pdf_email` | waivers/tasks.py | Send PDF to signer |
| `send_waiver_signed_notification` | waivers/tasks.py | Notify business |
| `send_signing_link_email` | waivers/tasks.py | Send signing invitation |
| `send_overage_notification` | billing/tasks.py | Usage limit exceeded |
| `send_grace_expired_notification` | billing/tasks.py | Grace period ended |
| `send_approaching_limit_notification` | billing/tasks.py | Near usage limit |

### Existing Tenant Email Settings

```python
# apps/core/models.py - Tenant model
from_email = models.EmailField(blank=True)
notification_email = models.EmailField(blank=True)
notify_on_waiver_signed = models.BooleanField(default=True)
send_signer_copy = models.BooleanField(default=True)
include_pdf_in_notification = models.BooleanField(default=False)
```

## 2.2 What's Missing

| Component | Priority | Notes |
|-----------|----------|-------|
| Production SMTP config | High | Environment variables for Bluehost |
| Domain authentication | High | SPF, DKIM records |
| Password reset template | High | Django auth integration |
| Restore complete template | Medium | Glacier restore notification |
| Signing reminder template | High | Automated follow-up |
| Reminder scheduling | High | Celery beat task |
| Tenant reminder settings | High | Model fields for configuration |

# 3. Feature Requirements

## 3.1 Production SMTP Configuration

### Environment Variables

```bash
# .env (Production - Hostinger)
EMAIL_HOST=smtp.hostinger.com
EMAIL_PORT=465
EMAIL_HOST_USER=noreply@signshield.io
EMAIL_HOST_PASSWORD=your-email-password
EMAIL_USE_SSL=True
EMAIL_USE_TLS=False
DEFAULT_FROM_EMAIL=SignShield <noreply@signshield.io>
```

**Note:** Hostinger SMTP settings:
- SMTP Server: `smtp.hostinger.com`
- Port 465 with SSL, OR
- Port 587 with TLS

### Django Settings Update

```python
# settings/production.py - Already exists, verify these settings

EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.environ.get('EMAIL_HOST')
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', 465))
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD')
EMAIL_USE_SSL = os.environ.get('EMAIL_USE_SSL', 'True') == 'True'
EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'False') == 'True'
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'SignShield <noreply@signshield.io>')
```

## 3.2 DNS Configuration for Email

### Important: Cloudflare DNS with Hostinger Email

Since Cloudflare manages DNS for signshield.io (nameservers point to Cloudflare), **all email-related DNS records must be configured in Cloudflare**, even though email is hosted on Hostinger.

```
┌─────────────────────────────────────────────────────────────┐
│                     DNS FLOW                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Internet                                                   │
│      │                                                       │
│      ▼                                                       │
│   Cloudflare DNS  ←── All DNS records configured here       │
│      │                                                       │
│      ├──► MX Record ──► Hostinger Mail Servers              │
│      │                                                       │
│      ├──► A Record (mail) ──► Hostinger Server IP           │
│      │    (DNS only - grey cloud!)                          │
│      │                                                       │
│      └──► A Record (www, @) ──► Linode Server               │
│           (Proxied - orange cloud)                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### MX Records (Mail Exchange)

MX records tell the internet where to deliver email for @signshield.io addresses.

**In Cloudflare DNS, add:**

| Type | Name | Mail Server | Priority | TTL |
|------|------|-------------|----------|-----|
| MX | @ | mail.signshield.io | 10 | Auto |

**Alternative (check Hostinger for exact MX servers):**

Check Hostinger hPanel → Emails → MX Entry for the correct server. It may be:

| Type | Name | Mail Server | Priority | TTL |
|------|------|-------------|----------|-----|
| MX | @ | mail.signshield.io | 0 | Auto |
| MX | @ | mail.signshield.io | 10 | Auto |

### Mail Server A Record

**Critical:** This record must be **DNS only** (grey cloud), NOT proxied through Cloudflare. Email protocols don't work through Cloudflare's HTTP proxy.

| Type | Name | Content | Proxy Status | TTL |
|------|------|---------|--------------|-----|
| A | mail | `<bluehost-server-ip>` | **DNS only** (grey cloud) | Auto |

**To find Hostinger server IP:**
1. Log into Hostinger hPanel
2. Go to Emails → Email Accounts
3. Look for "Server Information" or check the email setup instructions

### SPF Record (Sender Policy Framework)

SPF tells receiving servers which mail servers are authorized to send email for your domain.

| Type | Name | Content | TTL |
|------|------|---------|-----|
| TXT | @ | `v=spf1 include:_spf.hostinger.com ~all` | Auto |

**Note:** If you later add SendGrid or another provider, update to:
```
v=spf1 include:_spf.hostinger.com include:sendgrid.net ~all
```

### DKIM Record (DomainKeys Identified Mail)

DKIM adds a digital signature to verify emails weren't tampered with.

**Step 1:** Get DKIM key from Hostinger
1. Log into Hostinger hPanel
2. Go to **Emails** → **Email Accounts** → **DNS Configuration**
3. Find the DKIM record value (long string of characters)

**Step 2:** Add to Cloudflare DNS

| Type | Name | Content | TTL |
|------|------|---------|-----|
| TXT | default._domainkey | `v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3...` | Auto |

*(The actual value will be provided by Hostinger)*

### DMARC Record (Domain-based Message Authentication)

DMARC tells receiving servers what to do with emails that fail SPF/DKIM checks.

| Type | Name | Content | TTL |
|------|------|---------|-----|
| TXT | _dmarc | `v=DMARC1; p=none; rua=mailto:admin@signshield.io` | Auto |

**DMARC Policy Progression:**
1. Start with `p=none` (monitoring only) — emails still delivered, you get reports
2. After 2-4 weeks of clean reports, move to `p=quarantine` — failures go to spam
3. Eventually `p=reject` — failures blocked entirely

### Complete DNS Record Summary

All records configured in **Cloudflare DNS**:

| Type | Name | Content | Proxy | Purpose |
|------|------|---------|-------|---------|
| A | @ | `<linode-ip>` | Proxied (orange) | Web server |
| A | * | `<linode-ip>` | Proxied (orange) | Wildcard subdomains |
| A | www | `<linode-ip>` | Proxied (orange) | www subdomain |
| A | mail | `<bluehost-ip>` | **DNS only (grey)** | Mail server |
| MX | @ | mail.signshield.io | N/A | Mail routing |
| TXT | @ | `v=spf1 include:bluehost.com ~all` | N/A | SPF |
| TXT | default._domainkey | `[from Bluehost]` | N/A | DKIM |
| TXT | _dmarc | `v=DMARC1; p=none; ...` | N/A | DMARC |

### Verification Steps

After configuring DNS records:

1. **Check MX record:**
   ```bash
   dig MX signshield.io
   ```

2. **Check SPF record:**
   ```bash
   dig TXT signshield.io
   ```

3. **Test email deliverability:**
   - Send test email to https://mail-tester.com
   - Target score: 8+ out of 10

4. **Verify with MXToolbox:**
   - https://mxtoolbox.com/domain/signshield.io/

## 3.3 Missing Email Templates

### Template Structure

```
templates/emails/
├── base.html                          # CREATE - Base template
├── waiver_signed_notification.html    # EXISTS
├── waiver_signed_notification.txt     # EXISTS
├── verification.html                  # EXISTS
├── welcome.html                       # EXISTS
├── password_reset.html                # CREATE
├── password_reset.txt                 # CREATE
├── restore_complete.html              # CREATE
├── restore_complete.txt               # CREATE
├── signing_reminder.html              # CREATE
└── signing_reminder.txt               # CREATE
```

### Base Email Template

```html
<!-- templates/emails/base.html -->
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}SignShield{% endblock %}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333333;
            margin: 0;
            padding: 0;
            background-color: #f5f5f5;
        }
        .wrapper {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }
        .container {
            background-color: #ffffff;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
            background-color: #1a73e8;
            padding: 24px;
            text-align: center;
        }
        .header img {
            max-height: 40px;
        }
        .header h1 {
            color: #ffffff;
            margin: 0;
            font-size: 24px;
        }
        .content {
            padding: 32px 24px;
        }
        .button {
            display: inline-block;
            padding: 14px 28px;
            background-color: #1a73e8;
            color: #ffffff !important;
            text-decoration: none;
            border-radius: 6px;
            font-weight: 600;
            margin: 16px 0;
        }
        .button:hover {
            background-color: #1557b0;
        }
        .footer {
            padding: 24px;
            text-align: center;
            font-size: 12px;
            color: #666666;
            border-top: 1px solid #eeeeee;
        }
        .footer a {
            color: #1a73e8;
            text-decoration: none;
        }
        .muted {
            color: #666666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="container">
            <div class="header">
                {% block header %}
                <h1>SignShield</h1>
                {% endblock %}
            </div>
            <div class="content">
                {% block content %}{% endblock %}
            </div>
            <div class="footer">
                {% block footer %}
                <p>
                    <a href="https://signshield.io/privacy/">Privacy Policy</a> &bull;
                    <a href="https://signshield.io/terms/">Terms of Service</a>
                </p>
                <p>&copy; {% now "Y" %} SignShield by EchoForgeX. All rights reserved.</p>
                {% endblock %}
            </div>
        </div>
    </div>
</body>
</html>
```

### Password Reset Template

```html
<!-- templates/emails/password_reset.html -->
{% extends "emails/base.html" %}

{% block title %}Reset Your Password{% endblock %}

{% block content %}
<h2>Reset Your Password</h2>

<p>Hi {{ user.first_name|default:"there" }},</p>

<p>We received a request to reset your password for your SignShield account. Click the button below to create a new password:</p>

<p style="text-align: center;">
    <a href="{{ reset_url }}" class="button">Reset Password</a>
</p>

<p class="muted">This link will expire in 24 hours.</p>

<p class="muted">If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.</p>

<hr style="border: none; border-top: 1px solid #eeeeee; margin: 24px 0;">

<p class="muted">
    <strong>Security tip:</strong> SignShield will never ask for your password via email.
</p>
{% endblock %}
```

```text
<!-- templates/emails/password_reset.txt -->
Reset Your Password

Hi {{ user.first_name|default:"there" }},

We received a request to reset your password for your SignShield account.

Reset your password here:
{{ reset_url }}

This link will expire in 24 hours.

If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.

---
SignShield by EchoForgeX
https://signshield.io
```

### Restore Complete Template

```html
<!-- templates/emails/restore_complete.html -->
{% extends "emails/base.html" %}

{% block title %}Waiver Restored{% endblock %}

{% block content %}
<h2>Archived Waiver Restored</h2>

<p>Hi {{ user.first_name|default:"there" }},</p>

<p>The archived waiver you requested has been restored and is now available for viewing.</p>

<table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
    <tr>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;"><strong>Signer:</strong></td>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;">{{ signer_name }}</td>
    </tr>
    <tr>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;"><strong>Event:</strong></td>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;">{{ event_name|default:"N/A" }}</td>
    </tr>
    <tr>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;"><strong>Originally Signed:</strong></td>
        <td style="padding: 8px 0; border-bottom: 1px solid #eee;">{{ signed_date }}</td>
    </tr>
    <tr>
        <td style="padding: 8px 0;"><strong>Available Until:</strong></td>
        <td style="padding: 8px 0;">{{ expires_date }}</td>
    </tr>
</table>

<p style="text-align: center;">
    <a href="{{ waiver_url }}" class="button">View Waiver</a>
</p>

<p class="muted">
    <strong>Note:</strong> This restored waiver will be available for {{ restore_days }} days,
    after which it will return to archive storage.
</p>
{% endblock %}
```

```text
<!-- templates/emails/restore_complete.txt -->
Archived Waiver Restored

Hi {{ user.first_name|default:"there" }},

The archived waiver you requested has been restored and is now available.

Signer: {{ signer_name }}
Event: {{ event_name|default:"N/A" }}
Originally Signed: {{ signed_date }}
Available Until: {{ expires_date }}

View the waiver here:
{{ waiver_url }}

Note: This restored waiver will be available for {{ restore_days }} days, after which it will return to archive storage.

---
SignShield by EchoForgeX
https://signshield.io
```

### Signing Reminder Template

```html
<!-- templates/emails/signing_reminder.html -->
{% extends "emails/base.html" %}

{% block title %}Reminder: Please Sign Your Waiver{% endblock %}

{% block header %}
{% if tenant.logo_url %}
<img src="{{ tenant.logo_url }}" alt="{{ tenant.name }}" style="max-height: 50px;">
{% else %}
<h1 style="color: #ffffff; margin: 0;">{{ tenant.name }}</h1>
{% endif %}
{% endblock %}

{% block content %}
<h2>Reminder: Waiver Awaiting Your Signature</h2>

<p>Hi {{ signer_name }},</p>

<p>This is a friendly reminder that <strong>{{ tenant.name }}</strong> is waiting for you to sign a waiver{% if event_name %} for <strong>{{ event_name }}</strong>{% endif %}.</p>

<p style="text-align: center;">
    <a href="{{ signing_url }}" class="button">Sign Waiver Now</a>
</p>

<p class="muted">
    <strong>This link expires {{ expiration_text }}.</strong>
</p>

{% if event_date %}
<p>Event Date: <strong>{{ event_date }}</strong></p>
{% endif %}

<hr style="border: none; border-top: 1px solid #eeeeee; margin: 24px 0;">

<p class="muted">
    If you've already signed this waiver, please disregard this reminder.
</p>

<p class="muted">
    Questions? Contact {{ tenant.name }} at
    <a href="mailto:{{ tenant.support_email|default:tenant.owner_email }}">{{ tenant.support_email|default:tenant.owner_email }}</a>
</p>
{% endblock %}

{% block footer %}
<p>
    This waiver is powered by <a href="https://signshield.io">SignShield</a>
</p>
<p>
    <a href="https://signshield.io/privacy/">Privacy Policy</a> &bull;
    <a href="https://signshield.io/terms/">Terms of Service</a>
</p>
{% endblock %}
```

```text
<!-- templates/emails/signing_reminder.txt -->
Reminder: Waiver Awaiting Your Signature

Hi {{ signer_name }},

This is a friendly reminder that {{ tenant.name }} is waiting for you to sign a waiver{% if event_name %} for {{ event_name }}{% endif %}.

Sign your waiver here:
{{ signing_url }}

This link expires {{ expiration_text }}.

{% if event_date %}Event Date: {{ event_date }}{% endif %}

---

If you've already signed this waiver, please disregard this reminder.

Questions? Contact {{ tenant.name }} at {{ tenant.support_email|default:tenant.owner_email }}

---
Powered by SignShield
https://signshield.io
```

## 3.4 Tenant Reminder Settings

### Model Changes

```python
# apps/core/models.py - Add to Tenant model

class Tenant(models.Model):
    # ... existing fields ...

    # Signing reminder settings
    send_signing_reminders = models.BooleanField(
        default=True,
        help_text="Automatically send reminders for unsigned waivers"
    )
    reminder_days_before_expiry = models.PositiveIntegerField(
        default=7,
        help_text="Days before link expiry to send reminder"
    )
    max_reminders = models.PositiveIntegerField(
        default=2,
        help_text="Maximum number of reminders to send per signing link"
    )
```

### SigningLink Model Changes

```python
# apps/waivers/models.py - Add to SigningLink model

class SigningLink(TenantMixin):
    # ... existing fields ...

    # Reminder tracking
    reminders_sent = models.PositiveIntegerField(default=0)
    last_reminder_sent_at = models.DateTimeField(null=True, blank=True)
    reminder_disabled = models.BooleanField(
        default=False,
        help_text="Disable reminders for this specific link"
    )
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `reminders_sent` | PositiveIntegerField | 0 | Count of reminders sent |
| `last_reminder_sent_at` | DateTimeField | null | When last reminder was sent |
| `reminder_disabled` | BooleanField | False | Opt-out for specific link |

## 3.5 Automated Reminder Task

### Celery Task

```python
# apps/waivers/tasks.py

from datetime import timedelta
from django.utils import timezone
from django.template.loader import render_to_string
from django.core.mail import EmailMultiAlternatives
from celery import shared_task

@shared_task
def send_signing_reminders():
    """
    Daily task to send reminders for unsigned waivers.
    Runs at 10 AM UTC.
    """
    from apps.waivers.models import SigningLink
    from apps.core.models import Tenant

    now = timezone.now()
    reminders_sent = 0

    # Get all tenants with reminders enabled
    tenants = Tenant.objects.filter(
        send_signing_reminders=True,
        is_active=True,
    )

    for tenant in tenants:
        days_before = tenant.reminder_days_before_expiry
        max_reminders = tenant.max_reminders
        reminder_threshold = now + timedelta(days=days_before)

        # Find signing links that:
        # - Are not yet signed (status pending/sent)
        # - Expire within the reminder window
        # - Haven't reached max reminders
        # - Aren't disabled for reminders
        # - Haven't been reminded in the last 24 hours
        links_to_remind = SigningLink.objects.filter(
            tenant=tenant,
            status__in=['pending', 'sent'],
            expires_at__lte=reminder_threshold,
            expires_at__gt=now,  # Not already expired
            reminders_sent__lt=max_reminders,
            reminder_disabled=False,
        ).exclude(
            last_reminder_sent_at__gte=now - timedelta(hours=24)
        ).select_related('signer', 'event_participant__event')

        for link in links_to_remind:
            try:
                send_single_reminder.delay(str(link.id))
                reminders_sent += 1
            except Exception as e:
                logger.error(f"Failed to queue reminder for link {link.id}: {e}")

    logger.info(f"Queued {reminders_sent} signing reminders")
    return reminders_sent


@shared_task(bind=True, max_retries=3)
def send_single_reminder(self, signing_link_id):
    """Send a single signing reminder email."""
    from apps.waivers.models import SigningLink

    try:
        link = SigningLink.objects.select_related(
            'tenant', 'signer', 'event_participant__event'
        ).get(id=signing_link_id)
    except SigningLink.DoesNotExist:
        logger.error(f"SigningLink {signing_link_id} not found")
        return

    # Don't send if already signed
    if link.status == 'signed':
        return

    # Don't send if expired
    if link.is_expired:
        return

    signer = link.signer
    tenant = link.tenant
    event = link.event_participant.event if link.event_participant else None

    # Calculate expiration text
    days_until_expiry = (link.expires_at - timezone.now()).days
    if days_until_expiry <= 1:
        expiration_text = "tomorrow"
    elif days_until_expiry <= 7:
        expiration_text = f"in {days_until_expiry} days"
    else:
        expiration_text = f"on {link.expires_at.strftime('%B %d, %Y')}"

    # Build signing URL
    signing_url = f"https://{tenant.slug}.signshield.io/sign/{link.token}/"

    context = {
        'signer_name': signer.full_name,
        'tenant': tenant,
        'event_name': event.name if event else None,
        'event_date': event.event_date.strftime('%B %d, %Y') if event and event.event_date else None,
        'signing_url': signing_url,
        'expiration_text': expiration_text,
    }

    try:
        html_content = render_to_string('emails/signing_reminder.html', context)
        text_content = render_to_string('emails/signing_reminder.txt', context)

        subject = f"Reminder: Please sign your waiver for {tenant.name}"
        if event:
            subject = f"Reminder: Please sign your waiver for {event.name}"

        msg = EmailMultiAlternatives(
            subject=subject,
            body=text_content,
            from_email=tenant.get_from_email(),
            to=[signer.email],
        )
        msg.attach_alternative(html_content, "text/html")
        msg.send()

        # Update reminder tracking
        link.reminders_sent += 1
        link.last_reminder_sent_at = timezone.now()
        link.save(update_fields=['reminders_sent', 'last_reminder_sent_at'])

        logger.info(f"Sent reminder {link.reminders_sent} for SigningLink {link.id}")

    except Exception as e:
        logger.error(f"Failed to send reminder for link {signing_link_id}: {e}")
        raise self.retry(exc=e, countdown=300)
```

### Celery Beat Schedule

```python
# signshield/celery.py - Add to beat_schedule

CELERY_BEAT_SCHEDULE = {
    # ... existing tasks ...

    'send-signing-reminders-daily': {
        'task': 'apps.waivers.tasks.send_signing_reminders',
        'schedule': crontab(hour=10, minute=0),  # 10 AM UTC daily
    },
}
```

## 3.6 Password Reset Integration

### Django Configuration

```python
# settings/base.py

# Password reset email settings
PASSWORD_RESET_TIMEOUT = 86400  # 24 hours in seconds
```

### URL Configuration

```python
# urls.py - Ensure these are included

from django.contrib.auth import views as auth_views

urlpatterns = [
    # ... existing urls ...

    path('accounts/password_reset/',
         auth_views.PasswordResetView.as_view(
             template_name='registration/password_reset_form.html',
             email_template_name='emails/password_reset.txt',
             html_email_template_name='emails/password_reset.html',
             subject_template_name='emails/password_reset_subject.txt',
         ),
         name='password_reset'),

    path('accounts/password_reset/done/',
         auth_views.PasswordResetDoneView.as_view(
             template_name='registration/password_reset_done.html'
         ),
         name='password_reset_done'),

    path('accounts/reset/<uidb64>/<token>/',
         auth_views.PasswordResetConfirmView.as_view(
             template_name='registration/password_reset_confirm.html'
         ),
         name='password_reset_confirm'),

    path('accounts/reset/done/',
         auth_views.PasswordResetCompleteView.as_view(
             template_name='registration/password_reset_complete.html'
         ),
         name='password_reset_complete'),
]
```

### Subject Template

```text
<!-- templates/emails/password_reset_subject.txt -->
Reset your SignShield password
```

## 3.7 Update Restore Complete Notification

Update the existing task in `apps/waivers/tasks.py`:

```python
@shared_task
def send_restore_complete_notification(waiver_id):
    """Notify user that waiver restore is complete."""
    from apps.waivers.models import SignedWaiver

    try:
        waiver = SignedWaiver.objects.select_related(
            'tenant', 'signer', 'restore_requested_by__user', 'event_participant__event'
        ).get(id=waiver_id)
    except SignedWaiver.DoesNotExist:
        logger.error(f"Waiver {waiver_id} not found for restore notification")
        return

    if not waiver.restore_requested_by:
        return

    user = waiver.restore_requested_by.user
    tenant = waiver.tenant
    event = waiver.event_participant.event if waiver.event_participant else None

    context = {
        'user': user,
        'signer_name': waiver.signer.full_name,
        'event_name': event.name if event else None,
        'signed_date': waiver.signed_at.strftime('%B %d, %Y'),
        'expires_date': waiver.restore_expires_at.strftime('%B %d, %Y'),
        'restore_days': settings.WAIVER_RESTORE_DAYS,
        'waiver_url': f"https://{tenant.slug}.signshield.io/dashboard/waivers/{waiver.id}/",
    }

    try:
        html_content = render_to_string('emails/restore_complete.html', context)
        text_content = render_to_string('emails/restore_complete.txt', context)

        msg = EmailMultiAlternatives(
            subject=f"Waiver Restored: {waiver.signer.full_name}",
            body=text_content,
            from_email=tenant.get_from_email(),
            to=[user.email],
        )
        msg.attach_alternative(html_content, "text/html")
        msg.send()

        logger.info(f"Sent restore complete notification for waiver {waiver_id}")

    except Exception as e:
        logger.error(f"Failed to send restore notification for waiver {waiver_id}: {e}")
```

# 4. Future Considerations (Out of Scope)

- Bounce/complaint handling (EmailSuppression model, webhooks)
- Email provider migration to SendGrid/SES for better deliverability
- Tenant-customizable email templates
- Email analytics (open rates, click rates)
- Plan-based email sending limits
- Custom tenant sending domains (send from @tenant.com)
- Email preference center for signers
- Unsubscribe handling

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Production SMTP Configuration**
1. Create email account in Hostinger (noreply@signshield.io)
2. Add environment variables to production .env
3. Test email sending from Django shell
4. Verify delivery to Gmail/Outlook

**Phase 2: Domain Authentication**
1. Add SPF record to DNS
2. Configure DKIM from Hostinger
3. Add DMARC record (monitoring mode)
4. Verify with mail-tester.com

**Phase 3: Base Email Template**
1. Create base.html email template
2. Update existing templates to extend base (optional, for consistency)

**Phase 4: Missing Templates**
1. Create password_reset.html and .txt
2. Create restore_complete.html and .txt
3. Create signing_reminder.html and .txt
4. Create password_reset_subject.txt

**Phase 5: Reminder System**
1. Add reminder fields to Tenant model
2. Add tracking fields to SigningLink model
3. Run migrations
4. Implement send_signing_reminders task
5. Implement send_single_reminder task
6. Add to Celery beat schedule

**Phase 6: Password Reset Integration**
1. Configure Django auth password reset views
2. Add URL routes
3. Create password reset form templates

**Phase 7: Restore Notification**
1. Update send_restore_complete_notification task
2. Test with mock restore

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| deployment_infrastructure.md | Production server and environment |
| waiver_archival.md | Restore complete notification |
| Hostinger | Email hosting account |
| Cloudflare | DNS records for SPF/DKIM/DMARC |

# 6. Acceptance Criteria

## 6.1 SMTP Configuration

- [ ] noreply@signshield.io email account created in Bluehost
- [ ] Environment variables configured on production server
- [ ] Test email sends successfully from Django shell
- [ ] Email received in Gmail (check spam folder)
- [ ] Email received in Outlook (check spam folder)

## 6.2 Domain Authentication

- [ ] SPF record added and validates (check with mxtoolbox.com)
- [ ] DKIM configured if available
- [ ] DMARC record added
- [ ] mail-tester.com score of 8+ out of 10

## 6.3 Email Templates

- [ ] base.html template created with consistent styling
- [ ] password_reset.html and .txt created
- [ ] restore_complete.html and .txt created
- [ ] signing_reminder.html and .txt created
- [ ] All templates render correctly
- [ ] Plain text versions are readable

## 6.4 Reminder System

- [ ] Tenant model has reminder settings fields
- [ ] SigningLink model has reminder tracking fields
- [ ] Migrations created and applied
- [ ] send_signing_reminders task implemented
- [ ] send_single_reminder task implemented
- [ ] Celery beat schedule includes reminder task
- [ ] Reminders respect tenant settings (enabled, days, max)
- [ ] Reminders don't send for signed waivers
- [ ] Reminders don't send for expired links
- [ ] Reminder count increments correctly

## 6.5 Password Reset

- [ ] Password reset flow works end-to-end
- [ ] Reset email uses custom template
- [ ] Reset link expires after 24 hours
- [ ] User can set new password successfully

## 6.6 Restore Notification

- [ ] Notification sends when restore completes
- [ ] Email contains correct waiver details
- [ ] Link to view waiver works

---

# Changelog

## v1.2 - 2025-12-23
- Clarified DNS configuration for Cloudflare + Bluehost email setup
- Added MX record configuration
- Added mail subdomain A record (DNS only, not proxied)
- Added complete DNS record summary table
- Added verification steps (dig commands, mail-tester, MXToolbox)
- Added DNS flow diagram

## v1.1 - 2025-12-23
- Revised based on existing infrastructure analysis
- Changed from SendGrid/SES to Bluehost SMTP
- Removed bounce handling (future consideration)
- Added signing reminder system with tenant configuration
- Added all missing email templates
- Simplified scope to what's actually needed

## v1.0 - 2025-12-23
- Initial draft specification

---
*End of Specification*
