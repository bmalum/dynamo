defmodule Dynamo.Table do
  @moduledoc """
  Provides comprehensive functions for interacting with DynamoDB tables.

  This module handles all core CRUD operations, queries, scans, and batch operations
  for DynamoDB tables. It works seamlessly with schemas defined using `Dynamo.Schema`,
  automatically managing key generation, encoding, decoding, and error handling.

  ## Core Operations

  ### Single Item Operations

  - `put_item/2` - Create or replace an item
  - `get_item/2` - Retrieve a single item by primary key
  - `update_item/3` - Update specific attributes of an item
  - `delete_item/2` - Remove an item from the table

  ### Query and Scan Operations

  - `list_items/1` - Query items by partition key
  - `list_items/2` - Query items with advanced filters and conditions
  - `scan/2` - Scan the entire table with optional filters
  - `parallel_scan/2` - Perform parallel scans for improved performance on large tables

  ### Batch Operations

  - `batch_write_item/2` - Write multiple items in a single request
  - `batch_get_item/2` - Retrieve multiple items efficiently

  ## Query Building

  The module provides powerful query building capabilities through `build_query/2`,
  supporting:

  - Partition key equality conditions
  - Sort key comparison operators (=, <, >, <=, >=, begins_with, between)
  - Filter expressions for post-query filtering
  - Projection expressions to retrieve specific attributes
  - Index queries (GSI and LSI)
  - Pagination with exclusive start keys
  - Consistent reads for strongly consistent data

  ## Error Handling

  All operations return `{:ok, result}` or `{:error, %Dynamo.Error{}}` tuples,
  providing structured error information with context for debugging and error recovery.
  Common error types include:

  - `:validation_error` - Invalid parameters or schema definition
  - `:aws_error` - DynamoDB service errors (rate limits, table not found, etc.)
  - `:unknown_error` - Unexpected errors

  ## Examples

      # Simple create
      {:ok, user} = Dynamo.Table.put_item(%User{id: "123", name: "John"})

      # Retrieve with consistent read
      {:ok, user} = Dynamo.Table.get_item(
        %User{id: "123"},
        consistent_read: true
      )

      # Query with filters
      {:ok, users} = Dynamo.Table.list_items(
        %User{tenant: "acme"},
        filter_expression: "age >= :min_age",
        expression_attribute_values: %{":min_age" => %{"N" => "18"}}
      )

      # Batch operations
      {:ok, result} = Dynamo.Table.batch_write_item([user1, user2, user3])

      # Parallel scan for large tables
      {:ok, all_users} = Dynamo.Table.parallel_scan(User, segments: 8)

  ## Performance Considerations

  - Use batch operations when working with multiple items
  - Leverage parallel scans for large table scans
  - Use projection expressions to reduce data transfer
  - Implement pagination for large result sets
  - Consider using GSIs for alternative access patterns

  ## See Also

  - `Dynamo.Schema` - For defining table schemas
  - `Dynamo.Transaction` - For atomic multi-item operations
  - `Dynamo.Config` - For configuration management
  """

