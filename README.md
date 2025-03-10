# Dynamo

[![Hex.pm](https://img.shields.io/hexpm/v/dynamo.svg)](https://hex.pm/packages/dynamo)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/dynamo)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> An elegant, Ecto-inspired DSL for working with DynamoDB in Elixir

Dynamo provides a structured, type-safe way to interact with Amazon DynamoDB while maintaining the flexibility that makes DynamoDB powerful. Define schemas, encode/decode data, and perform operations with a clean, familiar syntax.

## Table of Contents

- [Installation](#installation)
- [Why Dynamo?](#why-dynamo)
- [Quick Start](#quick-start)
- [Key Concepts](#key-concepts)
- [Usage Guide](#usage-guide)
  - [Defining Schemas](#defining-schemas)
  - [Working with Items](#working-with-items)
  - [Querying Data](#querying-data)
  - [Batch Operations](#batch-operations)
  - [Advanced Queries](#advanced-queries)
- [Configuration](#configuration)
- [Advanced Usage](#advanced-usage)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add `dynamo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dynamo, github: "bmalum/dynamo"}
  ]
end
```

> Note: This package is not yet available on Hex. It will be published once it reaches a stable version.

## Why Dynamo?

DynamoDB is a powerful, flexible NoSQL database, but its schema-free nature can lead to inconsistencies in your data model. Dynamo bridges this gap by providing:

- **Type Safety**: Define schemas that enforce data consistency
- **Familiar Syntax**: Ecto-inspired DSL that feels natural to Elixir developers
- **Simplified Operations**: Clean abstractions for common DynamoDB operations
- **Flexible Configuration**: Multiple levels of configuration to suit your needs
- **Performance Optimizations**: Built-in support for batch operations and parallel scans

## Quick Start

Define a schema:

```elixir
defmodule MyApp.User do
  use Dynamo.Schema

  item do
    table_name "users"
    
    field :id, partition_key: true
    field :email, sort_key: true
    field :name
    field :role, default: "user"
    field :active, default: true
  end
end
```

Perform operations:

```elixir
# Create a user
user = %MyApp.User{id: "user-123", email: "john@example.com", name: "John Doe"}
{:ok, saved_user} = MyApp.User.put_item(user)

# Retrieve a user
{:ok, retrieved_user} = MyApp.User.get_item(%MyApp.User{id: "user-123", email: "john@example.com"})

# List users
{:ok, users} = MyApp.User.list_items(%MyApp.User{id: "user-123"})
```

## Key Concepts

### Schema Definition

Dynamo uses a schema-based approach to define the structure of your DynamoDB items. This provides:

- **Consistent Structure**: Ensure all items follow the same structure
- **Default Values**: Specify default values for fields
- **Key Generation**: Automatically generate partition and sort keys
- **Type Conversion**: Automatic conversion between Elixir types and DynamoDB types

### Key Management

Dynamo automatically handles the generation of composite keys based on your schema definition:

- **Partition Keys**: Define which fields make up the partition key
- **Sort Keys**: Define which fields make up the sort key
- **Composite Keys**: Combine multiple fields into a single key with configurable separators

### Configuration Levels

Dynamo provides three levels of configuration:

1. **Application Configuration**: Global defaults in your `config.exs`
2. **Process Configuration**: Override settings for specific processes
3. **Schema Configuration**: Schema-specific settings

## Usage Guide

### Defining Schemas

A schema defines the structure of your DynamoDB items:

```elixir
defmodule MyApp.Product do
  use Dynamo.Schema, key_separator: "_"

  item do
    table_name "products"
    
    field :category_id, partition_key: true
    field :product_id, sort_key: true
    field :name
    field :price
    field :stock, default: 0
    field :active, default: true
  end
end
```

#### Field Options

- `partition_key: true` - Marks the field as part of the partition key
- `sort_key: true` - Marks the field as part of the sort key
- `default: value` - Sets a default value for the field

#### Alternative Key Definition

You can also define keys separately from fields:

```elixir
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    table_name "orders"
    
    field :customer_id
    field :order_id
    field :status, default: "pending"
    field :total
    
    partition_key [:customer_id]
    sort_key [:order_id]
  end
end
```

### Working with Items

#### Creating Items

```elixir
# Create a struct
product = %MyApp.Product{
  category_id: "electronics",
  product_id: "prod-123",
  name: "Smartphone",
  price: 599.99
}

# Save to DynamoDB
{:ok, saved_product} = MyApp.Product.put_item(product)
```

#### Retrieving Items

```elixir
# Get by primary key
{:ok, product} = MyApp.Product.get_item(%MyApp.Product{
  category_id: "electronics",
  product_id: "prod-123"
})
```

#### Encoding and Decoding

Dynamo handles the conversion between Elixir types and DynamoDB types:

```elixir
# Encode a struct to DynamoDB format
dynamo_item = Dynamo.Encoder.encode_root(product)

# Decode a DynamoDB item to a map
decoded_map = Dynamo.Decoder.decode(dynamo_item)

# Decode a DynamoDB item to a struct
decoded_product = Dynamo.Decoder.decode(dynamo_item, as: MyApp.Product)
```

### Querying Data

#### Basic Queries

```elixir
# List all products in a category
{:ok, products} = MyApp.Product.list_items(%MyApp.Product{category_id: "electronics"})
```

#### Query Options

```elixir
# Query with sort key conditions
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-", 
    sk_operator: :begins_with,
    scan_index_forward: false  # Descending order
  ]
)

# Query with filter expressions
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    filter_expression: "price > :min_price",
    expression_attribute_values: %{
      ":min_price" => %{"N" => "500"}
    }
  ]
)
```

#### Pagination

```elixir
# First page
{:ok, page_1} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [limit: 10]
)

# Next page
{:ok, page_2} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    limit: 10,
    exclusive_start_key: page_1.last_evaluated_key
  ]
)
```

### Batch Operations

#### Batch Write

```elixir
products = [
  %MyApp.Product{category_id: "electronics", product_id: "prod-123", name: "Smartphone", price: 599.99},
  %MyApp.Product{category_id: "electronics", product_id: "prod-124", name: "Laptop", price: 1299.99},
  %MyApp.Product{category_id: "electronics", product_id: "prod-125", name: "Tablet", price: 399.99}
]

{:ok, result} = Dynamo.Table.batch_write_item(products)
```

#### Parallel Scan

For large tables, parallel scan can significantly improve performance:

```elixir
{:ok, all_products} = Dynamo.Table.parallel_scan(
  MyApp.Product,
  segments: 8,
  filter_expression: "category_id = :category",
  expression_attribute_values: %{
    ":category" => %{"S" => "electronics"}
  }
)
```

### Advanced Queries

#### Global Secondary Indexes

```elixir
# Query a GSI
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{name: "Smartphone"},
  [
    index_name: "NameIndex",
    consistent_read: false
  ]
)
```

#### Projection Expressions

```elixir
# Retrieve only specific attributes
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    projection_expression: "product_id, name, price"
  ]
)
```

## Configuration

Dynamo provides a flexible configuration system with three levels:

### 1. Application Configuration

In your `config.exs`:

```elixir
config :dynamo,
  partition_key_name: "pk",
  sort_key_name: "sk",
  key_separator: "#",
  suffix_partition_key: true,
  prefix_sort_key: false,
  table_has_sort_key: true
```

### 2. Process-level Configuration

For runtime configuration:

```elixir
# Set configuration for the current process
Dynamo.Config.put_process_config(key_separator: "-")

# Clear process configuration
Dynamo.Config.clear_process_config()
```

### 3. Schema-level Configuration

Per-schema configuration:

```elixir
defmodule MyApp.User do
  use Dynamo.Schema,
    key_separator: "_",
    prefix_sort_key: true,
    suffix_partition_key: false
    
  # schema definition...
end
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `partition_key_name` | Name of the partition key in DynamoDB | `"pk"` |
| `sort_key_name` | Name of the sort key in DynamoDB | `"sk"` |
| `key_separator` | Separator for composite keys | `"#"` |
| `suffix_partition_key` | Whether to add entity type suffix to partition key | `true` |
| `prefix_sort_key` | Whether to include field name as prefix in sort key | `false` |
| `table_has_sort_key` | Whether the table has a sort key | `true` |

## Advanced Usage

### Custom Key Generation

You can override the `before_write` function to customize how keys are generated:

```elixir
defmodule MyApp.TimeSeries do
  use Dynamo.Schema

  item do
    table_name "time_series"
    
    field :device_id, partition_key: true
    field :timestamp, sort_key: true
    field :value
  end
  
  def before_write(item) do
    # Add current timestamp if not provided
    item = if is_nil(item.timestamp) do
      %{item | timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}
    else
      item
    end
    
    # Call the default implementation
    item
    |> Dynamo.Schema.generate_and_add_partition_key()
    |> Dynamo.Schema.generate_and_add_sort_key()
    |> Dynamo.Encoder.encode_root()
  end
end
```

### Custom Encoding/Decoding

You can implement the `Dynamo.Encodable` and `Dynamo.Decodable` protocols for custom types:

```elixir
defimpl Dynamo.Encodable, for: MyApp.CustomType do
  def encode(value, _options) do
    # Convert your custom type to a DynamoDB-compatible format
    %{"S" => to_string(value)}
  end
end

defimpl Dynamo.Decodable, for: MyApp.CustomType do
  def decode(value) do
    # Convert from DynamoDB format back to your custom type
    MyApp.CustomType.from_string(value)
  end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
