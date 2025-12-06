# Partial Sort Key Generation

This document explains how partial sort key generation works for both regular schemas and `belongs_to` relationships.

## Problem

When querying DynamoDB with composite sort keys, you often want to query with progressively more specific criteria. For example:
- Query all orders for a customer (no sort key)
- Query all orders for a customer on a specific date (partial sort key)
- Query a specific order (full sort key)

## Solution: Partial Sort Key Generation

Both `generate_sort_key` and `generate_belongs_to_sort_key` functions now generate **partial sort keys** by stopping at the first `nil` field. This allows for hierarchical queries.

## Example

```elixir
defmodule Customer do
  use Dynamo.Schema

  item do
    table_name("customers")
    field(:customer_id, partition_key: true)
    field(:name)
    field(:email, sort_key: true)
  end
end

defmodule Order do
  use Dynamo.Schema

  item do
    table_name("orders")
    field(:customer_id)
    field(:order_date, sort_key: true)
    field(:order_id, sort_key: true)
    field(:total_amount)

    belongs_to(:customer, Customer, sk_strategy: :prefix)
  end
end
```

## Generated Sort Keys

### All fields set (full sort key)
```elixir
order = %Order{
  customer_id: "cust-123",
  order_date: "2023-01-01",
  order_id: "ord-456"
}

# Generated keys:
# pk: "customer#cust-123"
# sk: "order#2023-01-01#ord-456"
```

### Only first field set (partial sort key)
```elixir
order = %Order{
  customer_id: "cust-123",
  order_date: "2023-01-01",
  order_id: nil  # nil stops here
}

# Generated keys:
# pk: "customer#cust-123"
# sk: "order#2023-01-01"  # Stops at first nil
```

### No sort key fields set (entity prefix only)
```elixir
order = %Order{
  customer_id: "cust-123",
  order_date: nil,  # nil stops here
  order_id: "ord-456"
}

# Generated keys:
# pk: "customer#cust-123"
# sk: "order"  # Just the entity prefix
```

## Query Patterns

This enables powerful query patterns:

```elixir
# Query all orders for a customer
query_struct = %Order{customer_id: "cust-123", order_date: nil, order_id: nil}
# sk: "order" - matches all orders

# Query all orders for a customer on a specific date
query_struct = %Order{customer_id: "cust-123", order_date: "2023-01-01", order_id: nil}
# sk: "order#2023-01-01" - matches all orders on that date

# Query a specific order
query_struct = %Order{customer_id: "cust-123", order_date: "2023-01-01", order_id: "ord-456"}
# sk: "order#2023-01-01#ord-456" - matches exact order
```

## With prefix_sort_key: true

When using `prefix_sort_key: true`, field names are included in the sort key:

```elixir
defmodule OrderWithPrefix do
  use Dynamo.Schema, prefix_sort_key: true

  item do
    table_name("orders")
    field(:customer_id)
    field(:order_date, sort_key: true)
    field(:order_id, sort_key: true)
    
    belongs_to(:customer, Customer, sk_strategy: :prefix)
  end
end

order = %OrderWithPrefix{
  customer_id: "cust-123",
  order_date: "2023-01-01",
  order_id: nil
}

# Generated keys:
# pk: "customer#cust-123"
# sk: "orderwithprefix#order_date#2023-01-01"
```

## Benefits

1. **Flexible Queries**: Query at any level of specificity
2. **Efficient**: Only include the fields you need
3. **Intuitive**: nil values naturally stop the sort key generation
4. **DynamoDB Best Practice**: Follows single-table design patterns

## How Queries Work

When querying with `belongs_to` relationships, the system automatically:

1. **Generates the partition key** using the parent's format
2. **Generates a partial sort key** based on which fields are populated
3. **Applies `begins_with` operator** when no explicit operator is provided

### Example Query Flow

```elixir
# Query all orders for a customer on a specific date
query_struct = %Order{
  customer_id: "cust-123",
  order_date: "2023-01-01",
  order_id: nil  # nil means "match all order_ids"
}

Order.list_items(query_struct)

# Internally generates:
# pk: "customer#cust-123"
# sk: "order#2023-01-01" with begins_with operator
# This matches: "order#2023-01-01#ord-456", "order#2023-01-01#ord-789", etc.
```

### With Explicit Operators

You can also use explicit operators for more control:

```elixir
# Query orders from a specific date onwards
Order.list_items(
  %Order{customer_id: "cust-123", order_date: "2023-01-01", order_id: nil},
  sk_operator: :gte
)

# Query orders before a specific date
Order.list_items(
  %Order{customer_id: "cust-123", order_date: "2023-01-01", order_id: nil},
  sk_operator: :lt
)
```

## Implementation Details

Both functions use `Enum.reduce_while/3` to iterate through sort key fields and stop at the first `nil` value:

```elixir
sort_key_parts = arg.__struct__.sort_key()
|> Enum.reduce_while([], fn elm, acc ->
  field_value = Map.get(arg, elm)
  
  # Stop if we hit a nil or missing field
  if field_value == nil do
    {:halt, acc}
  else
    parts = if config[:prefix_sort_key] do
      [Atom.to_string(elm), field_value]
    else
      [field_value]
    end
    {:cont, acc ++ parts}
  end
end)
```

This applies to:
- `generate_sort_key/1` - Regular sort key generation
- `generate_belongs_to_sort_key/2` - Sort key generation for belongs_to relationships
