---
title: EchoForge Hub Testing Specification
version: "1.1"
status: testing
project: EchoForge Hub
created: 2025-12-31
updated: 2025-12-31
---

# EchoForge Hub Testing Specification

## 1. Overview

This specification defines the comprehensive testing strategy for EchoForge Hub Phase A components:
- Internal API
- Knowledge Base Processing
- Dynamic Onboarding Wizard
- Stripe Billing Integration

**Testing Framework:** pytest + Django test client + pytest-django
**Coverage Target:** 80% minimum for critical paths

---

## 2. Test Environment Setup

### 2.1 Dependencies

```bash
# requirements/testing.txt
pytest==8.0.0
pytest-django==4.7.0
pytest-cov==4.1.0
pytest-asyncio==0.23.0
factory-boy==3.3.0
faker==22.0.0
responses==0.24.0  # Mock HTTP requests
freezegun==1.2.0   # Time manipulation
stripe-mock==0.1.0  # Stripe API mocking
```

### 2.2 pytest Configuration

```python
# pytest.ini
[pytest]
DJANGO_SETTINGS_MODULE = echoforge_hub.settings.testing
python_files = tests.py test_*.py *_tests.py
addopts = --cov=apps --cov-report=html --cov-report=term-missing
filterwarnings =
    ignore::DeprecationWarning
```

### 2.3 Test Settings

```python
# echoforge_hub/settings/testing.py
from .base import *

DEBUG = False
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'echoforge_hub_test',
        'USER': 'postgres',
        'PASSWORD': 'postgres',
        'HOST': 'localhost',
        'PORT': '5435',
    }
}

# Use in-memory cache for tests
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    }
}

# Celery: run tasks synchronously in tests
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

# Stripe test mode
STRIPE_SECRET_KEY = 'sk_test_fake'
STRIPE_WEBHOOK_SECRET = 'whsec_test_fake'

# Internal API
HUB_SERVICE_SECRET = 'test-service-secret-32chars-min'

# OpenAI mock
OPENAI_API_KEY = 'sk-test-fake'
```

---

## 3. Test Factories

### 3.1 Customer Factories

```python
# apps/customers/tests/factories.py
import factory
from factory.django import DjangoModelFactory
from apps.customers.models import Customer, CustomerUser

class CustomerFactory(DjangoModelFactory):
    class Meta:
        model = Customer

    name = factory.Faker('company')
    slug = factory.LazyAttribute(lambda o: o.name.lower().replace(' ', '-'))
    email = factory.Faker('company_email')
    phone = factory.Faker('phone_number')
    stripe_customer_id = factory.Sequence(lambda n: f'cus_test_{n}')
    is_active = True

class CustomerUserFactory(DjangoModelFactory):
    class Meta:
        model = CustomerUser

    customer = factory.SubFactory(CustomerFactory)
    email = factory.Faker('email')
    first_name = factory.Faker('first_name')
    last_name = factory.Faker('last_name')
    role = 'admin'
    is_active = True
```

### 3.2 Agent Factories

```python
# apps/agents/tests/factories.py
import factory
from factory.django import DjangoModelFactory
from apps.agents.models import AgentType, AgentInstance
from apps.customers.tests.factories import CustomerFactory

class AgentTypeFactory(DjangoModelFactory):
    class Meta:
        model = AgentType

    name = factory.Faker('word')
    slug = factory.LazyAttribute(lambda o: o.name.lower())
    description = factory.Faker('sentence')
    system_prompt_template = "You are a helpful assistant for {company_name}."
    onboarding_schema = {
        "steps": [
            {
                "id": "basics",
                "title": "Basic Info",
                "fields": [
                    {"name": "agent_name", "type": "text", "required": True}
                ]
            }
        ],
        "knowledge_base": {
            "enabled": True,
            "required": False,
            "allow_existing": True,
            "allow_create_new": True
        }
    }
    is_active = True

class AgentInstanceFactory(DjangoModelFactory):
    class Meta:
        model = AgentInstance

    customer = factory.SubFactory(CustomerFactory)
    agent_type = factory.SubFactory(AgentTypeFactory)
    name = factory.Faker('word')
    configuration = {}
    is_active = True
    api_key_prefix = factory.Sequence(lambda n: f'efk_{n}')
    api_key_hash = factory.Sequence(lambda n: f'hash_{n}')
```

### 3.3 Knowledge Base Factories

```python
# apps/knowledge/tests/factories.py
import factory
from factory.django import DjangoModelFactory
from apps.knowledge.models import KnowledgeBase, KnowledgeDocument, DocumentChunk
from apps.customers.tests.factories import CustomerFactory

class KnowledgeBaseFactory(DjangoModelFactory):
    class Meta:
        model = KnowledgeBase

    customer = factory.SubFactory(CustomerFactory)
    name = factory.Faker('word')
    description = factory.Faker('sentence')

class KnowledgeDocumentFactory(DjangoModelFactory):
    class Meta:
        model = KnowledgeDocument

    knowledge_base = factory.SubFactory(KnowledgeBaseFactory)
    customer = factory.LazyAttribute(lambda o: o.knowledge_base.customer)
    title = factory.Faker('sentence')
    source_type = 'upload'
    status = 'pending'
    file_size = 1024

class DocumentChunkFactory(DjangoModelFactory):
    class Meta:
        model = DocumentChunk

    document = factory.SubFactory(KnowledgeDocumentFactory)
    customer = factory.LazyAttribute(lambda o: o.document.customer)
    content = factory.Faker('paragraph')
    chunk_index = factory.Sequence(lambda n: n)
    token_count = 100
    # embedding set in tests that need it
```

### 3.4 Billing Factories

```python
# apps/billing/tests/factories.py
import factory
from factory.django import DjangoModelFactory
from django.utils import timezone
from apps.billing.models import Plan, Subscription, UsageRecord, ExtraUsageBalance
from apps.customers.tests.factories import CustomerFactory

class PlanFactory(DjangoModelFactory):
    class Meta:
        model = Plan

    name = factory.Faker('word')
    slug = factory.LazyAttribute(lambda o: o.name.lower())
    stripe_price_id = factory.Sequence(lambda n: f'price_test_{n}')
    price_cents = 4900
    billing_period = 'monthly'
    limits = {
        "messages": 1000,
        "tokens": 100000,
        "agents": 3,
        "knowledge_bases": 2
    }
    is_active = True

class SubscriptionFactory(DjangoModelFactory):
    class Meta:
        model = Subscription

    customer = factory.SubFactory(CustomerFactory)
    plan = factory.SubFactory(PlanFactory)
    stripe_subscription_id = factory.Sequence(lambda n: f'sub_test_{n}')
    status = 'active'
    current_period_start = factory.LazyFunction(timezone.now)
    current_period_end = factory.LazyFunction(
        lambda: timezone.now() + timezone.timedelta(days=30)
    )

class UsageRecordFactory(DjangoModelFactory):
    class Meta:
        model = UsageRecord

    customer = factory.SubFactory(CustomerFactory)
    agent_instance = factory.SubFactory('apps.agents.tests.factories.AgentInstanceFactory')
    period_start = factory.LazyFunction(timezone.now)
    period_end = factory.LazyFunction(
        lambda: timezone.now() + timezone.timedelta(days=30)
    )
    messages = 0
    input_tokens = 0
    output_tokens = 0

class ExtraUsageBalanceFactory(DjangoModelFactory):
    class Meta:
        model = ExtraUsageBalance

    customer = factory.SubFactory(CustomerFactory)
    balance_cents = 0
```

