# Dynamo

[![Hex.pm](https://img.shields.io/hexpm/v/dynamo.svg)](https://hex.pm/packages/dynamo)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/dynamo)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> An elegant, Ecto-inspired DSL for working with DynamoDB in Elixir

Dynamo provides a structured, type-safe way to interact with Amazon DynamoDB while maintaining the flexibility that makes DynamoDB powerful. Define schemas with compile-time validation, encode/decode data automatically, and perform complex operations with a clean, familiar syntax inspired by Elixir's Ecto library.

Whether you're building a new application or migrating existing DynamoDB code, Dynamo helps you write more maintainable and robust code by bringing structure and type safety to your DynamoDB interactions without sacrificing the flexibility and performance that make DynamoDB powerful.

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

DynamoDB is a powerful, flexible NoSQL database, but its schema-free nature can lead to inconsistencies in your data model and verbose, error-prone code. Dynamo bridges this gap by providing:

- **Type Safety**: Define schemas with compile-time field validation that enforce data consistency across your application. Catch errors early in development rather than at runtime.

- **Familiar Syntax**: Ecto-inspired DSL that feels natural to Elixir developers. If you've used Ecto, you'll feel right at home with Dynamo's schema definitions and query patterns.

- **Simplified Operations**: Clean abstractions for common DynamoDB operations eliminate boilerplate code. Instead of manually constructing DynamoDB request payloads, work with native Elixir structs and let Dynamo handle the translation.

- **Flexible Configuration**: Multiple levels of configuration (application-wide, process-level, and schema-specific) give you fine-grained control over key generation, table naming conventions, and DynamoDB-specific settings.

- **Performance Optimizations**: Built-in support for batch operations and parallel scans allows you to efficiently process large datasets without writing complex concurrent code.

- **Comprehensive Error Handling**: Structured error types with detailed context make debugging and error recovery straightforward, replacing cryptic AWS error messages with actionable Elixir errors.

## Quick Start

Here's a complete example showing how to define a schema and perform basic operations:

```elixir
# 1. Define your schema
defmodule MyApp.User do
  use Dynamo.Schema

  item do
    table_name "users"
    
    # Define fields with their properties
    field :id, partition_key: true      # Primary identifier
    field :email, sort_key: true        # Secondary key for sorting/filtering
    field :name                         # Standard attribute
    field :role, default: "user"        # Field with default value
    field :active, default: true        # Boolean field with default
    field :created_at                   # Timestamp field
  end
end

# 2. Create and save a user
user = %MyApp.User{
  id: "user-123", 
  email: "john@example.com", 
  name: "John Doe",
  created_at: DateTime.utc_now() |> DateTime.to_iso8601()
}

{:ok, saved_user} = MyApp.User.put_item(user)
# => {:ok, %MyApp.User{id: "user-123", email: "john@example.com", ...}}

# 3. Retrieve a specific user by primary key
{:ok, retrieved_user} = MyApp.User.get_item(%MyApp.User{
  id: "user-123", 
  email: "john@example.com"
})
# => {:ok, %MyApp.User{id: "user-123", email: "john@example.com", name: "John Doe", ...}}

# 4. List all users with a specific partition key
{:ok, users} = MyApp.User.list_items(%MyApp.User{id: "user-123"})
# => {:ok, [%MyApp.User{...}, %MyApp.User{...}]}

# 5. Update a user's information
{:ok, updated_user} = Dynamo.Table.update_item(
  %MyApp.User{id: "user-123", email: "john@example.com"},
  %{name: "John Smith", role: "admin"},
  return_values: "ALL_NEW"
)
# => {:ok, %MyApp.User{id: "user-123", name: "John Smith", role: "admin", ...}}

# 6. Delete a user
{:ok, _} = Dynamo.Table.delete_item(%MyApp.User{
  id: "user-123", 
  email: "john@example.com"
})
# => {:ok, nil}
```

That's all you need to get started! Dynamo handles key generation, encoding/decoding, and AWS API interactions automatically.

## Key Concepts

Understanding these core concepts will help you make the most of Dynamo:

### Schema Definition

Dynamo uses a schema-based approach to define the structure of your DynamoDB items, similar to how Ecto defines database schemas. This provides several benefits:

- **Consistent Structure**: All items of the same type follow the same structure, preventing data inconsistencies
- **Default Values**: Specify default values that are automatically applied when creating new items
- **Key Generation**: Automatically generate composite partition and sort keys based on your field definitions
- **Type Conversion**: Automatic bidirectional conversion between Elixir types (strings, numbers, maps, lists, etc.) and DynamoDB types (S, N, M, L, etc.)
- **Compile-time Validation**: Catch schema definition errors during compilation rather than at runtime

Schemas are defined using the `item` block, where you specify your table name, fields, and key structure.

### Key Management

DynamoDB uses partition keys and sort keys to organize and retrieve data efficiently. Dynamo simplifies key management by automatically generating composite keys from your schema fields:

- **Partition Keys**: Define which field(s) make up the partition key (also called the hash key). This determines how DynamoDB distributes your data across partitions. Dynamo can generate composite partition keys from multiple fields.

- **Sort Keys**: Define which field(s) make up the sort key (also called the range key). Items with the same partition key are sorted by this value, enabling efficient range queries. Like partition keys, sort keys can be composite.

- **Composite Keys**: Combine multiple fields into a single key string with configurable separators. For example, fields `tenant: "acme"` and `user_id: "123"` might become partition key `"tenant#acme#user_id#123#user"`.

- **Key Customization**: Control key generation behavior through configuration options like `key_separator`, `suffix_partition_key`, and `prefix_sort_key`.

### Configuration Levels

Dynamo provides three hierarchical levels of configuration, allowing you to set defaults globally while overriding them for specific contexts:

1. **Application Configuration**: Global defaults defined in your `config.exs` file. These apply to all schemas unless overridden.

2. **Process Configuration**: Runtime overrides that apply only to the current process. Useful for multi-tenant applications or when you need different settings in different contexts (e.g., tests vs. production).

3. **Schema Configuration**: Schema-specific settings passed as options to `use Dynamo.Schema`. These take precedence over application and process settings, allowing fine-grained control per schema.

The configuration hierarchy means schema config > process config > application config > defaults, giving you maximum flexibility while maintaining sensible defaults.

## Usage Guide

### Defining Schemas

A schema defines the structure of your DynamoDB items using an intuitive DSL. Here's a comprehensive example:

```elixir
defmodule MyApp.Product do
  use Dynamo.Schema, key_separator: "_"

  item do
    table_name "products"
    
    # Partition key field - used to distribute data
    field :category_id, partition_key: true
    
    # Sort key field - used for sorting and range queries
    field :product_id, sort_key: true
    
    # Standard fields
    field :name
    field :description
    field :price
    field :currency, default: "USD"
    
    # Fields with default values
    field :stock, default: 0
    field :active, default: true
    field :tags, default: []
    
    # Timestamp fields
    field :created_at
    field :updated_at
  end
end
```

**Key Points:**
- Fields marked with `partition_key: true` form the partition key
- Fields marked with `sort_key: true` form the sort key
- Default values are applied when creating new structs
- The `key_separator` option controls how composite keys are joined (default is `"#"`)

#### Field Options

Each field supports the following options:

- `partition_key: true` - Marks the field as part of the partition key
- `sort_key: true` - Marks the field as part of the sort key  
- `default: value` - Sets a default value for the field when creating new structs

```elixir
field :status, default: "pending"          # String default
field :count, default: 0                   # Number default
field :enabled, default: true              # Boolean default
field :metadata, default: %{}              # Map default
field :tags, default: []                   # List default
```

#### Alternative Key Definition

You can also define partition and sort keys separately from field definitions, which is useful when you want to create composite keys from multiple fields:

```elixir
defmodule MyApp.Order do
  use Dynamo.Schema

  item do
    table_name "orders"
    
    # Define all fields first
    field :customer_id
    field :order_date
    field :order_id
    field :status, default: "pending"
    field :total
    field :items, default: []
    
    # Define composite partition key from multiple fields
    # This creates a key like: "customer_id#C123#order_date#2024-01-15"
    partition_key [:customer_id, :order_date]
    
    # Simple sort key from single field
    sort_key [:order_id]
  end
end
```

**When to use separate key definition:**
- Creating composite keys from multiple fields
- When field order in the key doesn't match declaration order
- For clarity when dealing with complex key structures

**Example of composite key generation:**
```elixir
order = %MyApp.Order{
  customer_id: "C123",
  order_date: "2024-01-15",
  order_id: "ORD-456"
}

# Dynamo generates:
# pk: "customer_id#C123#order_date#2024-01-15#order"
# sk: "order_id#ORD-456"
```

### Working with Items

#### Creating Items

Creating and saving items to DynamoDB is straightforward with Dynamo:

```elixir
# Create a product struct with your data
product = %MyApp.Product{
  category_id: "electronics",
  product_id: "prod-123",
  name: "Wireless Headphones",
  description: "Premium noise-cancelling headphones",
  price: 299.99,
  currency: "USD",
  stock: 50,
  tags: ["audio", "wireless", "premium"],
  created_at: DateTime.utc_now() |> DateTime.to_iso8601()
}

# Save to DynamoDB - Dynamo handles encoding and key generation
{:ok, saved_product} = MyApp.Product.put_item(product)

# Or use the alias
{:ok, saved_product} = Dynamo.Table.insert(product)

# With conditional expression (only create if it doesn't exist)
{:ok, new_product} = MyApp.Product.put_item(
  product,
  condition_expression: "attribute_not_exists(pk)"
)
```

**Behind the scenes**, Dynamo:
1. Generates partition and sort keys from your fields
2. Encodes all fields to DynamoDB format (strings → S, numbers → N, etc.)
3. Executes the PutItem operation
4. Decodes the response back to your struct

#### Retrieving Items

Retrieve items using their primary key (partition key + sort key):

```elixir
# Get a specific product by its primary key
{:ok, product} = MyApp.Product.get_item(%MyApp.Product{
  category_id: "electronics",
  product_id: "prod-123"
})

# Returns {:ok, %MyApp.Product{...}} if found
# Returns {:ok, nil} if not found

# With consistent read for strongly consistent data
{:ok, product} = MyApp.Product.get_item(
  %MyApp.Product{category_id: "electronics", product_id: "prod-123"},
  consistent_read: true
)

# Retrieve only specific attributes to reduce read cost
{:ok, product} = MyApp.Product.get_item(
  %MyApp.Product{category_id: "electronics", product_id: "prod-123"},
  projection_expression: "product_id, name, price, stock"
)

# Handle the result with pattern matching
case MyApp.Product.get_item(%MyApp.Product{category_id: "electronics", product_id: "prod-123"}) do
  {:ok, nil} -> 
    IO.puts("Product not found")
    
  {:ok, product} -> 
    IO.puts("Found product: #{product.name}")
    
  {:error, error} -> 
    IO.puts("Error: #{error.message}")
end
```

#### Encoding and Decoding

Dynamo automatically handles the conversion between Elixir types and DynamoDB types. You typically don't need to work with encoding/decoding directly, but it's available when you need low-level control:

```elixir
product = %MyApp.Product{
  category_id: "electronics",
  product_id: "prod-123",
  name: "Laptop",
  price: 1299.99,
  tags: ["computer", "portable"]
}

# Encode a struct to DynamoDB format
# Returns: %{"M" => %{"category_id" => %{"S" => "electronics"}, ...}}
dynamo_item = Dynamo.Encoder.encode_root(product)

# Decode a DynamoDB item to a plain map
decoded_map = Dynamo.Decoder.decode(dynamo_item)
# Returns: %{category_id: "electronics", product_id: "prod-123", ...}

# Decode a DynamoDB item to a specific struct type
decoded_product = Dynamo.Decoder.decode(dynamo_item, as: MyApp.Product)
# Returns: %MyApp.Product{category_id: "electronics", ...}

# This is useful when:
# - Working directly with AWS SDK responses
# - Implementing custom data processing pipelines
# - Debugging data format issues
# - Building custom import/export tools
```

**Supported type conversions:**
- String ↔ `%{"S" => "value"}`
- Number ↔ `%{"N" => "123"}`
- Boolean ↔ `%{"BOOL" => true}`
- Map ↔ `%{"M" => %{...}}`
- List ↔ `%{"L" => [...]}`
- Binary ↔ `%{"B" => binary}`
- String Set ↔ `%{"SS" => [...]}`
- Number Set ↔ `%{"NS" => [...]}`
- Null ↔ `%{"NULL" => true}`

### Querying Data

#### Basic Queries

List all items that share the same partition key:

```elixir
# List all products in the "electronics" category
{:ok, products} = MyApp.Product.list_items(%MyApp.Product{category_id: "electronics"})
# Returns all items with partition key matching "electronics"

# The result is a list of structs
Enum.each(products, fn product ->
  IO.puts("#{product.name}: $#{product.price}")
end)
```

#### Query Options

Dynamo supports a wide range of DynamoDB query capabilities through a clean options interface:

```elixir
# Query with sort key prefix match (begins_with)
# Finds all products starting with "prod-1"
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-1", 
    sk_operator: :begins_with
  ]
)

# Query with sort key comparison operators
# Finds products created after a specific ID
{:ok, recent_products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-1000",
    sk_operator: :gt  # Greater than
  ]
)

# Other comparison operators: :lt, :lte, :gte
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-500",
    sk_operator: :gte  # Greater than or equal
  ]
)

# Query with BETWEEN operator for range queries
{:ok, range_products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-100",
    sk_operator: :between,
    sk_end: "prod-200"
  ]
)

# Reverse sort order (descending)
{:ok, products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    scan_index_forward: false  # false = descending order
  ]
)

# Query with filter expression (applied after retrieving items)
# Note: Filters don't reduce read costs, but reduce data transfer
{:ok, expensive_products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    filter_expression: "price > :min_price AND stock > :min_stock",
    expression_attribute_values: %{
      ":min_price" => %{"N" => "500"},
      ":min_stock" => %{"N" => "10"}
    }
  ]
)

# Combine multiple options for complex queries
{:ok, filtered_products} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [
    sort_key: "prod-1",
    sk_operator: :begins_with,
    scan_index_forward: false,
    filter_expression: "active = :active AND price < :max_price",
    expression_attribute_values: %{
      ":active" => %{"BOOL" => true},
      ":max_price" => %{"N" => "1000"}
    },
    limit: 50
  ]
)
```

**Available sort key operators:**
- `:full_match` - Exact match (default if operator not specified)
- `:begins_with` - Prefix match
- `:gt` - Greater than
- `:lt` - Less than
- `:gte` - Greater than or equal
- `:lte` - Less than or equal
- `:between` - Range between two values (requires `:sk_end`)

#### Pagination

DynamoDB paginates query results automatically. Dynamo makes it easy to implement pagination in your application:

```elixir
# First page - retrieve initial batch of items
{:ok, page_1} = MyApp.Product.list_items(
  %MyApp.Product{category_id: "electronics"},
  [limit: 10]
)

# Check if there are more results
case page_1.last_evaluated_key do
  nil -> 
    IO.puts("No more pages")
    
  last_key ->
    # Retrieve the next page using the last evaluated key
    {:ok, page_2} = MyApp.Product.list_items(
      %MyApp.Product{category_id: "electronics"},
      [
        limit: 10,
        exclusive_start_key: last_key
      ]
    )
end

# Example: Paginate through all results
defmodule ProductPaginator do
  def fetch_all_pages(category_id, acc \\ [], last_key \\ nil) do
    opts = [limit: 100] ++ if last_key, do: [exclusive_start_key: last_key], else: []
    
    case MyApp.Product.list_items(%MyApp.Product{category_id: category_id}, opts) do
      {:ok, %{items: items, last_evaluated_key: nil}} ->
        # Last page reached
        {:ok, acc ++ items}
        
      {:ok, %{items: items, last_evaluated_key: last_key}} ->
        # More pages available
        fetch_all_pages(category_id, acc ++ items, last_key)
        
      {:error, error} ->
        {:error, error}
    end
  end
end

# Use the paginator
{:ok, all_products} = ProductPaginator.fetch_all_pages("electronics")
IO.puts("Retrieved #{length(all_products)} total products")
```

**Pagination Tips:**
- Use appropriate `limit` values to balance latency and throughput
- Store `last_evaluated_key` for stateless pagination (e.g., in URLs or session data)
- DynamoDB's limit applies to items scanned, not items returned (filters applied after)
- Consider using parallel scans for large table scans (see Advanced Queries)

### Batch Operations

Batch operations allow you to efficiently process multiple items in a single request, reducing network overhead and improving throughput.

#### Batch Write

Write multiple items to DynamoDB in a single request. Dynamo automatically handles AWS's 25-item batch limit by chunking larger batches:

```elixir
# Create multiple products
products = [
  %MyApp.Product{
    category_id: "electronics", 
    product_id: "prod-123", 
    name: "Smartphone", 
    price: 599.99,
    stock: 100
  },
  %MyApp.Product{
    category_id: "electronics", 
    product_id: "prod-124", 
    name: "Laptop", 
    price: 1299.99,
    stock: 50
  },
  %MyApp.Product{
    category_id: "electronics", 
    product_id: "prod-125", 
    name: "Tablet", 
    price: 399.99,
    stock: 75
  }
]

# Write all products in a batch
{:ok, result} = Dynamo.Table.batch_write_item(products)

# Check the result
IO.puts("Successfully wrote #{result.processed_items} items")
if length(result.unprocessed_items) > 0 do
  IO.puts("Failed to write #{length(result.unprocessed_items)} items")
  # Retry unprocessed items
  {:ok, retry_result} = Dynamo.Table.batch_write_item(result.unprocessed_items)
end

# Batch write handles large batches automatically (splits into chunks of 25)
large_batch = Enum.map(1..150, fn i ->
  %MyApp.Product{
    category_id: "electronics",
    product_id: "prod-#{i}",
    name: "Product #{i}",
    price: 100.0 + i,
    stock: i * 2
  }
end)

{:ok, result} = Dynamo.Table.batch_write_item(large_batch)
IO.puts("Processed #{result.processed_items} items across multiple batches")
```

**Important Notes:**
- All items must belong to the same table
- DynamoDB limits batches to 25 items per request (Dynamo handles chunking automatically)
- Batch writes are not atomic - some items may succeed while others fail
- Check `unprocessed_items` and implement retry logic for failed items
- Total request size cannot exceed 16 MB

#### Batch Get

Retrieve multiple items efficiently in a single request:

```elixir
# Define the items you want to retrieve (only keys needed)
items_to_fetch = [
  %MyApp.Product{category_id: "electronics", product_id: "prod-123"},
  %MyApp.Product{category_id: "electronics", product_id: "prod-124"},
  %MyApp.Product{category_id: "electronics", product_id: "prod-125"}
]

# Fetch all items in one request
{:ok, result} = Dynamo.Table.batch_get_item(items_to_fetch)

# Process retrieved items
Enum.each(result.items, fn product ->
  IO.puts("Retrieved: #{product.name} - $#{product.price}")
end)

# Check for items that couldn't be retrieved
if length(result.unprocessed_keys) > 0 do
  IO.puts("#{length(result.unprocessed_keys)} items couldn't be retrieved")
  # Retry unprocessed items if needed
  {:ok, retry_result} = Dynamo.Table.batch_get_item(result.unprocessed_keys)
end

# With consistent reads
{:ok, result} = Dynamo.Table.batch_get_item(items_to_fetch, consistent_read: true)

# Retrieve only specific attributes
{:ok, result} = Dynamo.Table.batch_get_item(
  items_to_fetch,
  projection_expression: "product_id, name, price"
)
```

**Important Notes:**
- DynamoDB limits batch gets to 100 items per request (Dynamo handles chunking)
- All items must belong to the same table
- Items are returned in no particular order
- Missing items are simply not included in the results
- Check `unprocessed_keys` and retry if necessary

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

Dynamo provides a flexible three-tier configuration system that allows you to set global defaults while maintaining the ability to override them for specific contexts or schemas.

### Configuration Hierarchy

Configuration is resolved in the following order (later overrides earlier):

1. **Default values** - Built into Dynamo
2. **Application configuration** - Defined in `config.exs`
3. **Process configuration** - Set at runtime for the current process
4. **Schema configuration** - Specified when defining a schema

### 1. Application Configuration

Set global defaults in your `config/config.exs` file:

```elixir
config :dynamo,
  # Key naming in DynamoDB
  partition_key_name: "pk",
  sort_key_name: "sk",
  
  # Key generation format
  key_separator: "#",              # Character(s) used to join key parts
  suffix_partition_key: true,      # Add entity type to partition key
  prefix_sort_key: false,          # Include field names in sort key
  
  # Table configuration
  table_has_sort_key: true         # Whether tables use sort keys
```

**Configuration Options Explained:**

- **`partition_key_name`** (default: `"pk"`): The attribute name for the partition key in your DynamoDB tables. Use consistent naming across tables for easier management.

- **`sort_key_name`** (default: `"sk"`): The attribute name for the sort key. Following a naming convention simplifies table design and GSI creation.

- **`key_separator`** (default: `"#"`): The character(s) used to join multiple field values in composite keys. Choose a separator that won't appear in your data (common choices: `"#"`, `"|"`, `"::"`, `"_"`).

- **`suffix_partition_key`** (default: `true`): When true, adds the entity type (lowercased schema name) to the partition key. This enables single-table design patterns where different entity types share the same table.
  ```elixir
  # With suffix_partition_key: true
  # User{id: "123"} → pk: "id#123#user"
  
  # With suffix_partition_key: false
  # User{id: "123"} → pk: "id#123"
  ```

- **`prefix_sort_key`** (default: `false`): When true, includes field names as prefixes in the sort key. Useful for creating hierarchical sort key patterns.
  ```elixir
  # With prefix_sort_key: false
  # {created_at: "2024-01-15", id: "123"} → sk: "2024-01-15#123"
  
  # With prefix_sort_key: true
  # {created_at: "2024-01-15", id: "123"} → sk: "created_at#2024-01-15#id#123"
  ```

- **`table_has_sort_key`** (default: `true`): Indicates whether your tables use sort keys. Set to `false` for tables with only partition keys.

### 2. Process-level Configuration

Override configuration at runtime for specific processes. This is useful for:
- Multi-tenant applications with different key formats per tenant
- Testing scenarios requiring different configurations
- Background jobs that need special settings

```elixir
# Set configuration for the current process
Dynamo.Config.put_process_config(
  key_separator: "-",
  suffix_partition_key: false
)

# Perform operations with the process-specific config
{:ok, user} = MyApp.User.put_item(%MyApp.User{id: "123"})

# Clear process configuration (reverts to application config)
Dynamo.Config.clear_process_config()

# Example: Multi-tenant configuration
defmodule MyApp.TenantConfig do
  def with_tenant_config(tenant_id, fun) do
    # Configure based on tenant
    case tenant_id do
      "tenant_a" ->
        Dynamo.Config.put_process_config(key_separator: "_")
      "tenant_b" ->
        Dynamo.Config.put_process_config(key_separator: "::")
      _ ->
        :ok
    end
    
    # Execute the function with tenant config
    result = fun.()
    
    # Clean up
    Dynamo.Config.clear_process_config()
    
    result
  end
end

# Use it
MyApp.TenantConfig.with_tenant_config("tenant_a", fn ->
  MyApp.User.put_item(%MyApp.User{id: "user-123"})
end)
```

### 3. Schema-level Configuration

Override settings per schema for fine-grained control:

```elixir
defmodule MyApp.User do
  use Dynamo.Schema,
    key_separator: "_",         # Use underscore for this schema only
    prefix_sort_key: true,       # Include field names in sort key
    suffix_partition_key: false  # No entity type suffix

  item do
    table_name "users"
    
    field :tenant_id, partition_key: true
    field :user_id, sort_key: true
    field :name
  end
end

# With this configuration:
# %User{tenant_id: "acme", user_id: "123"} generates:
# pk: "tenant_id_acme"  (no suffix due to suffix_partition_key: false)
# sk: "user_id_123"     (with prefix due to prefix_sort_key: true)

# Compare to a different schema with different config
defmodule MyApp.Product do
  use Dynamo.Schema,
    key_separator: "#",
    prefix_sort_key: false,
    suffix_partition_key: true

  item do
    table_name "products"
    
    field :category, partition_key: true
    field :product_id, sort_key: true
    field :name
    field :price
  end
end

# %Product{category: "electronics", product_id: "P123"} generates:
# pk: "category#electronics#product"  (with suffix)
# sk: "P123"                          (no prefix)
```

**When to use schema-level configuration:**
- Different tables have different key formats
- Specific schemas need special handling
- Migrating from another key format gradually
- Supporting legacy table structures

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `partition_key_name` | Name of the partition key in DynamoDB | `"pk"` |
| `sort_key_name` | Name of the sort key in DynamoDB | `"sk"` |
| `key_separator` | Separator for composite keys | `"#"` |
| `suffix_partition_key` | Whether to add entity type suffix to partition key | `true` |
| `prefix_sort_key` | Whether to include field name as prefix in sort key | `false` |
| `table_has_sort_key` | Whether the table has a sort key | `true` |

## Command Line Interface

Dynamo provides several mix tasks to help you work with DynamoDB tables:

### Creating Tables

```bash
# Create a table with default configuration (pk/sk keys)
mix dynamo.create_table users

# Create a table with custom keys
mix dynamo.create_table products --partition-key category_id --sort-key product_id

# Create a table with only a partition key (no sort key)
mix dynamo.create_table simple_counter --partition-key counter_id --no-sort-key

# Create a table with provisioned capacity
mix dynamo.create_table high_traffic --billing-mode PROVISIONED --read-capacity 50 --write-capacity 25

# Use with local DynamoDB
mix dynamo.create_table local_test --endpoint http://localhost:8000
```

### Listing Tables

```bash
# List all tables
mix dynamo.list_tables

# Filter tables by name
mix dynamo.list_tables --name-contains user

# List tables in a specific region
mix dynamo.list_tables --region eu-west-1
```

### Deleting Tables

```bash
# Delete a table (will prompt for confirmation)
mix dynamo.delete_table old_users

# Force delete without confirmation
mix dynamo.delete_table old_users --force
```

### Generating Schemas

```bash
# Generate a schema from an existing table
mix dynamo.generate_schema users

# Generate a schema with a specific module name
mix dynamo.generate_schema users --module MyApp.User

# Generate a schema with a custom output path
mix dynamo.generate_schema users --output lib/schemas/user.ex
```

## Transaction Support

Dynamo provides comprehensive support for DynamoDB transactions, enabling you to perform multiple operations atomically. This ensures data consistency across related items, even when they span multiple tables.

### Why Use Transactions?

Transactions are essential when you need to:
- Maintain consistency across multiple items (e.g., transferring money between accounts)
- Implement optimistic locking with conditional updates
- Ensure related data is created or deleted together
- Prevent race conditions in concurrent environments

### Transaction Operations

Transactions support four types of operations that can be combined:

#### 1. Put Operations
Create or replace items with optional conditions:

```elixir
# Simple put
{:put, %User{id: "user-123", name: "John Doe", email: "john@example.com"}}

# Conditional put (only if item doesn't exist)
{:put, %User{id: "user-123", name: "John Doe"},
  "attribute_not_exists(pk)",  # Condition expression
  nil}  # Optional expression attributes
```

#### 2. Update Operations
Modify specific attributes with special operators:

```elixir
# Simple update
{:update, %Account{id: "account-123"}, 
  %{balance: 1000.00, last_updated: DateTime.utc_now()}}

# Increment a counter
{:update, %Statistics{id: "stats-1"},
  %{view_count: {:increment, 1}}}

# Decrement inventory
{:update, %Product{id: "prod-123"},
  %{stock: {:decrement, 5}}}

# Append to a list
{:update, %User{id: "user-123"},
  %{order_ids: {:append, ["order-789"]}}}

# Prepend to a list  
{:update, %Feed{user_id: "user-123"},
  %{recent_items: {:prepend, [%{type: "post", id: "123"}]}}}

# Set value only if it doesn't exist
{:update, %User{id: "user-123"},
  %{created_at: {:if_not_exists, DateTime.utc_now()}}}
```

#### 3. Delete Operations
Remove items with optional conditions:

```elixir
# Simple delete
{:delete, %Session{id: "session-456"}}

# Conditional delete (only if session expired)
{:delete, %Session{id: "session-456"},
  "expires_at < :now",
  %{
    expression_attribute_values: %{
      ":now" => %{"S" => DateTime.utc_now() |> DateTime.to_iso8601()}
    }
  }}
```

#### 4. Check Operations
Verify conditions without modifying data:

```elixir
# Check that an account has sufficient balance
{:check, %Account{id: "account-123"},
  "balance >= :required_amount",
  %{
    expression_attribute_values: %{
      ":required_amount" => %{"N" => "100.00"}
    }
  }}

# Check that user is active
{:check, %User{id: "user-123"},
  "active = :active_val AND status = :status_val",
  %{
    expression_attribute_values: %{
      ":active_val" => %{"BOOL" => true},
      ":status_val" => %{"S" => "verified"}
    }
  }}
```

### Complete Transaction Examples

#### Example 1: Money Transfer Between Accounts

```elixir
# Transfer $100 from one account to another atomically
def transfer_money(source_id, dest_id, amount) do
  Dynamo.Transaction.transact([
    # 1. Verify source account has sufficient funds
    {:check, %Account{id: source_id},
      "balance >= :amount AND active = :active",
      %{
        expression_attribute_values: %{
          ":amount" => %{"N" => Float.to_string(amount)},
          ":active" => %{"BOOL" => true}
        }
      }},

    # 2. Verify destination account is active
    {:check, %Account{id: dest_id},
      "active = :active",
      %{
        expression_attribute_values: %{
          ":active" => %{"BOOL" => true}
        }
      }},

    # 3. Deduct from source account
    {:update, %Account{id: source_id},
      %{
        balance: {:decrement, amount},
        last_transaction: DateTime.utc_now() |> DateTime.to_iso8601()
      }},

    # 4. Add to destination account
    {:update, %Account{id: dest_id},
      %{
        balance: {:increment, amount},
        last_transaction: DateTime.utc_now() |> DateTime.to_iso8601()
      }},

    # 5. Record the transaction
    {:put, %Transaction{
      id: UUID.uuid4(),
      from_account: source_id,
      to_account: dest_id,
      amount: amount,
      timestamp: DateTime.utc_now(),
      status: "completed"
    }}
  ])
end

# Execute the transfer
case transfer_money("account-123", "account-456", 100.00) do
  {:ok, _result} ->
    IO.puts("Transfer completed successfully")

  {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
    IO.puts("Transfer failed: Insufficient funds or inactive account")

  {:error, error} ->
    IO.puts("Transfer failed: #{error.message}")
end
```

#### Example 2: Order Processing

```elixir
# Create an order and update inventory atomically
def process_order(user_id, product_id, quantity) do
  order_id = UUID.uuid4()
  
  Dynamo.Transaction.transact([
    # 1. Check product is in stock
    {:check, %Product{id: product_id},
      "stock >= :quantity AND active = :active",
      %{
        expression_attribute_values: %{
          ":quantity" => %{"N" => Integer.to_string(quantity)},
          ":active" => %{"BOOL" => true}
        }
      }},

    # 2. Decrease product inventory
    {:update, %Product{id: product_id},
      %{
        stock: {:decrement, quantity},
        sold_count: {:increment, quantity}
      }},

    # 3. Create the order
    {:put, %Order{
      id: order_id,
      user_id: user_id,
      product_id: product_id,
      quantity: quantity,
      status: "pending",
      created_at: DateTime.utc_now()
    }},

    # 4. Add order to user's order history
    {:update, %User{id: user_id},
      %{
        orders: {:append, [order_id]},
        order_count: {:increment, 1}
      }}
  ])
end
```

#### Example 3: Idempotent User Registration

```elixir
# Create a user and related records atomically, only if user doesn't exist
def register_user(user_id, email, name) do
  Dynamo.Transaction.transact([
    # 1. Create user (fails if already exists)
    {:put, %User{id: user_id, email: email, name: name, active: true},
      "attribute_not_exists(pk)",  # Only create if doesn't exist
      nil},

    # 2. Create user profile
    {:put, %Profile{
      user_id: user_id,
      bio: "",
      avatar_url: nil,
      created_at: DateTime.utc_now()
    }},

    # 3. Initialize user preferences
    {:put, %Preferences{
      user_id: user_id,
      notifications_enabled: true,
      theme: "light",
      language: "en"
    }},

    # 4. Add to email index for uniqueness
    {:put, %EmailIndex{email: email, user_id: user_id},
      "attribute_not_exists(pk)",
      nil}
  ])
end

# Usage with error handling
case register_user("user-123", "john@example.com", "John Doe") do
  {:ok, _} ->
    IO.puts("User registered successfully")

  {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
    IO.puts("User already exists")

  {:error, error} ->
    IO.puts("Registration failed: #{error.message}")
end
```

## Error Handling

Dynamo provides comprehensive error handling that converts DynamoDB errors into structured, meaningful Elixir errors. All operations return `{:ok, result}` or `{:error, %Dynamo.Error{}}` tuples, making error handling consistent and predictable.

### Error Structure

Every error is a `Dynamo.Error` struct containing:

```elixir
%Dynamo.Error{
  type: :resource_not_found,     # Categorized error type
  message: "Table 'users' not found",  # Human-readable description
  details: %{...}                 # Additional context and metadata
}
```

### Common Error Types

#### :resource_not_found
The requested table, item, or resource doesn't exist:

```elixir
case Dynamo.Table.get_item(%User{id: "nonexistent"}) do
  {:ok, nil} -> 
    # Item doesn't exist (not an error)
    IO.puts("User not found")
    
  {:error, %Dynamo.Error{type: :resource_not_found}} ->
    # Table doesn't exist (error condition)
    IO.puts("Table not found - check configuration")
end
```

#### :provisioned_throughput_exceeded
Rate limits exceeded - too many requests:

```elixir
case Dynamo.Table.put_item(user) do
  {:error, %Dynamo.Error{type: :provisioned_throughput_exceeded} = error} ->
    # Implement exponential backoff retry
    :timer.sleep(100)
    retry_put_item(user, attempts - 1)
    
  result -> result
end
```

#### :conditional_check_failed
A condition expression evaluated to false:

```elixir
case Dynamo.Table.put_item(
  user,
  condition_expression: "attribute_not_exists(pk)"
) do
  {:ok, user} ->
    IO.puts("User created successfully")
    
  {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
    IO.puts("User already exists")
    # Handle duplicate creation attempt
end
```

#### :validation_error
Invalid parameters or configuration:

```elixir
case Dynamo.Table.put_item(%InvalidStruct{}) do
  {:error, %Dynamo.Error{type: :validation_error, message: msg}} ->
    IO.puts("Configuration error: #{msg}")
    # Fix schema definition or parameters
end
```

#### :access_denied
Insufficient IAM permissions:

```elixir
case Dynamo.Table.put_item(user) do
  {:error, %Dynamo.Error{type: :access_denied}} ->
    IO.puts("Permission denied - check IAM policies")
    # Verify AWS credentials and permissions
end
```

#### :transaction_conflict
Transaction conflicts with another operation:

```elixir
case Dynamo.Transaction.transact(operations) do
  {:error, %Dynamo.Error{type: :transaction_conflict}} ->
    # Another operation modified the same item
    # Retry the transaction
    retry_transaction(operations, attempts - 1)
end
```

### Error Handling Patterns

#### Pattern 1: Basic Error Handling

```elixir
case Dynamo.Table.get_item(%User{id: user_id}) do
  {:ok, nil} -> 
    {:error, :user_not_found}
    
  {:ok, user} -> 
    {:ok, user}
    
  {:error, %Dynamo.Error{} = error} ->
    Logger.error("Failed to get user: #{error.message}")
    {:error, :database_error}
end
```

#### Pattern 2: Specific Error Handling

```elixir
def create_user(attrs) do
  case Dynamo.Table.put_item(
    %User{id: attrs.id, email: attrs.email, name: attrs.name},
    condition_expression: "attribute_not_exists(pk)"
  ) do
    {:ok, user} -> 
      {:ok, user}
      
    {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
      {:error, :user_already_exists}
      
    {:error, %Dynamo.Error{type: :validation_error, message: msg}} ->
      {:error, {:validation_failed, msg}}
      
    {:error, %Dynamo.Error{type: :provisioned_throughput_exceeded}} ->
      # Retry with backoff
      :timer.sleep(100)
      create_user(attrs)
      
    {:error, %Dynamo.Error{} = error} ->
      Logger.error("Unexpected error creating user: #{inspect(error)}")
      {:error, :internal_error}
  end
end
```

#### Pattern 3: Retry Logic with Exponential Backoff

```elixir
defmodule RetryHelper do
  @max_attempts 5
  @base_delay 100  # milliseconds

  def with_retry(fun, attempts \\ @max_attempts) do
    case fun.() do
      {:error, %Dynamo.Error{type: :provisioned_throughput_exceeded}} = error ->
        if attempts > 0 do
          delay = @base_delay * :math.pow(2, @max_attempts - attempts)
          :timer.sleep(trunc(delay))
          with_retry(fun, attempts - 1)
        else
          error
        end
        
      result -> 
        result
    end
  end
end

# Usage
RetryHelper.with_retry(fn ->
  Dynamo.Table.put_item(user)
end)
```

#### Pattern 4: Comprehensive Transaction Error Handling

```elixir
def safe_transfer(source_id, dest_id, amount) do
  operations = build_transfer_operations(source_id, dest_id, amount)
  
  case Dynamo.Transaction.transact(operations) do
    {:ok, _result} ->
      {:ok, :transfer_completed}
      
    {:error, %Dynamo.Error{type: :conditional_check_failed}} ->
      # Check which condition failed
      cond do
        !account_has_balance?(source_id, amount) ->
          {:error, :insufficient_funds}
          
        !account_is_active?(source_id) or !account_is_active?(dest_id) ->
          {:error, :inactive_account}
          
        true ->
          {:error, :precondition_failed}
      end
      
    {:error, %Dynamo.Error{type: :transaction_conflict}} ->
      # Retry the transaction
      Logger.info("Transaction conflict, retrying...")
      :timer.sleep(50)
      safe_transfer(source_id, dest_id, amount)
      
    {:error, %Dynamo.Error{type: :provisioned_throughput_exceeded}} ->
      {:error, :rate_limited}
      
    {:error, error} ->
      Logger.error("Transaction failed: #{inspect(error)}")
      {:error, :transaction_failed}
  end
end
```

### Error Logging Best Practices

```elixir
require Logger

# Log errors with context
case Dynamo.Table.put_item(user) do
  {:ok, user} -> 
    {:ok, user}
    
  {:error, error} ->
    Logger.error("""
    Failed to save user
    Error Type: #{error.type}
    Message: #{error.message}
    Details: #{inspect(error.details)}
    User Data: #{inspect(user)}
    """)
    {:error, :save_failed}
end
```

## Advanced Usage

### Using Dynamo with LiveBook

When using Dynamo in LiveBook, you may encounter issues with on-the-fly compiled modules. This is because LiveBook compiles modules in a way that can interfere with protocol implementations like `Dynamo.Encodable`.

To work around this issue, you need to override the `before_write/1` function in each schema module and manually handle the encoding process:

```elixir
defmodule MyApp.Product do
  use Dynamo.Schema
  
  item do
    table_name "products"
    
    field :category_id, partition_key: true
    field :product_id, sort_key: true
    field :name
    field :price
  end
  
  def before_write(arg) do
    arg
    |> IO.inspect() # Optional, useful for debugging
    |> Dynamo.Schema.generate_and_add_partition_key()
    |> Dynamo.Schema.generate_and_add_sort_key()
    |> Dynamo.Encodable.MyApp.Product.encode([])
    |> Map.get("M")
  end
end
```

This approach ensures that your schema modules work correctly in LiveBook by:
1. Generating and adding partition and sort keys
2. Explicitly calling the encode function for your specific module
3. Extracting the "M" (map) field from the encoded result

For a complete example of using Dynamo with LiveBook, see the [DynamoDB Bulk Insert Example](dynamo_bulk_insert_example.livemd) in the repository.

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
