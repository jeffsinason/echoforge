---
title: EchoForge Hub Billing System
version: "1.1"
status: testing
project: EchoForge Hub
created: 2025-12-29
updated: 2025-12-31
---

# 1. Executive Summary

This specification defines a comprehensive billing system for EchoForge Hub, replacing the basic billing models in the original Hub spec. The system supports flat-rate subscription plans with usage limits, premium agent add-on charges, and an "Extra Usage Balance" (prepaid wallet) for overage handling. It includes both customer-facing billing management and an internal admin interface for EchoForgeX staff.

**Key Features:**
- Subscription plans with defined limits (agents, messages, tokens)
- Premium agent types with additional monthly charges (prorated)
- Extra Usage Balance (single wallet) with auto-recharge
- Hierarchical overage rates (customer → plan → global)
- Customer portal for usage visibility and balance management
- Internal admin for full billing control

**Architecture Decision:** Billing is implemented within Hub (`apps/billing/`) with clean service boundaries, allowing future extraction to a standalone service if multi-product billing is needed.

---

# 2. Current System State

## 2.1 Existing Billing Models (from Hub Spec)

The original Hub specification defines basic billing:

| Model | Purpose | Limitation |
|-------|---------|------------|
| Subscription | Links customer to Stripe, stores plan as string | No Plan model, no pricing |
| UsageRecord | Tracks usage quantities | No pricing/charging logic |
| PlanLimit | Defines limits per plan slug | Static, no plan metadata |

## 2.2 Existing AgentType Field

```python
class AgentType(models.Model):
    pricing_tier = CharField(20)  # "starter", "pro", "enterprise"
```

This gates agent access by plan but doesn't support premium pricing.

## 2.3 Gaps Addressed by This Spec

- No Plan model with pricing
- No premium agent charges
- No overage handling mechanism
- No prepaid balance/wallet
- No customer-facing billing portal
- No internal admin tooling
- No invoice/payment history

---

# 3. Data Model

## 3.1 Plan Management

### Plan

Defines a subscription plan with pricing and limits.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| slug | SlugField | Unique identifier ("starter", "pro", "enterprise") |
| name | CharField(100) | Display name ("Starter", "Professional") |
| description | TextField | Marketing description |
| monthly_price_cents | IntegerField | Monthly price in cents (e.g., 4900 = $49.00) |
| annual_price_cents | IntegerField | Annual price in cents (discount applied) |
| stripe_monthly_price_id | CharField(100) | Stripe Price ID for monthly billing |
| stripe_annual_price_id | CharField(100) | Stripe Price ID for annual billing |
| max_agents | IntegerField | Max agent instances (-1 = unlimited) |
| max_messages_per_month | IntegerField | Message limit (-1 = unlimited) |
| max_tokens_per_month | BigIntegerField | Token limit (-1 = unlimited) |
| max_knowledge_docs | IntegerField | Knowledge base document limit |
| max_integrations | IntegerField | Integration connection limit |
| max_team_members | IntegerField | Team member limit (-1 = unlimited) |
| features | JSONField | Feature flags (e.g., {"priority_support": true}) |
| is_public | BooleanField | Visible in public pricing page |
| is_active | BooleanField | Available for new subscriptions |
| display_order | IntegerField | Sort order on pricing page |
| created_at | DateTimeField | Creation timestamp |
| updated_at | DateTimeField | Last update |

**Default Plans:**

| Plan | Monthly | Annual | Agents | Messages | Tokens | Docs | Integrations |
|------|---------|--------|--------|----------|--------|------|--------------|
| starter | $0 | $0 | 1 | 1,000 | 100K | 10 | 2 |
| pro | $49 | $490 | 5 | 10,000 | 1M | 100 | 10 |
| business | $149 | $1,490 | 15 | 50,000 | 5M | 500 | 25 |
| enterprise | Custom | Custom | -1 | -1 | -1 | -1 | -1 |

### PlanAgentTypeAccess

Defines which agent types are included in each plan (non-premium access).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| plan | FK(Plan) | Plan reference |
| agent_type | FK(AgentType) | Agent type reference |

*Agent types NOT in this table for a plan require premium pricing.*

---

## 3.2 Premium Agent Pricing

### AgentTypePricing

Defines premium pricing for agent types (when not included in plan).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| agent_type | FK(AgentType) | Agent type |
| monthly_price_cents | IntegerField | Additional monthly cost in cents |
| description | CharField(200) | Pricing description ("Advanced AI capabilities") |
| stripe_price_id | CharField(100) | Stripe Price ID for this add-on |
| is_active | BooleanField | Currently available |

### PremiumAgentSubscription

Tracks a customer's active premium agent subscriptions.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Customer |
| agent_instance | FK(AgentInstance) | The provisioned agent |
| agent_type_pricing | FK(AgentTypePricing) | Pricing applied |
| monthly_price_cents | IntegerField | Locked-in price at subscription time |
| started_at | DateTimeField | When premium billing started |
| ended_at | DateTimeField | When cancelled (null if active) |
| prorated_start_amount_cents | IntegerField | Initial prorated charge |
| stripe_subscription_item_id | CharField(100) | Stripe subscription item ID |
| status | CharField(20) | "active", "cancelled", "pending_cancellation" |