---

## 4. Internal API Tests

### 4.1 Authentication Tests

```python
# api/internal/tests/test_authentication.py
import pytest
from django.test import RequestFactory
from api.internal.authentication import ServiceSecretAuthentication
from apps.agents.tests.factories import AgentInstanceFactory

@pytest.mark.django_db
class TestServiceSecretAuthentication:
    """Test internal API authentication."""

    def setup_method(self):
        self.auth = ServiceSecretAuthentication()
        self.factory = RequestFactory()

    def test_valid_secret_and_agent_id(self):
        """Valid service secret and agent ID should authenticate."""
        agent = AgentInstanceFactory()
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer test-service-secret-32chars-min',
            HTTP_X_AGENT_INSTANCE_ID=str(agent.id)
        )
        user, auth = self.auth.authenticate(request)
        assert auth is not None
        assert auth['agent_instance'] == agent

    def test_missing_secret(self):
        """Missing Authorization header should fail."""
        request = self.factory.get('/api/internal/agent/config')
        result = self.auth.authenticate(request)
        assert result is None

    def test_invalid_secret(self):
        """Invalid service secret should raise AuthenticationFailed."""
        from rest_framework.exceptions import AuthenticationFailed
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer wrong-secret'
        )
        with pytest.raises(AuthenticationFailed):
            self.auth.authenticate(request)

    def test_missing_agent_id_header(self):
        """Missing X-Agent-Instance-ID should fail for agent-scoped endpoints."""
        from rest_framework.exceptions import AuthenticationFailed
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer test-service-secret-32chars-min'
        )
        with pytest.raises(AuthenticationFailed):
            self.auth.authenticate(request)

    def test_inactive_agent(self):
        """Inactive agent should fail authentication."""
        from rest_framework.exceptions import AuthenticationFailed
        agent = AgentInstanceFactory(is_active=False)
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer test-service-secret-32chars-min',
            HTTP_X_AGENT_INSTANCE_ID=str(agent.id)
        )
        with pytest.raises(AuthenticationFailed):
            self.auth.authenticate(request)

    def test_multiple_secrets_rotation(self, settings):
        """Should accept any of multiple secrets during rotation."""
        settings.HUB_SERVICE_SECRET = 'old-secret-32chars-minimum,new-secret-32chars-minimum'
        agent = AgentInstanceFactory()

        # Old secret should work
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer old-secret-32chars-minimum',
            HTTP_X_AGENT_INSTANCE_ID=str(agent.id)
        )
        user, auth = self.auth.authenticate(request)
        assert auth is not None

        # New secret should work
        request = self.factory.get(
            '/api/internal/agent/config',
            HTTP_AUTHORIZATION='Bearer new-secret-32chars-minimum',
            HTTP_X_AGENT_INSTANCE_ID=str(agent.id)
        )
        user, auth = self.auth.authenticate(request)
        assert auth is not None
```

### 4.2 Config Endpoint Tests

```python
# api/internal/tests/test_config_endpoint.py
import pytest
from django.urls import reverse
from rest_framework.test import APIClient
from apps.agents.tests.factories import AgentInstanceFactory, AgentTypeFactory
from apps.knowledge.tests.factories import KnowledgeBaseFactory
from apps.billing.tests.factories import SubscriptionFactory, PlanFactory

@pytest.mark.django_db
class TestAgentConfigEndpoint:
    """Test GET /api/internal/agent/{agent_id}/config"""

    def setup_method(self):
        self.client = APIClient()
        self.headers = {
            'HTTP_AUTHORIZATION': 'Bearer test-service-secret-32chars-min',
        }

    def test_get_config_success(self):
        """Should return complete agent configuration."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)

        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)
        response = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )

        assert response.status_code == 200
        data = response.json()

        # Verify required fields
        assert data['agent_id'] == str(agent.id)
        assert data['agent_type'] == agent.agent_type.slug
        assert data['customer_id'] == str(agent.customer.id)
        assert 'identity' in data
        assert 'system_prompt' in data
        assert 'billing' in data
        assert 'config_version' in data

    def test_config_includes_knowledge_base(self):
        """Config should include KB info when agent has one."""
        kb = KnowledgeBaseFactory()
        agent = AgentInstanceFactory(
            customer=kb.customer,
            knowledge_base=kb
        )
        SubscriptionFactory(customer=agent.customer)

        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)
        response = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )

        data = response.json()
        assert data['knowledge_base']['id'] == str(kb.id)
        assert data['knowledge_base']['enabled'] is True

    def test_config_billing_status(self):
        """Config should reflect accurate billing status."""
        plan = PlanFactory(limits={"messages": 100})
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer, plan=plan)

        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)
        response = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )

        data = response.json()
        assert data['billing']['can_respond'] is True
        assert 'usage_remaining' in data['billing']

    def test_config_embed_domains(self):
        """Config should include embed_domains if configured."""
        agent = AgentInstanceFactory(
            configuration={'embed_domains': ['example.com', 'test.com']}
        )
        SubscriptionFactory(customer=agent.customer)

        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)
        response = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )

        data = response.json()
        assert data['embed_domains'] == ['example.com', 'test.com']

    def test_agent_not_found(self):
        """Should return 404 for non-existent agent."""
        agent = AgentInstanceFactory()
        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)

        response = self.client.get(
            '/api/internal/agent/00000000-0000-0000-0000-000000000000/config',
            **self.headers
        )

        assert response.status_code == 404

    def test_config_version_changes_on_update(self):
        """config_version should change when agent is updated."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)
        self.headers['HTTP_X_AGENT_INSTANCE_ID'] = str(agent.id)

        # First request
        response1 = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )
        version1 = response1.json()['config_version']

        # Update agent
        agent.name = "Updated Name"
        agent.save()

        # Second request
        response2 = self.client.get(
            f'/api/internal/agent/{agent.id}/config',
            **self.headers
        )
        version2 = response2.json()['config_version']

        assert version1 != version2
```

### 4.3 API Key Validation Tests

```python
# api/internal/tests/test_validate_key.py
import pytest
from rest_framework.test import APIClient
from apps.agents.tests.factories import AgentInstanceFactory

@pytest.mark.django_db
class TestValidateKeyEndpoint:
    """Test GET /api/internal/agent/validate-key"""

    def setup_method(self):
        self.client = APIClient()
        self.headers = {
            'HTTP_AUTHORIZATION': 'Bearer test-service-secret-32chars-min',
        }

    def test_valid_key(self):
        """Valid API key should return agent info."""
        agent = AgentInstanceFactory(
            api_key_prefix='efk_test123',
            api_key_hash='hashed_value'
        )

        response = self.client.get(
            '/api/internal/agent/validate-key',
            HTTP_X_API_KEY='efk_test123_fullkey',
            **self.headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data['valid'] is True
        assert data['agent_instance_id'] == str(agent.id)

    def test_invalid_key(self):
        """Invalid API key should return valid=false."""
        response = self.client.get(
            '/api/internal/agent/validate-key',
            HTTP_X_API_KEY='efk_nonexistent',
            **self.headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data['valid'] is False

    def test_inactive_agent_key(self):
        """Key for inactive agent should return is_active=false."""
        agent = AgentInstanceFactory(
            is_active=False,
            api_key_prefix='efk_inactive'
        )

        response = self.client.get(
            '/api/internal/agent/validate-key',
            HTTP_X_API_KEY='efk_inactive_fullkey',
            **self.headers
        )

        data = response.json()
        assert data['is_active'] is False
```

### 4.4 Can-Respond Tests

