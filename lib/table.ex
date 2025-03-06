defmodule Dynamo.Table do
   @moduledoc """
  Provides functions for interacting with DynamoDB tables.
  This module handles basic CRUD operations and query building for DynamoDB tables.
  """

@doc """
  Puts an item into DynamoDB.

  Takes a struct that implements the required DynamoDB schema behavior and writes it to the corresponding table.

  ## Parameters
    * `struct` - A struct that implements the DynamoDB schema behavior

  ## Returns
    * `{:ok, item}` - Successfully inserted item
    * `{:error, error}` - Error occurred during insertion

  ## Examples
      iex> Dynamo.Table.put_item(%User{id: "123", name: "John"})
      {:ok, %User{id: "123", name: "John"}}
  """
  def put_item(struct) when is_struct(struct) do
    item = struct.__struct__.before_write(struct)

    table = struct.__struct__.table_name()

    payload = %{"TableName" => table, "Item" => item}

    case AWS.DynamoDB.put_item(Dynamo.AWS.client(), payload) do
      {:ok, _, _} -> {:ok, item |> Dynamo.Helper.decode_item(as: struct.__struct__)}
      error -> {:error, error}
    end
  end

  @doc """
  Alias for `put_item/1`
  """
  defdelegate insert(struct), to: __MODULE__, as: :put_item

  @doc """
  Retrieves an item from DynamoDB using partition key and optional sort key.

  ## Parameters
    * `struct` - A struct containing the necessary keys for retrieval

  ## Returns
    * `{:ok, item}` - The retrieved item
    * `{:ok, nil}` - No item found
    * `{:error, error}` - Error occurred during retrieval

  ## Examples
      iex> Dynamo.Table.get_item(%User{id: "123"})
      {:ok, %{"id" => %{"S" => "123"}, "name" => %{"S" => "John"}}}
  """
  def get_item(struct) when is_struct(struct) do
    pk = Dynamo.Schema.generate_partition_key(struct)
    sk = Dynamo.Schema.generate_sort_key(struct)
    table = struct.__struct__.table_name
    config = struct.__struct__.settings()

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    query = %{
      "TableName" => table,
      "Key" => %{
        partition_key_name => %{"S" => pk}
      }
    }

    query = if sk != nil, do: put_in(query, ["Key", sort_key_name], %{"S" => sk}), else: query

    case AWS.DynamoDB.get_item(Dynamo.AWS.client(), query) do
      {:ok, %{"Item" => item}, _} -> {:ok, item |> Dynamo.Helper.decode_item(as: struct.__struct__)}
      {:ok, %{}, _} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Builds a DynamoDB query with the given partition key and options.

  ## Parameters
    * `pk` - Partition key value
    * `options` - Keyword list of options:
      * `:sort_key` - Sort key value (optional)
      * `:sk_operator` - Sort key operator (`:full_match` or `:begins_with`)
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
    {sk, sk_operator} =
      case {sk, options[:sk_operator]} do
        {nil, nil} -> {nil, nil}
        {nil, _val2} -> raise "InvalidVariablesError"
        {val1, nil} -> {val1, :full_match}
        {val1, val2} -> {val1, val2}
      end

    query = if sk != nil do
      query = put_in(query, ["ExpressionAttributeValues", ":sk"], %{"S" => sk})

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
    * List of items or error tuple
  """
  def query(query) do
    query(query, :infinity, [], nil)
  end

  @doc """
  Executes a DynamoDB query with a specified limit.

  ## Parameters
    * `query` - Map containing the DynamoDB query
    * `limit` - Maximum number of items to return

  ## Returns
    * List of items or error tuple
  """
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

      {:error, error} ->
        {:error, error}
    end
  end

  # all items with this PK
  @doc """
  Lists all items for a given struct's partition key.

  ## Parameters
    * `struct` - Struct containing the partition key information

  ## Returns
    * List of items or error tuple

  ## Examples
      iex> Dynamo.Table.list_items(%User{id: "123"})
      [%{"id" => %{"S" => "123"}, ...}]
  """
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
      * `:sk_operator` - Sort key operator (`:full_match` or `:begins_with`)
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
    * `options` - Keyword list of additional options (reserved for future use)

  ## Returns
    * `{:ok, result}` - Successfully processed batch with result containing:
      * `:processed_items` - Number of successfully processed items
      * `:unprocessed_items` - List of items that couldn't be processed
    * `{:error, reason}` - Error occurred during batch processing

  ## Examples
      iex> Dynamo.Table.batch_write_item([%User{id: "123"}, %User{id: "456"}])
      {:ok, %{processed_items: 2, unprocessed_items: []}}
  """
  def batch_write_item(items, options \\ []) when is_list(items) and length(items) > 0 do
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

          {:error, error} ->
            # If a chunk fails completely, add all its items to unprocessed
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
      * `:segments` - Number of parallel segments (default: 4)
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:limit` - Maximum number of items to return
      * `:timeout` - Operation timeout in milliseconds (default: 60000)
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)

  ## Returns
    * `{:ok, items}` - Successfully scanned items
    * `{:error, reason}` - Error occurred during scan

  ## Examples
      iex> Dynamo.Table.parallel_scan(User, segments: 8, limit: 1000)
      {:ok, [%User{...}, ...]}
  """
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

      {:error, error} ->
        # Error scanning this segment
        {:error, error}
    end
  end
end
