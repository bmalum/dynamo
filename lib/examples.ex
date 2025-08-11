defmodule Dynamo.User do
  use Dynamo.Schema, key_separator: "_"

  item do
    field(:uuid4, default: "Nomnomnom")
    field(:tenant, default: "yolo")
    field(:first_name)
    field(:email, sort_key: true, default: "001")
    field(:created_at)
    field(:status)
    partition_key([:uuid4])

    table_name("test_table")

    # GSI Examples demonstrating various configurations

    # Partition-only GSI - Simple lookup by email
    global_secondary_index("EmailIndex", partition_key: :email)

    # Partition + Sort GSI - Query users by tenant with time-based sorting
    global_secondary_index("TenantIndex", partition_key: :tenant, sort_key: :created_at)

    # GSI with custom projection - Only include specific attributes
    global_secondary_index("TenantEmailIndex",
      partition_key: :tenant,
      sort_key: :email,
      projection: :include,
      projected_attributes: [:uuid4, :created_at, :status]
    )

    # GSI with keys-only projection - Minimal data transfer
    global_secondary_index("StatusIndex",
      partition_key: :status,
      projection: :keys_only
    )
  end
end

# Additional example schemas demonstrating different GSI patterns

defmodule Dynamo.Product do
  @moduledoc """
  Example schema showing GSI usage for an e-commerce product catalog.
  Demonstrates multiple access patterns through different GSIs.
  """

  use Dynamo.Schema

  item do
    field(:product_id)
    field(:category)
    field(:brand)
    field(:price)
    field(:created_at)
    field(:status)
    field(:name)
    field(:description)

    partition_key([:product_id])
    table_name("products")

    # GSI for browsing products by category
    global_secondary_index("CategoryIndex",
      partition_key: :category,
      sort_key: :created_at
    )

    # GSI for finding products by brand with price sorting
    global_secondary_index("BrandPriceIndex",
      partition_key: :brand,
      sort_key: :price,
      projection: :include,
      projected_attributes: [:product_id, :name, :status]
    )

    # GSI for admin queries by status
    global_secondary_index("StatusIndex",
      partition_key: :status,
      sort_key: :created_at,
      projection: :all
    )
  end
end

defmodule Dynamo.Order do
  @moduledoc """
  Example schema showing GSI usage for order management.
  Demonstrates partition-only GSIs and different projection types.
  """

  use Dynamo.Schema

  item do
    field(:order_id)
    field(:customer_id)
    field(:status)
    field(:total_amount)
    field(:created_at)
    field(:updated_at)
    field(:shipping_address)

    partition_key([:order_id])
    table_name("orders")

    # Partition-only GSI for customer order lookup
    global_secondary_index("CustomerIndex",
      partition_key: :customer_id
    )

    # GSI for order management by status with time sorting
    global_secondary_index("StatusTimeIndex",
      partition_key: :status,
      sort_key: :created_at,
      projection: :keys_only
    )
  end
end

