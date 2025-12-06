# DynamoDB Streaming Examples
#
# This file contains practical examples of using Dynamo's streaming capabilities.
# Run with: mix run examples/streaming_examples.exs

defmodule StreamingExamples do
  @moduledoc """
  Practical examples demonstrating DynamoDB streaming patterns.
  """

  # Example schema
  defmodule User do
    use Dynamo.Schema

    item do
      table_name "users"

      field :id, partition_key: true
      field :email, sort_key: true
      field :name
      field :tenant_id
      field :status, default: "active"
      field :age
      field :created_at
    end
  end

  @doc """
  Example 1: Simple sequential streaming
  Process users one at a time with minimal memory usage.
  """
  def example_1_sequential_stream do
    IO.puts("\n=== Example 1: Sequential Stream ===")

    Dynamo.Table.stream_scan(User)
    |> Stream.filter(&(&1.status == "active"))
    |> Stream.map(fn user ->
      IO.puts("Processing user: #{user.email}")
      user
    end)
    |> Enum.take(10)
    |> length()
    |> then(&IO.puts("Processed #{&1} users"))
  end

  @doc """
  Example 2: Parallel streaming with Flow
  High-throughput processing with automatic backpressure.
  """
  def example_2_parallel_with_flow do
    IO.puts("\n=== Example 2: Parallel Stream with Flow ===")

    Dynamo.Table.stream_parallel_scan(User, segments: 4)
    |> Flow.from_enumerable(max_demand: 500)
    |> Flow.partition()
    |> Flow.map(fn user ->
      # Simulate processing
      Process.sleep(1)
      {user.tenant_id, 1}
    end)
    |> Flow.partition(key: {:elem, 0})
    |> Flow.reduce(fn -> %{} end, fn {tenant_id, count}, acc ->
      Map.update(acc, tenant_id, count, &(&1 + count))
    end)
    |> Enum.to_list()
    |> then(fn results ->
      IO.puts("Users per tenant:")
      Enum.each(results, fn {tenant_id, count} ->
        IO.puts("  #{tenant_id}: #{count}")
      end)
    end)
  end

  @doc """
  Example 3: Send to process pattern
  Real-time processing with a GenServer consumer.
  """
  def example_3_send_to_process do
    IO.puts("\n=== Example 3: Send to Process ===")

    # Start consumer
    {:ok, consumer} = UserConsumer.start_link()

    # Start streaming to consumer
    {:ok, task} =
      Dynamo.Table.stream_scan_to_process(
        User,
        consumer,
        segments: 4,
        batch_size: 10
      )

    # Wait for completion
    Task.await(task, :infinity)

    # Get final stats
    stats = UserConsumer.get_stats(consumer)
    IO.puts("Final stats: #{inspect(stats)}")
  end

  @doc """
  Example 4: Export to CSV
  Stream large table to CSV file efficiently.
  """
  def example_4_export_to_csv(filename \\ "users_export.csv") do
    IO.puts("\n=== Example 4: Export to CSV ===")

    file = File.open!(filename, [:write, :utf8])

    try do
      # Write header
      IO.write(file, "id,email,name,status,created_at\n")

      # Stream and write
      count =
        Dynamo.Table.stream_scan(User, page_size: 500)
        |> Stream.with_index()
        |> Stream.each(fn {user, index} ->
          line = "#{user.id},#{user.email},#{user.name},#{user.status},#{user.created_at}\n"
          IO.write(file, line)

          if rem(index, 1000) == 0 do
            IO.puts("Exported #{index} users...")
          end
        end)
        |> Enum.count()

      IO.puts("Exported #{count} users to #{filename}")
    after
      File.close(file)
    end
  end

  @doc """
  Example 5: Data transformation pipeline
  Transform and migrate data using GenStage.
  """
  def example_5_genstage_pipeline do
    IO.puts("\n=== Example 5: GenStage Pipeline ===")

    children = [
      # Producer - scans DynamoDB
      {Dynamo.Table.Stream.Producer,
       schema: User, name: UserProducer, segments: 4, page_size: 100},

      # ProducerConsumer - transforms data
      {DataTransformer, subscribe_to: [UserProducer]},

      # Consumer - processes transformed data
      {DataProcessor, subscribe_to: [DataTransformer]}
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

    # Wait a bit for processing
    Process.sleep(5000)

    # Stop supervisor
    Supervisor.stop(supervisor)

    IO.puts("Pipeline completed")
  end

  @doc """
  Example 6: Conditional processing
  Different processing based on user attributes.
  """
  def example_6_conditional_processing do
    IO.puts("\n=== Example 6: Conditional Processing ===")

    Dynamo.Table.stream_scan(User)
    |> Stream.chunk_every(100)
    |> Stream.each(fn batch ->
      # Separate by status
      {active, inactive} = Enum.split_with(batch, &(&1.status == "active"))

      # Process in parallel
      Task.async(fn ->
        IO.puts("Processing #{length(active)} active users")
        Enum.each(active, &process_active_user/1)
      end)

      Task.async(fn ->
        IO.puts("Processing #{length(inactive)} inactive users")
        Enum.each(inactive, &process_inactive_user/1)
      end)
    end)
    |> Stream.run()
  end

  @doc """
  Example 7: Aggregation with Flow
  Calculate statistics across large dataset.
  """
  def example_7_aggregation do
    IO.puts("\n=== Example 7: Aggregation ===")

    stats =
      Dynamo.Table.stream_parallel_scan(User, segments: 8)
      |> Flow.from_enumerable(max_demand: 1000)
      |> Flow.partition()
      |> Flow.reduce(
        fn -> %{total: 0, by_status: %{}, age_sum: 0, age_count: 0} end,
        fn user, acc ->
          acc
          |> Map.update!(:total, &(&1 + 1))
          |> Map.update!(:by_status, fn status_map ->
            Map.update(status_map, user.status, 1, &(&1 + 1))
          end)
          |> Map.update!(:age_sum, &(&1 + (user.age || 0)))
          |> Map.update!(:age_count, &(&1 + if(user.age, do: 1, else: 0)))
        end
      )
      |> Enum.reduce(%{total: 0, by_status: %{}, age_sum: 0, age_count: 0}, fn partition_stats,
                                                                                 global_stats ->
        %{
          total: global_stats.total + partition_stats.total,
          by_status:
            Map.merge(global_stats.by_status, partition_stats.by_status, fn _k, v1, v2 ->
              v1 + v2
            end),
          age_sum: global_stats.age_sum + partition_stats.age_sum,
          age_count: global_stats.age_count + partition_stats.age_count
        }
      end)

    avg_age = if stats.age_count > 0, do: stats.age_sum / stats.age_count, else: 0

    IO.puts("Statistics:")
    IO.puts("  Total users: #{stats.total}")
    IO.puts("  Average age: #{Float.round(avg_age, 2)}")
    IO.puts("  By status:")

    Enum.each(stats.by_status, fn {status, count} ->
      IO.puts("    #{status}: #{count}")
    end)
  end

  @doc """
  Example 8: Rate-limited processing
  Process items with controlled rate to avoid overwhelming external APIs.
  """
  def example_8_rate_limited do
    IO.puts("\n=== Example 8: Rate Limited Processing ===")

    start_time = System.monotonic_time(:millisecond)

    count =
      Dynamo.Table.stream_scan(User, page_size: 50)
      |> Stream.each(fn user ->
        # Simulate API call
        call_external_api(user)

        # Rate limit: 10 requests per second
        Process.sleep(100)
      end)
      |> Enum.take(50)
      |> length()

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    IO.puts("Processed #{count} users in #{duration}ms")
    IO.puts("Rate: #{Float.round(count / (duration / 1000), 2)} users/second")
  end

  # Helper functions

  defp process_active_user(user) do
    # Simulate processing
    Process.sleep(1)
    {:ok, user}
  end

  defp process_inactive_user(user) do
    # Simulate processing
    Process.sleep(1)
    {:ok, user}
  end

  defp call_external_api(user) do
    # Simulate API call
    Process.sleep(10)
    {:ok, user}
  end
end

# Consumer GenServer for Example 3
defmodule UserConsumer do
  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{})
  end

  def get_stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  def init(_) do
    state = %{
      total: 0,
      batches: 0,
      by_status: %{}
    }

    {:ok, state}
  end

  def handle_info({:scan_batch, users}, state) do
    new_state =
      Enum.reduce(users, state, fn user, acc ->
        acc
        |> Map.update!(:total, &(&1 + 1))
        |> Map.update!(:by_status, fn status_map ->
          Map.update(status_map, user.status, 1, &(&1 + 1))
        end)
      end)
      |> Map.update!(:batches, &(&1 + 1))

    if rem(new_state.batches, 10) == 0 do
      IO.puts("Processed #{new_state.total} users in #{new_state.batches} batches")
    end

    {:noreply, new_state}
  end

  def handle_info(:scan_complete, state) do
    IO.puts("Scan complete! Total users: #{state.total}")
    {:noreply, state}
  end

  def handle_info({:scan_error, error}, state) do
    IO.puts("Scan error: #{inspect(error)}")
    {:noreply, state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end
end

# GenStage components for Example 5
defmodule DataTransformer do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:producer_consumer, %{count: 0}, subscribe_to: opts[:subscribe_to]}
  end

  def handle_events(users, _from, state) do
    # Transform users
    transformed =
      Enum.map(users, fn user ->
        %{user | email: String.downcase(user.email)}
      end)

    new_count = state.count + length(users)

    if rem(new_count, 100) == 0 do
      IO.puts("Transformed #{new_count} users")
    end

    {:noreply, transformed, %{state | count: new_count}}
  end
end

defmodule DataProcessor do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  def init(opts) do
    {:consumer, %{count: 0}, subscribe_to: opts[:subscribe_to]}
  end

  def handle_events(users, _from, state) do
    # Process users (e.g., save to database)
    Enum.each(users, fn user ->
      # Simulate processing
      Process.sleep(1)
    end)

    new_count = state.count + length(users)

    if rem(new_count, 100) == 0 do
      IO.puts("Processed #{new_count} users")
    end

    {:noreply, [], %{state | count: new_count}}
  end
end

# Run examples
IO.puts("DynamoDB Streaming Examples")
IO.puts("===========================")

# Uncomment to run specific examples:
# StreamingExamples.example_1_sequential_stream()
# StreamingExamples.example_2_parallel_with_flow()
# StreamingExamples.example_3_send_to_process()
# StreamingExamples.example_4_export_to_csv()
# StreamingExamples.example_5_genstage_pipeline()
# StreamingExamples.example_6_conditional_processing()
# StreamingExamples.example_7_aggregation()
# StreamingExamples.example_8_rate_limited()

IO.puts("\nTo run examples, uncomment the desired example calls at the end of this file.")
