---
title: Help Content Requirements
version: "1.0"
status: deployed
project: SignShield
created: 2025-12-23
updated: 2026-01-02
---

# 1. Executive Summary

Comprehensive help content requirements for all SignShield features. This document consolidates field hints, tooltips, knowledge base articles, FAQs, and contextual help across the entire system to ensure consistency and eliminate redundancy.

**Companion Spec:** `help_system.md` defines the technical implementation. This spec defines the content.

# 2. Content Organization

## 2.1 Redundancy Prevention Rules

1. **Single source of truth** - Each concept is explained once, then linked
2. **Layered depth** - Tooltip → Contextual Help → Article (increasing detail)
3. **Cross-reference, don't repeat** - Use "Learn more" links instead of duplicating
4. **Shared terminology** - Consistent terms across all content (see Glossary)

## 2.2 Content Hierarchy

```
TOOLTIP (10-20 words)
   └── Brief explanation, triggers curiosity

FIELD HINT (15-30 words)
   └── Actionable guidance, what to enter

CONTEXTUAL HELP (50-100 words)
   └── Feature overview, quick tips, links to articles

KNOWLEDGE BASE ARTICLE (300-1000 words)
   └── Complete guide, step-by-step, examples

FAQ (50-150 words)
   └── Direct answer to specific question
```

---

# 3. Glossary (Consistent Terminology)

Use these terms consistently across all help content:

| Term | Definition | Don't Use |
|------|------------|-----------|
| **Waiver** | A legal document that participants sign | Release, form, agreement |
| **Template** | A reusable waiver design | Waiver design, form template |
| **Event** | A group of participants (activity, class, date) | Activity, session, group |
| **Participant** | Someone who signs a waiver | Signer (use for action), customer |
| **Signing link** | URL sent to participant to sign | Waiver link, invite link |
| **Video consent** | Recording of participant stating agreement | Video verification, video proof |
| **Kiosk** | Tablet/device for on-site signing | Device, terminal |
| **Tenant** | A business using SignShield | Account, customer, organization |
| **Team member** | Someone with access to tenant dashboard | User, staff, admin |

---

# 4. Field Hints by Feature Area

## 4.1 Account & Registration

| Field | Help Text |
|-------|-----------|
| Company name | Your business name as it appears to customers |
| Subdomain | Your unique SignShield URL (e.g., yourbusiness.signshield.io). Letters, numbers, and hyphens only. |
| Email | Your login email. We'll send verification and account notifications here. |
| Password | At least 8 characters with a mix of letters and numbers |

## 4.2 Waiver Templates

| Field | Help Text |
|-------|-----------|
| Template name | Internal name for this template. Participants won't see this. |
| Waiver content | The legal text participants will read and agree to. Use the editor to format headings, lists, and emphasis. |
| Require video consent | When enabled, participants must record a video stating their name and agreement. |
| Video max length | How long participants can record (5-60 seconds). 30 seconds is typical. |
| Require signature | Participants must draw or type their signature. |
| Custom CSS | Advanced: Add custom styles to the signing page. Requires Professional plan. |

## 4.3 Events

| Field | Help Text |
|-------|-----------|
| Event name | Name shown to participants (e.g., "Summer Camp 2025" or "Saturday Yoga") |
| Event date | When the event takes place. Leave blank for ongoing activities. |
| Event location | Where the event is held. Shown to participants for reference. |
| Default template | The waiver template used for this event. All participants will sign this. |
| Waiver deadline | Participants must sign before this date/time. Leave blank for no deadline. |
| Auto-remind | Automatically send reminder emails to participants who haven't signed. |
| Reminder days | How many days before the deadline to send reminders. |

## 4.4 Participants

| Field | Help Text |
|-------|-----------|
| First name | Participant's first name |
| Last name | Participant's last name |
| Email | Participant's email address. We'll send the signing link here. |
| Phone | Optional. For SMS signing links (coming soon). |
| Is minor | Check if participant is under 18. A guardian must sign for them. |
| Guardian name | Required for minors. The adult legally responsible for signing. |
| Guardian email | Where to send the signing link for minor participants. |

