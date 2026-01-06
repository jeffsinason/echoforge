---
title: Contact Management - Privacy-First Multi-Platform Strategy
version: "1.0"
status: draft
project: EchoForge Platform
created: 2026-01-06
updated: 2026-01-06
components:
  - hub
  - agent
issue: 11
---

# 1. Executive Summary

A privacy-first contact management system that allows agents to resolve contact references ("send email to Xavier") while minimizing stored PII. Contacts are fetched from OAuth providers (Google, Outlook) or optional encrypted saved contacts, with only minimal reference data (provider + external_id + user-defined tags/aliases) stored in EchoForge.

# 2. Current System State

## 2.1 Existing Data Structures

| Entity | Key Fields | Current Usage |
|--------|------------|---------------|
| Integration | provider, access_token (encrypted), refresh_token | OAuth connections to Google/Outlook |
| IntegrationProvider | slug, oauth_config, scopes | Provider definitions |
| User | id, email, customer_id | User accounts |

## 2.2 Existing Workflows

- Users connect Google/Gmail via OAuth for email/calendar
- Users connect Outlook via OAuth for email/calendar
- Agent tools (email_send, calendar_create_event) accept raw email addresses
- No contact resolution or management exists

## 2.3 Current Gaps

- No way to resolve "Xavier" to an email address
- No contact tagging or grouping
- No nickname/alias support
- Agent cannot query user's contacts
- No GDPR-compliant contact storage option

# 3. Feature Requirements

## 3.1 Contact Reference Storage

**Description:** Store minimal, non-PII references to contacts with user-defined metadata.

**Component:** Hub

### Data Changes

| Field | Type | Description |
|-------|------|-------------|
| user | ForeignKey(User) | Owner of this reference |
| provider | CharField(50) | 'google', 'outlook', 'saved' |
| external_id | CharField(255) | Provider's contact ID |
| tags | JSONField | User-defined tags: ["family", "vip"] |
| aliases | JSONField | User-defined aliases: ["xav", "x-rod"] |
| created_at | DateTimeField | Auto timestamp |
| updated_at | DateTimeField | Auto timestamp |

### Business Rules

- Unique constraint on (user, provider, external_id)
- Tags are flat strings, case-insensitive for matching
- Aliases are flat strings, case-insensitive for matching
- No PII stored in this model - only pointers and metadata
- User can have references to contacts from only one provider at a time (single provider per user)

### Model Definition

```python
class ContactReference(models.Model):
    """
    Minimal reference to an external contact.
    Stores ONLY: pointer + user metadata (tags, aliases).
    NO contact PII stored here.
    """
    user = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='contact_references'
    )
    provider = models.CharField(max_length=50)  # 'google', 'outlook', 'saved'
    external_id = models.CharField(max_length=255)

    # User-defined metadata (not PII)
    tags = models.JSONField(default=list, blank=True)
    aliases = models.JSONField(default=list, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['user', 'provider', 'external_id']
        indexes = [
            models.Index(fields=['user', 'provider']),
        ]

    def add_tag(self, tag: str) -> bool:
        """Add tag if not present. Returns True if added."""
        tag_lower = tag.lower().strip()
        if tag_lower not in [t.lower() for t in self.tags]:
            self.tags.append(tag)
            return True
        return False

    def remove_tag(self, tag: str) -> bool:
        """Remove tag. Returns True if removed."""
        tag_lower = tag.lower().strip()
        original_len = len(self.tags)
        self.tags = [t for t in self.tags if t.lower() != tag_lower]
        return len(self.tags) < original_len

    def add_alias(self, alias: str) -> bool:
        """Add alias if not present. Returns True if added."""
        alias_lower = alias.lower().strip()
        if alias_lower not in [a.lower() for a in self.aliases]:
            self.aliases.append(alias)
            return True
        return False
```

---

## 3.2 Saved Contacts (Encrypted)

**Description:** Optional encrypted contact storage for users who want convenience without OAuth providers.

**Component:** Hub

### Data Changes

