# Simple Belongs To Example

Here's a clean example showing how the auto-inferred foreign key makes the API much simpler:

## Before (with explicit foreign_key)

```elixir
defmodule MyApp.Customer do
  use Dynamo.Schema

  item do
    field(:customer_id, partition_key: true)
    field(:name)
    field(:email, sort_key: true)
    
    table_name("customers")
  end
end

defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:customer_id)  # foreign key
    field(:order_id)
    field(:total_amount)
    field(:created_at, sort_key: true)

    # Had to explicitly specify foreign_key
    belongs_to :customer, MyApp.Customer,
      foreign_key: :customer_id,  # redundant!
      sk_strategy: :prefix

    table_name("orders")
  end
end
```

## After (with auto-inferred foreign_key)

```elixir
defmodule MyApp.Customer do
  use Dynamo.Schema

  item do
    field(:customer_id, partition_key: true)
    field(:name)
    field(:email, sort_key: true)
    
    table_name("customers")
  end
end

defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:customer_id)  # auto-inferred as foreign key!
    field(:order_id)
    field(:total_amount)
    field(:created_at, sort_key: true)

    # Much cleaner - foreign_key is auto-inferred from Customer's partition_key
    belongs_to :customer, MyApp.Customer, sk_strategy: :prefix

    table_name("orders")
  end
end
```

## How it works

1. **Auto-inference**: The system looks at `MyApp.Customer.partition_key()` which returns `[:customer_id]`
2. **Field matching**: It checks that the child schema has a field named `:customer_id`
3. **Key generation**: Orders will use the customer's partition key format: `"customer#123"`

## Benefits

- **Less repetition**: No need to specify what's already obvious
- **Less error-prone**: Can't accidentally specify the wrong foreign key
- **Cleaner code**: Focus on the relationship, not the implementation details
- **Still flexible**: Can override with explicit `:foreign_key` when needed

## Custom foreign key names

If you need a different field name, you can still override:

```elixir
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    field(:cust_id)  # different name
    field(:order_id)
    field(:created_at, sort_key: true)

    # Override the auto-inferred foreign key
    belongs_to :customer, MyApp.Customer, 
      foreign_key: :cust_id,
      sk_strategy: :prefix
  end
end
```

This gives you the best of both worlds - simple by default, flexible when needed!