## 4.5 Kiosk Mode

| Field | Help Text |
|-------|-----------|
| Device name | A name to identify this kiosk (e.g., "Front Desk iPad") |
| Default event | Participants signing on this kiosk will be added to this event. |
| Exit PIN | 4-6 digit code required to exit kiosk mode. Keep this private. |
| Inactivity timeout | Kiosk resets after this many seconds of no activity. 30-60 seconds recommended. |
| Allow event selection | Let participants choose their event at the kiosk. |
| Enable offline mode | Continue collecting signatures when internet is unavailable. Requires Professional plan. |

## 4.6 Team Members

| Field | Help Text |
|-------|-----------|
| Email | Team member's email address. They'll receive an invitation to join. |
| Role | Admin: Full access. Manager: Can manage events and waivers. Viewer: Read-only access. |
| Events access | Which events this team member can view and manage. Leave blank for all events. |

## 4.7 Notification Settings

| Field | Help Text |
|-------|-----------|
| Notify on waiver signed | Receive an email each time a participant signs a waiver. |
| Notification email | Where to send notifications. Defaults to account owner email. |
| Send signer copy | Participants receive a PDF copy of their signed waiver. |
| Include PDF in notification | Attach the signed PDF to your notification email. |

## 4.8 Billing & Plan

| Field | Help Text |
|-------|-----------|
| Plan | Your current subscription level. Determines limits and features. |
| Billing email | Where invoices and payment receipts are sent. |
| Card number | Credit or debit card for subscription payments. |
| Auto-renew | Subscription renews automatically each billing period. |

## 4.9 Branding (Tenant Settings)

| Field | Help Text |
|-------|-----------|
| Logo | Your company logo. Displayed on waiver signing pages and emails. PNG or JPG, max 2MB. |
| Primary color | Your brand color. Used for buttons and accents on signing pages. |
| Support email | Shown to participants if they have questions. |
| Timezone | Your local timezone. Affects event times and timestamps. |

## 4.10 Archival Settings

| Field | Help Text |
|-------|-----------|
| Retention period | How long to keep archived waivers before permanent deletion. 3-10 years depending on your industry. |
| Auto-archive | Automatically archive waivers after 1 year. Reduces storage costs. |

---

# 5. Tooltips by Feature Area

## 5.1 Dashboard Elements

| Element | Tooltip |
|---------|---------|
| Total signed | Number of waivers signed across all events |
| Pending signatures | Participants who received links but haven't signed yet |
| Expiring soon | Signing links that will expire within 7 days |
| Recent activity | Latest signing activity across all events |

## 5.2 Template Features

| Element | Tooltip |
|---------|---------|
| Video consent | Record participants stating their name and agreement for added legal protection |
| Template variables | Insert {company_name}, {event_name}, or {participant_name} to personalize waivers |
| Clone template | Create a copy of this template with all settings |
| Archive template | Remove from active list but keep for records |

## 5.3 Event Features

| Element | Tooltip |
|---------|---------|
| Import CSV | Upload a spreadsheet of participant names and emails |
| Send all links | Email signing links to all participants who haven't signed |
| Event status | Draft: Not visible. Active: Accepting signatures. Closed: No new signatures. |
| Waiver progress | Percentage of participants who have completed signing |

## 5.4 Signing Features

| Element | Tooltip |
|---------|---------|
| Signing link | Unique URL for this participant to sign their waiver |
| Link expires | Date when this signing link will no longer work |
| Resend link | Send another email with the signing link |
| Mark as signed | Manually mark as complete (use only for paper waivers) |

## 5.5 Kiosk Features