| Field | Type | Description |
|-------|------|-------------|
| user | ForeignKey(User) | Owner |
| name | EncryptedTextField | Full name (required) |
| email | EncryptedTextField | Email address |
| phone | EncryptedTextField | Phone number |
| photo_url | EncryptedTextField | URL to photo |
| notes | EncryptedTextField | User notes |
| created_at | DateTimeField | Auto timestamp |
| updated_at | DateTimeField | Auto timestamp |

### Business Rules

- All PII fields encrypted with AES-256 at rest
- Model PK serves as external_id for ContactReference (provider='saved')
- User must explicitly opt-in to use saved contacts
- Full CRUD available to user
- GDPR: exportable and deletable on request

### Model Definition

```python
class SavedContact(models.Model):
    """
    Optional encrypted contact storage for users without OAuth providers.
    Acts as the 'saved' provider.
    """
    user = models.ForeignKey(
        'auth.User',
        on_delete=models.CASCADE,
        related_name='saved_contacts'
    )

    # Encrypted fields (AES-256)
    name = EncryptedTextField()
    email = EncryptedTextField(blank=True, default='')
    phone = EncryptedTextField(blank=True, default='')
    photo_url = EncryptedTextField(blank=True, default='')
    notes = EncryptedTextField(blank=True, default='')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return f"SavedContact({self.id})"  # Don't expose name in logs
```

---

## 3.3 Contact Provider Interface

**Description:** Unified interface for fetching contacts from different sources.

**Component:** Hub

### Provider Interface

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

@dataclass
class Contact:
    """Unified contact representation."""
    provider: str
    external_id: str
    name: str
    email: str = ''
    phone: str = ''
    photo_url: str = ''
    # Merged from ContactReference if exists
    tags: list[str] = None
    aliases: list[str] = None

@dataclass
class ContactPage:
    """Paginated contact list."""
    contacts: list[Contact]
    next_page_token: Optional[str] = None
    total_count: Optional[int] = None

class ContactProvider(ABC):
    """Abstract base for all contact providers."""

    provider_slug: str  # 'google', 'outlook', 'saved'

    @abstractmethod
    async def search(self, query: str, limit: int = 20) -> list[Contact]:
        """
        Search contacts by name, email, or phone.
        Query is matched against all searchable fields.
        """
        pass

    @abstractmethod
    async def get(self, external_id: str) -> Optional[Contact]:
        """Get single contact by provider ID."""
        pass

    @abstractmethod
    async def list_all(self, page_token: str = None, page_size: int = 100) -> ContactPage:
        """List all contacts (paginated) for cache warming."""
        pass
```

### Google Contact Provider

```python
class GoogleContactProvider(ContactProvider):
    """
    Uses Google People API via existing OAuth integration.
    Requires 'https://www.googleapis.com/auth/contacts.readonly' scope.
    """
    provider_slug = 'google'

    def __init__(self, integration: Integration):
        self.integration = integration
        self.base_url = 'https://people.googleapis.com/v1'

    async def search(self, query: str, limit: int = 20) -> list[Contact]:
        """
        Uses People API searchContacts endpoint.
        GET /v1/people:searchContacts?query={query}&readMask=names,emailAddresses,phoneNumbers,photos
        """
        # Implementation fetches from Google, maps to Contact dataclass
        pass

    async def get(self, external_id: str) -> Optional[Contact]:
        """
        GET /v1/{resourceName}?personFields=names,emailAddresses,phoneNumbers,photos
        external_id format: 'people/c1234567890'
        """
        pass

    async def list_all(self, page_token: str = None, page_size: int = 100) -> ContactPage:
        """
        GET /v1/people/me/connections?personFields=...&pageSize=100&pageToken=...
        """
        pass
```

### Outlook Contact Provider

```python
class OutlookContactProvider(ContactProvider):
    """
    Uses Microsoft Graph API via existing OAuth integration.
    Requires 'Contacts.Read' scope.
    """
    provider_slug = 'outlook'

    def __init__(self, integration: Integration):
        self.integration = integration
        self.base_url = 'https://graph.microsoft.com/v1.0'

    async def search(self, query: str, limit: int = 20) -> list[Contact]:
        """
        GET /me/contacts?$filter=contains(displayName,'{query}') or contains(emailAddresses/any(e:contains(e/address,'{query}')))
        """
        pass

    async def get(self, external_id: str) -> Optional[Contact]:
        """
        GET /me/contacts/{id}
        """
        pass

    async def list_all(self, page_token: str = None, page_size: int = 100) -> ContactPage:
        """
        GET /me/contacts?$top=100&$skip=...
        """
        pass