```python
# api/internal/tests/test_can_respond.py
import pytest
from django.utils import timezone
from datetime import timedelta
from rest_framework.test import APIClient
from apps.agents.tests.factories import AgentInstanceFactory
from apps.billing.tests.factories import (
    SubscriptionFactory, PlanFactory, UsageRecordFactory, ExtraUsageBalanceFactory
)

@pytest.mark.django_db
class TestCanRespondEndpoint:
    """Test GET /api/internal/billing/can-respond/{agent_id}"""

    def setup_method(self):
        self.client = APIClient()
        self.headers = {
            'HTTP_AUTHORIZATION': 'Bearer test-service-secret-32chars-min',
        }

    def test_can_respond_within_limits(self):
        """Should allow response when under limits."""
        plan = PlanFactory(limits={"messages": 1000, "tokens": 100000})
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer, plan=plan)
        UsageRecordFactory(
            customer=agent.customer,
            agent_instance=agent,
            messages=100  # Under limit
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data['allowed'] is True
        assert data['in_grace_period'] is False

    def test_cannot_respond_over_limit_no_balance(self):
        """Should deny when over limits with no extra balance."""
        plan = PlanFactory(limits={"messages": 100})
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer, plan=plan)
        UsageRecordFactory(
            customer=agent.customer,
            agent_instance=agent,
            messages=100  # At limit
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is False
        assert 'reason' in data

    def test_can_respond_over_limit_with_balance(self):
        """Should allow when over limits but has extra balance."""
        plan = PlanFactory(limits={"messages": 100})
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer, plan=plan)
        UsageRecordFactory(
            customer=agent.customer,
            agent_instance=agent,
            messages=150  # Over limit
        )
        ExtraUsageBalanceFactory(
            customer=agent.customer,
            balance_cents=1000  # Has balance
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is True

    def test_grace_period_active(self):
        """Should indicate grace period status."""
        plan = PlanFactory(limits={"messages": 100})
        agent = AgentInstanceFactory()
        agent.customer.grace_period_ends_at = timezone.now() + timedelta(hours=12)
        agent.customer.save()
        SubscriptionFactory(customer=agent.customer, plan=plan)
        UsageRecordFactory(
            customer=agent.customer,
            agent_instance=agent,
            messages=150
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is True
        assert data['in_grace_period'] is True
        assert 'grace_period_ends_at' in data

    def test_grace_period_expired(self):
        """Should deny when grace period has expired."""
        plan = PlanFactory(limits={"messages": 100})
        agent = AgentInstanceFactory()
        agent.customer.grace_period_ends_at = timezone.now() - timedelta(hours=1)
        agent.customer.save()
        SubscriptionFactory(customer=agent.customer, plan=plan)
        UsageRecordFactory(
            customer=agent.customer,
            agent_instance=agent,
            messages=150
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is False

    def test_no_subscription(self):
        """Should deny when no active subscription."""
        agent = AgentInstanceFactory()
        # No subscription created

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is False
        assert 'subscription' in data['reason'].lower()

    def test_trial_subscription(self):
        """Should allow for trial subscriptions within limits."""
        plan = PlanFactory(slug='trial', limits={"messages": 50})
        agent = AgentInstanceFactory()
        SubscriptionFactory(
            customer=agent.customer,
            plan=plan,
            status='trialing',
            trial_ends_at=timezone.now() + timedelta(days=7)
        )

        response = self.client.get(
            f'/api/internal/billing/can-respond/{agent.id}',
            **self.headers
        )

        data = response.json()
        assert data['allowed'] is True
```

### 4.5 Usage Batch Tests

```python
# api/internal/tests/test_usage_batch.py
import pytest
import uuid
from rest_framework.test import APIClient
from apps.agents.tests.factories import AgentInstanceFactory
from apps.billing.tests.factories import SubscriptionFactory
from apps.billing.models import UsageRecord

@pytest.mark.django_db
class TestUsageBatchEndpoint:
    """Test POST /api/internal/usage/batch"""

    def setup_method(self):
        self.client = APIClient()
        self.headers = {
            'HTTP_AUTHORIZATION': 'Bearer test-service-secret-32chars-min',
        }

    def test_submit_usage_batch(self):
        """Should accept and store usage reports."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)

        payload = {
            "reports": [
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:00Z",
                    "metrics": {
                        "messages": 1,
                        "input_tokens": 150,
                        "output_tokens": 320
                    },
                    "request_id": str(uuid.uuid4())
                }
            ]
        }

        response = self.client.post(
            '/api/internal/usage/batch',
            payload,
            format='json',
            **self.headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data['accepted'] == 1
        assert data['rejected'] == 0

    def test_deduplicate_by_request_id(self):
        """Should deduplicate reports with same request_id."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)
        request_id = str(uuid.uuid4())

        payload = {
            "reports": [
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:00Z",
                    "metrics": {"messages": 1, "input_tokens": 100, "output_tokens": 200},
                    "request_id": request_id
                }
            ]
        }

        # Submit twice
        self.client.post('/api/internal/usage/batch', payload, format='json', **self.headers)
        response = self.client.post('/api/internal/usage/batch', payload, format='json', **self.headers)

        data = response.json()
        assert data['accepted'] == 0  # Duplicate rejected
        assert data['rejected'] == 1

    def test_multiple_reports_batch(self):
        """Should handle multiple reports in one batch."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)

        payload = {
            "reports": [
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:00Z",
                    "metrics": {"messages": 1, "input_tokens": 100, "output_tokens": 200},
                    "request_id": str(uuid.uuid4())
                },
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:05Z",
                    "metrics": {"messages": 1, "input_tokens": 150, "output_tokens": 250},
                    "request_id": str(uuid.uuid4())
                }
            ]
        }

        response = self.client.post(
            '/api/internal/usage/batch',
            payload,
            format='json',
            **self.headers
        )

        data = response.json()
        assert data['accepted'] == 2

    def test_usage_aggregation(self):
        """Usage should aggregate into UsageRecord."""
        agent = AgentInstanceFactory()
        SubscriptionFactory(customer=agent.customer)

        payload = {
            "reports": [
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:00Z",
                    "metrics": {"messages": 1, "input_tokens": 100, "output_tokens": 200},
                    "request_id": str(uuid.uuid4())
                },
                {
                    "agent_instance_id": str(agent.id),
                    "timestamp": "2025-01-15T10:30:05Z",
                    "metrics": {"messages": 1, "input_tokens": 150, "output_tokens": 250},
                    "request_id": str(uuid.uuid4())
                }
            ]
        }

        self.client.post('/api/internal/usage/batch', payload, format='json', **self.headers)

        record = UsageRecord.objects.get(
            customer=agent.customer,
            agent_instance=agent
        )
        assert record.messages == 2
        assert record.input_tokens == 250
        assert record.output_tokens == 450

    def test_invalid_agent_rejected(self):
        """Reports for non-existent agents should be rejected."""
        payload = {
            "reports": [
                {
                    "agent_instance_id": "00000000-0000-0000-0000-000000000000",
                    "timestamp": "2025-01-15T10:30:00Z",
                    "metrics": {"messages": 1},
                    "request_id": str(uuid.uuid4())
                }
            ]
        }

        response = self.client.post(
            '/api/internal/usage/batch',
            payload,
            format='json',
            **self.headers
        )

        data = response.json()
        assert data['rejected'] == 1
        assert len(data['errors']) == 1
```

---

## 5. Knowledge Base Tests

### 5.1 Document Processing Tests