| Element | Tooltip |
|---------|---------|
| Device status | Online: Connected. Offline: Syncs when reconnected. Inactive: Not in use. |
| Setup mode | Scan QR code or enter token to set up new device |
| Sync status | Number of signatures waiting to upload |
| Last activity | Most recent signing on this device |

## 5.6 Plan & Billing

| Element | Tooltip |
|---------|---------|
| Current usage | How much of your plan limits you've used this period |
| Overage | Additional charges for exceeding plan limits (paid plans only) |
| Grace period | Time to resolve issues before features are restricted |
| Complimentary | Free access granted by SignShield (beta, partner, etc.) |

---

# 6. Contextual Help Content

## 6.1 Dashboard Pages

### Dashboard Home
**page_key:** `dashboard.home`

**Title:** Welcome to Your Dashboard

**Summary:** Your dashboard gives you a quick overview of waiver activity across all events. See who's signed, who's pending, and what needs attention.

**Tips:**
- Click any metric tile to see details
- Use the search bar to find specific participants or waivers
- Set up notifications to get alerts when waivers are signed

**Links:** Getting Started Guide, Understanding Your Dashboard

---

### Events List
**page_key:** `events.list`

**Title:** Managing Events

**Summary:** Events help you organize participants by activity, date, or location. Each event uses a waiver template and tracks who has signed.

**Tips:**
- Create separate events for different dates or activities
- Import participants via CSV for large groups
- Send bulk signing links with one click

**Links:** Setting Up Your First Event, Importing Participants

---

### Event Detail
**page_key:** `events.detail`

**Title:** Event Details

**Summary:** View and manage all participants for this event. Track signing status, send reminders, and download signed waivers.

**Tips:**
- Click a participant row to view their signed waiver
- Use filters to see only unsigned participants
- Export signed waivers as a ZIP file

**Links:** Managing Participants, Sending Reminders

---

### Templates List
**page_key:** `templates.list`

**Title:** Waiver Templates

**Summary:** Templates are reusable waiver designs. Create templates for different activities, then assign them to events.

**Tips:**
- Use variables like {company_name} to personalize text
- Clone a template to create variations
- Archive templates you no longer use

**Links:** Creating Your First Template, Template Best Practices

---

### Template Editor
**page_key:** `templates.edit`

**Title:** Template Editor

**Summary:** Design your waiver content here. Use the rich text editor to format text, add headings, and create checkboxes for specific acknowledgments.

**Tips:**
- Preview how your waiver will appear to signers
- Enable video consent for added legal protection
- Test your template by sending yourself a signing link

**Links:** Video Verification Guide, Template Variables

---

### Kiosk Devices
**page_key:** `kiosks.list`

**Title:** Kiosk Devices

**Summary:** Kiosks let participants sign waivers on tablets at your location. Set up devices and monitor their status here.

**Tips:**
- Name kiosks by location (e.g., "Front Desk", "Check-in Tent")
- Keep your exit PIN private—it's needed to leave kiosk mode
- Professional plan includes offline mode for unreliable connections

**Links:** Setting Up Kiosk Mode, Kiosk Best Practices

---

### Team Members
**page_key:** `team.list`

**Title:** Team Members

**Summary:** Invite colleagues to help manage waivers and events. Assign roles to control what they can access.

**Tips:**
- Admins have full access; Managers can't change billing
- Remove inactive members to free up seats
- You can limit members to specific events

**Links:** Team Roles Explained, Inviting Team Members

---

### Billing & Plans
**page_key:** `billing.overview`

**Title:** Billing & Plans

**Summary:** View your current plan, usage, and payment history. Upgrade or downgrade your subscription here.

**Tips:**
- Upgrade anytime—you'll be charged prorated for the new plan
- Usage resets on your billing date each month
- Download invoices for your records

**Links:** Understanding Plans, Managing Payments

---

### Account Settings
**page_key:** `settings.account`

**Title:** Account Settings

**Summary:** Configure your company profile, branding, and notification preferences.

