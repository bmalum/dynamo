# DynamoDB Streaming Quick Start

Get started with streaming large DynamoDB tables in 5 minutes.

## Installation

No additional dependencies required! Streaming is built into Dynamo.

**Optional** (for advanced features):
```elixir
# mix.exs
def deps do
  [
    {:dynamo, github: "bmalum/dynamo"},
    {:flow, "~> 1.2"},      # For parallel processing with backpressure
    {:gen_stage, "~> 1.2"}  # For producer/consumer patterns
  ]
end
```

## Choose Your Pattern

### Pattern 1: Simple Sequential Stream (Start Here!)

**When to use**: Processing items one at a time, memory is limited, order matters.

```elixir
# Process active users
Dynamo.Table.Stream.scan(User)
|> Stream.filter(&(&1.status == "active"))
|> Stream.map(&send_email/1)
|> Stream.run()

# Export to CSV
Dynamo.Table.Stream.scan(User, page_size: 500)
|> Stream.each(&write_to_csv/1)
|> Stream.run()

# Take first 1000
Dynamo.Table.Stream.scan(User)
|> Enum.take(1000)
```

**Memory**: ~5MB (constant)  
**Speed**: Medium  
**Complexity**: Low ⭐

### Pattern 2: Parallel Stream with Flow

**When to use**: Large tables, high throughput needed, order doesn't matter.

```elixir
# Process millions of users in parallel
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&process_user/1)
|> Enum.to_list()

# Aggregate data
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
|> Flow.from_enumerable()
|> Flow.partition(key: {:key, :tenant_id})
|> Flow.reduce(fn -> %{} end, fn user, acc ->
  Map.update(acc, user.tenant_id, 1, &(&1 + 1))
end)
|> Enum.to_list()
```

**Memory**: ~40MB (segments × page_size)  
**Speed**: Fast  
**Complexity**: Medium ⭐⭐

### Pattern 3: Send to Process

**When to use**: Real-time processing, GenServer consumers, event-driven.

```elixir
# Start consumer
{:ok, consumer} = MyConsumer.start_link()

# Stream to consumer
{:ok, task} = Dynamo.Table.Stream.scan_to_process(
  User,
  consumer,
  segments: 4,
  batch_size: 50
)

# Consumer receives messages:
# {:scan_batch, [user1, user2, ...]}
# :scan_complete
```

**Memory**: ~10MB (batch_size × segments)  
**Speed**: Fast  
**Complexity**: Medium ⭐⭐

## Common Recipes

### Recipe 1: Filter at DynamoDB Level

```elixir
# Good - filter at DynamoDB (less data transfer)
Dynamo.Table.Stream.scan(User,
  filter_expression: "age > :min_age AND status = :status",
  expression_attribute_values: %{
    ":min_age" => %{"N" => "18"},
    ":status" => %{"S" => "active"}
  }
)
|> Enum.to_list()
```

### Recipe 2: Process in Batches

```elixir
# Process 100 items at a time
Dynamo.Table.Stream.scan(User, page_size: 500)
|> Stream.chunk_every(100)
|> Enum.each(fn batch ->
  # Process batch
  batch_process(batch)
end)
```

### Recipe 3: Track Progress

```elixir
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

### Recipe 4: Handle Errors

```elixir
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  try do
    process_user(user)
  rescue
    error ->
      Logger.error("Failed to process #{user.id}: #{inspect(error)}")
  end
end)
|> Stream.run()
```

### Recipe 5: Rate Limiting

```elixir
# Process 10 items per second
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  process_user(user)
  Process.sleep(100)  # 100ms = 10/second
end)
|> Stream.run()
```

## Performance Tuning

### Choosing Segment Count

```elixir
# Small table (<100K items)
segments: 1-4

# Medium table (100K-1M items)
segments: 4-8

# Large table (>1M items)
segments: 8-32

# Rule of thumb: 1 segment per 100K-500K items
```

### Choosing Page Size

```elixir
# Small items (<1KB)
page_size: 500-1000

# Medium items (1-10KB)
page_size: 100-500

# Large items (>10KB)
page_size: 50-100

# Remember: DynamoDB has 1MB response limit
```

### Memory vs Speed Trade-offs

```elixir
# Lowest memory (5MB)
Dynamo.Table.Stream.scan(User, page_size: 100)
|> Enum.each(&process_user/1)

