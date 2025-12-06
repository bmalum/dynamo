defmodule Dynamo.Table.Stream.Producer do
  @moduledoc """
  GenStage producer for streaming DynamoDB scan results with backpressure.

  This producer implements demand-driven scanning, only fetching pages from
  DynamoDB when consumers request more items. This provides automatic
  backpressure control and prevents overwhelming downstream consumers.

  ## Usage

  Add to your supervision tree:

      children = [
        {Dynamo.Table.Stream.Producer, schema: User, name: UserProducer, segments: 4},
        {MyConsumer, subscribe_to: [UserProducer]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Or start manually:

      {:ok, producer} = Dynamo.Table.Stream.Producer.start_link(
        schema: User,
        segments: 4,
        filter_expression: "active = :val",
        expression_attribute_values: %{":val" => %{"BOOL" => true}}
      )

      GenStage.stream([{producer, max_demand: 500}])
      |> Enum.each(&process_item/1)
  """

  use GenStage

  require Logger

  @doc """
  Starts a DynamoDB scan producer.

  ## Options
    * `:schema` - Schema module (required)
    * `:name` - Name to register the producer
    * `:segments` - Number of parallel segments (default: 1)
    * `:page_size` - Items per page (default: 100)
    * All other options from `Dynamo.Table.Stream.scan/2`
  """
  def start_link(opts) do
    schema = Keyword.fetch!(opts, :schema)
    name = Keyword.get(opts, :name)

    if name do
      GenStage.start_link(__MODULE__, opts, name: name)
    else
      GenStage.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    schema_module = Keyword.fetch!(opts, :schema)
    segments = Keyword.get(opts, :segments, 1)
    page_size = Keyword.get(opts, :page_size, 100)

    table = schema_module.table_name()

    # Build scan parameters
    base_params = build_scan_params(table, opts, page_size)

    # Initialize segment states
    segment_states =
      if segments > 1 do
        # Parallel scan - create state for each segment
        0..(segments - 1)
        |> Enum.map(fn segment ->
          params =
            base_params
            |> Map.put("Segment", segment)
            |> Map.put("TotalSegments", segments)

          %{
            params: params,
            last_key: nil,
            done: false,
            segment: segment
          }
        end)
      else
        # Sequential scan - single segment
        [%{params: base_params, last_key: nil, done: false, segment: 0}]
      end

    state = %{
      schema_module: schema_module,
      segments: segment_states,
      buffer: [],
      demand: 0
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    # Add to accumulated demand
    new_demand = state.demand + incoming_demand

    # Try to fulfill demand from buffer or fetch more
    fulfill_demand(%{state | demand: new_demand})
  end

  # Private functions

  defp fulfill_demand(%{demand: 0} = state) do
    # No demand, just return current state
    {:noreply, [], state}
  end

  defp fulfill_demand(%{buffer: buffer, demand: demand} = state) when length(buffer) >= demand do
    # Buffer has enough items to fulfill demand
    {items_to_send, remaining_buffer} = Enum.split(buffer, demand)
    {:noreply, items_to_send, %{state | buffer: remaining_buffer, demand: 0}}
  end

  defp fulfill_demand(%{buffer: buffer, demand: demand, segments: segments} = state) do
    # Need to fetch more items
    # Find a segment that's not done
    case find_active_segment(segments) do
      nil ->
        # All segments are done, send remaining buffer and stop
        {:noreply, buffer, %{state | buffer: [], demand: 0}}

      segment_index ->
        # Fetch next page from this segment
        segment = Enum.at(segments, segment_index)

        case fetch_segment_page(segment, state.schema_module) do
          {:ok, items, updated_segment} ->
            # Update segment state
            updated_segments = List.replace_at(segments, segment_index, updated_segment)

            # Add items to buffer
            new_buffer = buffer ++ items

            # Try to fulfill demand again
            fulfill_demand(%{state | buffer: new_buffer, segments: updated_segments})

          {:error, error} ->
            # Log error and mark segment as done
            Logger.error("DynamoDB scan error on segment #{segment.segment}: #{inspect(error)}")
            updated_segment = %{segment | done: true}
            updated_segments = List.replace_at(segments, segment_index, updated_segment)

            # Continue with other segments
            fulfill_demand(%{state | segments: updated_segments})
        end
    end
  end

  defp find_active_segment(segments) do
    Enum.find_index(segments, fn seg -> !seg.done end)
  end

  defp fetch_segment_page(%{done: true} = segment, _schema_module) do
    {:ok, [], segment}
  end

  defp fetch_segment_page(%{params: params, last_key: last_key} = segment, schema_module) do
    # Add exclusive start key if we have one
    scan_params =
      if last_key do
        Map.put(params, "ExclusiveStartKey", last_key)
      else
        params
      end

    case Dynamo.DynamoDB.scan(Dynamo.AWS.client(), scan_params) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => next_key}, _} ->
        # Decode items
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        updated_segment = %{segment | last_key: next_key}
        {:ok, decoded_items, updated_segment}

      {:ok, %{"Items" => items}, _} ->
        # Last page for this segment
        decoded_items = Dynamo.Helper.decode_item(items, as: schema_module)
        updated_segment = %{segment | done: true}
        {:ok, decoded_items, updated_segment}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_scan_params(table, options, page_size) do
    params = %{
      "TableName" => table,
      "Limit" => page_size,
      "ConsistentRead" => Keyword.get(options, :consistent_read, false)
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
end