```

### Saved Contact Provider

```python
class SavedContactProvider(ContactProvider):
    """Queries encrypted SavedContact model."""
    provider_slug = 'saved'

    def __init__(self, user: User):
        self.user = user

    async def search(self, query: str, limit: int = 20) -> list[Contact]:
        """
        Search saved contacts by decrypted name/email.
        Note: Requires decryption, so less efficient than provider APIs.
        """
        # Fetch all, decrypt, filter in Python
        pass

    async def get(self, external_id: str) -> Optional[Contact]:
        """Get by SavedContact PK."""
        pass

    async def list_all(self, page_token: str = None, page_size: int = 100) -> ContactPage:
        """List all saved contacts for user."""
        pass
```

---

## 3.4 Contact Caching

**Description:** Short-TTL cache for contact data fetched from providers.

**Component:** Hub

### Cache Schema

```python
# Redis key pattern
KEY = "contact:{user_id}:{provider}:{external_id}"

# Value (JSON)
{
    "name": "Xavier Rodriguez",
    "email": "xavier@example.com",
    "phone": "+1-555-0123",
    "provider_id": "people/c12345",
    "photo_url": "https://...",
    "aliases": ["xav"],      # Merged from ContactReference
    "tags": ["engineering"], # Merged from ContactReference
    "cached_at": "2026-01-06T12:00:00Z"
}

# TTL: 5 minutes (300 seconds) - configurable via settings
CONTACT_CACHE_TTL = int(os.environ.get('CONTACT_CACHE_TTL', 300))
```

### Cache Service

```python
class ContactCacheService:
    """Redis cache for contact data."""

    def __init__(self, redis_client, ttl: int = 300):
        self.redis = redis_client
        self.ttl = ttl

    def _key(self, user_id: int, provider: str, external_id: str) -> str:
        return f"contact:{user_id}:{provider}:{external_id}"

    async def get(self, user_id: int, provider: str, external_id: str) -> Optional[dict]:
        """Get cached contact, returns None if miss or expired."""
        key = self._key(user_id, provider, external_id)
        data = await self.redis.get(key)
        return json.loads(data) if data else None

    async def set(self, user_id: int, contact: Contact) -> None:
        """Cache contact with TTL."""
        key = self._key(user_id, contact.provider, contact.external_id)
        data = {
            'name': contact.name,
            'email': contact.email,
            'phone': contact.phone,
            'photo_url': contact.photo_url,
            'aliases': contact.aliases or [],
            'tags': contact.tags or [],
            'cached_at': timezone.now().isoformat(),
        }
        await self.redis.setex(key, self.ttl, json.dumps(data))

    async def invalidate(self, user_id: int, provider: str, external_id: str) -> None:
        """Remove contact from cache."""
        key = self._key(user_id, provider, external_id)
        await self.redis.delete(key)

    async def invalidate_user(self, user_id: int) -> None:
        """Remove all cached contacts for user."""
        pattern = f"contact:{user_id}:*"
        keys = await self.redis.keys(pattern)
        if keys:
            await self.redis.delete(*keys)
```

---

## 3.5 Contact Resolution Service

**Description:** Resolves name/alias queries to contacts, handling ambiguity.

**Component:** Hub (called by Agent)

### Resolution Logic

```python
@dataclass
class ResolutionResult:
    """Result of contact resolution."""
    status: str  # 'found', 'not_found', 'ambiguous'
    contacts: list[Contact]
    query: str