---

## 3.3 Subscription (Enhanced)

### Subscription

Enhanced from original spec to reference Plan model.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | OneToOne(Customer) | Owner |
| plan | FK(Plan) | Current plan |
| billing_interval | CharField(20) | "monthly" or "annual" |
| stripe_customer_id | CharField(100) | Stripe customer ID |
| stripe_subscription_id | CharField(100) | Stripe subscription ID |
| status | CharField(20) | "active", "past_due", "canceled", "trialing" |
| trial_ends_at | DateTimeField | Trial end date (null if no trial) |
| current_period_start | DateTimeField | Billing period start |
| current_period_end | DateTimeField | Billing period end |
| cancel_at_period_end | BooleanField | Scheduled cancellation |
| canceled_at | DateTimeField | When cancellation requested |
| created_at | DateTimeField | Subscription creation |
| updated_at | DateTimeField | Last update |

---

## 3.4 Extra Usage Balance (Wallet)

### CustomerBalance

The customer's prepaid balance for overage charges.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | OneToOne(Customer) | Owner |
| balance_cents | IntegerField | Current balance in cents |
| lifetime_deposits_cents | BigIntegerField | Total deposits ever made |
| lifetime_usage_cents | BigIntegerField | Total usage charges ever |
| auto_recharge_enabled | BooleanField | Auto-recharge on |
| auto_recharge_threshold_cents | IntegerField | Trigger threshold (e.g., 500 = $5) |
| auto_recharge_amount_cents | IntegerField | Amount to add (e.g., 2500 = $25) |
| stripe_payment_method_id | CharField(100) | Default payment method for recharge |
| last_recharge_at | DateTimeField | Last successful recharge |
| created_at | DateTimeField | Creation timestamp |
| updated_at | DateTimeField | Last update |

**Business Rules:**
- Minimum deposit: 1000 cents ($10.00)
- Auto-recharge minimum amount: 1000 cents ($10.00)
- Balance can go negative (for grace period edge cases), but usage stops at $0

### BalanceTransaction

Ledger of all balance changes.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| transaction_type | CharField(30) | See types below |
| amount_cents | IntegerField | Amount (positive=credit, negative=debit) |
| balance_after_cents | IntegerField | Balance after this transaction |
| description | CharField(500) | Human-readable description |
| reference_type | CharField(50) | Related object type (e.g., "usage_charge") |
| reference_id | UUID | Related object ID |
| stripe_payment_intent_id | CharField(100) | Stripe PI (for deposits) |
| metadata | JSONField | Additional context |
| created_by | FK(User) | User who initiated (null for system) |
| created_at | DateTimeField | Transaction timestamp |

**Transaction Types:**

| Type | Description | Amount Sign |
|------|-------------|-------------|
| deposit | Customer added funds | + |
| auto_recharge | Automatic recharge triggered | + |
| usage_charge | Overage usage deducted | - |
| premium_agent_credit | Prorated refund for cancelled premium agent | + |
| admin_credit | Manual credit by EchoForgeX admin | + |
| admin_debit | Manual debit by EchoForgeX admin | - |
| refund | Stripe refund processed | + |
| chargeback | Disputed charge | - |

---

## 3.5 Usage Tracking & Rating

### OverageRate

Defines per-unit pricing for usage beyond plan limits.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| scope_type | CharField(20) | "global", "plan", "customer" |
| scope_id | UUID | Plan ID or Customer ID (null for global) |
| metric | CharField(50) | "messages", "tokens", "api_calls" |
| unit_price_cents | IntegerField | Price per unit in cents |
| unit_quantity | IntegerField | Units per price (e.g., 1000 for "per 1K tokens") |
| effective_from | DateTimeField | When rate takes effect |
| effective_until | DateTimeField | When rate expires (null = indefinite) |
| created_at | DateTimeField | Creation timestamp |

**Rate Lookup Hierarchy:**
1. Customer-specific rate (scope_type="customer", scope_id=customer.id)
2. Plan-specific rate (scope_type="plan", scope_id=plan.id)
3. Global rate (scope_type="global", scope_id=null)

**Default Global Rates:**

| Metric | Unit Price | Unit Quantity | Effective Rate |
|--------|------------|---------------|----------------|
| messages | 1 cent | 1 | $0.01/message |
| tokens | 1 cent | 1000 | $0.01/1K tokens |

### UsageRecord (Enhanced)

Enhanced from original spec to support charging.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| agent_instance | FK(AgentInstance) | Agent (optional, for per-agent tracking) |
| metric | CharField(50) | "messages", "tokens", "api_calls" |
| quantity | BigIntegerField | Usage count |
| period_start | DateField | Usage period start |
| period_end | DateField | Usage period end |
| within_plan_limit | BooleanField | Was this within plan limits? |
| created_at | DateTimeField | Record creation |
| updated_at | DateTimeField | Last update |