**Tips:**
- Add your logo to personalize signing pages
- Set your timezone for accurate event times
- Configure notification preferences to stay informed

**Links:** Branding Guide, Notification Settings

---

### Archive Search
**page_key:** `archives.search`

**Title:** Waiver Archives

**Summary:** Search for waivers that have been archived to cold storage. Request restoration to view or download.

**Tips:**
- Archived waivers take 12-48 hours to restore
- Restored waivers are available for 15-30 days
- Use date ranges to narrow your search

**Links:** Understanding Archival, Restoring Archived Waivers

---

# 7. Knowledge Base Articles

## 7.1 Getting Started (5 Articles)

### Article 1: Quick Start Guide
**Slug:** `quick-start-guide`
**Category:** getting-started
**Audience:** tenant

**Summary:** Get up and running with SignShield in 5 minutes.

**Outline:**
1. Welcome to SignShield
2. Your first login
3. Understanding the dashboard
4. Creating your first waiver (link to article)
5. Sending your first signing link (link to article)
6. What's next?

---

### Article 2: Creating Your First Waiver Template
**Slug:** `first-waiver-template`
**Category:** getting-started
**Audience:** tenant

**Summary:** Step-by-step guide to creating a waiver template your participants will sign.

**Outline:**
1. Navigate to Templates
2. Click "New Template"
3. Enter template name
4. Add waiver content
5. Configure signature requirements
6. Enable video consent (optional)
7. Save and preview
8. Tips for effective waivers

---

### Article 3: Setting Up Your First Event
**Slug:** `first-event`
**Category:** getting-started
**Audience:** tenant

**Summary:** Learn how to create an event and start collecting participant waivers.

**Outline:**
1. What are events in SignShield?
2. Create a new event
3. Assign a waiver template
4. Add participants manually or via CSV
5. Review and publish
6. What happens next

---

### Article 4: Sending Signing Links
**Slug:** `sending-signing-links`
**Category:** getting-started
**Audience:** tenant

**Summary:** How to send waiver signing invitations to your participants.

**Outline:**
1. From the event page
2. Send to individual participants
3. Send to all unsigned participants
4. Customize the email message
5. Resending links
6. Tracking who has signed

---

### Article 5: Understanding Your Dashboard
**Slug:** `understanding-dashboard`
**Category:** getting-started
**Audience:** tenant

**Summary:** A tour of your SignShield dashboard and what each section shows.

**Outline:**
1. Dashboard overview
2. Metrics and tiles
3. Recent activity feed
4. Quick actions
5. Navigation sidebar
6. Account menu

---

## 7.2 Templates (5 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `creating-templates` | Creating Waiver Templates | How to build effective waiver templates |
| `video-consent-guide` | Video Consent Setup | When and how to use video verification |
| `template-variables` | Using Template Variables | Personalize waivers with dynamic content |
| `template-best-practices` | Template Best Practices | Tips for clear, legally-sound waivers |
| `managing-templates` | Managing Templates | Clone, archive, and organize templates |

---

## 7.3 Events (5 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `creating-events` | Creating Events | Set up events for activities, dates, or groups |
| `importing-participants` | Importing Participants | Upload participant lists via CSV |
| `managing-participants` | Managing Participants | Add, edit, and track participant status |
| `event-reminders` | Automatic Reminders | Configure reminder emails for unsigned waivers |
| `closing-events` | Closing Events | Archive completed events |

---

## 7.4 Signing & Collection (6 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `how-signing-works` | How Signing Works | What participants experience when signing |
| `signing-link-expiration` | Signing Link Expiration | When links expire and how to extend |
| `reminder-emails` | Reminder Emails | Automatic and manual reminder options |
| `pdf-generation` | PDF Waiver Generation | How signed waivers become PDFs |
| `mobile-signing` | Mobile Signing | Optimized experience for phones and tablets |
| `minor-signing` | Signing for Minors | Guardian signature process for under-18 participants |

---

