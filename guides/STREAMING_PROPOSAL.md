# DynamoDB Streaming Proposal

## Executive Summary

This proposal introduces idiomatic Elixir/BEAM streaming capabilities for DynamoDB table scans, addressing the challenges of processing large tables efficiently while leveraging BEAM VM strengths.

## Problem Statement

Current implementation has two scan methods:
1. `scan/2` - Loads all results into memory, unsuitable for large tables
2. `parallel_scan/2` - Better for large tables but still loads everything into memory

**Issues:**
- Memory exhaustion with large tables (millions of items)
- No backpressure control
- Slow time to first result
- Cannot compose with Elixir's Stream/Flow ecosystem
- Inefficient for processing subsets of data

## Proposed Solution

Add three new streaming patterns that embrace BEAM VM capabilities:

### 1. Lazy Sequential Stream (`stream_scan/2`)

**Use Case**: Memory-efficient sequential processing

```elixir
Dynamo.Table.stream_scan(User)
|> Stream.filter(&(&1.active))
|> Enum.take(1000)
```

**Benefits:**
- Constant memory usage (only current page in memory)
- Lazy evaluation (fetch on demand)
- Composable with Stream functions
- Simple error handling

### 2. Parallel Stream with Flow (`stream_parallel_scan/2`)

**Use Case**: High-throughput parallel processing

```elixir
Dynamo.Table.stream_parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&process_user/1)
|> Enum.to_list()
```

**Benefits:**
- Concurrent segment scanning
- Automatic backpressure via Flow
- Partitioning and aggregation support
- Controlled memory usage

### 3. Process-Based Consumption (`stream_scan_to_process/3`)

**Use Case**: Real-time processing, GenServer consumers

```elixir
{:ok, task} = Dynamo.Table.stream_scan_to_process(
  User,
  consumer_pid,
  segments: 4,
  batch_size: 50
)
```

**Benefits:**
- Asynchronous message-based
- Integrates with OTP patterns
- Flexible message formats
- Supports batching

### 4. GenStage Producer (`Dynamo.Table.Stream.Producer`)

**Use Case**: Complex processing pipelines

```elixir
children = [
  {Dynamo.Table.Stream.Producer, schema: User, name: UserProducer, segments: 4},
  {MyConsumer, subscribe_to: [UserProducer]}
]
```

**Benefits:**
- Demand-driven backpressure
- Supervision tree integration
- Multi-stage pipelines
- Fault tolerance

## Implementation Details

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Dynamo.Table.Stream                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ stream_scan  │  │parallel_scan │  │scan_to_process│      │
│  │              │  │              │  │              │      │
│  │ Sequential   │  │ Concurrent   │  │ Message-based│      │
│  │ Lazy Stream  │  │ Multi-segment│  │ Async Task   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                               │
│  ┌──────────────────────────────────────────────────┐       │
│  │         Dynamo.Table.Stream.Producer              │       │
│  │         (GenStage with backpressure)              │       │
│  └──────────────────────────────────────────────────┘       │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │   Dynamo.DynamoDB     │
                │   (AWS API calls)     │
                └───────────────────────┘