```python
# apps/knowledge/tests/test_processing.py
import pytest
from unittest.mock import patch, MagicMock
from apps.knowledge.tasks import process_document
from apps.knowledge.tests.factories import KnowledgeDocumentFactory, KnowledgeBaseFactory
from apps.knowledge.models import DocumentChunk

@pytest.mark.django_db
class TestDocumentProcessing:
    """Test document processing pipeline."""

    @patch('apps.knowledge.tasks.get_embedding')
    @patch('apps.knowledge.tasks.extract_text')
    def test_process_text_document(self, mock_extract, mock_embedding):
        """Should process text document and create chunks."""
        mock_extract.return_value = "This is test content. " * 100  # ~500 words
        mock_embedding.return_value = [0.1] * 1536  # Fake embedding

        doc = KnowledgeDocumentFactory(
            source_type='upload',
            file_path='/fake/path.txt',
            status='pending'
        )

        process_document(str(doc.id))

        doc.refresh_from_db()
        assert doc.status == 'indexed'
        assert DocumentChunk.objects.filter(document=doc).count() > 0

    @patch('apps.knowledge.tasks.get_embedding')
    @patch('apps.knowledge.tasks.extract_text')
    def test_chunking_parameters(self, mock_extract, mock_embedding):
        """Should chunk with correct parameters (500 tokens, 50 overlap)."""
        # Create content that will produce multiple chunks
        mock_extract.return_value = "word " * 1500  # ~1500 tokens
        mock_embedding.return_value = [0.1] * 1536

        doc = KnowledgeDocumentFactory(status='pending')

        process_document(str(doc.id))

        chunks = DocumentChunk.objects.filter(document=doc)
        # With 1500 tokens, 500 chunk size, 50 overlap: ~3-4 chunks
        assert chunks.count() >= 3

        # Check overlap exists (first chunk's end should appear in second chunk's start)
        chunk_contents = [c.content for c in chunks.order_by('chunk_index')]
        if len(chunk_contents) >= 2:
            # Some overlap should exist
            assert chunk_contents[0][-50:] in chunk_contents[1][:100] or \
                   any(word in chunk_contents[1][:100] for word in chunk_contents[0][-50:].split())

    @patch('apps.knowledge.tasks.get_embedding')
    @patch('apps.knowledge.tasks.extract_text')
    def test_processing_failure_marks_error(self, mock_extract, mock_embedding):
        """Failed processing should mark document as error."""
        mock_extract.side_effect = Exception("Extraction failed")

        doc = KnowledgeDocumentFactory(status='pending')

        with pytest.raises(Exception):
            process_document(str(doc.id))

        doc.refresh_from_db()
        assert doc.status == 'error'

    def test_skip_already_processed(self):
        """Should skip documents already indexed."""
        doc = KnowledgeDocumentFactory(status='indexed')

        # Should not raise, should just skip
        process_document(str(doc.id))

        doc.refresh_from_db()
        assert doc.status == 'indexed'
```

### 5.2 Text Extraction Tests

```python
# apps/knowledge/tests/test_extractors.py
import pytest
from io import BytesIO
from apps.knowledge.extractors import extract_text_from_file

class TestTextExtraction:
    """Test text extraction from various file types."""

    def test_extract_txt(self, tmp_path):
        """Should extract text from .txt files."""
        file_path = tmp_path / "test.txt"
        file_path.write_text("Hello, this is test content.")

        content = extract_text_from_file(str(file_path))
        assert "Hello, this is test content." in content

    def test_extract_markdown(self, tmp_path):
        """Should extract text from .md files."""
        file_path = tmp_path / "test.md"
        file_path.write_text("# Heading\n\nThis is **bold** text.")

        content = extract_text_from_file(str(file_path))
        assert "Heading" in content
        assert "bold" in content

    def test_extract_html(self, tmp_path):
        """Should extract text from HTML, stripping tags."""
        file_path = tmp_path / "test.html"
        file_path.write_text("<html><body><h1>Title</h1><p>Content here.</p></body></html>")

        content = extract_text_from_file(str(file_path))
        assert "Title" in content
        assert "Content here" in content
        assert "<h1>" not in content

    @pytest.mark.skip(reason="Requires pypdf library")
    def test_extract_pdf(self, tmp_path):
        """Should extract text from PDF files."""
        # Would need actual PDF file or mock
        pass

    @pytest.mark.skip(reason="Requires python-docx library")
    def test_extract_docx(self, tmp_path):
        """Should extract text from DOCX files."""
        # Would need actual DOCX file or mock
        pass
```

### 5.3 Vector Search Tests

```python
# apps/knowledge/tests/test_search.py
import pytest
from unittest.mock import patch
import numpy as np
from apps.knowledge.services import search_knowledge_base
from apps.knowledge.tests.factories import (
    KnowledgeBaseFactory, KnowledgeDocumentFactory, DocumentChunkFactory
)

@pytest.mark.django_db
class TestVectorSearch:
    """Test semantic search functionality."""

    @patch('apps.knowledge.services.get_embedding')
    def test_search_returns_relevant_chunks(self, mock_embedding):
        """Should return chunks ordered by similarity."""
        kb = KnowledgeBaseFactory()
        doc = KnowledgeDocumentFactory(knowledge_base=kb, status='indexed')

        # Create chunks with known embeddings
        chunk1 = DocumentChunkFactory(
            document=doc,
            content="How to reset your password",
            embedding=[0.9] + [0.0] * 1535  # Similar to query
        )
        chunk2 = DocumentChunkFactory(
            document=doc,
            content="Company holiday schedule",
            embedding=[0.1] + [0.0] * 1535  # Different from query
        )

        # Query embedding similar to chunk1
        mock_embedding.return_value = [0.85] + [0.0] * 1535

        results = search_knowledge_base(
            kb_id=str(kb.id),
            query="password reset help",
            top_k=5
        )

        assert len(results) >= 1
        assert results[0].content == "How to reset your password"

    @patch('apps.knowledge.services.get_embedding')
    def test_search_respects_min_score(self, mock_embedding):
        """Should filter results below min_score."""
        kb = KnowledgeBaseFactory()
        doc = KnowledgeDocumentFactory(knowledge_base=kb, status='indexed')

        # Create chunk with low similarity
        DocumentChunkFactory(
            document=doc,
            content="Unrelated content",
            embedding=[0.1] + [0.0] * 1535
        )

        mock_embedding.return_value = [0.9] + [0.0] * 1535

        results = search_knowledge_base(
            kb_id=str(kb.id),
            query="password reset",
            top_k=5,
            min_score=0.8
        )

        # Low similarity chunk should be filtered
        assert len(results) == 0

    @patch('apps.knowledge.services.get_embedding')
    def test_search_respects_top_k(self, mock_embedding):
        """Should return at most top_k results."""
        kb = KnowledgeBaseFactory()
        doc = KnowledgeDocumentFactory(knowledge_base=kb, status='indexed')

        # Create many chunks
        for i in range(10):
            DocumentChunkFactory(
                document=doc,
                content=f"Content {i}",
                embedding=[0.9 - (i * 0.05)] + [0.0] * 1535
            )

        mock_embedding.return_value = [0.9] + [0.0] * 1535

        results = search_knowledge_base(
            kb_id=str(kb.id),
            query="test",
            top_k=3
        )

        assert len(results) == 3

    @patch('apps.knowledge.services.get_embedding')
    def test_search_only_indexed_documents(self, mock_embedding):
        """Should only search chunks from indexed documents."""
        kb = KnowledgeBaseFactory()
        indexed_doc = KnowledgeDocumentFactory(knowledge_base=kb, status='indexed')
        pending_doc = KnowledgeDocumentFactory(knowledge_base=kb, status='pending')

        DocumentChunkFactory(
            document=indexed_doc,
            content="Indexed content",
            embedding=[0.9] + [0.0] * 1535
        )
        DocumentChunkFactory(
            document=pending_doc,
            content="Pending content",
            embedding=[0.9] + [0.0] * 1535
        )

        mock_embedding.return_value = [0.9] + [0.0] * 1535

        results = search_knowledge_base(kb_id=str(kb.id), query="test")

        contents = [r.content for r in results]
        assert "Indexed content" in contents
        assert "Pending content" not in contents
```