### UsageCharge

Records when usage exceeds limits and is charged to balance.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| agent_instance | FK(AgentInstance) | Agent that incurred usage (optional) |
| metric | CharField(50) | "messages", "tokens" |
| quantity | BigIntegerField | Overage quantity charged |
| overage_rate | FK(OverageRate) | Rate applied |
| unit_price_cents | IntegerField | Locked-in unit price |
| unit_quantity | IntegerField | Locked-in unit quantity |
| total_cents | IntegerField | Total charge |
| balance_transaction | FK(BalanceTransaction) | Ledger entry |
| period_date | DateField | Usage date |
| created_at | DateTimeField | Charge timestamp |

---

## 3.6 Payment History

### PaymentRecord

Tracks all payments (synced from Stripe).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| customer | FK(Customer) | Owner |
| payment_type | CharField(30) | "subscription", "deposit", "premium_agent" |
| amount_cents | IntegerField | Payment amount |
| currency | CharField(3) | Currency code (USD) |
| status | CharField(20) | "succeeded", "failed", "refunded", "disputed" |
| stripe_payment_intent_id | CharField(100) | Stripe Payment Intent ID |
| stripe_invoice_id | CharField(100) | Stripe Invoice ID (if applicable) |
| description | CharField(500) | Payment description |
| failure_reason | TextField | Failure details (if failed) |
| refunded_amount_cents | IntegerField | Amount refunded (if any) |
| metadata | JSONField | Additional context |
| paid_at | DateTimeField | When payment succeeded |
| created_at | DateTimeField | Record creation |

---

## 3.7 System Configuration

### BillingSettings

Global billing configuration stored in database for runtime configurability.

| Field | Type | Description |
|-------|------|-------------|
| key | CharField(100) | Unique setting key |
| value | JSONField | Setting value (supports any type) |
| description | TextField | Human-readable description |
| updated_at | DateTimeField | Last modification |
| updated_by | FK(User) | Admin who changed it |

**Default Settings:**

| Key | Default Value | Description |
|-----|---------------|-------------|
| `grace_period_hours` | 24 | Hours before service paused after $0 balance |
| `min_balance_deposit_cents` | 1000 | Minimum deposit amount ($10) |
| `auto_recharge_min_cents` | 1000 | Minimum auto-recharge amount ($10) |
| `trial_enabled` | true | Whether trials are offered |
| `trial_plan_slug` | "pro" | Which plan for trial period |
| `trial_duration_days` | 14 | Trial length in days |
| `default_plan_slug` | "starter" | Plan after trial expires |
| `low_balance_warning_cents` | 500 | Warn when balance below ($5) |

**Helper Function:**

```python
def get_billing_setting(key: str, default=None):
    """Get a billing setting with fallback to default."""
    try:
        setting = BillingSettings.objects.get(key=key)
        return setting.value
    except BillingSettings.DoesNotExist:
        return default
```

### Trial Configuration

Trials allow new customers to experience a premium plan before committing.

**Trial Flow:**
```
Customer signs up
  → Assigned trial plan (configurable: default "pro")
  → Trial duration starts (configurable: default 14 days)
  → Trial expiry warnings: 7 days, 3 days, 1 day before
  → Trial expires:
      → If upgraded: continue on chosen plan
      → If not: auto-downgrade to Starter (or configured default)
```

**Subscription Model Addition:**

```python
class Subscription(models.Model):
    # ... existing fields ...
    trial_ends_at = DateTimeField(null=True, blank=True)
    trial_converted = BooleanField(default=False)  # Did they upgrade before trial ended?
```

**Trial Business Rules:**
- Trial available once per customer
- Customer can upgrade anytime during trial
- Downgrade during trial = immediate switch to Starter
- Trial days remaining shown in dashboard
- Enterprise plan: no trial (contact sales)

---

# 4. Feature Requirements

## 4.1 Plan Management

### Plan Selection (Customer-Facing)

**Flow:**
1. Customer visits Billing → Subscription
2. Views current plan and available upgrades/downgrades
3. Selects new plan
4. If upgrade: immediate, prorated charge for remainder of period
5. If downgrade: takes effect at next billing period
6. Stripe subscription updated
7. Confirmation shown

**Business Rules:**
- Upgrades: Immediate, prorated
- Downgrades: End of current period
- Enterprise: Contact sales (no self-service)
- Cannot downgrade if current usage exceeds new plan limits (agents, etc.)

### Plan Administration (Internal)

**Capabilities:**
- Create/edit plans (pricing, limits, features)
- Activate/deactivate plans
- Manage Stripe Price IDs
- View customers per plan
- Bulk migrate customers between plans

---

## 4.2 Premium Agent Pricing

### Provisioning Premium Agent

**Flow:**
1. Customer selects agent type in catalog
2. System checks if agent type is included in customer's plan
3. If NOT included (premium):
   - Show premium pricing modal
   - "This agent requires an additional $X/month"
   - Show prorated amount for current period