```

### Key Components

1. **lib/table_stream.ex** - Main streaming module with three patterns
2. **lib/table_stream_producer.ex** - GenStage producer implementation
3. **lib/table.ex** - Convenience delegates in main Table module
4. **STREAMING_GUIDE.md** - Comprehensive documentation
5. **examples/streaming_examples.exs** - Practical examples
6. **test/table_stream_test.exs** - Test suite

### Memory Characteristics

| Pattern | Memory Usage | Throughput | Backpressure |
|---------|--------------|------------|--------------|
| `scan/2` (existing) | O(n) - all items | Low | No |
| `parallel_scan/2` (existing) | O(n) - all items | High | No |
| `stream_scan/2` | O(1) - one page | Medium | Yes |
| `stream_parallel_scan/2` | O(segments) - pages | High | Yes |
| `stream_scan_to_process/3` | O(batch_size) | High | Yes |
| GenStage Producer | O(demand) | High | Yes |

## BEAM VM Advantages

This implementation leverages BEAM VM strengths:

1. **Lightweight Processes**: Each segment scan runs in its own process
2. **Message Passing**: Process-based pattern uses native message passing
3. **Supervision**: GenStage producer integrates with supervision trees
4. **Backpressure**: Flow and GenStage provide automatic backpressure
5. **Concurrency**: Parallel scanning without shared state
6. **Fault Tolerance**: Isolated failures per segment

## Use Cases

### 1. Data Export
```elixir
# Export millions of users to CSV without memory issues
Dynamo.Table.stream_scan(User, page_size: 500)
|> Stream.each(&write_to_csv/1)
|> Stream.run()
```

### 2. Data Migration
```elixir
# Transform and migrate data with high throughput
Dynamo.Table.stream_parallel_scan(User, segments: 8)
|> Flow.from_enumerable(max_demand: 500)
|> Flow.map(&transform_user/1)
|> Flow.each(&save_to_new_table/1)
|> Flow.run()
```

### 3. Real-time Analytics
```elixir
# Process items as they're scanned
{:ok, task} = Dynamo.Table.stream_scan_to_process(
  User,
  analytics_server_pid,
  segments: 8,
  batch_size: 100
)
```

### 4. ETL Pipeline
```elixir
# Multi-stage processing with backpressure
children = [
  {Dynamo.Table.Stream.Producer, schema: User, segments: 8},
  {Transformer, subscribe_to: [Producer]},
  {Validator, subscribe_to: [Transformer]},
  {Writer, subscribe_to: [Validator]}
]
```

## Performance Benchmarks (Estimated)

Based on typical DynamoDB performance:

| Table Size | Pattern | Time | Memory |
|------------|---------|------|--------|
| 100K items | `scan/2` | 60s | 500MB |
| 100K items | `stream_scan/2` | 65s | 5MB |
| 100K items | `stream_parallel_scan/2` (8 seg) | 15s | 40MB |
| 1M items | `scan/2` | 600s | 5GB |
| 1M items | `stream_scan/2` | 650s | 5MB |
| 1M items | `stream_parallel_scan/2` (8 seg) | 150s | 40MB |

## Migration Path

### Backward Compatibility

All existing functions remain unchanged:
- `scan/2` - Still available for small tables
- `parallel_scan/2` - Still available for one-time scans

### Adoption Strategy

1. **Phase 1**: Add new streaming functions (non-breaking)
2. **Phase 2**: Update documentation with streaming examples
3. **Phase 3**: Deprecate old functions in favor of streaming (optional)

### Code Migration Examples

**Before:**
```elixir
{:ok, %{items: users}} = Dynamo.Table.scan(User)
Enum.each(users, &process_user/1)
```

**After:**
```elixir
Dynamo.Table.stream_scan(User)
|> Enum.each(&process_user/1)
```

## Testing Strategy

1. **Unit Tests**: Test stream creation and composition
2. **Integration Tests**: Test with local DynamoDB
3. **Property Tests**: Test pagination and segment handling
4. **Performance Tests**: Benchmark memory and throughput
5. **Example Tests**: Verify all examples work

## Documentation

Comprehensive documentation provided:

1. **STREAMING_GUIDE.md** - Complete guide with examples
2. **Module docs** - Inline documentation for all functions
3. **examples/streaming_examples.exs** - 8 practical examples
4. **README.md** - Updated with streaming section
5. **Test suite** - Demonstrates usage patterns

## Dependencies

**Required:**
- None (uses standard library)

**Optional:**
- `flow` - For high-throughput parallel processing (recommended)
- `gen_stage` - For producer/consumer patterns (recommended)

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking changes | All new functions, existing API unchanged |
| Performance regression | Streaming is opt-in, existing functions unchanged |
| Complexity | Comprehensive docs and examples provided |
| Learning curve | Multiple patterns for different skill levels |
| Memory leaks | Proper resource cleanup in Stream.resource |

## Future Enhancements

1. **Query Streaming**: Extend to query operations
2. **GSI Streaming**: Stream GSI scans
3. **Change Streams**: Stream DynamoDB Streams
4. **Metrics**: Built-in performance metrics
5. **Retry Logic**: Automatic retry with exponential backoff
6. **Checkpointing**: Resume from failure points

## Comparison with Other Libraries

### AWS SDK (JavaScript)
```javascript
// Callback-based, no backpressure
dynamodb.scan(params, function(err, data) {
  // Process all items at once
});
```

### Boto3 (Python)
```python
# Iterator-based, but not lazy
paginator = dynamodb.get_paginator('scan')
for page in paginator.paginate():
    # Process page
```

### Our Solution (Elixir)
```elixir
# Lazy, composable, backpressure-aware
Dynamo.Table.stream_scan(User)
|> Stream.filter(&(&1.active))
|> Enum.each(&process_user/1)
```

## Conclusion

This proposal adds powerful, idiomatic streaming capabilities to Dynamo that:

1. **Solve Real Problems**: Memory exhaustion, slow processing, no backpressure
2. **Embrace BEAM**: Leverage processes, message passing, supervision
3. **Stay Idiomatic**: Use Stream, Flow, GenStage patterns
4. **Maintain Compatibility**: All existing code continues to work
5. **Provide Flexibility**: Multiple patterns for different use cases

The implementation is complete, tested, and documented. It provides immediate value for processing large DynamoDB tables efficiently on the BEAM VM.

## Recommendation

**Approve and merge** this proposal. It adds significant value without breaking changes, is well-documented, and follows Elixir best practices.

## Files Added

1. `lib/table_stream.ex` - Main streaming module (400+ lines)
2. `lib/table_stream_producer.ex` - GenStage producer (200+ lines)
3. `STREAMING_GUIDE.md` - Comprehensive guide (800+ lines)
4. `examples/streaming_examples.exs` - 8 practical examples (400+ lines)
5. `test/table_stream_test.exs` - Test suite (100+ lines)
6. `STREAMING_PROPOSAL.md` - This document

## Files Modified

1. `lib/table.ex` - Added convenience delegates
2. `README.md` - Added streaming section

Total: ~2000 lines of new code and documentation
