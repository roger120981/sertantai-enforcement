# API Strategy & Implementation Plan

**Status**: Planning
**Target**: Q1 2025 (March)
**Owner**: Engineering

---

## Overview

Expose the EHS Enforcement data via RESTful API using Ash JSON:API, enabling programmatic access for Risk & Compliance professionals integrating enforcement data into their internal systems.

---

## Goals

1. **Enable programmatic access** to all public data (cases, notices, offenders, legislation)
2. **Implement authentication** via API keys (Bearer tokens)
3. **Enforce rate limiting** per subscription tier
4. **Track API usage** for billing and analytics
5. **Provide excellent developer experience** (clear docs, predictable responses)

---

## Technical Approach

### Phase 1: JSON:API Endpoints (Week 9-10)

**Ash JSON:API** is already installed and configured. We just need to expose routes.

**Resources to Expose**:
```elixir
# router.ex
scope "/api/v1" do
  pipe_through :api

  AshJsonApi.Resource.routes(
    Case,
    actions: [:index, :show],
    relationships: [:offender, :agency, :offences]
  )

  AshJsonApi.Resource.routes(
    Notice,
    actions: [:index, :show],
    relationships: [:offender, :agency]
  )

  AshJsonApi.Resource.routes(
    Offender,
    actions: [:index, :show],
    relationships: [:cases, :notices]
  )

  AshJsonApi.Resource.routes(
    Legislation,
    actions: [:index, :show]
  )
end
```

**JSON:API Features**:
- **Sparse fieldsets**: `?fields[cases]=regulator_id,offence_fine,offence_action_date`
- **Include relationships**: `?include=offender,agency`
- **Filtering**: `?filter[agency]=hse&filter[offence_action_date][gte]=2024-01-01`
- **Sorting**: `?sort=-offence_action_date` (descending by date)
- **Pagination**: `?page[size]=50&page[number]=2`

---

### Phase 2: API Authentication (Week 4 + Week 10)

**API Key System**:

```elixir
defmodule EhsEnforcement.Accounts.Resources.ApiKey do
  use Ash.Resource,
    domain: EhsEnforcement.Accounts,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :key_hash, :string, allow_nil?: false
    attribute :key_prefix, :string, allow_nil?: false  # "sk_live_abc123..." → "sk_live_abc"
    attribute :name, :string  # User-provided label
    attribute :last_used_at, :utc_datetime
    attribute :request_count, :integer, default: 0
    attribute :is_active, :boolean, default: true
  end

  relationships do
    belongs_to :user, EhsEnforcement.Accounts.User
  end

  actions do
    create :generate do
      accept [:name]
      argument :user_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        # Generate secure random token
        token = "sk_live_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        key_hash = :crypto.hash(:sha256, token) |> Base.encode64()
        key_prefix = String.slice(token, 0, 12)  # First 12 chars for display

        changeset
        |> Ash.Changeset.change_attribute(:key_hash, key_hash)
        |> Ash.Changeset.change_attribute(:key_prefix, key_prefix)
        |> Ash.Changeset.force_change_attribute(:__token__, token)  # Return to user once
      end
    end

    read :verify do
      argument :token, :string, allow_nil?: false
      filter expr(key_hash == ^hash_token(token) and is_active == true)
    end
  end
end
```

**Authentication Plug**:
```elixir
defmodule EhsEnforcementWeb.Plugs.ApiAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_key} <- Accounts.verify_api_key(token),
         {:ok, user} <- Accounts.get_user(api_key.user_id) do

      # Track usage
      Accounts.increment_api_key_usage(api_key.id)

      # Store in conn for rate limiting
      conn
      |> assign(:current_user, user)
      |> assign(:api_key, api_key)
    else
      _ ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Invalid or missing API key"})
        |> halt()
    end
  end
end
```

---

### Phase 3: Rate Limiting (Week 10-11)

**Ash Rate Limiter** is already installed. Configuration per tier:

```elixir
# Case resource
rate_limits do
  rate_limit :api_read, [
    user_id: actor(:id),
    tier: actor(:subscription_tier)
  ] do
    # Free tier: 1,000 requests/month (~33/day)
    limit 33, :per_day when tier == :free

    # Professional tier: 10,000 requests/month (~333/day)
    limit 333, :per_day when tier == :professional

    # Business tier: 100,000 requests/month (~3,333/day)
    limit 3333, :per_day when tier == :business

    # Enterprise: unlimited (no rate limit)
  end
end
```