---

## 6. Onboarding Wizard Tests

### 6.1 Wizard Flow Tests

```python
# apps/agents/tests/test_onboarding_wizard.py
import pytest
from django.urls import reverse
from django.test import Client
from apps.agents.tests.factories import AgentTypeFactory
from apps.agents.models import AgentInstance, OnboardingSession
from apps.customers.tests.factories import CustomerFactory, CustomerUserFactory

@pytest.mark.django_db
class TestOnboardingWizard:
    """Test dynamic onboarding wizard."""

    def setup_method(self):
        self.client = Client()
        self.customer = CustomerFactory()
        self.user = CustomerUserFactory(customer=self.customer)
        self.client.force_login(self.user)

    def test_wizard_loads_first_step(self):
        """Wizard should load and display first step from schema."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "title": "Basic Info",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True}
                        ]
                    }
                ]
            }
        )

        response = self.client.get(
            reverse('agents:onboarding', args=[agent_type.slug])
        )

        assert response.status_code == 200
        assert "Basic Info" in response.content.decode()
        assert "agent_name" in response.content.decode()

    def test_wizard_creates_session(self):
        """Starting wizard should create OnboardingSession."""
        agent_type = AgentTypeFactory()

        self.client.get(reverse('agents:onboarding', args=[agent_type.slug]))

        session = OnboardingSession.objects.filter(
            customer=self.customer,
            agent_type=agent_type
        ).first()
        assert session is not None
        assert session.status == 'in_progress'

    def test_wizard_step_validation(self):
        """Required fields should be validated."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "title": "Basic Info",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True}
                        ]
                    }
                ]
            }
        )

        # Submit without required field
        response = self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'basics']),
            data={}
        )

        assert response.status_code == 200
        assert "required" in response.content.decode().lower() or \
               response.context.get('errors')

    def test_wizard_advances_steps(self):
        """Valid submission should advance to next step."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "title": "Basic Info",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True}
                        ]
                    },
                    {
                        "id": "advanced",
                        "title": "Advanced",
                        "fields": [
                            {"name": "greeting", "type": "textarea", "required": False}
                        ]
                    }
                ]
            }
        )

        # Start wizard
        self.client.get(reverse('agents:onboarding', args=[agent_type.slug]))

        # Submit first step
        response = self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'basics']),
            data={'agent_name': 'My Agent'},
            follow=True
        )

        assert "Advanced" in response.content.decode()

    def test_wizard_saves_data_to_session(self):
        """Step data should be saved to OnboardingSession."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True}
                        ]
                    }
                ]
            }
        )

        self.client.get(reverse('agents:onboarding', args=[agent_type.slug]))
        self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'basics']),
            data={'agent_name': 'Test Agent'}
        )

        session = OnboardingSession.objects.get(
            customer=self.customer,
            agent_type=agent_type
        )
        assert session.data['agent_name'] == 'Test Agent'

    def test_wizard_completion_creates_agent(self):
        """Completing wizard should create AgentInstance."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True}
                        ]
                    }
                ]
            }
        )

        self.client.get(reverse('agents:onboarding', args=[agent_type.slug]))
        self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'basics']),
            data={'agent_name': 'My New Agent'}
        )

        agent = AgentInstance.objects.filter(
            customer=self.customer,
            agent_type=agent_type
        ).first()

        assert agent is not None
        assert agent.name == 'My New Agent'
        assert agent.api_key_prefix.startswith('efk_')


@pytest.mark.django_db
class TestKnowledgeBaseStep:
    """Test KB configuration in onboarding."""

    def setup_method(self):
        self.client = Client()
        self.customer = CustomerFactory()
        self.user = CustomerUserFactory(customer=self.customer)
        self.client.force_login(self.user)

    def test_kb_step_shown_when_enabled(self):
        """KB step should appear when enabled in schema."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {"id": "basics", "fields": [{"name": "name", "type": "text"}]}
                ],
                "knowledge_base": {
                    "enabled": True,
                    "required": False
                }
            }
        )

        response = self.client.get(
            reverse('agents:onboarding', args=[agent_type.slug])
        )

        # KB step should be in the wizard steps
        assert "knowledge" in response.content.decode().lower()

    def test_kb_step_hidden_when_disabled(self):
        """KB step should not appear when disabled."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {"id": "basics", "fields": [{"name": "name", "type": "text"}]}
                ],
                "knowledge_base": {
                    "enabled": False
                }
            }
        )

        response = self.client.get(
            reverse('agents:onboarding', args=[agent_type.slug])
        )

        # Should not have KB references
        content = response.content.decode().lower()
        # Check it's not a required step
        assert "knowledge base" not in content or "optional" in content

    def test_kb_required_validation(self):
        """Required KB should prevent completion without it."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [],
                "knowledge_base": {
                    "enabled": True,
                    "required": True
                }
            }
        )

        self.client.get(reverse('agents:onboarding', args=[agent_type.slug]))

        # Try to complete without KB
        response = self.client.post(
            reverse('agents:onboarding_complete', args=[agent_type.slug]),
            data={}
        )

        # Should fail or show error
        assert response.status_code != 302 or \
               AgentInstance.objects.filter(customer=self.customer).count() == 0
```

---

## 7. Stripe Billing Tests

### 7.1 Checkout Tests

```python
# apps/billing/tests/test_checkout.py
import pytest
from unittest.mock import patch, MagicMock
from django.urls import reverse
from django.test import Client
from apps.billing.tests.factories import PlanFactory
from apps.customers.tests.factories import CustomerFactory, CustomerUserFactory

@pytest.mark.django_db
class TestStripeCheckout:
    """Test Stripe Checkout flow."""

    def setup_method(self):
        self.client = Client()
        self.customer = CustomerFactory(stripe_customer_id='cus_test123')
        self.user = CustomerUserFactory(customer=self.customer)
        self.client.force_login(self.user)

    @patch('stripe.checkout.Session.create')
    def test_create_checkout_session(self, mock_create):
        """Should create Stripe Checkout session."""
        mock_create.return_value = MagicMock(url='https://checkout.stripe.com/test')
        plan = PlanFactory(stripe_price_id='price_test123')

        response = self.client.post(
            reverse('billing:create_checkout'),
            data={'plan': plan.slug}
        )

        assert response.status_code == 302
        assert 'checkout.stripe.com' in response.url

        mock_create.assert_called_once()
        call_kwargs = mock_create.call_args[1]
        assert call_kwargs['customer'] == 'cus_test123'
        assert call_kwargs['line_items'][0]['price'] == 'price_test123'

    def test_checkout_requires_login(self):
        """Checkout should require authentication."""
        self.client.logout()
        plan = PlanFactory()

        response = self.client.post(
            reverse('billing:create_checkout'),
            data={'plan': plan.slug}
        )

        assert response.status_code == 302
        assert 'login' in response.url

    def test_checkout_invalid_plan(self):
        """Should 404 for non-existent plan."""
        response = self.client.post(
            reverse('billing:create_checkout'),
            data={'plan': 'nonexistent'}
        )

        assert response.status_code == 404
```

