# Dynamo Agent Guide

A comprehensive guide for AI agents and developers on using the Dynamo library effectively with DynamoDB.

## Table of Contents

- [Understanding the DSL](#understanding-the-dsl)
- [Schema Design Decisions](#schema-design-decisions)
- [Partition Key Strategies](#partition-key-strategies)
- [Sort Key Strategies](#sort-key-strategies)
- [DynamoDB Best Practices](#dynamodb-best-practices)
- [Phoenix Contexts](#phoenix-contexts)
- [Common Patterns](#common-patterns)
- [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
- [Quick Reference](#quick-reference)

---

## Understanding the DSL

Dynamo provides an Ecto-inspired DSL for defining DynamoDB schemas. The core building blocks are:

### Basic Schema Structure

```elixir
defmodule MyApp.Entity do
  use Dynamo.Schema

  item do
    table_name "table_name"
    
    field :field_name, partition_key: true
    field :another_field, sort_key: true
    field :regular_field
    field :with_default, default: "value"
  end
end
```

### Schema Options

Pass options to `use Dynamo.Schema`:

```elixir
use Dynamo.Schema,
  key_separator: "#",      # Separator for composite keys (default: "#")
  prefix_sort_key: true    # Include field name prefix in sort key
```

### Field Definitions

| Option | Purpose |
|--------|---------|
| `partition_key: true` | Marks field as part of partition key |
| `sort_key: true` | Marks field as part of sort key |
| `default: value` | Sets default value |

### Alternative Key Definition

For complex keys spanning multiple fields:

```elixir
item do
  table_name "orders"
  
  field :tenant_id
  field :customer_id
  field :order_date
  field :order_id
  
  partition_key [:tenant_id, :customer_id]
  sort_key [:order_date, :order_id]
end
```

This generates keys like:
- PK: `tenant123#customer456`
- SK: `2024-01-15#order789`

---

## Schema Design Decisions

### Single-Table vs Multi-Table Design

**Single-Table Design** (Recommended for most cases):
- Store multiple entity types in one table
- Use prefixes to distinguish entity types
- Enables efficient queries across related entities

```elixir
defmodule MyApp.UserEntity do
  use Dynamo.Schema

  item do
    table_name "app_data"
    
    field :entity_type, default: "USER"
    field :user_id, partition_key: true
    field :sk_type, sort_key: true, default: "PROFILE"
    field :email
    field :name
  end
end

defmodule MyApp.UserOrder do
  use Dynamo.Schema

  item do
    table_name "app_data"
    
    field :entity_type, default: "ORDER"
    field :user_id, partition_key: true
    field :order_id, sort_key: true
    field :total
    field :status
  end
end
```

**Multi-Table Design** (Use when):
- Entities have completely different access patterns
- Different throughput requirements per entity
- Regulatory/compliance requires data separation

### Choosing Your Key Strategy

Ask these questions:

1. **What queries do I need?** - List all access patterns first
2. **What's the cardinality?** - High cardinality = better distribution
3. **What's the query frequency?** - Hot partitions are problematic
4. **Do I need range queries?** - Determines sort key design

---

## Partition Key Strategies

### Goal: Even Data Distribution

DynamoDB distributes data across partitions based on partition key hash. Uneven distribution creates "hot partitions."

### Strategy 1: Natural Unique Identifier

Best for: User profiles, products, sessions

```elixir
field :user_id, partition_key: true  # UUID or unique ID
```

### Strategy 2: Composite Partition Key

Best for: Multi-tenant applications, hierarchical data

```elixir
partition_key [:tenant_id, :entity_type]
# Results in: "tenant123#USER"
```

### Strategy 3: Write Sharding

Best for: High-write scenarios with predictable keys (counters, time-series)

```elixir
defmodule MyApp.Counter do
  use Dynamo.Schema

  item do
    table_name "counters"
    
    field :counter_name
    field :shard, partition_key: true  # counter_name#0, counter_name#1, etc.
    field :count, default: 0
  end
  
  def sharded_key(name), do: "#{name}##{:rand.uniform(10) - 1}"
end
```

### Partition Key Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Date as PK | All writes hit same partition | Add unique ID or shard |
| Status as PK | Few values, uneven distribution | Use as sort key or GSI |
| Sequential IDs | Predictable, causes hot spots | Use UUIDs |
| Low cardinality | Limited distribution | Combine with other fields |

---

## Sort Key Strategies

### Goal: Enable Efficient Range Queries

Sort keys determine item ordering within a partition and enable powerful query patterns.

### Strategy 1: Hierarchical Data

```elixir
# Access pattern: Get all orders for a user, filter by date
partition_key [:user_id]
sort_key [:order_date, :order_id]
# SK: "2024-01-15#order123"

# Query: All orders after a date
MyApp.Order.list_items(
  %MyApp.Order{user_id: "user123", order_date: "2024-01-01"},
  sk_operator: :gte
)
```

### Strategy 2: Entity Type Prefix

```elixir
# Store multiple entity types, query by type
sort_key [:entity_type, :entity_id]
# SK: "ORDER#order123" or "PROFILE#profile456"

# Query: All orders for user
MyApp.Entity.list_items(
  %MyApp.Entity{user_id: "user123", entity_type: "ORDER"},
  sk_operator: :begins_with
)
```

### Strategy 3: Time-Based Ordering

```elixir
# Access pattern: Recent items first
field :created_at, sort_key: true

# Query descending (newest first)
MyApp.Item.list_items(
  %MyApp.Item{user_id: "user123"},
  scan_index_forward: false
)
```

### Strategy 4: Composite Sort Key for Multiple Access Patterns

```elixir
sort_key [:status, :created_at, :order_id]
# SK: "PENDING#2024-01-15T10:30:00Z#order123"

# Query: All pending orders
MyApp.Order.list_items(
  %MyApp.Order{user_id: "user123", status: "PENDING"},
  sk_operator: :begins_with
)

# Query: Pending orders after date
MyApp.Order.list_items(
  %MyApp.Order{user_id: "user123", status: "PENDING", created_at: "2024-01-01"},
  sk_operator: :begins_with
)
```

### Sort Key Operators

| Operator | Use Case |
|----------|----------|
| `:eq` | Exact match |
| `:lt`, `:lte` | Less than (before date, lower value) |
| `:gt`, `:gte` | Greater than (after date, higher value) |
| `:begins_with` | Prefix matching (hierarchical queries) |
| `:between` | Range queries (date ranges) |

---

## DynamoDB Best Practices

### 1. Capacity Planning

**On-Demand Mode** (Recommended for):
- Unpredictable workloads
- New applications
- Development/testing

**Provisioned Mode** (Recommended for):
- Predictable, steady workloads
- Cost optimization at scale
- When you understand your traffic patterns

### 2. Item Size Optimization

- Maximum item size: 400KB
- Keep items small for better performance
- Use S3 for large objects, store reference in DynamoDB

```elixir
# Store S3 reference instead of large content
field :document_s3_key  # "bucket/path/to/document.pdf"
field :document_metadata  # Small metadata only
```

### 3. Efficient Queries

**Do:**
```elixir
# Use projection to fetch only needed attributes
MyApp.User.list_items(
  %MyApp.User{tenant_id: "tenant123"},
  projection_expression: "user_id, email, #name",
  expression_attribute_names: %{"#name" => "name"}
)
```

**Don't:**
```elixir
# Avoid scanning entire table into memory
{:ok, %{items: users}} = Dynamo.Table.scan(MyApp.User)  # Loads everything!

# ✅ Better for large tables: Use streaming (but still expensive!)
Dynamo.Table.Stream.scan(MyApp.User)
|> Stream.filter(&(&1.active))
|> Enum.each(&process_user/1)
```

**Important:** Scans are expensive operations even with streaming. They consume read capacity for every item examined (not just returned). Always prefer queries with partition keys when possible. Use scans only when necessary (data exports, migrations, analytics).

### 4. Batch Operations

```elixir
# Batch writes (up to 25 items)
items = Enum.map(1..25, fn i ->
  %MyApp.Product{category: "electronics", id: "prod-#{i}", name: "Product #{i}"}
end)

{:ok, _} = Dynamo.Table.batch_write_item(items)
```

### 5. Use GSIs Strategically

```elixir
item do
  table_name "users"
  
  field :user_id, partition_key: true
  field :created_at, sort_key: true
  field :email
  field :status

  # GSI for email lookups
  global_secondary_index "EmailIndex", partition_key: :email

  # GSI for status queries with time ordering
  global_secondary_index "StatusIndex",
    partition_key: :status,
    sort_key: :created_at,
    projection: :keys_only  # Minimize storage cost
end
```

**GSI Guidelines:**
- Maximum 20 GSIs per table
- GSIs consume additional write capacity
- Use `:keys_only` or `:include` projections when possible
- GSIs are eventually consistent only

**Querying GSIs:**
```elixir
# Query by email
MyApp.User.list_items(
  %MyApp.User{email: "user@example.com"},
  index_name: "EmailIndex"
)

# Query by status with time range
MyApp.User.list_items(
  %MyApp.User{status: "active", created_at: "2024-01-01"},
  index_name: "StatusIndex",
  sk_operator: :gte
)
```

### 6. Error Handling & Retries

```elixir
case MyApp.User.get_item(%MyApp.User{id: "user123"}) do
  {:ok, user} -> 
    handle_user(user)
    
  {:error, %Dynamo.Error{type: :provisioned_throughput_exceeded}} ->
    # Implement exponential backoff
    Process.sleep(100)
    retry_operation()
    
  {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
    # Handle optimistic locking failure
    handle_conflict()
    
  {:error, error} ->
    Logger.error("DynamoDB error: #{error.message}")
end
```

**Common Error Types:**
- `:resource_not_found` - The requested resource doesn't exist
- `:provisioned_throughput_exceeded` - Rate limits exceeded
- `:conditional_check_failed` - Condition expression evaluated to false
- `:validation_error` - Parameter validation failed
- `:access_denied` - Insufficient permissions
- `:transaction_conflict` - Transaction conflicts with another operation

### 7. Transactions for Consistency

```elixir
# Atomic operations across items
Dynamo.Transaction.transact([
  {:check, %Account{id: "source"}, "balance >= :amount", %{":amount" => %{"N" => "100"}}},
  {:update, %Account{id: "source"}, %{balance: {:decrement, 100}}},
  {:update, %Account{id: "dest"}, %{balance: {:increment, 100}}}
])
```

**Transaction Limits:**
- Maximum 100 items per transaction
- 4MB total request size
- All items must be in same region

**Note:** Transaction support requires the `Dynamo.Transaction` module. See README for implementation details.

### 8. TTL for Data Lifecycle

DynamoDB can automatically delete expired items. Design your schema to include TTL:

```elixir
field :ttl  # Unix timestamp for expiration
```

Enable TTL on the table via AWS Console or CLI.

### 9. Streaming for Large Tables

When you need to process large tables, use streaming to avoid memory exhaustion:

**Sequential Streaming** (memory-efficient):
```elixir
# Process items lazily, constant memory usage
Dynamo.Table.Stream.scan(User, page_size: 500)
|> Stream.filter(&(&1.active))
|> Enum.each(&process_user/1)
```

**Parallel Streaming** (high-throughput):
```elixir
# Scan multiple segments concurrently
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&process_user/1)
|> Enum.to_list()
```

**Process-Based** (real-time):
```elixir
# Send items to a GenServer as they're scanned
{:ok, task} = Dynamo.Table.Stream.scan_to_process(
  User,
  consumer_pid,
  segments: 4,
  batch_size: 50
)
```

**Important:** Streaming reduces memory usage but doesn't reduce cost. Scans still consume read capacity for every item examined. See `guides/STREAMING_GUIDE.md` for detailed documentation.

---

## Phoenix Contexts

Phoenix contexts provide a clean boundary between your web layer and data access. They encapsulate business logic and make your application testable and maintainable.

### Basic Context Structure

```elixir
# Schema
defmodule MyApp.Accounts.User do
  use Dynamo.Schema

  item do
    table_name "users"
    
    field :id, partition_key: true
    field :email, sort_key: true
    field :name
    field :role, default: "user"
    field :inserted_at
    
    global_secondary_index "EmailIndex", partition_key: :email
  end
end

# Context
defmodule MyApp.Accounts do
  alias MyApp.Accounts.User
  
  def list_users do
    {:ok, Dynamo.Table.Stream.scan(User) |> Enum.to_list()}
  end
  
  def get_user(id, email) do
    User.get_item(%User{id: id, email: email})
  end
  
  def get_user_by_email(email) do
    case User.list_items(%User{email: email}, index_name: "EmailIndex") do
      {:ok, [user | _]} -> {:ok, user}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end
  
  def create_user(attrs) do
    user = %User{
      id: generate_id(),
      email: attrs[:email],
      name: attrs[:name],
      role: attrs[:role] || "user",
      inserted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    User.put_item(user)
  end
  
  def update_user(%User{} = user, attrs) do
    updated = %{user | name: attrs[:name] || user.name}
    User.put_item(updated)
  end
  
  def delete_user(%User{} = user) do
    User.delete_item(user)
  end
  
  defp generate_id do
    "user_" <> (:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false))
  end
end
```

### Phoenix Controller Integration

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias MyApp.Accounts
  
  def index(conn, _params) do
    {:ok, users} = Accounts.list_users()
    render(conn, :index, users: users)
  end
  
  def show(conn, %{"id" => id, "email" => email}) do
    case Accounts.get_user(id, email) do
      {:ok, user} -> render(conn, :show, user: user)
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/users")
    end
  end
  
  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created")
        |> redirect(to: ~p"/users/#{user.id}")
      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed: #{inspect(reason)}")
        |> render(:new)
    end
  end
end
```

### Context Best Practices

1. **Keep contexts focused** - One context per domain (Accounts, Orders, Billing)
2. **Return tuples** - Use `{:ok, result}` or `{:error, reason}` consistently
3. **Handle errors** - Convert DynamoDB errors to domain errors
4. **Use GSIs** - Define GSIs for secondary access patterns
5. **Document patterns** - List all access patterns in module docs

### Multi-Tenant Pattern

```elixir
defmodule MyApp.Organizations do
  alias MyApp.Organizations.Member
  
  def list_members(org_id) do
    Member.list_items(%Member{org_id: org_id})
  end
  
  def add_member(org_id, user_id, role \\ "member") do
    member = %Member{
      org_id: org_id,
      user_id: user_id,
      role: role,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    Member.put_item(member)
  end
end

defmodule MyApp.Organizations.Member do
  use Dynamo.Schema
  
  item do
    table_name "org_members"
    field :org_id, partition_key: true
    field :user_id, sort_key: true
    field :role
    field :joined_at
  end
end
```

**See `guides/PHOENIX_CONTEXT_GUIDE.md` for comprehensive examples including authentication, e-commerce, transactions, and testing strategies.**

---

## Common Patterns

### Pattern 1: User with Related Entities

```elixir
# Single table design
defmodule MyApp.UserData do
  use Dynamo.Schema

  item do
    table_name "user_data"
    
    field :user_id, partition_key: true
    field :sk, sort_key: true  # "PROFILE", "ORDER#123", "ADDRESS#home"
    # ... other fields
  end
end

# Query all user data
MyApp.UserData.list_items(%MyApp.UserData{user_id: "user123"})

# Query only orders
MyApp.UserData.list_items(
  %MyApp.UserData{user_id: "user123", sk: "ORDER"},
  sk_operator: :begins_with
)
```

### Pattern 2: Time-Series Data

```elixir
defmodule MyApp.Metric do
  use Dynamo.Schema

  item do
    table_name "metrics"
    
    field :device_id, partition_key: true
    field :timestamp, sort_key: true
    field :value
    field :ttl  # Auto-expire old data
  end
end

# Query last 24 hours
yesterday = DateTime.utc_now() |> DateTime.add(-86400) |> DateTime.to_iso8601()

MyApp.Metric.list_items(
  %MyApp.Metric{device_id: "device123", timestamp: yesterday},
  sk_operator: :gte,
  scan_index_forward: false  # Newest first
)
```

### Pattern 3: Multi-Tenant Application

```elixir
defmodule MyApp.TenantEntity do
  use Dynamo.Schema

  item do
    table_name "saas_data"
    
    field :tenant_id
    field :entity_type
    field :entity_id
    
    partition_key [:tenant_id]
    sort_key [:entity_type, :entity_id]
  end
end

# All users for tenant
MyApp.TenantEntity.list_items(
  %MyApp.TenantEntity{tenant_id: "tenant123", entity_type: "USER"},
  sk_operator: :begins_with
)
```

### Pattern 4: Adjacency List (Graph)

```elixir
defmodule MyApp.GraphEdge do
  use Dynamo.Schema

  item do
    table_name "graph"
    
    field :node_id, partition_key: true
    field :edge, sort_key: true  # "FOLLOWS#user456", "LIKED_BY#user789"
    field :created_at
  end
end

# Get all followers
MyApp.GraphEdge.list_items(
  %MyApp.GraphEdge{node_id: "user123", edge: "FOLLOWED_BY"},
  sk_operator: :begins_with
)
```

---

## Anti-Patterns to Avoid

### 1. Scan Operations in Production

```elixir
# ❌ Bad: Full table scan loading all into memory
{:ok, %{items: users}} = Dynamo.Table.scan(MyApp.User)

# ✅ Better: Use streaming for memory efficiency (but still expensive!)
Dynamo.Table.Stream.scan(MyApp.User)
|> Stream.filter(&(&1.active))
|> Enum.each(&process_user/1)

# ✅ Best: Query with partition key
MyApp.User.list_items(%MyApp.User{tenant_id: "tenant123"})
```

**Note:** Scans consume read capacity for every item examined, regardless of streaming. Always prefer queries when possible.

### 2. Hot Partitions

```elixir
# ❌ Bad: All writes to same partition
field :date, partition_key: true  # "2024-01-15" - all day's data in one partition

# ✅ Good: Distribute writes
partition_key [:date, :shard]  # "2024-01-15#3"
```

### 3. Large Items

```elixir
# ❌ Bad: Storing large blobs
field :file_content  # Could exceed 400KB

# ✅ Good: Store reference
field :s3_bucket
field :s3_key
```

### 4. Unbounded Lists in Items

```elixir
# ❌ Bad: Growing list in single item
field :comments  # List that grows forever

# ✅ Good: Separate items per comment
# PK: post_id, SK: COMMENT#timestamp#comment_id
```

### 5. Ignoring Access Patterns

```elixir
# ❌ Bad: Designing schema without knowing queries
# Results in expensive scans or multiple GSIs

# ✅ Good: Document access patterns first
# 1. Get user by ID
# 2. Get user by email
# 3. List users by tenant, ordered by created_at
# 4. List active users by tenant
# Then design schema to support these patterns
```

---

## Quick Reference

### Schema Checklist

- [ ] Identified all access patterns
- [ ] Partition key has high cardinality
- [ ] Sort key enables required range queries
- [ ] GSIs cover secondary access patterns
- [ ] Item size stays under 400KB
- [ ] TTL configured for ephemeral data
- [ ] Error handling implemented

### Key Design Formula

```
Partition Key = [tenant] + [entity_type] + [high_cardinality_id]
Sort Key = [query_dimension_1] + [query_dimension_2] + [unique_id]
```

### Capacity Estimation

```
Read Capacity Units (RCU):
- 1 RCU = 1 strongly consistent read/sec (up to 4KB)
- 1 RCU = 2 eventually consistent reads/sec (up to 4KB)

Write Capacity Units (WCU):
- 1 WCU = 1 write/sec (up to 1KB)
```