4. Customer confirms
5. System:
   - Creates PremiumAgentSubscription
   - Charges prorated amount to payment method (or balance)
   - Adds subscription item to Stripe subscription
   - Proceeds with normal onboarding

**Proration Calculation:**
```python
def calculate_prorated_charge(monthly_price_cents: int, subscription: Subscription) -> int:
    """Calculate prorated charge for premium agent added mid-cycle."""
    now = timezone.now()
    period_end = subscription.current_period_end
    period_start = subscription.current_period_start

    total_days = (period_end - period_start).days
    remaining_days = (period_end - now).days

    if remaining_days <= 0:
        return 0  # At period end, full charge on next cycle

    prorated = (monthly_price_cents * remaining_days) // total_days
    return prorated
```

### Cancelling Premium Agent

**Flow:**
1. Customer deletes/deactivates agent instance
2. If agent has PremiumAgentSubscription:
   - Calculate prorated credit for remaining period
   - Create BalanceTransaction (premium_agent_credit)
   - Add credit to CustomerBalance
   - Cancel Stripe subscription item
   - Mark PremiumAgentSubscription as cancelled

**Proration Credit Calculation:**
```python
def calculate_prorated_credit(premium_sub: PremiumAgentSubscription, subscription: Subscription) -> int:
    """Calculate prorated credit for cancelled premium agent."""
    now = timezone.now()
    period_end = subscription.current_period_end
    period_start = subscription.current_period_start

    total_days = (period_end - period_start).days
    remaining_days = (period_end - now).days

    if remaining_days <= 0:
        return 0

    credit = (premium_sub.monthly_price_cents * remaining_days) // total_days
    return credit
```

---

## 4.3 Extra Usage Balance System

### Balance Deposits (Customer-Facing)

**Flow:**
1. Customer visits Billing → Extra Usage Balance
2. Views current balance
3. Clicks "Add Funds"
4. Selects amount ($10, $25, $50, $100, or custom)
5. Confirms payment method
6. Stripe charges payment method
7. BalanceTransaction created
8. Balance updated

**Business Rules:**
- Minimum deposit: $10.00
- Maximum single deposit: $1,000.00
- Payment method: Saved card or Stripe Checkout

### Auto-Recharge Configuration

**Flow:**
1. Customer visits Billing → Extra Usage Balance → Settings
2. Toggles auto-recharge on/off
3. Configures:
   - Threshold: "When balance falls below $X" (min $5)
   - Amount: "Add $Y" (min $10)
4. Saves configuration

**Auto-Recharge Trigger:**
```python
def check_and_recharge_balance(customer: Customer) -> Optional[BalanceTransaction]:
    """Check if auto-recharge should trigger and execute if so."""
    balance = customer.balance

    if not balance.auto_recharge_enabled:
        return None

    if balance.balance_cents > balance.auto_recharge_threshold_cents:
        return None

    # Attempt charge
    try:
        payment_intent = stripe.PaymentIntent.create(
            amount=balance.auto_recharge_amount_cents,
            currency='usd',
            customer=customer.subscription.stripe_customer_id,
            payment_method=balance.stripe_payment_method_id,
            confirm=True,
            off_session=True,
        )

        if payment_intent.status == 'succeeded':
            transaction = BalanceTransaction.objects.create(
                customer=customer,
                transaction_type='auto_recharge',
                amount_cents=balance.auto_recharge_amount_cents,
                balance_after_cents=balance.balance_cents + balance.auto_recharge_amount_cents,
                description=f"Auto-recharge triggered (threshold: ${balance.auto_recharge_threshold_cents/100:.2f})",
                stripe_payment_intent_id=payment_intent.id,
            )

            balance.balance_cents += balance.auto_recharge_amount_cents
            balance.last_recharge_at = timezone.now()
            balance.save()

            return transaction

    except stripe.error.CardError as e:
        # Log failure, notify customer
        notify_auto_recharge_failed(customer, str(e))
        return None
```

### Usage Overage Charging

**Trigger:** Called after each usage increment that exceeds plan limits.