@doc """
  Puts an item into DynamoDB.

  Takes a struct that implements the required DynamoDB schema behavior and writes it to the corresponding table.

  ## Parameters
    * `struct` - A struct that implements the DynamoDB schema behavior
    * `opts` - Optional keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:condition_expression` - Optional condition expression for the put operation
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders

  ## Returns
    * `{:ok, item}` - Successfully inserted item
    * `{:error, error}` - Error occurred during insertion, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.put_item(%User{id: "123", name: "John"})
      {:ok, %User{id: "123", name: "John"}}

      # With condition expression
      iex> Dynamo.Table.put_item(%User{id: "123", name: "John"},
      ...>   condition_expression: "attribute_not_exists(id)",
      ...> )
      {:ok, %User{id: "123", name: "John"}}
  """
  @spec put_item(struct(), keyword()) :: {:ok, struct()} | {:error, Dynamo.Error.t()}
  def put_item(struct, opts \\ []) when is_struct(struct) do
    # Validate struct has required fields
    if struct.__struct__.partition_key() == [] do
      {:error, Dynamo.Error.new(:validation_error, "Struct must have a partition key defined")}
    else
      item = struct.__struct__.before_write(struct)
      table = struct.__struct__.table_name()
      client = opts[:client] || Dynamo.AWS.client()

      # Build the base payload
      payload = %{"TableName" => table, "Item" => item}

      # Add optional parameters if provided
      payload = if opts[:condition_expression] do
        Map.put(payload, "ConditionExpression", opts[:condition_expression])
      else
        payload
      end

      payload = if opts[:expression_attribute_names] do
        Map.put(payload, "ExpressionAttributeNames", opts[:expression_attribute_names])
      else
        payload
      end

      payload = if opts[:expression_attribute_values] do
        Map.put(payload, "ExpressionAttributeValues", opts[:expression_attribute_values])
      else
        payload
      end

      case AWS.DynamoDB.put_item(client, payload) do
        {:ok, _, _} ->
          {:ok, item |> Dynamo.Helper.decode_item(as: struct.__struct__)}

        {:error, %{"__type" => type, "Message" => message}} ->
          {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

        {:error, error} ->
          {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

        error ->
          {:error, Dynamo.Error.new(:unknown_error, "Unknown error during put_item", error)}
      end
    end
  end

  @doc """
  Alias for `put_item/2`

  ## Parameters
    * `struct` - A struct that implements the DynamoDB schema behavior
    * `opts` - Optional keyword list of options (see `put_item/2` for details)

  ## Returns
    * `{:ok, item}` - Successfully inserted item
    * `{:error, error}` - Error occurred during insertion, where error is a `Dynamo.Error` struct
  """
  @spec insert(struct(), keyword()) :: {:ok, struct()} | {:error, Dynamo.Error.t()}
  defdelegate insert(struct, opts \\ []), to: __MODULE__, as: :put_item

  @doc """
  Retrieves an item from DynamoDB using partition key and optional sort key.

  ## Parameters
    * `struct` - A struct containing the necessary keys for retrieval
    * `opts` - Optional keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders

  ## Returns
    * `{:ok, item}` - The retrieved item
    * `{:ok, nil}` - No item found
    * `{:error, error}` - Error occurred during retrieval, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.get_item(%User{id: "123"})
      {:ok, %User{id: "123", name: "John"}}

      # With consistent read
      iex> Dynamo.Table.get_item(%User{id: "123"}, consistent_read: true)
      {:ok, %User{id: "123", name: "John"}}

      # With projection expression
      iex> Dynamo.Table.get_item(%User{id: "123"},
      ...>   projection_expression: "id, name",
      ...>   expression_attribute_names: %{"#n" => "name"}
      ...> )
      {:ok, %User{id: "123", name: "John"}}
  """
  @spec get_item(struct(), keyword()) :: {:ok, struct() | nil} | {:error, Dynamo.Error.t()}
  def get_item(struct, opts \\ []) when is_struct(struct) do
    # Validate struct has required fields
    if struct.__struct__.partition_key() == [] do
      {:error, Dynamo.Error.new(:validation_error, "Struct must have a partition key defined")}
    else
      pk = Dynamo.Schema.generate_partition_key(struct)
      sk = Dynamo.Schema.generate_sort_key(struct)
      table = struct.__struct__.table_name
      config = struct.__struct__.settings()
      client = opts[:client] || Dynamo.AWS.client()

      partition_key_name = config[:partition_key_name]
      sort_key_name = config[:sort_key_name]

      # Build the base query
      query = %{
        "TableName" => table,
        "Key" => %{
          partition_key_name => %{"S" => pk}
        }
      }

      # Add sort key if available
      query = if sk != nil, do: put_in(query, ["Key", sort_key_name], %{"S" => sk}), else: query

      # Add optional parameters if provided
      query = if opts[:consistent_read], do: Map.put(query, "ConsistentRead", true), else: query

      query = if opts[:projection_expression] do
        Map.put(query, "ProjectionExpression", opts[:projection_expression])
      else
        query
      end

      query = if opts[:expression_attribute_names] do
        Map.put(query, "ExpressionAttributeNames", opts[:expression_attribute_names])
      else
        query
      end

      case AWS.DynamoDB.get_item(client, query) do
        {:ok, %{"Item" => item}, _} ->
          {:ok, item |> Dynamo.Helper.decode_item(as: struct.__struct__)}

        {:ok, %{}, _} ->
          {:ok, nil}

        {:error, %{"__type" => type, "Message" => message}} ->
          {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

        {:error, error} ->
          {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

        error ->
          {:error, Dynamo.Error.new(:unknown_error, "Unknown error during get_item", error)}
      end
    end
  end

  @doc """
  Builds a DynamoDB query with the given partition key and options.

  ## Parameters
    * `pk` - Partition key value
    * `options` - Keyword list of options:
      * `:sort_key` - Sort key value (optional)
      * `:sk_operator` - Sort key operator:
        * `:full_match` - Exact match (=)
        * `:begins_with` - Prefix match (begins_with)
        * `:gt` - Greater than (>)
        * `:lt` - Less than (<)
        * `:gte` - Greater than or equal (>=)
        * `:lte` - Less than or equal (<=)
        * `:between` - Between two values (requires `:sk_end` parameter)
      * `:sk_end` - End value for BETWEEN operator
      * `:scan_index_forward` - Boolean for scan direction (default: true)
      * `:table_name` - Name of the DynamoDB table
      * `:index_name` - Name of the index to query (GSI/LSI)
      * `:filter_expression` - Filter expression to apply to results
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:select` - Return value specification (`:all_attributes`, `:projected_attributes`, `:count`, `:specific_attributes`)
      * `:consistent_read` - Whether to use strongly consistent reads
      * `:exclusive_start_key` - Key to start the query from (for pagination)
      * `:limit` - Maximum number of items to evaluate

  ## Returns
    * Map containing the formatted DynamoDB query

  ## Examples
      iex> Dynamo.Table.build_query("user#123", table_name: "Users")
      %{"TableName" => "Users", "KeyConditionExpression" => "pk = :pk", ...}
  """
  @spec build_query(String.t(), keyword()) :: map()
  def build_query(pk, options \\ []) do
    defaults = [
      sort_key: nil,
      sk_operator: nil,
      scan_index_forward: true,
      index_name: nil,
      filter_expression: nil,
      projection_expression: nil,
      expression_attribute_names: nil,
      expression_attribute_values: nil,
      select: nil,
      consistent_read: false,
      exclusive_start_key: nil,
      return_consumed_capacity: nil
    ]

    options = Keyword.merge(defaults, options)
    table = options[:table_name]
    sk = options[:sort_key]

    # Get configuration from module specified in options or use defaults
    config = if options[:schema_module] do
      options[:schema_module].settings()
    else
      Dynamo.Config.config()
    end

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    pk_query_fragment = "#{partition_key_name} = :pk"

    # Build the base query
    query = %{
      "TableName" => table,
      "KeyConditionExpression" => pk_query_fragment,
      "ScanIndexForward" => options[:scan_index_forward],
      "ExpressionAttributeValues" => %{
        ":pk" => %{"S" => pk}
      }
    }

    # Add sort key if provided
    {sk, sk_operator, sk_end} =
      case {sk, options[:sk_operator], options[:sk_end]} do
        {nil, nil, nil} -> {nil, nil, nil}
        {nil, _op, _end} -> raise Dynamo.Error.new(:validation_error, "Sort key operator provided but sort key is nil")
        {val, nil, nil} -> {val, :full_match, nil}
        {val, op, end_val} -> {val, op, end_val}
      end

    query = if sk != nil do
      # Add the first sort key value
      query = put_in(query, ["ExpressionAttributeValues", ":sk"], %{"S" => sk})

      # Add the second sort key value if needed for BETWEEN
      query = if sk_end != nil do
        put_in(query, ["ExpressionAttributeValues", ":sk_end"], %{"S" => sk_end})
      else
        query
      end

      # Build the appropriate condition expression based on the operator
      case sk_operator do
        :full_match ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} = :sk"
          )
        :begins_with ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND begins_with(#{sort_key_name}, :sk)"
          )
        :gt ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} > :sk"
          )
        :lt ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} < :sk"
          )
        :gte ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} >= :sk"
          )
        :lte ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} <= :sk"
          )
        :between ->
          if sk_end == nil do
            raise Dynamo.Error.new(:validation_error, "BETWEEN operator requires sk_end parameter")
          end
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND #{sort_key_name} BETWEEN :sk AND :sk_end"
          )
        _ ->
          raise Dynamo.Error.new(:validation_error, "Unsupported sort key operator: #{inspect(sk_operator)}")
      end
    else
      query
    end

    # Add index name if provided
    query = if options[:index_name], do: Map.put(query, "IndexName", options[:index_name]), else: query

    # Add filter expression if provided
    query = if options[:filter_expression], do: Map.put(query, "FilterExpression", options[:filter_expression]), else: query

    # Add projection expression if provided
    query = if options[:projection_expression], do: Map.put(query, "ProjectionExpression", options[:projection_expression]), else: query

    # Add expression attribute names if provided
    query = if options[:expression_attribute_names], do: Map.put(query, "ExpressionAttributeNames", options[:expression_attribute_names]), else: query

    # Add any additional expression attribute values if provided
    query = if options[:expression_attribute_values] do
      updated_values = Map.merge(query["ExpressionAttributeValues"], options[:expression_attribute_values])
      Map.put(query, "ExpressionAttributeValues", updated_values)
    else
      query
    end

    # Add select if provided
    query = if options[:select] do
      select_value = case options[:select] do
        :all_attributes -> "ALL_ATTRIBUTES"
        :projected_attributes -> "ALL_PROJECTED_ATTRIBUTES"
        :count -> "COUNT"
        :specific_attributes -> "SPECIFIC_ATTRIBUTES"
        other when is_binary(other) -> other
        _ -> nil
      end
      if select_value, do: Map.put(query, "Select", select_value), else: query
    else
      query
    end

    # Add consistent read if provided
    query = if options[:consistent_read], do: Map.put(query, "ConsistentRead", true), else: query

    # Add limit if provided in options (not from external limit parameter)
    query = if options[:limit] && options[:limit] != :infinity, do: Map.put(query, "Limit", options[:limit]), else: query

    # Add exclusive start key for pagination if provided
    query = if options[:exclusive_start_key], do: Map.put(query, "ExclusiveStartKey", options[:exclusive_start_key]), else: query

    # Add return consumed capacity if provided
    query = if options[:return_consumed_capacity] do
      capacity_value = case options[:return_consumed_capacity] do
        :total -> "TOTAL"
        :indexes -> "INDEXES"
        :none -> "NONE"
        other when is_binary(other) -> other
        _ -> nil
      end
      if capacity_value, do: Map.put(query, "ReturnConsumedCapacity", capacity_value), else: query
    else
      query
    end

    query
  end

  @doc """
  Executes a DynamoDB query with unlimited results.

  ## Parameters
    * `query` - Map containing the DynamoDB query

  ## Returns
    * `{:ok, items}` - List of items matching the query
    * `{:error, error}` - Error occurred during query, where error is a `Dynamo.Error` struct
  """
  @spec query(map()) :: {:ok, [map()]} | {:error, Dynamo.Error.t()}
  def query(query) do
    query(query, :infinity, [], nil)
  end

  @doc """
  Executes a DynamoDB query with a specified limit.

  ## Parameters
    * `query` - Map containing the DynamoDB query
    * `limit` - Maximum number of items to return

  ## Returns
    * `{:ok, items}` - List of items matching the query
    * `{:error, error}` - Error occurred during query, where error is a `Dynamo.Error` struct
  """
  @spec query(map(), non_neg_integer() | :infinity) :: {:ok, [map()]} | {:error, Dynamo.Error.t()}
  def query(query, limit) do
    query(query, limit, [], nil)
  end


  defp query(_query, limit, acc, _last_key)
       when limit != :infinity and length(acc) >= limit do
       {:ok, Enum.take(acc, limit)}
  end

  defp query(query, limit, acc, last_key)
       when length(acc) < limit or limit == :infinity do
    query = if last_key, do: Map.put(query, "ExclusiveStartKey", last_key), else: query

    case AWS.DynamoDB.query(Dynamo.AWS.client(), query) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => last_evaluated_key}, _} ->
        query(query, limit, acc ++ items, last_evaluated_key)

      {:ok, %{"Items" => items}, _} ->
        case limit do
          :infinity -> {:ok, acc ++ items}
          limit ->
            {:ok, Enum.take(acc ++ items, limit)}
        end

      {:error, %{"__type" => type, "Message" => message}} ->
        {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

      {:error, error} ->
        {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

      error ->
        {:error, Dynamo.Error.new(:unknown_error, "Unknown error during query", error)}
    end
  end

  # all items with this PK
  @doc """
  Lists all items for a given struct's partition key.

  ## Parameters
    * `struct` - Struct containing the partition key information

  ## Returns
    * `{:ok, items}` - List of items matching the query
    * `{:error, error}` - Error occurred during query, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.list_items(%User{id: "123"})
      {:ok, [%User{...}, ...]}
  """
  @spec list_items(struct()) :: {:ok, [struct()]} | {:error, Dynamo.Error.t()}
  def list_items(struct) when is_struct(struct) do
    pk = Dynamo.Schema.generate_partition_key(struct)
    table = struct.__struct__.table_name

    build_query(pk, table_name: table, schema_module: struct.__struct__)
    |> query(:infinity, [], nil)
    |> decode_res(struct)
  end

  @doc """
  Lists items for a given struct's partition key with additional options.

  ## Parameters
    * `struct` - Struct containing the partition key information
    * `options` - Additional query options:
      * `:sort_key` - Sort key value (optional)
      * `:sk_operator` - Sort key operator:
        * `:full_match` - Exact match (=)
        * `:begins_with` - Prefix match (begins_with)
        * `:gt` - Greater than (>)
        * `:lt` - Less than (<)
        * `:gte` - Greater than or equal (>=)
        * `:lte` - Less than or equal (<=)
        * `:between` - Between two values (requires `:sk_end` parameter)
      * `:sk_end` - End value for BETWEEN operator
      * `:scan_index_forward` - Boolean for scan direction (default: true)
      * `:index_name` - Name of the index to query (GSI/LSI)
      * `:filter_expression` - Filter expression to apply to results
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:select` - Return value specification (`:all_attributes`, `:projected_attributes`, `:count`, `:specific_attributes`)
      * `:consistent_read` - Whether to use strongly consistent reads
      * `:exclusive_start_key` - Key to start the query from (for pagination)
      * `:limit` - Maximum number of items to return (default: :infinity)

  ## Returns
    * {:ok, items} - List of items matching the query
    * {:error, error} - Error occurred during query

  ## Examples
      # Basic query with sort key
      iex> User.list_items(%User{id: "123"}, sort_key: "profile", sk_operator: :begins_with)
      {:ok, [%User{...}, %User{...}]}

      # Query with comparison operators
      iex> User.list_items(%User{id: "123"}, sort_key: "2023-01-01", sk_operator: :gt)
      {:ok, [%User{...}, %User{...}]}

      # Query with BETWEEN operator
      iex> User.list_items(%User{id: "123"},
      ...>   sort_key: "2023-01-01",
      ...>   sk_operator: :between,
      ...>   sk_end: "2023-12-31"
      ...> )
      {:ok, [%User{...}, %User{...}]}

      # Query with filter expression
      iex> User.list_items(%User{tenant: "acme"},
      ...>   filter_expression: "active = :active_val",
      ...>   expression_attribute_values: %{":active_val" => %{"BOOL" => true}}
      ...> )
      {:ok, [%User{...}]}

      # Query a global secondary index
      iex> User.list_items(%User{email: "user@example.com"},
      ...>   index_name: "EmailIndex"
      ...> )
      {:ok, [%User{...}]}
  """
  @spec list_items(struct(), keyword()) :: {:ok, [struct()]} | {:error, Dynamo.Error.t()}
  def list_items(struct, options) when is_struct(struct) do
    pk = Dynamo.Schema.generate_partition_key(struct)
    table = struct.__struct__.table_name
    opts = [table_name: table, limit: :infinity, schema_module: struct.__struct__]
    |> Keyword.merge(options)
    build_query(pk, opts)
    |> query(opts[:limit], [], nil)
    |> decode_res(struct)
  end

  defp decode_res(res, struct) do
    case res do
      {:ok, items} -> {:ok, items |> Dynamo.Helper.decode_item(as: struct.__struct__)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Writes multiple items to DynamoDB in a single batch request.

  Takes a list of structs that implement the required DynamoDB schema behavior and writes them to
  the corresponding table. All items must belong to the same table.

  Note: DynamoDB limits batch writes to 25 items per request. This function automatically handles
  chunking for larger batches.

  ## Parameters
    * `items` - List of structs that implement the DynamoDB schema behavior
    * `options` - Keyword list of additional options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)

  ## Returns
    * `{:ok, result}` - Successfully processed batch with result containing:
      * `:processed_items` - Number of successfully processed items
      * `:unprocessed_items` - List of items that couldn't be processed
    * `{:error, error}` - Error occurred during batch processing, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.batch_write_item([%User{id: "123"}, %User{id: "456"}])
      {:ok, %{processed_items: 2, unprocessed_items: []}}
  """
  @spec batch_write_item([struct()], keyword()) :: {:ok, map()} | {:error, Dynamo.Error.t()}
  def batch_write_item(items, _options \\ []) when is_list(items) and length(items) > 0 do
    # Validate all items have the same table and struct type
    first_item = List.first(items)
    module = first_item.__struct__
    table_name = module.table_name()

    # Ensure all items are of the same type and table
    Enum.each(items, fn item ->
      unless item.__struct__ == module and item.__struct__.table_name() == table_name do
        raise ArgumentError, "All items must belong to the same schema and table"
      end
    end)

    # Prepare items through before_write hook
    prepared_items = Enum.map(items, fn item ->
      item.__struct__.before_write(item)
    end)

    # Build write request items
    write_requests = Enum.map(prepared_items, fn item ->
      %{"PutRequest" => %{"Item" => item}}
    end)

    # Split into chunks of 25 (AWS limit)
    chunked_requests = chunk_requests(write_requests, 25)

    # Process each chunk and track results
    process_batch_chunks(chunked_requests, table_name, module)
  end

  defp chunk_requests(requests, chunk_size) do
    Enum.chunk_every(requests, chunk_size)
  end

  defp process_batch_chunks(chunks, table_name, module) do
    # Process chunks sequentially, tracking results
    {result, unprocessed} =
      Enum.reduce(chunks, {0, []}, fn chunk, {processed_count, unprocessed_items} ->
        # Create the batch write request
        batch_request = %{
          "RequestItems" => %{
            table_name => chunk
          }
        }

        case AWS.DynamoDB.batch_write_item(Dynamo.AWS.client(), batch_request) do
          {:ok, %{"UnprocessedItems" => %{^table_name => unprocessed}} = _response, _context} when unprocessed != [] ->
            # Some items weren't processed - add them to unprocessed list
            {processed_count + (length(chunk) - length(unprocessed)),
             unprocessed_items ++ unprocessed}

          {:ok, _response, _context} ->
            # All items in this chunk were processed
            {processed_count + length(chunk), unprocessed_items}

          {:error, %{"__type" => _type, "Message" => message}} ->
            # If a chunk fails completely, add all its items to unprocessed
            IO.warn("DynamoDB error during batch write: #{message}")
            {processed_count, unprocessed_items ++ chunk}

          {:error, error} ->
            # If a chunk fails completely, add all its items to unprocessed
            IO.warn("AWS error during batch write: #{inspect(error)}")
            {processed_count, unprocessed_items ++ chunk}

          error ->
            # If a chunk fails completely, add all its items to unprocessed
            IO.warn("Unknown error during batch write: #{inspect(error)}")
            {processed_count, unprocessed_items ++ chunk}
        end
      end)

    # Decode unprocessed items back to their original struct format
    decoded_unprocessed =
      case unprocessed do
        [] -> []
        items ->
          # Extract actual items from PutRequest wrappers
          Enum.map(items, fn %{"PutRequest" => %{"Item" => item}} ->
            Dynamo.Helper.decode_item(item, as: module)
          end)
      end

    {:ok, %{
      processed_items: result,
      unprocessed_items: decoded_unprocessed
    }}
  end

  @doc """
  Performs a parallel scan of a DynamoDB table using multiple segments for improved performance with large datasets.

  This function divides the table into the specified number of segments and processes them concurrently,
  resulting in significantly faster scan operations for large tables.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `options` - Keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:segments` - Number of parallel segments (default: 4)
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:limit` - Maximum number of items to return
      * `:timeout` - Operation timeout in milliseconds (default: 60000)
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)

  ## Returns
    * `{:ok, items}` - Successfully scanned items
    * `{:ok, %{items: items, partial: true, errors: errors}}` - Partially successful scan with some errors
    * `{:error, error}` - Error occurred during scan, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.parallel_scan(User, segments: 8, limit: 1000)
      {:ok, [%User{...}, ...]}

      # With filter expression
      iex> Dynamo.Table.parallel_scan(User,
      ...>   filter_expression: "active = :active_val",
      ...>   expression_attribute_values: %{":active_val" => %{"BOOL" => true}}
      ...> )
      {:ok, [%User{...}, ...]}
  """
  @spec parallel_scan(module(), keyword()) ::
    {:ok, [struct()]} |
    {:ok, %{items: [struct()], partial: boolean(), errors: [any()]}} |
    {:error, Dynamo.Error.t()}
  def parallel_scan(schema_module, options \\ []) do
    table = schema_module.table_name()
    segments = options[:segments] || 4
    timeout = options[:timeout] || 60_000
    limit = options[:limit] || :infinity

    # Create base scan parameters that will be shared by all segments
    base_params = %{
      "TableName" => table,
      "ConsistentRead" => options[:consistent_read] || false
    }

    # Add optional parameters if provided
    base_params = if options[:filter_expression] do
      Map.put(base_params, "FilterExpression", options[:filter_expression])
    else
      base_params
    end

    base_params = if options[:projection_expression] do
      Map.put(base_params, "ProjectionExpression", options[:projection_expression])
    else
      base_params
    end

    # Add expression attribute values if provided
    base_params = if options[:expression_attribute_values] do
      Map.put(base_params, "ExpressionAttributeValues", options[:expression_attribute_values])
    else
      base_params
    end

    # Add expression attribute names if provided
    base_params = if options[:expression_attribute_names] do
      Map.put(base_params, "ExpressionAttributeNames", options[:expression_attribute_names])
    else
      base_params
    end

    # Create a range of segment indices
    segment_indices = 0..(segments - 1)

    # Execute parallel scans using Task.async_stream
    scan_results =
      Task.async_stream(
        segment_indices,
        fn segment ->
          scan_segment(base_params, segment, segments, limit)
        end,
        timeout: timeout,
        ordered: false,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:ok, items}}, {acc_items, acc_errors} ->
          {acc_items ++ items, acc_errors}
        {:ok, {:error, error}}, {acc_items, acc_errors} ->
          {acc_items, [error | acc_errors]}
        {:exit, reason}, {acc_items, acc_errors} ->
          {acc_items, [{:segment_error, reason} | acc_errors]}
      end)

    case scan_results do
      {items, []} when is_list(items) ->
        # All segments completed successfully
        items_with_limit = if limit != :infinity, do: Enum.take(items, limit), else: items
        decoded_items = Dynamo.Helper.decode_item(items_with_limit, as: schema_module)
        {:ok, decoded_items}

      {items, errors} when is_list(errors) and length(errors) < segments ->
        # Some segments failed but we have partial results
        items_with_limit = if limit != :infinity, do: Enum.take(items, limit), else: items
        decoded_items = Dynamo.Helper.decode_item(items_with_limit, as: schema_module)
        {:ok, %{
          items: decoded_items,
          partial: true,
          errors: errors
        }}

      {_items, errors} when length(errors) == segments ->
        # All segments failed
        {:error, {:scan_failed, errors}}
    end
  end

  # Helper function to scan a segment
  defp scan_segment(base_params, segment, total_segments, limit) do
    # Add segment information to the parameters
    segment_params = base_params
      |> Map.put("Segment", segment)
      |> Map.put("TotalSegments", total_segments)

    # Execute the scan for this segment with pagination handling
    scan_segment_with_pagination(segment_params, limit, [], nil)
  end

  # Handle pagination for segment scanning
  defp scan_segment_with_pagination(_params, limit, acc, _last_key)
       when limit != :infinity and length(acc) >= limit do
    {:ok, Enum.take(acc, limit)}
  end

  defp scan_segment_with_pagination(params, limit, acc, last_key) do
    # Add the exclusive start key for pagination if present
    scan_params = if last_key, do: Map.put(params, "ExclusiveStartKey", last_key), else: params

    case AWS.DynamoDB.scan(Dynamo.AWS.client(), scan_params) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => last_evaluated_key}, _} ->
        # Continue scanning if we have a last evaluated key
        scan_segment_with_pagination(params, limit, acc ++ items, last_evaluated_key)

      {:ok, %{"Items" => items}, _} ->
        # Final page for this segment
        {:ok, acc ++ items}

      {:error, %{"__type" => type, "Message" => message}} ->
        # Error scanning this segment
        {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

      {:error, error} ->
        # Error scanning this segment
        {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

      error ->
        # Error scanning this segment
        {:error, Dynamo.Error.new(:unknown_error, "Unknown error during scan", error)}
    end
  end

  @doc """
  Deletes an item from DynamoDB.

  Takes a struct that implements the required DynamoDB schema behavior and deletes the corresponding item.

  ## Parameters
    * `struct` - A struct containing the necessary keys for deletion
    * `opts` - Optional keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:condition_expression` - Optional condition expression for the delete operation
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:return_values` - What to return (NONE, ALL_OLD)

  ## Returns
    * `{:ok, deleted_item}` - Successfully deleted item (when return_values is ALL_OLD)
    * `{:ok, nil}` - Successfully deleted (when return_values is NONE)
    * `{:error, error}` - Error occurred during deletion, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.delete_item(%User{id: "123"})
      {:ok, nil}

      # With condition expression
      iex> Dynamo.Table.delete_item(%User{id: "123"},
      ...>   condition_expression: "attribute_exists(id)",
      ...>   return_values: "ALL_OLD"
      ...> )
      {:ok, %User{id: "123", name: "John"}}
  """
  @spec delete_item(struct(), keyword()) :: {:ok, struct() | nil} | {:error, Dynamo.Error.t()}
  def delete_item(struct, opts \\ []) when is_struct(struct) do
    # Validate struct has required fields
    if struct.__struct__.partition_key() == [] do
      {:error, Dynamo.Error.new(:validation_error, "Struct must have a partition key defined")}
    else
      pk = Dynamo.Schema.generate_partition_key(struct)
      sk = Dynamo.Schema.generate_sort_key(struct)
      table = struct.__struct__.table_name()
      config = struct.__struct__.settings()
      client = opts[:client] || Dynamo.AWS.client()

      partition_key_name = config[:partition_key_name]
      sort_key_name = config[:sort_key_name]

      # Build the base delete request
      payload = %{
        "TableName" => table,
        "Key" => %{
          partition_key_name => %{"S" => pk}
        }
      }

      # Add sort key if available
      payload = if sk != nil, do: put_in(payload, ["Key", sort_key_name], %{"S" => sk}), else: payload

      # Add optional parameters if provided
      payload = if opts[:return_values], do: Map.put(payload, "ReturnValues", opts[:return_values]), else: payload

      payload = if opts[:condition_expression] do
        Map.put(payload, "ConditionExpression", opts[:condition_expression])
      else
        payload
      end

      payload = if opts[:expression_attribute_names] do
        Map.put(payload, "ExpressionAttributeNames", opts[:expression_attribute_names])
      else
        payload
      end

      payload = if opts[:expression_attribute_values] do
        Map.put(payload, "ExpressionAttributeValues", opts[:expression_attribute_values])
      else
        payload
      end

      case AWS.DynamoDB.delete_item(client, payload) do
        {:ok, %{"Attributes" => attributes}, _} ->
          {:ok, attributes |> Dynamo.Helper.decode_item(as: struct.__struct__)}

        {:ok, _, _} ->
          {:ok, nil}

        {:error, %{"__type" => type, "Message" => message}} ->
          {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

        {:error, error} ->
          {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

        error ->
          {:error, Dynamo.Error.new(:unknown_error, "Unknown error during delete_item", error)}
      end
    end
  end

  @doc """
  Performs a scan of a DynamoDB table.

  Unlike parallel_scan, this function performs a simple scan that can be paginated and is suitable
  for smaller tables or when you need more control over the scanning process.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `options` - Keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:limit` - Maximum number of items to return
      * `:exclusive_start_key` - Key to start the scan from (for pagination)
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)

  ## Returns
    * `{:ok, %{items: items, last_evaluated_key: key}}` - Successfully scanned items with pagination key
    * `{:error, error}` - Error occurred during scan, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.scan(User)
      {:ok, %{items: [%User{...}, ...], last_evaluated_key: nil}}

      # With filter expression
      iex> Dynamo.Table.scan(User,
      ...>   filter_expression: "active = :active_val",
      ...>   expression_attribute_values: %{":active_val" => %{"BOOL" => true}}
      ...> )
      {:ok, %{items: [%User{...}, ...], last_evaluated_key: nil}}

      # With pagination
      iex> Dynamo.Table.scan(User, limit: 10)
      {:ok, %{items: [%User{...}, ...], last_evaluated_key: %{...}}}

      # Continue a paginated scan
      iex> Dynamo.Table.scan(User,
      ...>   exclusive_start_key: last_key,
      ...>   limit: 10
      ...> )
      {:ok, %{items: [%User{...}, ...], last_evaluated_key: %{...}}}
  """
  @spec scan(module(), keyword()) ::
    {:ok, %{items: [struct()], last_evaluated_key: map() | nil}} |
    {:error, Dynamo.Error.t()}
  def scan(schema_module, options \\ []) do
    table = schema_module.table_name()
    client = options[:client] || Dynamo.AWS.client()

    # Create scan parameters
    params = %{
      "TableName" => table
    }

    # Add optional parameters if provided
    params = if options[:filter_expression] do
      Map.put(params, "FilterExpression", options[:filter_expression])
    else
      params
    end

    params = if options[:projection_expression] do
      Map.put(params, "ProjectionExpression", options[:projection_expression])
    else
      params
    end

    params = if options[:expression_attribute_values] do
      Map.put(params, "ExpressionAttributeValues", options[:expression_attribute_values])
    else
      params
    end

    params = if options[:expression_attribute_names] do
      Map.put(params, "ExpressionAttributeNames", options[:expression_attribute_names])
    else
      params
    end

    params = if options[:consistent_read], do: Map.put(params, "ConsistentRead", true), else: params

    params = if options[:limit], do: Map.put(params, "Limit", options[:limit]), else: params

    params = if options[:exclusive_start_key] do
      Map.put(params, "ExclusiveStartKey", options[:exclusive_start_key])
    else
      params
    end

    case AWS.DynamoDB.scan(client, params) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => last_evaluated_key}, _} ->
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        {:ok, %{items: decoded_items, last_evaluated_key: last_evaluated_key}}

      {:ok, %{"Items" => items}, _} ->
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        {:ok, %{items: decoded_items, last_evaluated_key: nil}}

      {:error, %{"__type" => type, "Message" => message}} ->
        {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

      {:error, error} ->
        {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

      error ->
        {:error, Dynamo.Error.new(:unknown_error, "Unknown error during scan", error)}
    end
  end

  @doc """
  Updates an item in DynamoDB.

  Takes a struct that implements the required DynamoDB schema behavior and updates the corresponding item.

  ## Parameters
    * `struct` - A struct containing the necessary keys for identification
    * `updates` - Map of attribute updates
    * `opts` - Optional keyword list of options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:update_expression` - Custom update expression (overrides automatic generation from updates)
      * `:condition_expression` - Optional condition expression for the update operation
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:return_values` - What to return (NONE, ALL_OLD, ALL_NEW, UPDATED_OLD, UPDATED_NEW)

  ## Returns
    * `{:ok, updated_item}` - Successfully updated item (when return_values specified)
    * `{:ok, nil}` - Successfully updated (when return_values is NONE or not specified)
    * `{:error, error}` - Error occurred during update, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.update_item(%User{id: "123"}, %{name: "Jane", status: "active"})
      {:ok, nil}

      # With return values
      iex> Dynamo.Table.update_item(%User{id: "123"}, %{name: "Jane"}, return_values: "ALL_NEW")
      {:ok, %User{id: "123", name: "Jane", email: "jane@example.com"}}

      # With custom update expression
      iex> Dynamo.Table.update_item(%User{id: "123"}, %{},
      ...>   update_expression: "SET #name = :name, #count = #count + :inc",
      ...>   expression_attribute_names: %{"#name" => "name", "#count" => "login_count"},
      ...>   expression_attribute_values: %{":name" => %{"S" => "Jane"}, ":inc" => %{"N" => "1"}}
      ...> )
      {:ok, nil}
  """
  @spec update_item(struct(), map(), keyword()) :: {:ok, struct() | nil} | {:error, Dynamo.Error.t()}
  def update_item(struct, updates, opts \\ []) when is_struct(struct) do
    # Validate struct has required fields
    if struct.__struct__.partition_key() == [] do
      {:error, Dynamo.Error.new(:validation_error, "Struct must have a partition key defined")}
    else
      pk = Dynamo.Schema.generate_partition_key(struct)
      sk = Dynamo.Schema.generate_sort_key(struct)
      table = struct.__struct__.table_name()
      config = struct.__struct__.settings()
      client = opts[:client] || Dynamo.AWS.client()

      partition_key_name = config[:partition_key_name]
      sort_key_name = config[:sort_key_name]

      # Build the base update request
      payload = %{
        "TableName" => table,
        "Key" => %{
          partition_key_name => %{"S" => pk}
        }
      }

      # Add sort key if available
      payload = if sk != nil, do: put_in(payload, ["Key", sort_key_name], %{"S" => sk}), else: payload

      # Generate update expression or use the provided one
      {update_expression, expr_attr_names, expr_attr_values} =
        if opts[:update_expression] do
          {
            opts[:update_expression],
            opts[:expression_attribute_names] || %{},
            opts[:expression_attribute_values] || %{}
          }
        else
          build_update_expression(updates)
        end

      # Add update expression to payload
      payload = Map.put(payload, "UpdateExpression", update_expression)

      # Add expression attribute names if any
      payload = if map_size(expr_attr_names) > 0 do
        Map.put(payload, "ExpressionAttributeNames", expr_attr_names)
      else
        payload
      end

      # Add expression attribute values if any
      payload = if map_size(expr_attr_values) > 0 do
        Map.put(payload, "ExpressionAttributeValues", expr_attr_values)
      else
        payload
      end

      # Add optional parameters if provided
      payload = if opts[:return_values], do: Map.put(payload, "ReturnValues", opts[:return_values]), else: payload

      payload = if opts[:condition_expression] do
        Map.put(payload, "ConditionExpression", opts[:condition_expression])
      else
        payload
      end

      # Merge any additional expression attribute names and values
      payload = if opts[:expression_attribute_names] && !opts[:update_expression] do
        updated_names = Map.merge(
          payload["ExpressionAttributeNames"] || %{},
          opts[:expression_attribute_names]
        )
        Map.put(payload, "ExpressionAttributeNames", updated_names)
      else
        payload
      end

      payload = if opts[:expression_attribute_values] && !opts[:update_expression] do
        updated_values = Map.merge(
          payload["ExpressionAttributeValues"] || %{},
          opts[:expression_attribute_values]
        )
        Map.put(payload, "ExpressionAttributeValues", updated_values)
      else
        payload
      end

      case AWS.DynamoDB.update_item(client, payload) do
        {:ok, %{"Attributes" => attributes}, _} ->
          {:ok, attributes |> Dynamo.Helper.decode_item(as: struct.__struct__)}

        {:ok, _, _} ->
          {:ok, nil}

        {:error, %{"__type" => type, "Message" => message}} ->
          {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}

        {:error, error} ->
          {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}

        error ->
          {:error, Dynamo.Error.new(:unknown_error, "Unknown error during update_item", error)}
      end
    end
  end

  # Helper function to build update expressions
  defp build_update_expression(updates) when is_map(updates) do
    # Initialize accumulators
    {set_expressions, names, values} =
      Enum.reduce(updates, {[], %{}, %{}}, fn {key, value}, {set_exprs, names_acc, values_acc} ->
        # Generate placeholders for this key
        attr_name = "#attr_#{key}"
        attr_value = ":val_#{key}"

        # Add to expression and accumulators
        {
          [attr_name <> " = " <> attr_value | set_exprs],
          Map.put(names_acc, attr_name, to_string(key)),
          Map.put(values_acc, attr_value, encode_attribute_value(value))
        }
      end)

    # Build the final expression
    update_expression =
      case set_expressions do
        [] -> ""
        _ -> "SET " <> Enum.join(set_expressions, ", ")
      end

    {update_expression, names, values}
  end

  # Helper to encode attribute values for update expressions
  defp encode_attribute_value(value) do
    case value do
      %{"S" => _} -> value
      %{"N" => _} -> value
      %{"B" => _} -> value
      %{"BOOL" => _} -> value
      %{"NULL" => _} -> value
      %{"M" => _} -> value
      %{"L" => _} -> value
      %{"SS" => _} -> value
      %{"NS" => _} -> value
      %{"BS" => _} -> value
      _ ->
        # Need to encode it
        Dynamo.Encoder.encode(value)
    end
  end

  @doc """
  Retrieves multiple items from DynamoDB in a single batch request.

  Takes a list of structs that implement the required DynamoDB schema behavior and retrieves
  the corresponding items. All items must belong to the same table.

  Note: DynamoDB limits batch gets to 100 items per request. This function automatically handles
  chunking for larger batches.

  ## Parameters
    * `items` - List of structs containing the necessary keys for retrieval
    * `opts` - Keyword list of additional options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)

  ## Returns
    * `{:ok, result}` - Successfully processed batch with result containing:
      * `:items` - List of retrieved items
      * `:unprocessed_keys` - List of keys that couldn't be processed
    * `{:error, error}` - Error occurred during batch processing, where error is a `Dynamo.Error` struct

  ## Examples
      iex> Dynamo.Table.batch_get_item([%User{id: "123"}, %User{id: "456"}])
      {:ok, %{items: [%User{id: "123", ...}, %User{id: "456", ...}], unprocessed_keys: []}}

      # With consistent read
      iex> Dynamo.Table.batch_get_item([%User{id: "123"}, %User{id: "456"}], consistent_read: true)
      {:ok, %{items: [%User{id: "123", ...}, %User{id: "456", ...}], unprocessed_keys: []}}
  """
  @spec batch_get_item([struct()], keyword()) :: {:ok, map()} | {:error, Dynamo.Error.t()}
  def batch_get_item(items, opts \\ []) when is_list(items) and length(items) > 0 do
    # Validate all items have the same table and struct type
    first_item = List.first(items)
    module = first_item.__struct__
    table_name = module.table_name()
    config = module.settings()
    client = opts[:client] || Dynamo.AWS.client()

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    # Ensure all items are of the same type
    Enum.each(items, fn item ->
      unless item.__struct__ == module do
        raise ArgumentError, "All items must belong to the same schema"
      end
    end)

    # Generate keys for each item
    keys = Enum.map(items, fn item ->
      pk = Dynamo.Schema.generate_partition_key(item)
      sk = Dynamo.Schema.generate_sort_key(item)

      key = %{
        partition_key_name => %{"S" => pk}
      }

      # Add sort key if available
      if sk != nil, do: Map.put(key, sort_key_name, %{"S" => sk}), else: key
    end)

    # Build the table attributes
    table_attrs = %{}

    # Add consistent read if specified
    table_attrs = if opts[:consistent_read] do
      Map.put(table_attrs, "ConsistentRead", true)
    else
      table_attrs
    end

    # Add projection expression if specified
    table_attrs = if opts[:projection_expression] do
      Map.put(table_attrs, "ProjectionExpression", opts[:projection_expression])
    else
      table_attrs
    end

    # Add expression attribute names if specified
    table_attrs = if opts[:expression_attribute_names] do
      Map.put(table_attrs, "ExpressionAttributeNames", opts[:expression_attribute_names])
    else
      table_attrs
    end

    # Split keys into chunks of 100 (AWS limit)
    chunked_keys = Enum.chunk_every(keys, 100)

    # Track original key positions for proper unprocessed key handling
    original_keys = Enum.with_index(items) |> Enum.into(%{}, fn {item, idx} -> {idx, item} end)

    # Process each chunk and track results
    process_batch_get(chunked_keys, table_name, table_attrs, module, client, original_keys)
  end

  # Process batch get chunks
  defp process_batch_get(chunks, table_name, table_attrs, module, client, _original_keys) do
    # Process chunks sequentially, collecting results
    result = Enum.reduce_while(chunks, {[], []}, fn chunk, {items_acc, unprocessed_acc} ->
      # Create the batch get request
      keys_list = %{"Keys" => chunk}
      table_request = Map.merge(keys_list, table_attrs)

      batch_request = %{
        "RequestItems" => %{
          table_name => table_request
        }
      }

      case AWS.DynamoDB.batch_get_item(client, batch_request) do
        {:ok, %{"Responses" => %{^table_name => items}, "UnprocessedKeys" => %{^table_name => %{"Keys" => unprocessed}}}, _} ->
          # We have items and some unprocessed keys
          {:cont, {items_acc ++ items, unprocessed_acc ++ unprocessed}}

        {:ok, %{"Responses" => %{^table_name => items}, "UnprocessedKeys" => %{}}, _} ->
          # All keys were processed
          {:cont, {items_acc ++ items, unprocessed_acc}}

        {:ok, %{"Responses" => %{^table_name => items}}, _} ->
          # All keys were processed (no UnprocessedKeys in response)
          {:cont, {items_acc ++ items, unprocessed_acc}}

        {:ok, %{"Responses" => %{}}, _} ->
          # No items found for any key
          {:cont, {items_acc, unprocessed_acc}}

        {:error, %{"__type" => type, "Message" => message}} ->
          # Error processing this chunk - halt processing and return error
          {:halt, {:error, Dynamo.Error.new(:aws_error, "DynamoDB error: #{message}", %{type: type})}}

        {:error, error} ->
          # Error processing this chunk
          {:halt, {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}}

        error ->
          # Unknown error
          {:halt, {:error, Dynamo.Error.new(:unknown_error, "Unknown error during batch_get_item", error)}}
      end
    end)

    case result do
      {:error, _} = error ->
        error
      {retrieved_items, unprocessed} ->
        # Decode items back to their original struct format
        decoded_items = Dynamo.Helper.decode_item(retrieved_items, as: module)

        # Return retrieved items and unprocessed keys (empty if all processed)
        {:ok, %{
          items: decoded_items,
          unprocessed_keys: unprocessed
        }}
    end
  end
end