### 7.2 Webhook Tests

```python
# apps/billing/tests/test_webhooks.py
import pytest
import json
from unittest.mock import patch, MagicMock
from django.test import Client
from apps.billing.models import Subscription
from apps.billing.tests.factories import PlanFactory, SubscriptionFactory
from apps.customers.tests.factories import CustomerFactory

@pytest.mark.django_db
class TestStripeWebhooks:
    """Test Stripe webhook handling."""

    def setup_method(self):
        self.client = Client()

    def create_webhook_event(self, event_type, data):
        """Helper to create mock Stripe event."""
        return {
            'id': 'evt_test123',
            'type': event_type,
            'data': {'object': data}
        }

    @patch('stripe.Webhook.construct_event')
    def test_checkout_completed_creates_subscription(self, mock_construct):
        """checkout.session.completed should create subscription."""
        customer = CustomerFactory(stripe_customer_id='cus_test123')
        plan = PlanFactory(stripe_price_id='price_test123')

        event_data = {
            'customer': 'cus_test123',
            'subscription': 'sub_test123',
            'metadata': {'customer_id': str(customer.id)}
        }
        mock_construct.return_value = self.create_webhook_event(
            'checkout.session.completed', event_data
        )

        with patch('stripe.Subscription.retrieve') as mock_sub:
            mock_sub.return_value = MagicMock(
                id='sub_test123',
                status='active',
                items=MagicMock(data=[MagicMock(price=MagicMock(id='price_test123'))]),
                current_period_start=1704067200,
                current_period_end=1706745600
            )

            response = self.client.post(
                '/billing/webhook/',
                data=json.dumps({}),
                content_type='application/json',
                HTTP_STRIPE_SIGNATURE='test_sig'
            )

        assert response.status_code == 200
        assert Subscription.objects.filter(
            customer=customer,
            stripe_subscription_id='sub_test123'
        ).exists()

    @patch('stripe.Webhook.construct_event')
    def test_invoice_paid_updates_period(self, mock_construct):
        """invoice.paid should update subscription period."""
        subscription = SubscriptionFactory(stripe_subscription_id='sub_test123')

        event_data = {
            'subscription': 'sub_test123',
            'period_start': 1706745600,
            'period_end': 1709424000
        }
        mock_construct.return_value = self.create_webhook_event(
            'invoice.paid', event_data
        )

        response = self.client.post(
            '/billing/webhook/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_STRIPE_SIGNATURE='test_sig'
        )

        assert response.status_code == 200
        subscription.refresh_from_db()
        # Period should be updated

    @patch('stripe.Webhook.construct_event')
    def test_payment_failed_updates_status(self, mock_construct):
        """invoice.payment_failed should update subscription status."""
        subscription = SubscriptionFactory(
            stripe_subscription_id='sub_test123',
            status='active'
        )

        event_data = {
            'subscription': 'sub_test123'
        }
        mock_construct.return_value = self.create_webhook_event(
            'invoice.payment_failed', event_data
        )

        response = self.client.post(
            '/billing/webhook/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_STRIPE_SIGNATURE='test_sig'
        )

        assert response.status_code == 200
        subscription.refresh_from_db()
        assert subscription.status == 'past_due'

    @patch('stripe.Webhook.construct_event')
    def test_subscription_deleted_cancels(self, mock_construct):
        """customer.subscription.deleted should cancel subscription."""
        subscription = SubscriptionFactory(
            stripe_subscription_id='sub_test123',
            status='active'
        )

        event_data = {
            'id': 'sub_test123'
        }
        mock_construct.return_value = self.create_webhook_event(
            'customer.subscription.deleted', event_data
        )

        response = self.client.post(
            '/billing/webhook/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_STRIPE_SIGNATURE='test_sig'
        )

        assert response.status_code == 200
        subscription.refresh_from_db()
        assert subscription.status == 'canceled'

    @patch('stripe.Webhook.construct_event')
    def test_invalid_signature_rejected(self, mock_construct):
        """Invalid webhook signature should be rejected."""
        mock_construct.side_effect = Exception("Invalid signature")

        response = self.client.post(
            '/billing/webhook/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_STRIPE_SIGNATURE='invalid'
        )

        assert response.status_code == 400
```

### 7.3 Grace Period Tests

```python
# apps/billing/tests/test_grace_period.py
import pytest
from unittest.mock import patch
from django.utils import timezone
from datetime import timedelta
from freezegun import freeze_time
from apps.billing.services import enter_grace_period, check_can_respond
from apps.billing.tasks import check_grace_period_expired
from apps.billing.tests.factories import (
    PlanFactory, SubscriptionFactory, UsageRecordFactory
)
from apps.agents.tests.factories import AgentInstanceFactory
from apps.customers.tests.factories import CustomerFactory

@pytest.mark.django_db
class TestGracePeriod:
    """Test grace period functionality."""

    def test_enter_grace_period(self):
        """Should set grace_period_ends_at on customer."""
        customer = CustomerFactory()

        with patch('apps.billing.services.BillingSettings.get') as mock_setting:
            mock_setting.return_value = 24  # 24 hours

            enter_grace_period(str(customer.id))

        customer.refresh_from_db()
        assert customer.grace_period_ends_at is not None

        # Should be ~24 hours from now
        expected = timezone.now() + timedelta(hours=24)
        diff = abs((customer.grace_period_ends_at - expected).total_seconds())
        assert diff < 60  # Within 1 minute

    @patch('apps.billing.tasks.send_grace_period_expired_email')
    @patch('apps.billing.tasks.disable_customer_agents')
    def test_grace_period_expiry_task(self, mock_disable, mock_email):
        """Expired grace periods should disable agents."""
        # Customer with expired grace period
        customer = CustomerFactory(
            grace_period_ends_at=timezone.now() - timedelta(hours=1)
        )
        AgentInstanceFactory(customer=customer, is_active=True)

        check_grace_period_expired()

        mock_disable.assert_called()
        mock_email.assert_called()

    def test_grace_period_allows_response(self):
        """Should allow responses during grace period."""
        plan = PlanFactory(limits={"messages": 100})
        customer = CustomerFactory(
            grace_period_ends_at=timezone.now() + timedelta(hours=12)
        )
        agent = AgentInstanceFactory(customer=customer)
        SubscriptionFactory(customer=customer, plan=plan)
        UsageRecordFactory(customer=customer, agent_instance=agent, messages=150)

        result = check_can_respond(str(agent.id))

        assert result['allowed'] is True
        assert result['in_grace_period'] is True

    def test_expired_grace_period_blocks(self):
        """Should block when grace period expired."""
        plan = PlanFactory(limits={"messages": 100})
        customer = CustomerFactory(
            grace_period_ends_at=timezone.now() - timedelta(hours=1)
        )
        agent = AgentInstanceFactory(customer=customer)
        SubscriptionFactory(customer=customer, plan=plan)
        UsageRecordFactory(customer=customer, agent_instance=agent, messages=150)

        result = check_can_respond(str(agent.id))

        assert result['allowed'] is False


@pytest.mark.django_db
class TestTrialSystem:
    """Test trial subscription system."""

    def test_start_trial(self):
        """Should create trial subscription."""
        from apps.billing.services import start_trial

        customer = CustomerFactory()
        trial_plan = PlanFactory(slug='trial')

        with patch('apps.billing.services.BillingSettings.get') as mock_setting:
            mock_setting.side_effect = lambda key, default=None: {
                'trial_plan_slug': 'trial',
                'trial_duration_days': 14
            }.get(key, default)

            start_trial(str(customer.id))

        subscription = Subscription.objects.get(customer=customer)
        assert subscription.status == 'trialing'
        assert subscription.plan == trial_plan

        # Should end in ~14 days
        expected_end = timezone.now() + timedelta(days=14)
        diff = abs((subscription.trial_ends_at - expected_end).total_seconds())
        assert diff < 60

    @freeze_time("2025-01-15 12:00:00")
    def test_trial_expiry(self):
        """Expired trial should not allow responses."""
        plan = PlanFactory(slug='trial', limits={"messages": 50})
        customer = CustomerFactory()
        agent = AgentInstanceFactory(customer=customer)
        SubscriptionFactory(
            customer=customer,
            plan=plan,
            status='trialing',
            trial_ends_at=timezone.now() - timedelta(days=1)  # Expired
        )

        result = check_can_respond(str(agent.id))

        assert result['allowed'] is False
        assert 'trial' in result['reason'].lower()
```