```python
class UsageChargeService:
    def record_usage_and_charge(
        self,
        customer: Customer,
        agent_instance: AgentInstance,
        metric: str,
        quantity: int
    ) -> tuple[UsageRecord, Optional[UsageCharge]]:
        """Record usage and charge to balance if over limit."""

        subscription = customer.subscription
        plan = subscription.plan

        # Get current period usage
        period_start = subscription.current_period_start.date()
        current_usage = UsageRecord.objects.filter(
            customer=customer,
            metric=metric,
            period_start=period_start,
        ).aggregate(total=Sum('quantity'))['total'] or 0

        # Get plan limit
        plan_limit = self.get_plan_limit(plan, metric)

        # Calculate how much of new usage is over limit
        usage_after = current_usage + quantity

        if plan_limit == -1:  # Unlimited
            overage = 0
        elif current_usage >= plan_limit:
            overage = quantity  # All new usage is overage
        elif usage_after > plan_limit:
            overage = usage_after - plan_limit  # Partial overage
        else:
            overage = 0

        # Record usage
        usage_record = UsageRecord.objects.create(
            customer=customer,
            agent_instance=agent_instance,
            metric=metric,
            quantity=quantity,
            period_start=period_start,
            period_end=subscription.current_period_end.date(),
            within_plan_limit=(overage == 0),
        )

        # Charge overage to balance
        usage_charge = None
        if overage > 0:
            usage_charge = self.charge_overage(customer, agent_instance, metric, overage)

        return usage_record, usage_charge

    def charge_overage(
        self,
        customer: Customer,
        agent_instance: AgentInstance,
        metric: str,
        quantity: int
    ) -> UsageCharge:
        """Charge overage usage to customer balance."""

        # Get applicable rate (hierarchical lookup)
        rate = self.get_overage_rate(customer, metric)

        # Calculate charge
        units = quantity / rate.unit_quantity
        total_cents = int(units * rate.unit_price_cents)

        if total_cents == 0:
            return None

        balance = customer.balance

        # Check if balance sufficient
        if balance.balance_cents < total_cents:
            # Check auto-recharge
            check_and_recharge_balance(customer)
            balance.refresh_from_db()

        # Create balance transaction
        new_balance = balance.balance_cents - total_cents

        transaction = BalanceTransaction.objects.create(
            customer=customer,
            transaction_type='usage_charge',
            amount_cents=-total_cents,
            balance_after_cents=new_balance,
            description=f"Overage: {quantity:,} {metric} @ ${rate.unit_price_cents/100:.4f}/{rate.unit_quantity}",
            metadata={
                'metric': metric,
                'quantity': quantity,
                'agent_instance_id': str(agent_instance.id) if agent_instance else None,
            }
        )

        # Update balance
        balance.balance_cents = new_balance
        balance.lifetime_usage_cents += total_cents
        balance.save()

        # Create usage charge record
        usage_charge = UsageCharge.objects.create(
            customer=customer,
            agent_instance=agent_instance,
            metric=metric,
            quantity=quantity,
            overage_rate=rate,
            unit_price_cents=rate.unit_price_cents,
            unit_quantity=rate.unit_quantity,
            total_cents=total_cents,
            balance_transaction=transaction,
            period_date=timezone.now().date(),
        )

        return usage_charge

    def get_overage_rate(self, customer: Customer, metric: str) -> OverageRate:
        """Get applicable overage rate using hierarchy."""
        now = timezone.now()

        # 1. Customer-specific rate
        rate = OverageRate.objects.filter(
            scope_type='customer',
            scope_id=customer.id,
            metric=metric,
            effective_from__lte=now,
        ).filter(
            Q(effective_until__isnull=True) | Q(effective_until__gt=now)
        ).first()

        if rate:
            return rate

        # 2. Plan-specific rate
        rate = OverageRate.objects.filter(
            scope_type='plan',
            scope_id=customer.subscription.plan.id,
            metric=metric,
            effective_from__lte=now,
        ).filter(
            Q(effective_until__isnull=True) | Q(effective_until__gt=now)
        ).first()

        if rate:
            return rate

        # 3. Global rate
        rate = OverageRate.objects.filter(
            scope_type='global',
            scope_id__isnull=True,
            metric=metric,
            effective_from__lte=now,
        ).filter(
            Q(effective_until__isnull=True) | Q(effective_until__gt=now)
        ).first()

        if not rate:
            raise ValueError(f"No overage rate configured for metric: {metric}")

        return rate
```

### Grace Period at Zero Balance

When a customer's Extra Usage Balance reaches $0, they enter a configurable grace period before service is paused. This gives customers time to add funds while maintaining service continuity.

**Grace Period Flow:**
```
Balance hits $0
  → Grace period starts (configurable, default 24 hours)
  → Warning email sent to customer
  → Warning banner in Hub dashboard
  → Agent continues responding with warning flag in metadata

Grace period expires + still $0
  → Hard stop - agent stops responding
  → "Service paused" email notification
  → Agent returns friendly "service paused" message
```

**Implementation:**

