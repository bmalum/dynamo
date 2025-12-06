# Belongs To Collections Guide

This guide explains how to use the `belongs_to` functionality in Dynamo.Schema to create collections where child entities share the same partition key as their parent entities, enabling efficient single-table design patterns in DynamoDB.

## Overview

The `belongs_to` feature allows you to define relationships between entities where:
- Child entities use their parent's partition key format
- Child entities can choose how to handle their sort key (prefix or use as-is)
- Related entities are stored in the same partition for efficient querying

## Basic Usage

### Defining Parent and Child Schemas

```elixir
# Parent entity
defmodule MyApp.Customer do
  use Dynamo.Schema

  item do
    field(:customer_id, partition_key: true)
    field(:name)
    field(:email, sort_key: true)
    field(:created_at)

    table_name("customers")
  end
end

# Child entity that belongs to Customer
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:customer_id)  # foreign key
    field(:order_id)
    field(:total_amount)
    field(:status)
    field(:created_at, sort_key: true)

    # Define the belongs_to relationship
    # foreign_key is auto-inferred from Customer's partition key
    belongs_to :customer, MyApp.Customer, sk_strategy: :prefix

    table_name("orders")
  end
end
```

## Sort Key Strategies

The `sk_strategy` option controls how the child entity's sort key is generated:

### `:prefix` Strategy (Default)

Prefixes the child's sort key with the entity name:

```elixir
# Auto-inferred foreign key (recommended)
belongs_to :customer, MyApp.Customer, sk_strategy: :prefix

# Explicit foreign key (for custom naming)
belongs_to :customer, MyApp.Customer, 
  foreign_key: :cust_id,
  sk_strategy: :prefix
```

**Key Generation:**
- Customer: `pk="customer#cust-123"`, `sk="john@example.com"`
- Order: `pk="customer#cust-123"`, `sk="order#2024-01-15T10:30:00Z"`

### `:use_defined` Strategy

Uses the child's sort key as-is without prefixing:

```elixir
belongs_to :customer, MyApp.Customer, sk_strategy: :use_defined
```

**Key Generation:**
- Customer: `pk="customer#cust-123"`, `sk="john@example.com"`
- Order: `pk="customer#cust-123"`, `sk="2024-01-15T10:30:00Z"`

## Complete Example

```elixir
defmodule MyApp.Customer do
  use Dynamo.Schema

  item do
    field(:customer_id, partition_key: true)
    field(:name)
    field(:email, sort_key: true)
    field(:created_at)

    table_name("customers")

    global_secondary_index("EmailIndex", partition_key: :email)
  end
end

defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:customer_id)
    field(:order_id)
    field(:total_amount)
    field(:status)
    field(:created_at, sort_key: true)

    belongs_to :customer, MyApp.Customer, sk_strategy: :prefix

    table_name("orders")

    global_secondary_index("StatusIndex", 
      partition_key: :status, 
      sort_key: :created_at)
  end
end

defmodule MyApp.OrderItem do
  use Dynamo.Schema

  item do
    field(:order_id)
    field(:product_id)
    field(:quantity)
    field(:price)
    field(:created_at, sort_key: true)

    belongs_to :order, MyApp.Order,
      foreign_key: :order_id,
      sk_strategy: :prefix

    table_name("order_items")
  end
end
```

## Usage Examples

```elixir
# Create entities
customer = %MyApp.Customer{
  customer_id: "cust-123",
  name: "John Doe",
  email: "john@example.com",
  created_at: "2024-01-15T10:00:00Z"
}

order = %MyApp.Order{
  customer_id: "cust-123",  # foreign key
  order_id: "order-456",
  total_amount: 99.99,
  status: "completed",
  created_at: "2024-01-15T11:00:00Z"
}

item = %MyApp.OrderItem{
  order_id: "order-456",  # foreign key
  product_id: "prod-111",
  quantity: 2,
  price: 49.99,
  created_at: "2024-01-15T11:01:00Z"
}

# Generated keys:
# Customer: pk="customer#cust-123", sk="john@example.com"
# Order:    pk="customer#cust-123", sk="order#2024-01-15T11:00:00Z"
# Item:     pk="order#order-456",   sk="orderitem#2024-01-15T11:01:00Z"

# Query all orders for a customer (same partition)
{:ok, customer_orders} = 
  Dynamo.Table.list_items(%MyApp.Order{customer_id: "cust-123"})

# Query all items for an order (same partition)
{:ok, order_items} = 
  Dynamo.Table.list_items(%MyApp.OrderItem{order_id: "order-456"})

# Query orders by status using GSI
{:ok, completed_orders} =
  Dynamo.Table.list_items(
    %MyApp.Order{status: "completed"},
    index_name: "StatusIndex"
  )
```

## Benefits

1. **Efficient Queries**: Related entities share the same partition, enabling fast queries
2. **Single-Table Design**: Multiple entity types can coexist in the same table
3. **Flexible Sort Keys**: Choose between prefixed or natural sort key ordering
4. **GSI Support**: Child entities can still define their own GSIs
5. **Type Safety**: Compile-time validation of foreign key fields

## Configuration Options

### Optional Options

- `:sk_strategy` - How to handle sort keys (`:prefix` or `:use_defined`, defaults to `:prefix`)
- `:foreign_key` - The field that references the parent's partition key (auto-inferred from parent's partition key)

## Validation

The schema validates:
- Parent module has a defined partition key for auto-inference
- Foreign key field (auto-inferred or explicit) exists in the child schema
- Sort key strategy is valid (`:prefix` or `:use_defined`)
- All standard schema validations still apply

## Limitations

- Currently supports single `belongs_to` relationship per entity
- Foreign key must reference the parent's partition key value
- Child entities inherit the parent's partition key format

## Best Practices

1. **Use `:prefix` strategy** when you need to distinguish between different entity types in the same partition
2. **Use `:use_defined` strategy** when you want natural sort ordering across entity types
3. **Define GSIs on child entities** for access patterns that don't follow the parent-child hierarchy
4. **Keep foreign key fields populated** to ensure proper key generation
5. **Consider partition size limits** when designing deeply nested relationships

## Migration from Existing Schemas

To add `belongs_to` to existing schemas:

1. Add the foreign key field to your child schema
2. Add the `belongs_to` declaration
3. Update any existing data to use the new key format
4. Test key generation with your existing data patterns

```elixir
# Before
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:order_id, partition_key: true)
    field(:customer_id)
    field(:created_at, sort_key: true)
    # ...
  end
end

# After
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:order_id)  # no longer partition key
    field(:customer_id)  # now the foreign key
    field(:created_at, sort_key: true)

    belongs_to :customer, MyApp.Customer, sk_strategy: :prefix

    # ...
  end
end
```