defmodule Dynamo.Examples do
  @moduledoc """
  Example usage patterns for GSI queries demonstrating the enhanced list_items functionality.
  """

  alias Dynamo.{User, Product, Order, Table}

  @doc """
  Example GSI query patterns for User schema
  """
  def user_examples do
    # Create a sample user
    _user = %User{
      uuid4: "user-123",
      tenant: "acme-corp",
      email: "john@example.com",
      first_name: "John",
      created_at: "2024-01-15T10:30:00Z",
      status: "active"
    }

    # Query using partition-only GSI
    # Find user by email
    {:ok, _users} =
      Table.list_items(
        %User{email: "john@example.com"},
        index_name: "EmailIndex"
      )

    # Query using partition + sort GSI with different operators
    # Find all users in tenant created after a specific date
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp", created_at: "2024-01-01T00:00:00Z"},
        index_name: "TenantIndex",
        sk_operator: :gt
      )

    # Query with begins_with operator
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp", created_at: "2024-01"},
        index_name: "TenantIndex",
        sk_operator: :begins_with
      )

    # Query with between operator
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp", created_at: "2024-01-01T00:00:00Z"},
        index_name: "TenantIndex",
        sk_operator: :between,
        sk_end: "2024-01-31T23:59:59Z"
      )

    # Query with filter expression
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp"},
        index_name: "TenantIndex",
        filter_expression: "attribute_exists(first_name) AND #status = :status",
        expression_attribute_names: %{"#status" => "status"},
        expression_attribute_values: %{":status" => %{"S" => "active"}}
      )

    # Query with projection expression
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp"},
        index_name: "TenantEmailIndex",
        projection_expression: "uuid4, created_at, #status",
        expression_attribute_names: %{"#status" => "status"}
      )

    # Query with pagination
    {:ok, _users} =
      Table.list_items(
        %User{status: "active"},
        index_name: "StatusIndex",
        limit: 10
      )

    # Query with scan direction (descending order)
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp"},
        index_name: "TenantIndex",
        scan_index_forward: false
      )
  end

  @doc """
  Example GSI query patterns for Product schema
  """
  def product_examples do
    # Query products by category with time-based sorting
    {:ok, _products} =
      Table.list_items(
        %Product{category: "electronics", created_at: "2024-01-01T00:00:00Z"},
        index_name: "CategoryIndex",
        sk_operator: :gt
      )

    # Query products by brand with price range
    {:ok, _products} =
      Table.list_items(
        %Product{brand: "Apple", price: 100},
        index_name: "BrandPriceIndex",
        sk_operator: :between,
        sk_end: 1000
      )

    # Admin query for products by status with projection
    {:ok, _products} =
      Table.list_items(
        %Product{status: "pending_review"},
        index_name: "StatusIndex",
        projection_expression: "product_id, #name, #status",
        expression_attribute_names: %{
          "#name" => "name",
          "#status" => "status"
        }
      )

    # Query with complex filter expression
    {:ok, _products} =
      Table.list_items(
        %Product{category: "electronics"},
        index_name: "CategoryIndex",
        filter_expression: "price BETWEEN :min_price AND :max_price AND #status = :status",
        expression_attribute_names: %{"#status" => "status"},
        expression_attribute_values: %{
          ":min_price" => %{"N" => "100"},
          ":max_price" => %{"N" => "500"},
          ":status" => %{"S" => "active"}
        }
      )
  end

  @doc """
  Example GSI query patterns for Order schema
  """
  def order_examples do
    # Find all orders for a customer (partition-only GSI)
    {:ok, _orders} =
      Table.list_items(
        %Order{customer_id: "customer-456"},
        index_name: "CustomerIndex"
      )

    # Find orders by status with time sorting
    {:ok, _orders} =
      Table.list_items(
        %Order{status: "processing", created_at: "2024-01-01T00:00:00Z"},
        index_name: "StatusTimeIndex",
        sk_operator: :gte
      )

    # Find recent orders by status (keys-only projection)
    {:ok, _orders} =
      Table.list_items(
        %Order{status: "shipped"},
        index_name: "StatusTimeIndex",
        limit: 20,
        # Most recent first
        scan_index_forward: false
      )

    # Find orders with filter on total amount
    {:ok, _orders} =
      Table.list_items(
        %Order{customer_id: "customer-456"},
        index_name: "CustomerIndex",
        filter_expression: "total_amount > :min_amount",
        expression_attribute_values: %{
          ":min_amount" => %{"N" => "100"}
        }
      )
  end

  @doc """
  Example error scenarios and handling
  """
  def error_examples do
    # Missing partition key data
    case Table.list_items(%User{email: nil}, index_name: "EmailIndex") do
      {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
        IO.puts("Expected error: #{message}")
        # "GSI 'EmailIndex' requires field 'email' to be populated"
    end

    # Invalid index name
    case Table.list_items(%User{email: "john@example.com"}, index_name: "NonExistentIndex") do
      {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
        IO.puts("Expected error: #{message}")

        # "GSI 'NonExistentIndex' not found. Available indexes: EmailIndex, TenantIndex, TenantEmailIndex, StatusIndex"
    end

    # Missing sort key data for sort operation
    case Table.list_items(%User{tenant: "acme-corp", created_at: nil},
           index_name: "TenantIndex",
           sk_operator: :gt
         ) do
      {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
        IO.puts("Expected error: #{message}")
        # "GSI 'TenantIndex' sort operation requires field 'created_at' to be populated"
    end

    # Consistent read with GSI (not supported)
    case Table.list_items(%User{email: "john@example.com"},
           index_name: "EmailIndex",
           consistent_read: true
         ) do
      {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
        IO.puts("Expected error: #{message}")
        # "Consistent reads are not supported for Global Secondary Index queries"
    end

    # Sort operation on partition-only GSI
    case Table.list_items(%User{email: "john@example.com"},
           index_name: "EmailIndex",
           sk_operator: :begins_with
         ) do
      {:error, %Dynamo.Error{type: :validation_error, message: message}} ->
        IO.puts("Expected error: #{message}")
        # "GSI 'EmailIndex' does not have a sort key but sort operation was requested"
    end
  end

  @doc """
  Debugging and inspection utilities for GSI development
  """
  def debugging_examples do
    # Inspect all GSI configurations for a schema
    gsi_configs = User.global_secondary_indexes()
    IO.puts("Available GSIs:")

    Enum.each(gsi_configs, fn config ->
      IO.puts("  - #{config.name}: #{config.partition_key} -> #{config.sort_key || "none"}")
    end)

    # Get specific GSI configuration
    case Dynamo.Schema.get_gsi_config(%User{}, "TenantIndex") do
      {:ok, gsi_config} ->
        IO.inspect(gsi_config, label: "TenantIndex Config")

      {:error, error} ->
        IO.puts("Error: #{error.message}")
    end

    # Validate GSI configuration and data
    user = %User{tenant: "acme-corp", created_at: "2024-01-15T10:30:00Z"}

    case Dynamo.Schema.validate_gsi_config(user, "TenantIndex", true) do
      {:ok, gsi_config} ->
        IO.puts("GSI validation passed")

        # Generate and inspect GSI keys
        gsi_pk = Dynamo.Schema.generate_gsi_partition_key(user, gsi_config)
        gsi_sk = Dynamo.Schema.generate_gsi_sort_key(user, gsi_config)

        IO.puts("Generated GSI keys:")
        IO.puts("  Partition Key: #{gsi_pk}")
        IO.puts("  Sort Key: #{gsi_sk}")

      {:error, error} ->
        IO.puts("GSI validation failed: #{error.message}")
    end

    # Test key generation for different GSI configurations
    test_user = %User{
      uuid4: "user-123",
      tenant: "acme-corp",
      email: "john@example.com",
      status: "active",
      created_at: "2024-01-15T10:30:00Z"
    }

    Enum.each(User.global_secondary_indexes(), fn gsi_config ->
      gsi_pk = Dynamo.Schema.generate_gsi_partition_key(test_user, gsi_config)
      gsi_sk = Dynamo.Schema.generate_gsi_sort_key(test_user, gsi_config)

      IO.puts("GSI: #{gsi_config.name}")
      IO.puts("  PK: #{gsi_pk}")
      IO.puts("  SK: #{gsi_sk || "none"}")
    end)
  end

  @doc """
  Performance optimization examples for GSI queries
  """
  def performance_examples do
    # Efficient: Query with both partition and sort key
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp", email: "john@example.com"},
        index_name: "TenantEmailIndex"
      )

    # Less efficient: Query with only partition key on composite GSI
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp"},
        index_name: "TenantEmailIndex"
      )

    # Use projection expressions to reduce data transfer
    {:ok, _users} =
      Table.list_items(
        %User{tenant: "acme-corp"},
        index_name: "TenantEmailIndex",
        projection_expression: "uuid4, email, #status",
        expression_attribute_names: %{"#status" => "status"}
      )

    # Use keys-only projection for count queries
    {:ok, _orders} =
      Table.list_items(
        %Order{status: "completed"},
        index_name: "StatusTimeIndex",
        select: :count
      )

    # Paginate large result sets
    {:ok, _users} =
      Table.list_items(
        %User{status: "active"},
        index_name: "StatusIndex",
        limit: 100
      )
  end
end