class ContactResolutionService:
    """Resolves names/aliases to contacts."""

    def __init__(self, user: User, provider: ContactProvider, cache: ContactCacheService):
        self.user = user
        self.provider = provider
        self.cache = cache

    async def resolve(self, query: str) -> ResolutionResult:
        """
        Resolve a name or alias to contact(s).

        Resolution order:
        1. Check aliases in ContactReference (exact match, case-insensitive)
        2. Search provider by name (exact match first, then contains)
        3. Return results with status
        """
        query_lower = query.lower().strip()

        # Step 1: Check aliases
        alias_refs = await self._find_by_alias(query_lower)
        if len(alias_refs) == 1:
            contact = await self._fetch_contact(alias_refs[0])
            return ResolutionResult('found', [contact], query)
        elif len(alias_refs) > 1:
            contacts = [await self._fetch_contact(ref) for ref in alias_refs]
            return ResolutionResult('ambiguous', contacts, query)

        # Step 2: Search provider
        contacts = await self.provider.search(query, limit=10)

        # Exact name match?
        exact = [c for c in contacts if c.name.lower() == query_lower]
        if len(exact) == 1:
            return ResolutionResult('found', exact, query)
        elif len(exact) > 1:
            return ResolutionResult('ambiguous', exact, query)

        # Partial matches
        if len(contacts) == 1:
            return ResolutionResult('found', contacts, query)
        elif len(contacts) > 1:
            return ResolutionResult('ambiguous', contacts, query)

        return ResolutionResult('not_found', [], query)

    async def _find_by_alias(self, alias: str) -> list[ContactReference]:
        """Find ContactReferences with matching alias."""
        # Query ContactReference where alias in aliases (case-insensitive)
        # Note: JSONField querying varies by DB; may need raw SQL or iteration
        refs = ContactReference.objects.filter(user=self.user)
        return [r for r in refs if alias in [a.lower() for a in r.aliases]]

    async def _fetch_contact(self, ref: ContactReference) -> Contact:
        """Fetch contact details, using cache."""
        cached = await self.cache.get(self.user.id, ref.provider, ref.external_id)
        if cached:
            return Contact(
                provider=ref.provider,
                external_id=ref.external_id,
                **cached
            )

        contact = await self.provider.get(ref.external_id)
        if contact:
            contact.tags = ref.tags
            contact.aliases = ref.aliases
            await self.cache.set(self.user.id, contact)
        return contact
```

---

## 3.6 Contact Tools (Agent)

**Description:** Agent tools for contact operations.

**Component:** Agent

### Tool Definitions

```python
CONTACT_TOOLS = [
    {
        "name": "contacts_search",
        "description": "Search user's contacts by name, email, or tag. Returns matching contacts.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search term (name, email, or partial match)"
                },
                "tag": {
                    "type": "string",
                    "description": "Optional: filter by tag"
                },
                "limit": {
                    "type": "integer",
                    "description": "Max results (default 10)",
                    "default": 10
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "contacts_resolve",
        "description": "Resolve a name or alias to a specific contact. Use when user mentions someone by name. Returns contact if unique match, or asks user to clarify if ambiguous.",
        "input_schema": {
            "type": "object",
            "properties": {
                "name_or_alias": {
                    "type": "string",
                    "description": "Name or alias to resolve (e.g., 'Xavier', 'Xav')"
                }
            },
            "required": ["name_or_alias"]
        }
    },
    {
        "name": "contacts_get_details",
        "description": "Get full details for a specific contact by provider and ID.",
        "input_schema": {
            "type": "object",
            "properties": {
                "provider": {
                    "type": "string",
                    "enum": ["google", "outlook", "saved"]
                },
                "external_id": {
                    "type": "string",
                    "description": "Contact ID from the provider"
                }
            },
            "required": ["provider", "external_id"]
        }
    },
    {
        "name": "contacts_list_tags",
        "description": "List all tags the user has created for their contacts.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "contacts_tag",
        "description": "Add a tag to one or more contacts.",
        "input_schema": {
            "type": "object",
            "properties": {
                "contacts": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "provider": {"type": "string"},
                            "external_id": {"type": "string"}
                        },
                        "required": ["provider", "external_id"]
                    },
                    "description": "Contacts to tag"
                },
                "tag": {
                    "type": "string",
                    "description": "Tag to add"
                }
            },
            "required": ["contacts", "tag"]
        }
    },
    {
        "name": "contacts_untag",
        "description": "Remove a tag from one or more contacts.",
        "input_schema": {
            "type": "object",
            "properties": {
                "contacts": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "provider": {"type": "string"},
                            "external_id": {"type": "string"}
                        },
                        "required": ["provider", "external_id"]
                    }
                },
                "tag": {
                    "type": "string",
                    "description": "Tag to remove"
                }
            },
            "required": ["contacts", "tag"]
        }
    },
    {
        "name": "contacts_get_by_tag",
        "description": "Get all contacts with a specific tag.",
        "input_schema": {
            "type": "object",
            "properties": {
                "tag": {
                    "type": "string",
                    "description": "Tag to filter by"
                }
            },
            "required": ["tag"]
        }
    },
    {
        "name": "contacts_add_alias",
        "description": "Add a nickname/alias for a contact so it can be referenced by that name.",
        "input_schema": {
            "type": "object",
            "properties": {
                "provider": {"type": "string"},
                "external_id": {"type": "string"},
                "alias": {
                    "type": "string",
                    "description": "Alias to add (e.g., 'Xav' for Xavier)"
                }
            },
            "required": ["provider", "external_id", "alias"]
        }
    }
]
```

### Tool Execution (Hub Internal API)

```python
# POST /api/internal/tools/execute/
# Tool execution routes to ContactToolExecutor