---

## 8. Integration Tests

### 8.1 End-to-End Agent Creation

```python
# tests/integration/test_agent_creation_e2e.py
import pytest
from django.test import Client
from django.urls import reverse
from apps.customers.tests.factories import CustomerFactory, CustomerUserFactory
from apps.agents.tests.factories import AgentTypeFactory
from apps.billing.tests.factories import PlanFactory, SubscriptionFactory
from apps.agents.models import AgentInstance
from apps.knowledge.models import KnowledgeBase

@pytest.mark.django_db
class TestAgentCreationE2E:
    """End-to-end test for agent creation flow."""

    def setup_method(self):
        self.client = Client()
        self.customer = CustomerFactory()
        self.user = CustomerUserFactory(customer=self.customer)
        self.client.force_login(self.user)

        # Setup billing
        plan = PlanFactory(limits={"agents": 5, "knowledge_bases": 3})
        SubscriptionFactory(customer=self.customer, plan=plan)

    def test_full_agent_creation_with_kb(self):
        """Test creating agent with knowledge base through wizard."""
        agent_type = AgentTypeFactory(
            onboarding_schema={
                "steps": [
                    {
                        "id": "basics",
                        "title": "Basic Info",
                        "fields": [
                            {"name": "agent_name", "type": "text", "required": True},
                            {"name": "greeting", "type": "textarea", "required": False}
                        ]
                    }
                ],
                "knowledge_base": {
                    "enabled": True,
                    "required": False,
                    "allow_create_new": True
                }
            }
        )

        # Step 1: Start wizard
        response = self.client.get(
            reverse('agents:onboarding', args=[agent_type.slug])
        )
        assert response.status_code == 200

        # Step 2: Submit basics
        response = self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'basics']),
            data={
                'agent_name': 'Support Bot',
                'greeting': 'Hello! How can I help?'
            },
            follow=True
        )
        assert response.status_code == 200

        # Step 3: Create KB (if prompted)
        response = self.client.post(
            reverse('agents:onboarding_step', args=[agent_type.slug, 'knowledge_base']),
            data={
                'create_new': True,
                'kb_name': 'Support Docs'
            },
            follow=True
        )

        # Verify agent created
        agent = AgentInstance.objects.filter(
            customer=self.customer,
            name='Support Bot'
        ).first()

        assert agent is not None
        assert agent.configuration.get('greeting') == 'Hello! How can I help?'
        assert agent.api_key_prefix.startswith('efk_')

        # Verify KB created and linked
        assert agent.knowledge_base is not None
        assert agent.knowledge_base.name == 'Support Docs'
```

### 8.2 End-to-End Billing Cycle

```python
# tests/integration/test_billing_cycle_e2e.py
import pytest
from unittest.mock import patch, MagicMock
from django.test import Client
from django.utils import timezone
from datetime import timedelta
from apps.customers.tests.factories import CustomerFactory, CustomerUserFactory
from apps.agents.tests.factories import AgentInstanceFactory
from apps.billing.tests.factories import PlanFactory, SubscriptionFactory
from apps.billing.models import UsageRecord
from rest_framework.test import APIClient

@pytest.mark.django_db
class TestBillingCycleE2E:
    """End-to-end test for billing cycle."""

    def setup_method(self):
        self.api_client = APIClient()
        self.web_client = Client()

        self.customer = CustomerFactory()
        self.user = CustomerUserFactory(customer=self.customer)
        self.web_client.force_login(self.user)

        self.plan = PlanFactory(limits={"messages": 100, "tokens": 10000})
        SubscriptionFactory(customer=self.customer, plan=self.plan)

        self.agent = AgentInstanceFactory(customer=self.customer)
        self.headers = {
            'HTTP_AUTHORIZATION': 'Bearer test-service-secret-32chars-min',
            'HTTP_X_AGENT_INSTANCE_ID': str(self.agent.id)
        }

    def test_usage_accumulation_and_limit(self):
        """Test usage accumulates and triggers limit."""
        import uuid

        # Report usage up to limit
        for i in range(100):
            self.api_client.post(
                '/api/internal/usage/batch',
                {
                    "reports": [{
                        "agent_instance_id": str(self.agent.id),
                        "timestamp": timezone.now().isoformat(),
                        "metrics": {"messages": 1, "input_tokens": 50, "output_tokens": 50},
                        "request_id": str(uuid.uuid4())
                    }]
                },
                format='json',
                **self.headers
            )

        # Check can-respond - should be at limit
        response = self.api_client.get(
            f'/api/internal/billing/can-respond/{self.agent.id}',
            **self.headers
        )

        data = response.json()
        # Should either deny or be in grace period
        if data['allowed']:
            assert data['in_grace_period'] is True
        else:
            assert 'limit' in data['reason'].lower()

    @patch('stripe.checkout.Session.create')
    def test_upgrade_plan_flow(self, mock_checkout):
        """Test upgrading plan via Stripe."""
        mock_checkout.return_value = MagicMock(url='https://checkout.stripe.com/upgrade')

        higher_plan = PlanFactory(
            name='Pro',
            slug='pro',
            limits={"messages": 1000}
        )

        response = self.web_client.post(
            '/billing/checkout/',
            data={'plan': 'pro'},
            follow=False
        )

        assert response.status_code == 302
        mock_checkout.assert_called_once()
```

---

## 9. Test Commands

### 9.1 Running Tests

```bash
# Run all tests
cd backend
pytest

# Run with coverage
pytest --cov=apps --cov-report=html

# Run specific test file
pytest apps/billing/tests/test_webhooks.py

# Run specific test class
pytest apps/billing/tests/test_webhooks.py::TestStripeWebhooks

# Run specific test
pytest apps/billing/tests/test_webhooks.py::TestStripeWebhooks::test_checkout_completed

# Run tests matching pattern
pytest -k "grace_period"

# Run with verbose output
pytest -v

# Run integration tests only
pytest tests/integration/

# Run fast (no slow tests)
pytest -m "not slow"
```

### 9.2 CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: echoforge_hub_test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        ports:
          - 5435:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7
        ports:
          - 6382:6379

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          cd backend
          pip install -r requirements/testing.txt

      - name: Install pgvector
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-15-pgvector

      - name: Run tests
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5435/echoforge_hub_test
          REDIS_URL: redis://localhost:6382
        run: |
          cd backend
          pytest --cov=apps --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: backend/coverage.xml
