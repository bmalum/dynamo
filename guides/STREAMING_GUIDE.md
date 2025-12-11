# DynamoDB Streaming Guide

This guide explains how to efficiently stream large DynamoDB tables using Dynamo's streaming capabilities, designed specifically for the BEAM VM.

## Table of Contents

- [Why Streaming?](#why-streaming)
- [Streaming Patterns](#streaming-patterns)
- [API Reference](#api-reference)
- [Performance Considerations](#performance-considerations)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Why Streaming?

Traditional scan operations load all results into memory before returning, which can cause issues with large tables:

- **Memory Exhaustion**: Loading millions of items can crash your application
- **Slow Time to First Result**: Must wait for entire scan to complete
- **No Backpressure**: Can overwhelm downstream consumers
- **Inefficient**: Fetches data you might not need

Streaming solves these problems by:

- **Lazy Evaluation**: Fetches pages on-demand as needed
- **Constant Memory**: Only keeps current page in memory
- **Backpressure Support**: Consumers control the flow rate
- **Composable**: Works with Elixir's Stream and Flow modules
- **Concurrent**: Parallel scanning with multiple segments

## Streaming Patterns

Dynamo provides three streaming patterns for different use cases:

### 1. Lazy Sequential Stream

**Best for**: Memory-efficient processing where order matters or you need fine-grained control.

```elixir
# Basic usage
Dynamo.Table.Stream.scan(User)
|> Stream.filter(&(&1.active))
|> Stream.map(&transform_user/1)
|> Enum.take(1000)

# Process in chunks
Dynamo.Table.Stream.scan(User, page_size: 50)
|> Stream.chunk_every(100)
|> Enum.each(&batch_process/1)
```

**Characteristics**:
- Single-threaded sequential scanning
- Minimal memory footprint
- Predictable ordering
- Simple error handling

### 2. Parallel Stream with Flow

**Best for**: High-throughput processing of large tables where order doesn't matter.

```elixir
# Basic parallel processing
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.partition()
|> Flow.map(&process_user/1)
|> Enum.to_list()

# Advanced aggregation
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 1000)
|> Flow.partition(key: {:key, :tenant_id})
|> Flow.reduce(fn -> %{} end, fn user, acc ->
  Map.update(acc, user.tenant_id, 1, &(&1 + 1))
end)
|> Enum.to_list()
```

**Characteristics**:
- Multi-segment concurrent scanning
- Automatic backpressure via Flow
- High throughput
- Built-in partitioning and aggregation

### 3. Process-Based Consumption

**Best for**: Real-time processing, GenServer consumers, or event-driven architectures.

```elixir
# Send to a GenServer
{:ok, task} = Dynamo.Table.Stream.scan_to_process(User, consumer_pid)

# Parallel with batching
{:ok, task} = Dynamo.Table.Stream.scan_to_process(
  User,
  consumer_pid,
  segments: 8,
  batch_size: 50
)

# Consumer implementation
defmodule UserConsumer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{count: 0})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_info({:scan_item, user}, state) do
    # Process individual user
    process_user(user)
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_info({:scan_batch, users}, state) do
    # Process batch of users
    Enum.each(users, &process_user/1)
    {:noreply, %{state | count: state.count + length(users)}}
  end

  def handle_info(:scan_complete, state) do
    IO.puts("Processed #{state.count} users")
    {:noreply, state}
  end

  def handle_info({:scan_error, error}, state) do
    IO.puts("Error: #{inspect(error)}")
    {:noreply, state}
  end
end
```

**Characteristics**:
- Asynchronous message-based
- Integrates with OTP patterns
- Flexible message formats
- Supports batching

## API Reference

### `Dynamo.Table.Stream.scan/2`

Creates a lazy stream for sequential scanning.

**Options**:
- `:filter_expression` - DynamoDB filter expression
- `:projection_expression` - Attributes to retrieve
- `:expression_attribute_names` - Attribute name placeholders
- `:expression_attribute_values` - Attribute value placeholders
- `:consistent_read` - Use strongly consistent reads (default: false)
- `:page_size` - Items per page (default: 100)

**Returns**: `Enumerable.t()`

### `Dynamo.Table.Stream.parallel_scan/2`

Creates a parallel stream using multiple segments.

**Options**: Same as `stream_scan/2` plus:
- `:segments` - Number of parallel segments (default: 4)
- `:max_concurrency` - Maximum concurrent segment scans (default: segments)

**Returns**: `Enumerable.t()`

### `Dynamo.Table.Stream.scan_to_process/3`

Scans and sends items to a process.

**Options**: Same as `stream_parallel_scan/2` plus:
- `:message_format` - Format of messages (default: `{:scan_item, :item}`)
- `:completion_message` - Completion message (default: `:scan_complete`)
- `:error_message` - Error message format (default: `{:scan_error, :error}`)
- `:batch_size` - Send items in batches (default: 1)

**Returns**: `{:ok, task_pid}` or `{:error, reason}`

### `Dynamo.Table.Stream.Producer`

GenStage producer for demand-driven scanning.

```elixir
# In supervision tree
children = [
  {Dynamo.Table.Stream.Producer, 
   schema: User, 
   name: UserProducer, 
   segments: 4},
  {MyConsumer, subscribe_to: [UserProducer]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Performance Considerations

### Choosing the Right Pattern

| Use Case | Pattern | Segments | Page Size |
|----------|---------|----------|-----------|
| Small table (<10k items) | `stream_scan` | 1 | 100-500 |
| Large table, sequential | `stream_scan` | 1 | 500-1000 |
| Large table, parallel | `stream_parallel_scan` | 4-16 | 100-500 |
| Real-time processing | `stream_scan_to_process` | 4-8 | 50-200 |
| Maximum throughput | `stream_parallel_scan` + Flow | 8-32 | 500-1000 |

### Segment Count Guidelines

- **Small tables (<100k items)**: 1-4 segments
- **Medium tables (100k-1M items)**: 4-8 segments
- **Large tables (>1M items)**: 8-32 segments
- **Rule of thumb**: 1 segment per 100k-500k items

### Page Size Guidelines

- **Small items (<1KB)**: 500-1000 items per page
- **Medium items (1-10KB)**: 100-500 items per page
- **Large items (>10KB)**: 50-100 items per page
- **Consider**: DynamoDB's 1MB response limit

### Memory Usage

```elixir
# Low memory - processes one item at a time
Dynamo.Table.Stream.scan(User, page_size: 100)
|> Enum.each(&process_user/1)

# Medium memory - processes in chunks
Dynamo.Table.Stream.scan(User, page_size: 500)
|> Stream.chunk_every(100)
|> Enum.each(&batch_process/1)

# Higher memory - parallel with buffering
Dynamo.Table.Stream.parallel_scan(User, segments: 8, page_size: 500)
|> Flow.from_enumerable(max_demand: 1000)
|> Flow.map(&process_user/1)
|> Enum.to_list()
```

## Best Practices

### 1. Use Appropriate Filters

Apply filters at the DynamoDB level to reduce data transfer:

```elixir
# Good - filter at DynamoDB
Dynamo.Table.Stream.scan(User,
  filter_expression: "active = :val AND age > :min_age",
  expression_attribute_values: %{
    ":val" => %{"BOOL" => true},
    ":min_age" => %{"N" => "18"}
  }
)

# Less efficient - filter in Elixir
Dynamo.Table.Stream.scan(User)
|> Stream.filter(&(&1.active and &1.age > 18))
```

### 2. Handle Errors Gracefully

```elixir
# With try/rescue
try do
  Dynamo.Table.Stream.scan(User)
  |> Enum.each(&process_user/1)
rescue
  error ->
    Logger.error("Scan failed: #{inspect(error)}")
    # Handle error
end

# With Stream.each for side effects
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  try do
    process_user(user)
  rescue
    error ->
      Logger.error("Failed to process user #{user.id}: #{inspect(error)}")
  end
end)
|> Stream.run()
```

### 3. Monitor Progress

```elixir
# Track progress
Dynamo.Table.Stream.scan(User)
|> Stream.with_index()
|> Stream.each(fn {user, index} ->
  if rem(index, 1000) == 0 do
    IO.puts("Processed #{index} users")
  end
  process_user(user)
end)
|> Stream.run()
```

### 4. Use Projection Expressions

Only fetch the attributes you need:

```elixir
Dynamo.Table.Stream.scan(User,
  projection_expression: "id, email, #name",
  expression_attribute_names: %{"#name" => "name"}
)
```

### 5. Implement Backpressure

```elixir
# With Flow for automatic backpressure
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&slow_process/1)  # Flow handles backpressure
|> Enum.to_list()

# Manual rate limiting
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  process_user(user)
  Process.sleep(10)  # Rate limit
end)
|> Stream.run()
```

## Examples

### Example 1: Export to CSV

```elixir
defmodule UserExporter do
  def export_to_csv(filename) do
    file = File.open!(filename, [:write, :utf8])
    
    # Write header
    IO.write(file, "id,email,name,created_at\n")
    
    # Stream users and write to CSV
    Dynamo.Table.Stream.scan(User, page_size: 500)
    |> Stream.each(fn user ->
      line = "#{user.id},#{user.email},#{user.name},#{user.created_at}\n"
      IO.write(file, line)
    end)
    |> Stream.run()
    
    File.close(file)
  end
end
```

### Example 2: Data Migration

```elixir
defmodule DataMigration do
  def migrate_users do
    Dynamo.Table.Stream.parallel_scan(User, segments: 8)
    |> Flow.from_enumerable(max_demand: 500)
    |> Flow.map(&transform_user/1)
    |> Flow.partition()
    |> Flow.each(&save_to_new_table/1)
    |> Flow.run()
  end
  
  defp transform_user(user) do
    %{user | 
      email: String.downcase(user.email),
      updated_at: DateTime.utc_now()
    }
  end
  
  defp save_to_new_table(user) do
    Dynamo.Table.put_item(user)
  end
end
```

### Example 3: Real-time Analytics

```elixir
defmodule AnalyticsProcessor do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def start_scan do
    pid = Process.whereis(__MODULE__)
    Dynamo.Table.Stream.scan_to_process(
      User,
      pid,
      segments: 8,
      batch_size: 100
    )
  end
  
  def init(_) do
    state = %{
      total: 0,
      by_tenant: %{},
      by_status: %{}
    }
    {:ok, state}
  end
  
  def handle_info({:scan_batch, users}, state) do
    new_state = Enum.reduce(users, state, fn user, acc ->
      acc
      |> update_in([:total], &(&1 + 1))
      |> update_in([:by_tenant, user.tenant_id], fn
        nil -> 1
        count -> count + 1
      end)
      |> update_in([:by_status, user.status], fn
        nil -> 1
        count -> count + 1
      end)
    end)
    
    {:noreply, new_state}
  end
  
  def handle_info(:scan_complete, state) do
    IO.puts("Analytics complete!")
    IO.inspect(state)
    {:noreply, state}
  end
end
```

### Example 4: Conditional Processing

```elixir
defmodule ConditionalProcessor do
  def process_users do
    Dynamo.Table.Stream.scan(User)
    |> Stream.chunk_every(100)
    |> Stream.each(fn batch ->
      # Separate users by type
      {premium, regular} = Enum.split_with(batch, &(&1.premium))
      
      # Process differently
      Task.async(fn -> process_premium_users(premium) end)
      process_regular_users(regular)
    end)
    |> Stream.run()
  end
  
  defp process_premium_users(users) do
    # High-priority processing
    Enum.each(users, &send_premium_email/1)
  end
  
  defp process_regular_users(users) do
    # Standard processing
    Enum.each(users, &send_regular_email/1)
  end
end
```

### Example 5: GenStage Pipeline

```elixir
defmodule ScanPipeline do
  def start_link do
    children = [
      # Producer - scans DynamoDB
      {Dynamo.Table.Stream.Producer,
       schema: User,
       name: UserProducer,
       segments: 8,
       page_size: 500},
      
      # ProducerConsumer - transforms data
      {Transformer, subscribe_to: [UserProducer]},
      
      # Consumer - saves to database
      {DatabaseWriter, subscribe_to: [Transformer]}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule Transformer do
  use GenStage
  
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    {:producer_consumer, %{}, subscribe_to: opts[:subscribe_to]}
  end
  
  def handle_events(users, _from, state) do
    transformed = Enum.map(users, &transform_user/1)
    {:noreply, transformed, state}
  end
  
  defp transform_user(user) do
    # Transform logic
    %{user | email: String.downcase(user.email)}
  end
end

defmodule DatabaseWriter do
  use GenStage
  
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    {:consumer, %{}, subscribe_to: opts[:subscribe_to]}
  end
  
  def handle_events(users, _from, state) do
    # Batch write to database
    Enum.each(users, &save_to_db/1)
    {:noreply, [], state}
  end
  
  defp save_to_db(user) do
    # Save logic
    :ok
  end
end
```

## Comparison with Existing Functions

| Function | Memory | Speed | Backpressure | Use Case |
|----------|--------|-------|--------------|----------|
| `scan/2` | High | Slow | No | Small tables, pagination |
| `parallel_scan/2` | High | Fast | No | Medium tables, one-time scans |
| `stream_scan/2` | Low | Medium | Yes | Large tables, sequential |
| `stream_parallel_scan/2` | Medium | Fast | Yes | Large tables, parallel |
| `stream_scan_to_process/3` | Low | Fast | Yes | Real-time, event-driven |

## Troubleshooting

### Issue: Stream is slow

**Solution**: Increase page size or use parallel scanning:

```elixir
# Increase page size
Dynamo.Table.Stream.scan(User, page_size: 1000)

# Or use parallel scanning
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
```

### Issue: Running out of memory

**Solution**: Reduce page size or process items individually:

```elixir
# Smaller pages
Dynamo.Table.Stream.scan(User, page_size: 50)
|> Enum.each(&process_user/1)
```

### Issue: Overwhelming downstream systems

**Solution**: Add rate limiting or use Flow with controlled demand:

```elixir
# Rate limiting
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  process_user(user)
  Process.sleep(10)
end)
|> Stream.run()

# Flow with backpressure
Dynamo.Table.Stream.parallel_scan(User, segments: 4)
|> Flow.from_enumerable(max_demand: 100)
|> Flow.map(&process_user/1)
|> Enum.to_list()
```

### Issue: Need to resume after failure

**Solution**: Track progress and use pagination:

```elixir
defmodule ResumableScan do
  def scan_with_checkpoint(checkpoint_file) do
    last_key = load_checkpoint(checkpoint_file)
    
    scan_page(last_key, checkpoint_file)
  end
  
  defp scan_page(last_key, checkpoint_file) do
    opts = if last_key, do: [exclusive_start_key: last_key], else: []
    
    case Dynamo.Table.scan(User, opts ++ [limit: 1000]) do
      {:ok, %{items: items, last_evaluated_key: next_key}} ->
        # Process items
        Enum.each(items, &process_user/1)
        
        # Save checkpoint
        if next_key do
          save_checkpoint(checkpoint_file, next_key)
          scan_page(next_key, checkpoint_file)
        end
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end
  
  defp load_checkpoint(file) do
    case File.read(file) do
      {:ok, content} -> Jason.decode!(content)
      _ -> nil
    end
  end
  
  defp save_checkpoint(file, key) do
    File.write!(file, Jason.encode!(key))
  end
end
```

## Conclusion

Dynamo's streaming capabilities provide powerful, memory-efficient ways to process large DynamoDB tables on the BEAM VM. Choose the pattern that best fits your use case:

- **Sequential processing**: Use `stream_scan/2`
- **High throughput**: Use `stream_parallel_scan/2` with Flow
- **Real-time/event-driven**: Use `stream_scan_to_process/3`
- **Complex pipelines**: Use `Dynamo.Table.Stream.Producer` with GenStage

All patterns leverage BEAM's strengths: lightweight processes, message passing, and supervision trees.