class ContactToolExecutor:
    """Executes contact tools on behalf of agent."""

    async def execute(self, tool_name: str, params: dict, user: User) -> dict:
        if tool_name == 'contacts_search':
            return await self._search(params, user)
        elif tool_name == 'contacts_resolve':
            return await self._resolve(params, user)
        elif tool_name == 'contacts_get_details':
            return await self._get_details(params, user)
        elif tool_name == 'contacts_list_tags':
            return await self._list_tags(user)
        elif tool_name == 'contacts_tag':
            return await self._tag(params, user)
        elif tool_name == 'contacts_untag':
            return await self._untag(params, user)
        elif tool_name == 'contacts_get_by_tag':
            return await self._get_by_tag(params, user)
        elif tool_name == 'contacts_add_alias':
            return await self._add_alias(params, user)
        else:
            raise ValueError(f"Unknown contact tool: {tool_name}")

    async def _resolve(self, params: dict, user: User) -> dict:
        """
        Resolve name/alias to contact.
        Returns structured response for agent to handle ambiguity.
        """
        service = self._get_resolution_service(user)
        result = await service.resolve(params['name_or_alias'])

        if result.status == 'found':
            contact = result.contacts[0]
            return {
                'status': 'found',
                'contact': {
                    'provider': contact.provider,
                    'external_id': contact.external_id,
                    'name': contact.name,
                    'email': contact.email,
                    'phone': contact.phone,
                }
            }
        elif result.status == 'ambiguous':
            return {
                'status': 'ambiguous',
                'message': f"Multiple contacts match '{params['name_or_alias']}'",
                'options': [
                    {
                        'provider': c.provider,
                        'external_id': c.external_id,
                        'name': c.name,
                        'email': c.email,
                    }
                    for c in result.contacts
                ]
            }
        else:
            return {
                'status': 'not_found',
                'message': f"No contact found matching '{params['name_or_alias']}'"
            }
```

---

## 3.7 Integration with Existing Tools

**Description:** Modify existing tools to accept contact references.

**Component:** Agent + Hub

### Updated Tool Schemas

```python
# email_send - updated schema
{
    "name": "email_send",
    "description": "Send an email. Accepts either raw email address or contact reference.",
    "input_schema": {
        "type": "object",
        "properties": {
            "to": {
                "oneOf": [
                    {
                        "type": "string",
                        "format": "email",
                        "description": "Raw email address"
                    },
                    {
                        "type": "object",
                        "description": "Contact reference",
                        "properties": {
                            "provider": {"type": "string"},
                            "external_id": {"type": "string"}
                        },
                        "required": ["provider", "external_id"]
                    }
                ]
            },
            "subject": {"type": "string"},
            "body": {"type": "string"}
        },
        "required": ["to", "subject", "body"]
    }
}