```python
class AgentAccessService:
    def can_agent_respond(self, agent_instance: AgentInstance) -> tuple[bool, str, dict]:
        """Check if agent can respond based on billing status.

        Returns: (allowed, reason, metadata)
        """
        customer = agent_instance.customer
        subscription = customer.subscription
        balance = customer.balance

        # Check subscription status
        if subscription.status not in ('active', 'trialing'):
            return False, "Subscription inactive", {}

        # Get current usage
        current_usage = self.get_current_period_usage(customer, 'messages')
        plan_limit = subscription.plan.max_messages_per_month

        # Within plan limits - allow
        if plan_limit == -1 or current_usage < plan_limit:
            return True, "OK", {}

        # Over limit - check balance
        if balance.balance_cents <= 0:
            # Attempt auto-recharge first
            result = check_and_recharge_balance(customer)
            if result:
                balance.refresh_from_db()
                return True, "OK (auto-recharged)", {}

            # Check grace period
            grace_status = self.check_grace_period(balance)

            if grace_status['in_grace_period']:
                return True, "In grace period", {
                    'in_grace_period': True,
                    'grace_period_ends_at': grace_status['ends_at'].isoformat(),
                    'warning_message': "Your usage limit has been reached. Add funds to avoid service interruption."
                }
            else:
                # Grace period expired
                return False, "Usage limit exceeded - service paused", {
                    'customer_message': "Service paused due to usage limits. Please add funds to continue."
                }

        # Has balance - allow (will be charged)
        return True, "OK (using extra balance)", {}

    def check_grace_period(self, balance: CustomerBalance) -> dict:
        """Check if customer is in grace period."""
        if balance.balance_cents > 0:
            return {'in_grace_period': False}

        grace_hours = get_billing_setting('grace_period_hours', default=24)

        if not balance.grace_period_started_at:
            # Start grace period now
            balance.grace_period_started_at = timezone.now()
            balance.save(update_fields=['grace_period_started_at'])

        grace_end = balance.grace_period_started_at + timedelta(hours=grace_hours)

        if timezone.now() < grace_end:
            return {
                'in_grace_period': True,
                'ends_at': grace_end,
                'hours_remaining': (grace_end - timezone.now()).total_seconds() / 3600
            }
        else:
            return {'in_grace_period': False, 'expired': True}
```

**CustomerBalance Model Addition:**

```python
class CustomerBalance(models.Model):
    # ... existing fields ...
    grace_period_started_at = models.DateTimeField(null=True, blank=True)
```

**Agent Runtime Integration:**

The Agent runtime calls Hub's internal API before responding:

```
GET /api/internal/agent/{agent_id}/can-respond

Response (success):
{
    "allowed": true,
    "reason": "OK",
    "in_grace_period": false
}

Response (grace period warning):
{
    "allowed": true,
    "reason": "In grace period",
    "in_grace_period": true,
    "grace_period_ends_at": "2025-01-16T10:30:00Z",
    "warning_message": "Your usage limit has been reached. Add funds to avoid service interruption."
}

Response (blocked):
{
    "allowed": false,
    "reason": "Usage limit exceeded - service paused",
    "customer_message": "Service paused due to usage limits. Please add funds to continue."
}
```

---

## 4.4 Customer Billing Portal

### Billing Dashboard

**URL:** `/billing/`

**Components:**
1. **Current Plan Card**
   - Plan name, price
   - Current period dates
   - Upgrade/downgrade button

2. **Usage Summary**
   - Messages: X / Y used (progress bar)
   - Tokens: X / Y used (progress bar)
   - Agents: X / Y active
   - Knowledge docs: X / Y

3. **Extra Usage Balance**
   - Current balance
   - Add funds button
   - Auto-recharge status
   - Recent transactions (last 5)

4. **Premium Agents**
   - List of active premium agent subscriptions
   - Monthly cost per agent
   - Total premium charges

### Usage Details Page

**URL:** `/billing/usage/`

**Components:**
1. **Period Selector** (current month, previous months)
2. **Usage by Metric**
   - Chart showing daily usage
   - Breakdown by agent
3. **Overage Charges**
   - List of charges with quantities and amounts

### Balance Management Page

**URL:** `/billing/balance/`

**Components:**
1. **Current Balance** (large display)
2. **Add Funds Form**
   - Preset amounts: $10, $25, $50, $100
   - Custom amount input
   - Payment method selector
3. **Auto-Recharge Settings**
   - Enable/disable toggle
   - Threshold amount
   - Recharge amount
4. **Transaction History**
   - Paginated list of all transactions
   - Filter by type
   - Export to CSV

### Payment Methods Page

**URL:** `/billing/payment-methods/`

**Components:**
1. **Saved Cards** list
2. **Add Card** (Stripe Elements)
3. **Set Default** for auto-recharge
4. **Remove Card** (with confirmation)

### Invoices Page

**URL:** `/billing/invoices/`

**Components:**
1. **Invoice List** from Stripe
   - Date, amount, status
   - Download PDF link
2. **Filter by Year**

---

## 4.5 Internal Admin Interface

### Overview Dashboard

**URL:** `/admin/billing/`

**Components:**
1. **Revenue Summary**
   - MRR (Monthly Recurring Revenue)
   - ARR (Annual Recurring Revenue)
   - Total balance deposits this month
   - Total overage charges this month

2. **Customer Metrics**
   - Active subscriptions by plan
   - Customers with low balance
   - Customers approaching limits

3. **Recent Activity**
   - Recent signups
   - Recent upgrades/downgrades
   - Failed payments

### Plan Management

**URL:** `/admin/billing/plans/`

**Capabilities:**
- List all plans with subscriber counts
- Create new plan
- Edit plan (pricing, limits, features)
- Deactivate plan (prevent new signups)
- View customers on plan

### Customer Billing Admin

**URL:** `/admin/billing/customers/{customer_id}/`

**Capabilities:**
1. **Subscription Management**
   - View/change plan
   - Apply discount
   - Cancel subscription
   - Extend trial

2. **Balance Management**
   - View current balance
   - Add credit (with note)
   - Add debit (with note)
   - View full transaction history

