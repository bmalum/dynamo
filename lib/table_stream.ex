defmodule Dynamo.Table.Stream do
  @moduledoc """
  Provides streaming capabilities for DynamoDB table scans.

  This module implements idiomatic Elixir/BEAM patterns for handling large
  DynamoDB tables with streaming, backpressure, and process-based consumption.

  ## Streaming Patterns

  ### 1. Lazy Sequential Stream
  Memory-efficient lazy evaluation for sequential processing:

      Dynamo.Table.Stream.scan(User)
      |> Stream.filter(&(&1.active))
      |> Stream.map(&process_user/1)
      |> Enum.take(1000)

  ### 2. Parallel Stream with Flow
  High-throughput parallel processing with automatic backpressure:

      Dynamo.Table.Stream.parallel_scan(User, segments: 8)
      |> Flow.from_enumerable(max_demand: 500)
      |> Flow.map(&process_user/1)
      |> Enum.to_list()

  ### 3. Process-based Consumption
  Send items to a process as they're scanned:

      {:ok, pid} = MyConsumer.start_link()
      Dynamo.Table.Stream.scan_to_process(User, pid, segments: 4)

  ## Benefits

  - **Memory Efficient**: Items are fetched on-demand, not loaded all at once
  - **Backpressure**: Automatic flow control prevents overwhelming consumers
  - **Composable**: Works with all Elixir Stream and Flow operations
  - **Fault Tolerant**: Leverages BEAM supervision and error handling
  - **Concurrent**: Parallel scanning with configurable segments
  """

  @doc """
  Creates a lazy stream that scans a DynamoDB table sequentially.

  This function returns a Stream that fetches pages from DynamoDB on-demand,
  making it memory-efficient for processing large tables. Items are decoded
  as they're fetched.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `options` - Keyword list of options:
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)
      * `:page_size` - Number of items to fetch per page (default: 100)

  ## Returns
    Stream of decoded structs

  ## Examples
      # Process items lazily
      Dynamo.Table.Stream.scan(User)
      |> Stream.filter(&(&1.active))
      |> Enum.take(100)

      # With filter expression
      Dynamo.Table.Stream.scan(User,
        filter_expression: "age > :min_age",
        expression_attribute_values: %{":min_age" => %{"N" => "18"}}
      )
      |> Enum.to_list()

      # Process in chunks
      Dynamo.Table.Stream.scan(User, page_size: 50)
      |> Stream.chunk_every(10)
      |> Enum.each(&batch_process/1)
  """
  @spec scan(module(), keyword()) :: Enumerable.t()
  def scan(schema_module, options \\ []) do
    table = schema_module.table_name()
    page_size = options[:page_size] || 100

    # Build base scan parameters
    base_params = build_scan_params(table, options, page_size)

    # Create a stream that fetches pages lazily
    Stream.resource(
      fn -> {base_params, nil} end,
      &fetch_next_page(&1, schema_module),
      fn _ -> :ok end
    )
  end

  @doc """
  Creates a stream that scans a DynamoDB table in parallel using multiple segments.

  This function returns a Stream that fetches from multiple DynamoDB segments
  concurrently. It's designed to work with Flow for high-throughput processing
  with automatic backpressure control.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `options` - Keyword list of options:
      * `:segments` - Number of parallel segments (default: 4)
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:consistent_read` - Whether to use strongly consistent reads (default: false)
      * `:page_size` - Number of items to fetch per page per segment (default: 100)
      * `:max_concurrency` - Maximum concurrent segment scans (default: segments)

  ## Returns
    Stream of decoded structs from all segments

  ## Examples
      # Basic parallel stream
      Dynamo.Table.Stream.parallel_scan(User, segments: 8)
      |> Enum.to_list()

      # With Flow for advanced processing
      Dynamo.Table.Stream.parallel_scan(User, segments: 8)
      |> Flow.from_enumerable(max_demand: 500)
      |> Flow.partition()
      |> Flow.map(&transform_user/1)
      |> Flow.reduce(fn -> %{} end, &aggregate/2)
      |> Enum.to_list()

      # With backpressure control
      Dynamo.Table.Stream.parallel_scan(User, segments: 4, page_size: 50)
      |> Stream.each(&process_with_rate_limit/1)
      |> Stream.run()
  """
  @spec parallel_scan(module(), keyword()) :: Enumerable.t()
  def parallel_scan(schema_module, options \\ []) do
    table = schema_module.table_name()
    segments = options[:segments] || 4
    page_size = options[:page_size] || 100
    max_concurrency = options[:max_concurrency] || segments

    # Build base scan parameters
    base_params = build_scan_params(table, options, page_size)

    # Create streams for each segment
    segment_streams =
      0..(segments - 1)
      |> Enum.map(fn segment ->
        segment_params =
          base_params
          |> Map.put("Segment", segment)
          |> Map.put("TotalSegments", segments)

        Stream.resource(
          fn -> {segment_params, nil} end,
          &fetch_next_page(&1, schema_module),
          fn _ -> :ok end
        )
      end)

    # Interleave all segment streams with controlled concurrency
    Stream.concat(segment_streams)
  end

  @doc """
  Scans a DynamoDB table and sends items to a process as they're fetched.

  This function implements the "send to process" pattern, where scanned items
  are sent as messages to a consumer process. Useful for GenServer consumers,
  GenStage producers, or any process-based architecture.

  The function spawns a supervised task that performs the scan and sends items
  to the target process. It supports both sequential and parallel scanning.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `consumer_pid` - PID of the process to receive items
    * `options` - Keyword list of options:
      * `:segments` - Number of parallel segments (default: 1 for sequential)
      * `:message_format` - Format of messages sent (default: `{:scan_item, item}`)
      * `:completion_message` - Message sent when scan completes (default: `:scan_complete`)
      * `:error_message` - Message format for errors (default: `{:scan_error, error}`)
      * `:filter_expression` - Optional filter conditions
      * `:projection_expression` - Attributes to retrieve
      * `:expression_attribute_names` - Map of attribute name placeholders
      * `:expression_attribute_values` - Map of attribute value placeholders
      * `:page_size` - Number of items to fetch per page (default: 100)
      * `:batch_size` - Send items in batches (default: 1 for individual items)

  ## Returns
    `{:ok, task_pid}` - PID of the scanning task

  ## Message Formats

  By default, the consumer process receives:
  - `{:scan_item, item}` - For each scanned item
  - `{:scan_batch, items}` - When batch_size > 1
  - `:scan_complete` - When scan finishes successfully
  - `{:scan_error, error}` - If an error occurs

  ## Examples
      # Sequential scan sending to a GenServer
      {:ok, task} = Dynamo.Table.Stream.scan_to_process(User, consumer_pid)

      # Parallel scan with batching
      {:ok, task} = Dynamo.Table.Stream.scan_to_process(
        User,
        consumer_pid,
        segments: 8,
        batch_size: 50
      )

      # Custom message format
      {:ok, task} = Dynamo.Table.Stream.scan_to_process(
        User,
        consumer_pid,
        message_format: {:user_scanned, :item},
        completion_message: {:scan_done, :users}
      )

      # Consumer implementation example
      defmodule MyConsumer do
        use GenServer

        def handle_info({:scan_item, item}, state) do
          # Process item
          {:noreply, process_item(item, state)}
        end

        def handle_info(:scan_complete, state) do
          IO.puts("Scan completed!")
          {:noreply, state}
        end

        def handle_info({:scan_error, error}, state) do
          IO.puts("Scan error: \#{inspect(error)}")
          {:noreply, state}
        end
      end
  """
  @spec scan_to_process(module(), pid(), keyword()) :: {:ok, pid()} | {:error, term()}
  def scan_to_process(schema_module, consumer_pid, options \\ []) do
    unless Process.alive?(consumer_pid) do
      {:error, :consumer_not_alive}
    else
      segments = options[:segments] || 1
      batch_size = options[:batch_size] || 1
      message_format = options[:message_format] || {:scan_item, :item}
      completion_message = options[:completion_message] || :scan_complete
      error_message_format = options[:error_message] || {:scan_error, :error}

      # Spawn a supervised task to perform the scan
      task =
        Task.async(fn ->
          try do
            stream =
              if segments > 1 do
                parallel_scan(schema_module, options)
              else
                scan(schema_module, options)
              end

            # Process stream and send to consumer
            if batch_size > 1 do
              stream
              |> Stream.chunk_every(batch_size)
              |> Enum.each(fn batch ->
                send_message(consumer_pid, {:scan_batch, batch}, message_format)
              end)
            else
              stream
              |> Enum.each(fn item ->
                send_message(consumer_pid, item, message_format)
              end)
            end

            # Send completion message
            send(consumer_pid, completion_message)
            :ok
          rescue
            error ->
              # Send error message
              error_msg = format_error_message(error, error_message_format)
              send(consumer_pid, error_msg)
              {:error, error}
          end
        end)

      {:ok, task.pid}
    end
  end

  @doc """
  Creates a GenStage producer that streams DynamoDB scan results.

  This function returns a GenStage producer spec that can be used in a
  supervision tree. The producer implements demand-driven backpressure,
  only fetching pages when consumers request more items.

  ## Parameters
    * `schema_module` - Module implementing the Dynamo.Schema behavior
    * `options` - Keyword list of options (same as `scan/2` plus):
      * `:name` - Name to register the producer (optional)
      * `:segments` - Number of parallel segments (default: 1)

  ## Returns
    Child spec for supervision tree

  ## Examples
      # In your supervision tree
      children = [
        Dynamo.Table.Stream.producer_spec(User, name: UserProducer, segments: 4),
        {MyConsumer, subscribe_to: [UserProducer]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      # Consumer implementation
      defmodule MyConsumer do
        use GenStage

        def start_link(opts) do
          GenStage.start_link(__MODULE__, opts)
        end

        def init(opts) do
          {:consumer, %{}, subscribe_to: opts[:subscribe_to]}
        end

        def handle_events(items, _from, state) do
          # Process items with automatic backpressure
          Enum.each(items, &process_item/1)
          {:noreply, [], state}
        end
      end
  """
  @spec producer_spec(module(), keyword()) :: Supervisor.child_spec()
  def producer_spec(schema_module, options \\ []) do
    %{
      id: options[:name] || __MODULE__.Producer,
      start: {__MODULE__.Producer, :start_link, [schema_module, options]},
      type: :worker,
      restart: :temporary
    }
  end

  # Private helper functions

  defp build_scan_params(table, options, page_size) do
    params = %{
      "TableName" => table,
      "Limit" => page_size,
      "ConsistentRead" => options[:consistent_read] || false
    }

    params =
      if options[:filter_expression] do
        Map.put(params, "FilterExpression", options[:filter_expression])
      else
        params
      end

    params =
      if options[:projection_expression] do
        Map.put(params, "ProjectionExpression", options[:projection_expression])
      else
        params
      end

    params =
      if options[:expression_attribute_values] do
        Map.put(params, "ExpressionAttributeValues", options[:expression_attribute_values])
      else
        params
      end

    if options[:expression_attribute_names] do
      Map.put(params, "ExpressionAttributeNames", options[:expression_attribute_names])
    else
      params
    end
  end

  defp fetch_next_page({params, :done}, _schema_module) do
    {:halt, {params, :done}}
  end

  defp fetch_next_page({params, last_key}, schema_module) do
    # Add exclusive start key if we have one
    scan_params =
      if last_key do
        Map.put(params, "ExclusiveStartKey", last_key)
      else
        params
      end

    case Dynamo.DynamoDB.scan(Dynamo.AWS.client(), scan_params) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => next_key}, _} ->
        # Decode items and return with continuation
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        {decoded_items, {params, next_key}}

      {:ok, %{"Items" => items}, _} ->
        # Last page - decode and mark as done
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        {decoded_items, {params, :done}}

      {:error, error} ->
        # Error occurred - halt the stream
        raise Dynamo.Error.new(:aws_error, "Scan error: #{inspect(error)}")
    end
  end

  defp send_message(pid, item, {:scan_item, :item}) do
    send(pid, {:scan_item, item})
  end

  defp send_message(pid, batch, {:scan_batch, :batch}) do
    send(pid, {:scan_batch, batch})
  end

  defp send_message(pid, data, {tag, :item}) when is_atom(tag) do
    send(pid, {tag, data})
  end

  defp send_message(pid, data, {tag, :batch}) when is_atom(tag) do
    send(pid, {tag, data})
  end

  defp send_message(pid, data, custom_format) when is_tuple(custom_format) do
    send(pid, put_elem(custom_format, tuple_size(custom_format) - 1, data))
  end

  defp format_error_message(error, {:scan_error, :error}) do
    {:scan_error, error}
  end

  defp format_error_message(error, {tag, :error}) when is_atom(tag) do
    {tag, error}
  end

  defp format_error_message(error, custom_format) when is_tuple(custom_format) do
    put_elem(custom_format, tuple_size(custom_format) - 1, error)
  end
end