# calendar_create_event - updated attendees
{
    "name": "calendar_create_event",
    "properties": {
        "attendees": {
            "type": "array",
            "items": {
                "oneOf": [
                    {"type": "string", "format": "email"},
                    {
                        "type": "object",
                        "properties": {
                            "provider": {"type": "string"},
                            "external_id": {"type": "string"}
                        }
                    }
                ]
            }
        }
    }
}
```

### Resolution in Tool Execution

```python
async def resolve_recipient(recipient: Union[str, dict], user: User) -> str:
    """
    Resolve recipient to email address.
    - If string, return as-is (raw email)
    - If dict with contact_ref, fetch contact and return email
    """
    if isinstance(recipient, str):
        return recipient

    # Contact reference
    provider = recipient['provider']
    external_id = recipient['external_id']

    contact = await fetch_contact(user, provider, external_id)
    if not contact or not contact.email:
        raise ValueError(f"Contact {external_id} has no email address")

    return contact.email
```

---

## 3.8 Hub UI - Contacts Section

**Description:** UI for managing contacts, tags, and aliases.

**Component:** Hub

### URL Structure

```python
# apps/contacts/urls.py
urlpatterns = [
    path('contacts/', views.ContactListView.as_view(), name='contact_list'),
    path('contacts/saved/', views.SavedContactListView.as_view(), name='saved_contact_list'),
    path('contacts/saved/create/', views.SavedContactCreateView.as_view(), name='saved_contact_create'),
    path('contacts/saved/<int:pk>/edit/', views.SavedContactUpdateView.as_view(), name='saved_contact_edit'),
    path('contacts/saved/<int:pk>/delete/', views.SavedContactDeleteView.as_view(), name='saved_contact_delete'),
    path('contacts/tags/', views.TagManagementView.as_view(), name='contact_tags'),
    path('contacts/export/', views.ContactExportView.as_view(), name='contact_export'),
    path('contacts/delete-all/', views.ContactDeleteAllView.as_view(), name='contact_delete_all'),
]
```

### UI Flow - Contact List

1. User navigates to Contacts section
2. System displays contacts from connected provider (if any)
3. For each contact, show:
   - Name, email, phone (from provider/cache)
   - Tags (editable inline)
   - Aliases (editable inline)
4. Search/filter bar at top
5. Tag filter dropdown

### UI Flow - Saved Contacts

1. If no OAuth provider connected, prompt to either:
   - Connect Google/Outlook
   - Use Saved Contacts (with privacy notice)
2. If opted into Saved Contacts:
   - CRUD interface for manual contact entry
   - Same tag/alias functionality

### UI Flow - GDPR Actions

1. Export: Download all contact data as JSON/CSV
2. Delete All: Confirm dialog, then delete all ContactReferences + SavedContacts

---

## 3.9 GDPR Compliance Endpoints

**Description:** Endpoints for data access and deletion rights.

**Component:** Hub

### Export Endpoint

```python
# GET /contacts/export/?format=json|csv

class ContactExportView(LoginRequiredMixin, View):
    def get(self, request):
        format = request.GET.get('format', 'json')
        user = request.user

        # Gather all contact data
        data = {
            'exported_at': timezone.now().isoformat(),
            'contact_references': list(
                ContactReference.objects.filter(user=user).values()
            ),
            'saved_contacts': [
                {
                    'id': c.id,
                    'name': c.name,  # Decrypted
                    'email': c.email,
                    'phone': c.phone,
                    'notes': c.notes,
                }
                for c in SavedContact.objects.filter(user=user)
            ]
        }

        if format == 'csv':
            return self._export_csv(data)
        return JsonResponse(data)
```

### Delete All Endpoint

```python
# POST /contacts/delete-all/

class ContactDeleteAllView(LoginRequiredMixin, View):
    def post(self, request):
        user = request.user

        # Delete all contact references
        ContactReference.objects.filter(user=user).delete()

        # Delete all saved contacts
        SavedContact.objects.filter(user=user).delete()

        # Invalidate cache
        cache_service.invalidate_user(user.id)

        messages.success(request, "All contact data has been deleted.")
        return redirect('contact_list')