3. **Premium Agents**
   - View active premium subscriptions
   - Cancel premium subscription
   - Apply credit

4. **Usage**
   - View current period usage
   - View historical usage
   - View overage charges

5. **Payments**
   - View payment history
   - Issue refund
   - View failed payments

### Overage Rate Management

**URL:** `/admin/billing/rates/`

**Capabilities:**
- View/edit global rates
- Create plan-specific rates
- Create customer-specific rates
- Set effective dates

### Reports

**URL:** `/admin/billing/reports/`

**Reports:**
1. **Revenue Report**
   - Subscription revenue by plan
   - Premium agent revenue
   - Balance deposit revenue

2. **Usage Report**
   - Total usage across all customers
   - Usage by plan tier
   - Top usage customers

3. **Churn Report**
   - Cancellations by month
   - Downgrade trends

---

# 5. Stripe Integration

## 5.1 Webhook Events

| Event | Handler |
|-------|---------|
| `customer.subscription.created` | Create/update Subscription record |
| `customer.subscription.updated` | Update Subscription (plan, status, period) |
| `customer.subscription.deleted` | Mark Subscription cancelled |
| `invoice.paid` | Record payment, update period dates |
| `invoice.payment_failed` | Update status, notify customer |
| `payment_intent.succeeded` | For balance deposits |
| `payment_intent.payment_failed` | Log failure, notify if auto-recharge |
| `charge.refunded` | Create refund BalanceTransaction |
| `charge.dispute.created` | Flag customer, create chargeback transaction |

## 5.2 Stripe Objects

| Hub Model | Stripe Object |
|-----------|---------------|
| Customer.subscription.stripe_customer_id | Customer |
| Subscription.stripe_subscription_id | Subscription |
| Plan.stripe_monthly_price_id | Price |
| PremiumAgentSubscription.stripe_subscription_item_id | Subscription Item |
| PaymentRecord.stripe_payment_intent_id | Payment Intent |
| PaymentRecord.stripe_invoice_id | Invoice |

---

# 6. API Endpoints

## 6.1 Customer-Facing API

```
# Subscription
GET    /api/billing/subscription/
POST   /api/billing/subscription/change-plan/
POST   /api/billing/subscription/cancel/

# Balance
GET    /api/billing/balance/
POST   /api/billing/balance/deposit/
PUT    /api/billing/balance/auto-recharge/

# Usage
GET    /api/billing/usage/
GET    /api/billing/usage/history/

# Payment Methods
GET    /api/billing/payment-methods/
POST   /api/billing/payment-methods/
DELETE /api/billing/payment-methods/{id}/
PUT    /api/billing/payment-methods/{id}/default/

# Invoices
GET    /api/billing/invoices/

# Premium Agents
GET    /api/billing/premium-agents/
```

## 6.2 Internal API (for Agent Runtime)

```
# Check if agent can respond
GET    /api/internal/billing/can-respond/{agent_id}/

# Report usage (called after each message)
POST   /api/internal/billing/usage/
{
    "agent_instance_id": "...",
    "metric": "messages",
    "quantity": 1
}

POST   /api/internal/billing/usage/
{
    "agent_instance_id": "...",
    "metric": "tokens",
    "quantity": 1523
}
```

## 6.3 Admin API

```
# Plans
GET    /api/admin/billing/plans/
POST   /api/admin/billing/plans/
PUT    /api/admin/billing/plans/{id}/
DELETE /api/admin/billing/plans/{id}/

# Customer billing
GET    /api/admin/billing/customers/{id}/
PUT    /api/admin/billing/customers/{id}/subscription/
POST   /api/admin/billing/customers/{id}/credit/
POST   /api/admin/billing/customers/{id}/debit/

# Rates
GET    /api/admin/billing/rates/
POST   /api/admin/billing/rates/
PUT    /api/admin/billing/rates/{id}/

# Reports
GET    /api/admin/billing/reports/revenue/
GET    /api/admin/billing/reports/usage/
GET    /api/admin/billing/reports/churn/
```

---

# 7. Future Considerations (Out of Scope)

Features noted for potential future development:

1. **Multi-Product Billing** — Single wallet already designed for this; would need product-scoped usage tracking
2. **Usage Alerts** — Email when approaching limits (80%, 100%)
3. **Spending Limits** — Cap maximum overage spend per period
4. **Promotional Credits** — Time-limited credits for marketing
5. **Referral Program** — Credit for referring new customers
6. **Annual Prepay Discounts** — Larger discounts for annual commitment
7. **Metered Billing to Stripe** — Report usage to Stripe for unified invoicing
8. **Tax Calculation** — Integration with Stripe Tax or Avalara
9. **Multi-Currency** — Support non-USD pricing

---

# 8. Implementation Approach

## 8.1 Recommended Phases

**Phase 1: Foundation (1 week)**
1. Plan model and seeding default plans
2. Enhanced Subscription model
3. Migrate existing string-based plans to Plan FK
4. Basic Stripe subscription flow