## 7.5 Kiosk Mode (5 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `setting-up-kiosk` | Setting Up Kiosk Mode | Register devices and configure kiosk settings |
| `kiosk-signing-flow` | Kiosk Signing Flow | What happens when participants sign at a kiosk |
| `offline-kiosk` | Offline Kiosk Mode | Continue collecting signatures without internet |
| `kiosk-security` | Kiosk Security | Exit PIN, lockdown mode, and best practices |
| `kiosk-troubleshooting` | Kiosk Troubleshooting | Common issues and solutions |

---

## 7.6 Team & Permissions (3 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `inviting-team` | Inviting Team Members | Add colleagues to your account |
| `team-roles` | Team Roles Explained | Admin, Manager, and Viewer permissions |
| `removing-members` | Removing Team Members | Deactivate or remove access |

---

## 7.7 Billing & Plans (6 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `understanding-plans` | Understanding Plans | Features and limits for each plan |
| `upgrading-plan` | Upgrading Your Plan | How to upgrade and what changes |
| `downgrading-plan` | Downgrading Your Plan | What to expect when downgrading |
| `plan-limits` | Plan Limits & Overages | What happens when you exceed limits |
| `payment-methods` | Managing Payment Methods | Add, update, or remove cards |
| `invoices-receipts` | Invoices & Receipts | Access and download billing history |

---

## 7.8 Account Settings (4 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `branding-guide` | Branding Your Account | Logo, colors, and custom styling |
| `notification-settings` | Notification Settings | Email preferences and alerts |
| `account-security` | Account Security | Password, two-factor, and access |
| `data-export` | Exporting Your Data | Download your waivers and data |

---

## 7.9 Troubleshooting (8 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `video-issues` | Video Recording Issues | Camera and recording problems |
| `email-delivery` | Email Delivery Issues | Signing links not arriving |
| `signature-problems` | Signature Pad Issues | Drawing and capturing signatures |
| `login-issues` | Login Problems | Password reset and access issues |
| `browser-compatibility` | Browser Compatibility | Supported browsers and devices |
| `pdf-issues` | PDF Generation Issues | Problems with waiver PDFs |
| `kiosk-issues` | Kiosk Troubleshooting | Device and sync problems |
| `sync-issues` | Offline Sync Issues | Data not uploading properly |

---

## 7.10 Archive & Retention (2 Articles)

| Slug | Title | Summary |
|------|-------|---------|
| `understanding-archival` | Understanding Waiver Archival | How and when waivers are archived |
| `restoring-waivers` | Restoring Archived Waivers | Access waivers in cold storage |

---

## 7.11 API Documentation (Enterprise)

| Slug | Title | Summary |
|------|-------|---------|
| `api-overview` | API Overview | Introduction to the SignShield API |
| `api-authentication` | API Authentication | Keys, tokens, and security |
| `api-webhooks` | Webhooks | Real-time event notifications |
| `api-reference` | API Reference | Complete endpoint documentation |

---

# 8. Frequently Asked Questions

## 8.1 General FAQs

| Question | Answer |
|----------|--------|
| What is SignShield? | SignShield is a waiver management platform that helps businesses collect legally-binding electronic signatures with optional video verification. |
| Is SignShield legally binding? | Yes. Electronic signatures collected through SignShield comply with the ESIGN Act and UETA. Video verification adds additional evidence of consent. |
| Can I try SignShield for free? | Yes! The Free plan lets you create 1 event with up to 10 waivers per month at no cost. |

---

## 8.2 Template FAQs

| Question | Answer |
|----------|--------|
| How do I add video verification to my waivers? | When creating or editing a template, toggle "Require video consent" to ON. Participants will record a short video stating their name and agreement. |
| Can I use the same template for multiple events? | Yes. Templates are reusable. Assign the same template to as many events as you need. |
| Can I customize the signing page appearance? | Yes. Add your logo and brand color in Account Settings. Professional plans can add custom CSS. |
| What should I include in my waiver? | Include a clear description of activities and risks, release of liability language, acknowledgment of understanding, and emergency contact authorization if relevant. Consult legal counsel for your specific needs. |

