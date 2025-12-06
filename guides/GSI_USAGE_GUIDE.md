# Global Secondary Index (GSI) Usage Guide

This guide provides comprehensive documentation for using Global Secondary Indexes with Dynamo schemas.

## Table of Contents

1. [Overview](#overview)
2. [Defining GSIs](#defining-gsis)
3. [Querying GSIs](#querying-gsis)
4. [Error Handling](#error-handling)
5. [Performance Optimization](#performance-optimization)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)

## Overview

Global Secondary Indexes (GSIs) allow you to query DynamoDB tables using different partition and sort keys than the main table. Dynamo provides seamless GSI support through schema definitions and automatic key resolution.

### Key Benefits

- **Flexible Access Patterns**: Query data using different attributes
- **Automatic Key Resolution**: No manual key management required
- **Consistent API**: Same `list_items/2` function for table and GSI queries
- **Comprehensive Error Handling**: Clear validation and error messages
- **Performance Optimization**: Built-in support for projections and filtering

## Defining GSIs

### Basic GSI Definition

```elixir
defmodule MyApp.User do
  use Dynamo.Schema

  item do
    table_name "users"
    
    field :id, partition_key: true
    field :email
    field :tenant
    field :created_at, sort_key: true
    
    # Partition-only GSI
    global_secondary_index "EmailIndex", partition_key: :email
    
    # Partition + Sort GSI
    global_secondary_index "TenantIndex", 
      partition_key: :tenant, 
      sort_key: :created_at
  end
end
```

### GSI Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `partition_key` | atom | Yes | Field name for GSI partition key |
| `sort_key` | atom | No | Field name for GSI sort key |
| `projection` | atom | No | Projection type (`:all`, `:keys_only`, `:include`) |
| `projected_attributes` | list | No | Attributes to include when projection is `:include` |

### Projection Types

#### `:all` (Default)
Projects all attributes from the main table.

```elixir
global_secondary_index "EmailIndex", 
  partition_key: :email,
  projection: :all
```

#### `:keys_only`
Projects only key attributes (table keys + GSI keys).

```elixir
global_secondary_index "StatusIndex",
  partition_key: :status,
  projection: :keys_only
```

#### `:include`
Projects specific attributes plus key attributes.

```elixir
global_secondary_index "TenantEmailIndex",
  partition_key: :tenant,
  sort_key: :email,
  projection: :include,
  projected_attributes: [:id, :name, :created_at]
```

## Querying GSIs

### Basic GSI Query

```elixir
# Query partition-only GSI
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{email: "user@example.com"},
  index_name: "EmailIndex"
)

# Query partition + sort GSI
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01-01"},
  index_name: "TenantIndex"
)
```

### Sort Key Operators

GSI queries support all the same sort key operators as table queries:

#### Exact Match (`:full_match`)
```elixir
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01-01T10:30:00Z"},
  index_name: "TenantIndex",
  sk_operator: :full_match  # or omit for default
)
```

#### Begins With (`:begins_with`)
```elixir
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01"},
  index_name: "TenantIndex",
  sk_operator: :begins_with
)
```

#### Comparison Operators
```elixir
# Greater than
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01-01"},
  index_name: "TenantIndex",
  sk_operator: :gt
)

# Less than or equal
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-12-31"},
  index_name: "TenantIndex",
  sk_operator: :lte
)
```

#### Between Operator
```elixir
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01-01"},
  index_name: "TenantIndex",
  sk_operator: :between,
  sk_end: "2023-12-31"
)
```

### Advanced Query Options

#### Filter Expressions
```elixir
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex",
  filter_expression: "attribute_exists(#name) AND #status = :status",
  expression_attribute_names: %{"#name" => "name", "#status" => "status"},
  expression_attribute_values: %{":status" => %{"S" => "active"}}
)
```

#### Projection Expressions
```elixir
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{email: "user@example.com"},
  index_name: "EmailIndex",
  projection_expression: "id, #name, email",
  expression_attribute_names: %{"#name" => "name"}
)
```

#### Pagination
```elixir
# First page
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex",
  limit: 10
)

# Next page (if LastEvaluatedKey was returned)
{:ok, more_users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex",
  limit: 10,
  exclusive_start_key: last_evaluated_key
)
```

#### Scan Direction
```elixir
# Descending order (newest first)
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex",
  scan_index_forward: false
)
```

## Error Handling

### Common Validation Errors

#### Missing GSI
```elixir
case MyApp.User.list_items(%MyApp.User{email: "user@example.com"}, 
                          index_name: "NonExistentIndex") do
  {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
    # "GSI 'NonExistentIndex' not found. Available indexes: EmailIndex, TenantIndex"
    IO.puts("Error: #{message}")
end
```

#### Missing Partition Key Data
```elixir
case MyApp.User.list_items(%MyApp.User{email: nil}, 
                          index_name: "EmailIndex") do
  {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
    # "GSI 'EmailIndex' requires field 'email' to be populated"
    IO.puts("Error: #{message}")
end
```

#### Missing Sort Key Data for Sort Operations
```elixir
case MyApp.User.list_items(%MyApp.User{tenant: "acme", created_at: nil}, 
                          index_name: "TenantIndex", sk_operator: :gt) do
  {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
    # "GSI 'TenantIndex' sort operation requires field 'created_at' to be populated"
    IO.puts("Error: #{message}")
end
```

#### Consistent Read with GSI
```elixir
case MyApp.User.list_items(%MyApp.User{email: "user@example.com"}, 
                          index_name: "EmailIndex", consistent_read: true) do
  {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
    # "Consistent reads are not supported for Global Secondary Index queries"
    IO.puts("Error: #{message}")
end
```

### Error Handling Best Practices

```elixir
def query_users_by_email(email) do
  case MyApp.User.list_items(%MyApp.User{email: email}, index_name: "EmailIndex") do
    {:ok, users} -> 
      {:ok, users}
      
    {:error, %Dynamo.Error{type: :validation_error} = error} ->
      # Log validation errors for debugging
      Logger.warn("GSI query validation error: #{error.message}")
      {:error, :invalid_query}
      
    {:error, %Dynamo.Error{type: :aws_error} = error} ->
      # Handle AWS-specific errors
      Logger.error("AWS error during GSI query: #{error.message}")
      {:error, :service_unavailable}
      
    {:error, error} ->
      # Handle unexpected errors
      Logger.error("Unexpected error during GSI query: #{inspect(error)}")
      {:error, :unknown_error}
  end
end
```

## Performance Optimization

### Efficient Query Patterns

#### Use Both Partition and Sort Keys When Possible
```elixir
# Efficient - Uses both keys
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme", created_at: "2023-01-01"},
  index_name: "TenantIndex",
  sk_operator: :gte
)

# Less efficient - Only uses partition key
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex"
)
```

#### Choose Appropriate Projection Types
```elixir
# For count queries - use keys_only
{:ok, count_result} = MyApp.User.list_items(
  %MyApp.User{status: "active"},
  index_name: "StatusIndex",
  select: :count
)

# For specific attributes - use projection expressions
{:ok, users} = MyApp.User.list_items(
  %MyApp.User{tenant: "acme"},
  index_name: "TenantIndex",
  projection_expression: "id, email, #name",
  expression_attribute_names: %{"#name" => "name"}
)
```

#### Use Pagination for Large Result Sets
```elixir
def get_all_users_paginated(tenant, page_size \\ 100) do
  get_users_recursive(%MyApp.User{tenant: tenant}, nil, page_size, [])
end

defp get_users_recursive(query_struct, start_key, page_size, acc) do
  options = [
    index_name: "TenantIndex",
    limit: page_size
  ]
  
  options = if start_key, do: [{:exclusive_start_key, start_key} | options], else: options
  
  case MyApp.User.list_items(query_struct, options) do
    {:ok, %{items: users, last_evaluated_key: nil}} ->
      {:ok, acc ++ users}
      
    {:ok, %{items: users, last_evaluated_key: last_key}} ->
      get_users_recursive(query_struct, last_key, page_size, acc ++ users)
      
    {:error, error} ->
      {:error, error}
  end
end
```

## Troubleshooting

### Debugging GSI Configuration

#### List All GSIs for a Schema
```elixir
gsi_configs = MyApp.User.global_secondary_indexes()
IO.puts("Available GSIs:")
Enum.each(gsi_configs, fn config ->
  sort_key = config.sort_key || "none"
  projection = config.projection
  IO.puts("  - #{config.name}: #{config.partition_key} -> #{sort_key} (#{projection})")
end)
```

#### Get Specific GSI Configuration
```elixir
case Dynamo.Schema.get_gsi_config(%MyApp.User{}, "TenantIndex") do
  {:ok, gsi_config} ->
    IO.inspect(gsi_config, label: "TenantIndex Configuration")
  {:error, error} ->
    IO.puts("Error: #{error.message}")
end
```

#### Validate GSI Data
```elixir
user = %MyApp.User{tenant: "acme", created_at: "2023-01-01"}

case Dynamo.Schema.validate_gsi_config(user, "TenantIndex", true) do
  {:ok, gsi_config} ->
    IO.puts("GSI validation passed")
    
    # Generate and inspect keys
    gsi_pk = Dynamo.Schema.generate_gsi_partition_key(user, gsi_config)
    gsi_sk = Dynamo.Schema.generate_gsi_sort_key(user, gsi_config)
    
    IO.puts("Generated keys:")
    IO.puts("  Partition Key: #{gsi_pk}")
    IO.puts("  Sort Key: #{gsi_sk}")
    
  {:error, error} ->
    IO.puts("GSI validation failed: #{error.message}")
end
```

### Common Issues and Solutions

#### Issue: "Field does not exist in schema"
**Cause:** GSI references a field that isn't defined in the schema.

**Solution:**
```elixir
# Add the missing field to your schema
defmodule MyApp.User do
  use Dynamo.Schema

  item do
    field :id, partition_key: true
    field :email  # Make sure this field exists
    field :created_at, sort_key: true
    
    global_secondary_index "EmailIndex", partition_key: :email
  end
end
```

#### Issue: GSI queries return no results
**Cause:** GSI key generation doesn't match expected values.

**Debug:**
```elixir
user = %MyApp.User{email: "user@example.com"}
{:ok, gsi_config} = Dynamo.Schema.get_gsi_config(user, "EmailIndex")
gsi_pk = Dynamo.Schema.generate_gsi_partition_key(user, gsi_config)
IO.puts("Generated GSI partition key: #{gsi_pk}")
# Should output something like: "user#user@example.com"
```

#### Issue: Performance problems with GSI queries
**Solutions:**
1. Use more specific partition keys to distribute load
2. Add sort keys to enable range queries
3. Use appropriate projection types
4. Implement pagination for large result sets

## Best Practices

### Schema Design

1. **Choose Meaningful GSI Names**
   ```elixir
   # Good - descriptive names
   global_secondary_index "UsersByEmail", partition_key: :email
   global_secondary_index "UsersByTenantAndDate", partition_key: :tenant, sort_key: :created_at
   
   # Avoid - generic names
   global_secondary_index "GSI1", partition_key: :email
   ```

2. **Design for Access Patterns**
   ```elixir
   # Design GSIs based on how you'll query the data
   global_secondary_index "ActiveUsersByTenant", 
     partition_key: :tenant,
     sort_key: :last_login_at,
     projection: :include,
     projected_attributes: [:id, :email, :status]
   ```

3. **Consider Projection Types Carefully**
   - Use `:all` when you need all attributes (default)
   - Use `:keys_only` for count queries or when you only need keys
   - Use `:include` with specific attributes to balance performance and cost

### Query Optimization

1. **Use Both Keys When Possible**
   ```elixir
   # Efficient
   {:ok, users} = MyApp.User.list_items(
     %MyApp.User{tenant: "acme", status: "active"},
     index_name: "TenantStatusIndex"
   )
   ```

2. **Implement Proper Error Handling**
   ```elixir
   def safe_gsi_query(params) do
     case MyApp.User.list_items(params.struct, index_name: params.index) do
       {:ok, results} -> {:ok, results}
       {:error, %Dynamo.Error{type: :validation_error}} -> {:ok, []}
       {:error, error} -> {:error, error}
     end
   end
   ```

3. **Use Pagination for Large Datasets**
   ```elixir
   # Always use limits for potentially large result sets
   {:ok, users} = MyApp.User.list_items(
     %MyApp.User{status: "active"},
     index_name: "StatusIndex",
     limit: 100
   )
   ```

### Monitoring and Maintenance

1. **Log GSI Query Patterns**
   ```elixir
   def query_with_logging(struct, options) do
     start_time = System.monotonic_time()
     
     result = MyApp.User.list_items(struct, options)
     
     duration = System.monotonic_time() - start_time
     Logger.info("GSI query completed", [
       index: options[:index_name],
       duration_ms: System.convert_time_unit(duration, :native, :millisecond),
       result_count: case result do
         {:ok, items} -> length(items)
         _ -> 0
       end
     ])
     
     result
   end
   ```

2. **Monitor GSI Usage**
   - Track which GSIs are used most frequently
   - Monitor query performance and adjust projections as needed
   - Consider adding new GSIs for common query patterns

This guide provides comprehensive coverage of GSI usage with Dynamo. For additional examples, see the `lib/examples.ex` file in the project.