# Balanced (40MB)
Dynamo.Table.Stream.parallel_scan(User, segments: 4, page_size: 200)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&process_user/1)
|> Enum.to_list()

# Highest speed (100MB+)
Dynamo.Table.Stream.parallel_scan(User, segments: 16, page_size: 500)
|> Flow.from_enumerable(max_demand: 1000)
|> Flow.map(&process_user/1)
|> Enum.to_list()
```

## Real-World Examples

### Example 1: Export 1M Users to CSV

```elixir
defmodule UserExporter do
  def export(filename) do
    file = File.open!(filename, [:write, :utf8])
    IO.write(file, "id,email,name\n")
    
    count = Dynamo.Table.Stream.scan(User, page_size: 500)
    |> Stream.each(fn user ->
      IO.write(file, "#{user.id},#{user.email},#{user.name}\n")
    end)
    |> Enum.count()
    
    File.close(file)
    IO.puts("Exported #{count} users")
  end
end

# Usage
UserExporter.export("users.csv")
```

### Example 2: Data Migration

```elixir
defmodule DataMigration do
  def migrate do
    Dynamo.Table.Stream.parallel_scan(User, segments: 8)
    |> Flow.from_enumerable(max_demand: 500)
    |> Flow.map(&transform_user/1)
    |> Flow.each(&save_to_new_table/1)
    |> Flow.run()
  end
  
  defp transform_user(user) do
    %{user | email: String.downcase(user.email)}
  end
  
  defp save_to_new_table(user) do
    Dynamo.Table.put_item(user)
  end
end

# Usage
DataMigration.migrate()
```

### Example 3: Real-time Analytics

```elixir
defmodule Analytics do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{total: 0, by_status: %{}}, name: __MODULE__)
  end
  
  def start_scan do
    pid = Process.whereis(__MODULE__)
    Dynamo.Table.Stream.scan_to_process(User, pid, 
      segments: 8,
      batch_size: 100
    )
  end
  
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def init(state), do: {:ok, state}
  
  def handle_info({:scan_batch, users}, state) do
    new_state = Enum.reduce(users, state, fn user, acc ->
      acc
      |> Map.update!(:total, &(&1 + 1))
      |> update_in([:by_status, user.status], fn
        nil -> 1
        count -> count + 1
      end)
    end)
    {:noreply, new_state}
  end
  
  def handle_info(:scan_complete, state) do
    IO.puts("Scan complete! Stats: #{inspect(state)}")
    {:noreply, state}
  end
  
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end
end

# Usage
{:ok, _} = Analytics.start_link([])
{:ok, _task} = Analytics.start_scan()
# Wait for completion...
stats = Analytics.get_stats()
```

## Troubleshooting

### Problem: Stream is slow

**Solution**: Use parallel scanning
```elixir
# Instead of:
Dynamo.Table.Stream.scan(User)

# Use:
Dynamo.Table.Stream.parallel_scan(User, segments: 8)
```

### Problem: Running out of memory

**Solution**: Reduce page size
```elixir
Dynamo.Table.Stream.scan(User, page_size: 50)
|> Enum.each(&process_user/1)
```

### Problem: Overwhelming downstream system

**Solution**: Add rate limiting
```elixir
Dynamo.Table.Stream.scan(User)
|> Stream.each(fn user ->
  process_user(user)
  Process.sleep(100)  # Rate limit
end)
|> Stream.run()
```

## Next Steps

1. **Read the full guide**: [STREAMING_GUIDE.md](STREAMING_GUIDE.md)
2. **Try examples**: [examples/streaming_examples.exs](examples/streaming_examples.exs)
3. **Check tests**: [test/table_stream_test.exs](test/table_stream_test.exs)

## Quick Reference

| Function | Use Case | Memory | Speed |
|----------|----------|--------|-------|
| `stream_scan/2` | Sequential, low memory | Low | Medium |
| `stream_parallel_scan/2` | Parallel, high throughput | Medium | High |
| `stream_scan_to_process/3` | Real-time, event-driven | Low | High |

## Getting Help

- Full documentation: [STREAMING_GUIDE.md](STREAMING_GUIDE.md)
- Examples: [examples/streaming_examples.exs](examples/streaming_examples.exs)
- Module docs: `h Dynamo.Table.Stream`

Happy streaming! 🚀