**Rate Limit Response**:
```json
HTTP/1.1 429 Too Many Requests
Retry-After: 86400
X-RateLimit-Limit: 333
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1672531200

{
  "error": "Rate limit exceeded",
  "message": "You have reached your daily request limit of 333. Upgrade to Business tier for higher limits.",
  "retry_after": "2025-01-08T00:00:00Z"
}
```

---

### Phase 4: API Documentation (Week 9)

**OpenAPI Spec Generation**:

Ash JSON:API can auto-generate OpenAPI 3.0 spec:

```elixir
# Generate openapi.json
mix ash_json_api.generate_openapi_spec
```

**SwaggerUI Integration**:

```elixir
# router.ex
scope "/docs" do
  pipe_through :browser
  forward "/api", PhoenixSwagger.Plug.SwaggerUI, otp_app: :ehs_enforcement, swagger_file: "openapi.json"
end
```

**Documentation Page** (`/docs/api`):
- Interactive API explorer (try requests in browser)
- Code examples (cURL, Python, JavaScript, Elixir)
- Authentication guide (how to get API key)
- Rate limit explanations
- Filtering/sorting syntax
- Relationship loading examples

---

## API Usage Tracking

**ApiUsage Resource**:
```elixir
defmodule EhsEnforcement.Accounts.Resources.ApiUsage do
  use Ash.Resource

  attributes do
    uuid_primary_key :id
    attribute :request_count, :integer, default: 0
    attribute :period_start, :date
    attribute :period_end, :date
  end

  relationships do
    belongs_to :api_key, ApiKey
    belongs_to :user, User
  end

  calculations do
    calculate :quota_percentage, :decimal do
      calculation fn records, _context ->
        # tier limits: free=1000, pro=10000, business=100000
        Enum.map(records, fn record ->
          limit = get_tier_limit(record.user.subscription_tier)
          Decimal.div(record.request_count, limit) |> Decimal.mult(100)
        end)
      end
    end
  end
end
```

**Usage Dashboard Component**:
```heex
<div class="api-usage-card">
  <h3>API Usage (Current Month)</h3>
  <div class="progress-bar">
    <div class="progress" style={"width: #{@usage.quota_percentage}%"}></div>
  </div>
  <p><%= @usage.request_count %> / <%= @usage.limit %> requests</p>

  <%= if @usage.quota_percentage > 80 do %>
    <div class="alert alert-warning">
      You've used <%= trunc(@usage.quota_percentage) %>% of your monthly quota.
      <%= if @usage.quota_percentage >= 100 do %>
        Upgrade to continue using the API.
      <% end %>
    </div>
  <% end %>
end
```

---

## Rate Limit Exhaustion Alerts

**Email Alerts** (via Swoosh):
- **80% quota**: "You've used 800 of 1,000 monthly API requests"
- **100% quota**: "You've reached your API limit. Upgrade to continue."

**Implementation**:
```elixir
defmodule EhsEnforcement.Accounts.ApiQuotaMonitor do
  use AshOban.Worker,
    queue: :default,
    max_attempts: 3

  @impl true
  def perform(_args) do
    # Run daily at midnight
    users_near_limit = Accounts.get_users_near_api_limit(threshold: 0.8)

    Enum.each(users_near_limit, fn user ->
      ApiQuotaMailer.send_quota_warning(user)
    end)

    :ok
  end
end
```

---

## API Client Libraries (Future)

**Phase 2026**: Official SDKs

- **Python**: `pip install ehs-enforcement`
- **JavaScript/TypeScript**: `npm install @ehs-enforcement/client`
- **Elixir**: Ash SDK auto-generates client from resources

Example Python usage:
```python
from ehs_enforcement import Client

client = Client(api_key="sk_live_...")

# Get recent cases
cases = client.cases.list(
    filters={"agency": "hse", "offence_action_date[gte]": "2024-01-01"},
    sort="-offence_action_date",
    page={"size": 50}
)

for case in cases:
    print(f"{case.regulator_id}: £{case.offence_fine}")
```

---

## Success Metrics

**Developer Adoption**:
- 50+ API keys generated in Q1
- 1,000+ API requests/month by March 2025
- 10+ active integrations (users making >100 requests/month)

**User Satisfaction**:
- API documentation NPS score >60
- <5% error rate (4xx/5xx responses)
- p95 response time <500ms

---

## Related Documents

- [Strategic Roadmap](../ROADMAP.md)
- [Q1 2025 Plan](../roadmap/2025-Q1.md)
- [Ash JSON:API Documentation](https://hexdocs.pm/ash_json_api)

---

**Created**: January 7, 2025
**Target Completion**: March 31, 2025