```

---

# 4. Future Considerations (Out of Scope)

Features noted for potential future development but not included in this spec:

- **Mobile on-device resolution:** Phase 2 of original issue - requires mobile app
- **Cross-provider sync:** Merging contacts across Google + Outlook
- **Fuzzy matching:** "Javier" matching "Xavier"
- **Contact creation/editing:** Write-back to providers
- **Hierarchical tags:** Nested tag structure (Work > Engineering > Backend)
- **Tag suggestions:** Agent suggesting tags based on context
- **Contact preferences learning:** Agent learning which contact user means over time
- **Photo proxying:** Caching photos through EchoForge to avoid tracking

---

# 5. Implementation Approach

## 5.1 Recommended Phases

**Phase 1: Foundation (Hub)**

1. Create `apps/contacts/` Django app (Hub)
2. Implement ContactReference model + migrations (Hub)
3. Implement SavedContact model with EncryptedTextField (Hub)
4. Create SavedContactProvider (Hub)
5. Implement ContactCacheService (Hub)
6. Add contact tools to agent config (Hub)
7. Basic Hub UI: Saved contacts CRUD (Hub)
8. GDPR endpoints: export, delete-all (Hub)

**Phase 2: OAuth Providers (Hub)**

1. Add 'contacts.readonly' scope to Google OAuth config (Hub)
2. Add 'Contacts.Read' scope to Outlook OAuth config (Hub)
3. Implement GoogleContactProvider (Hub)
4. Implement OutlookContactProvider (Hub)
5. Implement ContactResolutionService (Hub)
6. Hub UI: View provider contacts, manage tags/aliases (Hub)

**Phase 3: Agent Tools (Agent + Hub)**

1. Register contact tools in agent tool registry (Agent)
2. Implement ContactToolExecutor in Hub internal API (Hub)
3. Update email_send to accept contact references (Agent + Hub)
4. Update calendar tools to accept contact references (Agent + Hub)
5. Test end-to-end: "Send email to Xavier" flow

**Phase 4: Polish**

1. Inline tag/alias management via conversation
2. Performance optimization (cache warming strategy)
3. Error handling and edge cases
4. Documentation

## 5.2 Dependencies

| Dependency | Notes |
|------------|-------|
| Google People API scope | Add to existing OAuth config |
| Microsoft Graph API scope | Add to existing OAuth config |
| EncryptedTextField | Already exists in Hub (core.encryption) |
| Redis | Already available for caching |

---

# 6. Acceptance Criteria

## 6.1 Contact Reference Storage

- [ ] ContactReference model stores provider, external_id, tags, aliases
- [ ] Unique constraint enforced on (user, provider, external_id)
- [ ] Tags and aliases are case-insensitive for matching
- [ ] No PII is stored in ContactReference

## 6.2 Saved Contacts

- [ ] SavedContact model encrypts all PII fields
- [ ] User can create, read, update, delete saved contacts
- [ ] Saved contacts appear in contact search results

## 6.3 OAuth Provider Integration

- [ ] Google contacts fetchable via People API
- [ ] Outlook contacts fetchable via Graph API
- [ ] Contacts cached in Redis with configurable TTL
- [ ] Cache invalidated when tags/aliases change

## 6.4 Contact Resolution

- [ ] "Xavier" resolves to correct contact if unique match
- [ ] "Xav" resolves via alias lookup
- [ ] Multiple matches return ambiguous status with options
- [ ] No matches return not_found status

## 6.5 Agent Tools

- [ ] contacts_search returns matching contacts
- [ ] contacts_resolve handles unique, ambiguous, and not_found cases
- [ ] contacts_tag adds tag to ContactReference (creates if needed)
- [ ] contacts_untag removes tag from ContactReference
- [ ] contacts_list_tags returns all user's tags
- [ ] contacts_get_by_tag returns contacts with specified tag
- [ ] contacts_add_alias adds alias to ContactReference

## 6.6 Tool Integration

- [ ] email_send accepts contact reference instead of raw email
- [ ] calendar_create_event accepts contact references for attendees
- [ ] Contact reference resolved to email before sending

## 6.7 Hub UI

- [ ] Contacts section accessible from sidebar
- [ ] Can view contacts from connected provider
- [ ] Can add/remove tags inline
- [ ] Can add/remove aliases inline
- [ ] Can manage saved contacts (CRUD)

## 6.8 GDPR Compliance

- [ ] Export endpoint returns all contact data (JSON/CSV)
- [ ] Delete-all endpoint removes all ContactReferences and SavedContacts
- [ ] Cache invalidated on delete
- [ ] Explicit opt-in required for Saved Contacts feature

---

*End of Specification*