---

## 8.3 Event FAQs

| Question | Answer |
|----------|--------|
| What's the difference between an event and a template? | A template defines the waiver content. An event is a group of participants who will sign that waiver. Think of templates as the form, and events as specific instances where people sign it. |
| Can participants sign without receiving an email? | Yes, with kiosk mode (Starter plan and above). Participants can sign on a device at your location without needing a signing link. |
| How do I send signing links to all participants at once? | On the event page, click "Send All Links." This sends emails only to participants who haven't yet signed. |

---

## 8.4 Signing FAQs

| Question | Answer |
|----------|--------|
| Can signers use their phone to sign? | Yes! The signing experience is fully optimized for mobile devices. Participants can sign from any smartphone or tablet. |
| How long are signing links valid? | By default, 30 days. You can adjust this per event or resend expired links. |
| What happens if someone tries to sign after the deadline? | They'll see a message that the deadline has passed and won't be able to complete signing. Contact your administrator to extend the deadline if needed. |
| Do signers need to create an account? | No. Signers access their waiver via the signing link—no login or account required. |

---

## 8.5 Video Consent FAQs

| Question | Answer |
|----------|--------|
| What do signers say in the video? | Signers state their full name and that they've read and agree to the waiver. The exact wording is shown on screen during recording. |
| What if a signer's camera doesn't work? | If video is required, signers must resolve camera issues to complete the waiver. Common solutions include allowing camera permissions, trying a different browser, or using a different device. |
| Is video consent required? | It's optional per template. You decide whether to require video for each waiver type. |
| How long should the video be? | Most signers complete their statement in 10-15 seconds. We recommend allowing 30 seconds. Maximum is 60 seconds. |

---

## 8.6 Kiosk FAQs

| Question | Answer |
|----------|--------|
| What devices work as kiosks? | Any tablet or computer with a modern browser. iPads, Android tablets, and touchscreen laptops work great. |
| Can I use kiosk mode offline? | Yes, with the Professional plan. Offline mode stores signatures locally and syncs when internet is available. |
| How do I exit kiosk mode? | Tap the screen 5 times rapidly, then enter your exit PIN. This prevents participants from accidentally leaving kiosk mode. |
| How many kiosks can I have? | Free: 0, Starter: 1, Professional: 3, Enterprise: Unlimited. |

---

## 8.7 Billing FAQs

| Question | Answer |
|----------|--------|
| What happens when I exceed my plan limits? | Free plan: You won't be able to create new waivers until next month. Paid plans: Additional waivers are billed at $0.35-$0.50 each. |
| Can I change plans at any time? | Yes. Upgrades take effect immediately. Downgrades take effect at your next billing date. |
| How do I cancel my subscription? | Go to Billing & Plans and click "Cancel Subscription." You'll keep access until the end of your current billing period. |
| What happens to my data if I cancel? | Your data remains accessible on the Archive Only plan ($5/month + storage). Or you can export everything before canceling. |

---

## 8.8 Privacy & Security FAQs

| Question | Answer |
|----------|--------|
| Is my data secure? | Yes. All data is encrypted in transit (TLS) and at rest (AES-256). We use secure cloud infrastructure and regular security audits. |
| Where is data stored? | Data is stored in secure US data centers. Archived waivers are stored in AWS S3 Glacier. |
| Can I delete participant data? | Yes. You can delete individual signed waivers or request full account deletion. Note that some data may be retained for legal compliance. |
| Is SignShield HIPAA compliant? | Contact us for a Business Associate Agreement (BAA) if you need HIPAA compliance for healthcare-related waivers. |

---

# 9. Signer Help Content

## 9.1 Signer FAQ (Modal Content)