**Phase 2: Extra Usage Balance (1 week)**
1. CustomerBalance model
2. BalanceTransaction ledger
3. Deposit flow (manual)
4. Auto-recharge configuration and trigger
5. Balance management UI

**Phase 3: Usage Charging (1 week)**
1. OverageRate model and hierarchy
2. Enhanced UsageRecord
3. UsageCharge model
4. Usage reporting from Agent runtime
5. Charging logic integration
6. Grace period implementation (with configurable duration)

**Phase 4: Premium Agents (1 week)**
1. AgentTypePricing model
2. PremiumAgentSubscription model
3. Premium agent provisioning flow
4. Proration calculations
5. Cancellation credit flow

**Phase 5: Customer Portal (1 week)**
1. Billing dashboard
2. Usage details page
3. Balance management page
4. Payment methods (Stripe Elements)
5. Invoices page

**Phase 6: Internal Admin (1 week)**
1. Admin dashboard
2. Plan management
3. Customer billing management
4. Rate management
5. Basic reports

## 8.2 Dependencies

| Dependency | Notes |
|------------|-------|
| Stripe Account | API keys, webhook configuration |
| Agent Runtime | Must call usage reporting API |
| Existing Customers | Migration path for existing subscriptions |

## 8.3 Migration Strategy

For existing customers (if any):

1. Create Plan records for existing plan slugs
2. Migrate Subscription.plan string → Plan FK
3. Create CustomerBalance for each customer (starting at $0)
4. Backfill OverageRate global defaults

---

# 9. Acceptance Criteria

## 9.1 Plan Management

- [ ] Plan model stores pricing and limits
- [ ] Default plans seeded (starter, pro, business, enterprise)
- [ ] Customer can view available plans
- [ ] Customer can upgrade plan (immediate, prorated)
- [ ] Customer can downgrade plan (end of period)
- [ ] Plan limits enforced (agents, messages, tokens)

## 9.2 Premium Agents

- [ ] Premium agent types identified (not in PlanAgentTypeAccess)
- [ ] Premium pricing displayed during agent provisioning
- [ ] Prorated charge calculated and applied on add
- [ ] Premium subscription created in Stripe
- [ ] Prorated credit calculated on cancellation
- [ ] Credit added to Extra Usage Balance

## 9.3 Extra Usage Balance

- [ ] CustomerBalance created for each customer
- [ ] Customer can deposit funds (min $10)
- [ ] Auto-recharge configurable
- [ ] Auto-recharge triggers at threshold
- [ ] Transaction history accurate
- [ ] Balance displays correctly in UI

## 9.4 Usage & Charging

- [ ] Usage recorded per customer/agent
- [ ] Plan limits checked on each usage
- [ ] Overage rate hierarchy works (customer → plan → global)
- [ ] Overage charges deducted from balance
- [ ] UsageCharge records created
- [ ] Grace period starts when balance reaches $0
- [ ] Grace period warnings sent to customer
- [ ] Service paused after grace period expires

## 9.5 Customer Portal

- [ ] Billing dashboard shows plan, usage, balance
- [ ] Usage page shows daily breakdown
- [ ] Balance page allows deposits
- [ ] Payment methods manageable
- [ ] Invoices downloadable

## 9.6 Internal Admin

- [ ] Admin can create/edit plans
- [ ] Admin can view customer billing
- [ ] Admin can add credits/debits
- [ ] Admin can manage overage rates
- [ ] Basic revenue reports available

## 9.7 Stripe Integration

- [ ] Subscription lifecycle synced
- [ ] Payment intents for deposits
- [ ] Webhooks processed correctly
- [ ] Invoice history accessible

## 9.8 Trial System

- [ ] New customers receive configurable trial plan
- [ ] Trial duration configurable via BillingSettings
- [ ] Trial expiry warnings sent (7, 3, 1 days)
- [ ] Auto-downgrade to Starter on trial expiry
- [ ] Customer can upgrade during trial
- [ ] Trial status visible in dashboard

## 9.9 Configuration

- [ ] BillingSettings model stores all configurable values
- [ ] Grace period duration configurable
- [ ] Trial plan and duration configurable
- [ ] Minimum deposit amounts configurable
- [ ] Admin can update settings without code deploy
- [ ] Settings have sensible defaults

---

# 10. Service Boundary Notes (For Future Extraction)

To enable future extraction to a standalone billing service:

1. **Loose Coupling:** Billing models reference `customer_id` (UUID) rather than direct FK where possible
2. **Service Layer:** All billing logic in `apps/billing/services/` — not in views or models
3. **Event-Driven:** Consider publishing events (customer.created, agent.provisioned) that billing subscribes to
4. **API-First:** Internal admin uses API endpoints, not direct ORM access
5. **Config Separation:** Billing-specific settings in `BILLING_*` namespace

If extraction needed:
1. Create new `echoforge-billing` Django project
2. Copy `apps/billing/` models and services
3. Create sync mechanism for Customer data (webhook or API)
4. Update Hub to call Billing service APIs
5. Update Agent runtime to call Billing service APIs

---

*End of Specification*