```

---

## 10. Security Tests

### 10.1 OAuth Token Encryption Tests

```python
# apps/integrations/tests/test_encryption.py
import pytest
from django.conf import settings
from apps.integrations.models import Integration
from apps.integrations.tests.factories import IntegrationFactory
from apps.core.encryption import encrypt_value, decrypt_value, EncryptedTextField

@pytest.mark.django_db
class TestTokenEncryption:
    """Test OAuth token encryption at rest."""

    def test_encryption_key_configured(self):
        """ENCRYPTION_KEY must be configured."""
        assert settings.ENCRYPTION_KEY, "ENCRYPTION_KEY not configured - SECURITY RISK"
        assert len(settings.ENCRYPTION_KEY) >= 32, "ENCRYPTION_KEY too short"

    def test_access_token_encrypted_in_database(self):
        """Access tokens must be encrypted when stored."""
        integration = IntegrationFactory(
            access_token="test_plaintext_token_12345"
        )

        # Query raw database value
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT access_token FROM integrations_integration WHERE id = %s",
                [str(integration.id)]
            )
            raw_value = cursor.fetchone()[0]

        # Raw value should NOT be plaintext
        assert raw_value != "test_plaintext_token_12345", \
            "CRITICAL: Access token stored in PLAINTEXT!"

        # Raw value should start with Fernet prefix
        assert raw_value.startswith("gAAAAA"), \
            "Access token not properly encrypted (missing Fernet prefix)"

        # But model should decrypt it
        integration.refresh_from_db()
        assert integration.access_token == "test_plaintext_token_12345"

    def test_refresh_token_encrypted_in_database(self):
        """Refresh tokens must be encrypted when stored."""
        integration = IntegrationFactory(
            refresh_token="test_refresh_token_67890"
        )

        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT refresh_token FROM integrations_integration WHERE id = %s",
                [str(integration.id)]
            )
            raw_value = cursor.fetchone()[0]

        assert raw_value != "test_refresh_token_67890", \
            "CRITICAL: Refresh token stored in PLAINTEXT!"
        assert raw_value.startswith("gAAAAA"), \
            "Refresh token not properly encrypted"

    def test_encrypt_decrypt_roundtrip(self):
        """Encrypt/decrypt should roundtrip correctly."""
        original = "sensitive_oauth_token_abc123"
        encrypted = encrypt_value(original)
        decrypted = decrypt_value(encrypted)

        assert encrypted != original, "Value not encrypted"
        assert decrypted == original, "Decrypt failed"

    def test_different_tokens_different_ciphertext(self):
        """Same plaintext should produce different ciphertext (IV)."""
        token = "same_token_value"
        encrypted1 = encrypt_value(token)
        encrypted2 = encrypt_value(token)

        # Fernet uses random IV, so ciphertexts should differ
        assert encrypted1 != encrypted2, \
            "Same ciphertext for same plaintext - IV not random!"

    def test_empty_token_handling(self):
        """Empty tokens should be handled safely."""
        integration = IntegrationFactory(
            access_token="",
            refresh_token=""
        )

        integration.refresh_from_db()
        assert integration.access_token == ""
        assert integration.refresh_token == ""

    def test_null_token_handling(self):
        """Null tokens should be handled safely."""
        integration = IntegrationFactory()
        integration.access_token = None
        integration.save()

        integration.refresh_from_db()
        # Should not raise, should return None or empty

    def test_invalid_ciphertext_handling(self):
        """Invalid ciphertext should not crash."""
        decrypted = decrypt_value("invalid_not_fernet_data")
        assert decrypted == "", "Invalid ciphertext should return empty string"

    def test_tokens_excluded_from_admin(self):
        """Tokens should not be visible in admin."""
        from apps.integrations.admin import IntegrationAdmin

        assert 'access_token' in IntegrationAdmin.exclude, \
            "access_token visible in admin - SECURITY RISK"
        assert 'refresh_token' in IntegrationAdmin.exclude, \
            "refresh_token visible in admin - SECURITY RISK"


@pytest.mark.django_db
class TestCredentialSecurity:
    """Test credential handling security."""

    def test_tokens_not_in_str_representation(self):
        """Tokens should not appear in __str__ or __repr__."""
        integration = IntegrationFactory(
            access_token="secret_token_xyz",
            refresh_token="secret_refresh_abc"
        )

        str_repr = str(integration)
        repr_repr = repr(integration)

        assert "secret_token_xyz" not in str_repr
        assert "secret_refresh_abc" not in str_repr
        assert "secret_token_xyz" not in repr_repr
        assert "secret_refresh_abc" not in repr_repr

    def test_tokens_not_in_serialized_output(self):
        """Tokens should not appear in JSON serialization."""
        from django.core import serializers

        integration = IntegrationFactory(
            access_token="secret_in_json",
            refresh_token="refresh_in_json"
        )

        # Default Django serialization
        serialized = serializers.serialize('json', [integration])

        # Tokens should be encrypted in serialized output
        assert "secret_in_json" not in serialized
        assert "refresh_in_json" not in serialized

    def test_internal_api_decrypts_for_agent(self):
        """Internal API should return decrypted tokens to Agent."""
        # This is intentional - Agent needs plaintext to call external APIs
        # But should only happen over secure internal network
        integration = IntegrationFactory(
            access_token="decrypted_for_agent"
        )

        # Simulate internal API credential fetch
        from apps.integrations.oauth import get_integration_credentials
        creds = get_integration_credentials(integration)

        assert creds is not None
        assert creds['access_token'] == "decrypted_for_agent"
```

### 10.2 Integration Factory for Security Tests

```python
# apps/integrations/tests/factories.py (addition)

class IntegrationFactory(DjangoModelFactory):
    class Meta:
        model = Integration

    customer = factory.SubFactory(CustomerFactory)
    provider = factory.SubFactory(IntegrationProviderFactory)
    account_id = factory.Sequence(lambda n: f'account_{n}')
    account_name = factory.Faker('company')
    status = 'active'
    # Note: access_token and refresh_token use EncryptedTextField
    # so they will be auto-encrypted on save
```

---

## 11. Acceptance Criteria

### 11.1 Internal API
- [ ] All authentication tests pass
- [ ] Config endpoint returns correct structure
- [ ] API key validation works
- [ ] Can-respond considers all billing factors
- [ ] Usage batch deduplicates correctly

### 11.2 Knowledge Base
- [ ] Document processing creates chunks
- [ ] Chunking parameters are correct (500/50)
- [ ] Vector search returns relevant results
- [ ] Only indexed documents are searchable

### 11.3 Onboarding Wizard
- [ ] Wizard renders from schema
- [ ] Validation enforces required fields
- [ ] KB step respects schema config
- [ ] Agent created on completion

### 11.4 Stripe Billing
- [ ] Checkout creates session
- [ ] All webhooks handled
- [ ] Grace period triggers correctly
- [ ] Trial system works

### 11.5 Security (CRITICAL)
- [ ] ENCRYPTION_KEY configured in environment
- [ ] OAuth tokens encrypted at rest in database
- [ ] Tokens not visible in Django admin
- [ ] Tokens not exposed in logs or error messages
- [ ] Tokens not in model __str__ representation
- [ ] Invalid ciphertext handled gracefully

### 11.6 Coverage
- [ ] Overall coverage ≥ 80%
- [ ] Critical paths (billing, auth, encryption) ≥ 90%
- [ ] No untested error handlers

---

*Testing Specification v1.1 - EchoForge Hub*