| Question | Answer |
|----------|--------|
| What is video verification? | Video verification records you stating your name and that you agree to the waiver. This helps confirm your identity and understanding. |
| How do I record my video? | Click "Start Recording," state your full name and that you agree to the waiver, then click "Stop Recording." You can re-record if needed. |
| My camera isn't working | 1) Make sure you allowed camera access when prompted. 2) Try refreshing the page. 3) Check that no other app is using your camera. 4) Try a different browser (Chrome recommended). |
| How do I sign on the signature pad? | Use your finger (touch screen) or mouse to draw your signature. Click "Clear" to start over if needed. |
| I'm signing for a minor | Select "I am signing as a parent/guardian" and enter both your information and the minor's information. |
| I didn't receive my signing link | Check your spam/junk folder. If not there, contact the organization that requested your signature to resend the link. |
| Can I save and finish later? | Your progress is saved automatically. Return using the same link to continue where you left off. |
| How do I get a copy of my signed waiver? | You'll receive an email with a PDF copy after completing the waiver (if enabled by the organization). |

---

# 10. Implementation Notes

## 10.1 Content Priority

**Phase 1 - Launch Essentials:**
- All field hints (Section 4)
- Getting Started articles (5)
- Top 10 FAQs
- Contextual help for main pages

**Phase 2 - Core Features:**
- All tooltips (Section 5)
- Templates articles (5)
- Events articles (5)
- Signing articles (6)

**Phase 3 - Advanced Features:**
- Kiosk articles (5)
- Team articles (3)
- Billing articles (6)
- Troubleshooting articles (8)

**Phase 4 - Polish:**
- Remaining FAQs
- Archive articles (2)
- API documentation (4)
- Signer help modal

## 10.2 Content Review Checklist

Before publishing any help content:

- [ ] Uses consistent terminology (see Glossary)
- [ ] Avoids duplicating content from other articles
- [ ] Links to related articles where appropriate
- [ ] Written at appropriate reading level (8th grade)
- [ ] Tested on mobile device
- [ ] Screenshots are current (if any)
- [ ] Contact support link works

## 10.3 Maintenance Schedule

| Task | Frequency |
|------|-----------|
| Review analytics for low-rated articles | Monthly |
| Update screenshots after UI changes | As needed |
| Add FAQs from support tickets | Weekly |
| Full content audit | Quarterly |

---

# 11. Acceptance Criteria

## 11.1 Field Hints

- [ ] All form fields across application have help_text
- [ ] Help text displays below each field
- [ ] Text is concise (under 30 words)
- [ ] Text uses consistent terminology

## 11.2 Tooltips

- [ ] All dashboard metrics have tooltips
- [ ] All feature toggles have tooltips
- [ ] Tooltips display on hover/focus
- [ ] Tooltips are 10-20 words

## 11.3 Contextual Help

- [ ] All 10 dashboard pages have contextual help entries
- [ ] Help sidebar loads correct content per page
- [ ] "Learn more" links work
- [ ] Tips are actionable and relevant

## 11.4 Knowledge Base

- [ ] All 45+ articles written and published
- [ ] Articles organized in correct categories
- [ ] Search returns relevant results
- [ ] Mobile responsive layout

## 11.5 FAQs

- [ ] All 30+ FAQs entered
- [ ] FAQs grouped by category
- [ ] Accordion expands correctly
- [ ] Links to articles work

## 11.6 Signer Help

- [ ] Signer help modal accessible on signing page
- [ ] All 8 signer FAQs included
- [ ] Business contact info displayed
- [ ] Modal works on mobile

---

# Changelog

## v1.0 - 2025-12-23
- Initial comprehensive help content specification
- Consolidated field hints for all feature areas
- Defined all tooltips by feature
- Mapped contextual help for 10 dashboard pages
- Outlined 45+ knowledge base articles
- Documented 30+ FAQs across 8 categories
- Created signer help modal content

---
*End of Specification*
