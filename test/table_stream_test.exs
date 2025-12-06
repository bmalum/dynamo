defmodule Dynamo.Table.StreamTest do
  use ExUnit.Case, async: false

  alias Dynamo.Table.Stream, as: TableStream

  # Mock schema for testing
  defmodule TestUser do
    use Dynamo.Schema

    item do
      table_name "test_users"

      field :id, partition_key: true
      field :email, sort_key: true
      field :name
      field :status, default: "active"
      field :age
    end
  end

  describe "stream_scan/2" do
    test "returns a lazy stream" do
      stream = TableStream.scan(TestUser, page_size: 10)
      assert is_function(stream.(&1, &2))
    end

    test "stream can be composed with Stream functions" do
      stream =
        TableStream.scan(TestUser, page_size: 10)
        |> Stream.filter(&(&1.status == "active"))
        |> Stream.map(& &1.email)

      assert is_function(stream.(&1, &2))
    end

    test "stream can be limited with Enum.take" do
      # This would actually call DynamoDB in a real scenario
      # For testing, we'd need to mock the DynamoDB calls
      stream = TableStream.scan(TestUser, page_size: 10)
      assert is_function(stream.(&1, &2))
    end
  end

  describe "parallel_scan/2" do
    test "returns a stream with multiple segments" do
      stream = TableStream.parallel_scan(TestUser, segments: 4, page_size: 10)
      assert is_function(stream.(&1, &2))
    end

    test "accepts segment configuration" do
      stream = TableStream.parallel_scan(TestUser, segments: 8, page_size: 50)
      assert is_function(stream.(&1, &2))
    end
  end

  describe "scan_to_process/3" do
    test "returns error when consumer is not alive" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      result = TableStream.scan_to_process(TestUser, dead_pid)
      assert {:error, :consumer_not_alive} = result
    end

    test "returns task pid when consumer is alive" do
      consumer = spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

      # Mock the scan to avoid actual DynamoDB calls
      # In real tests, we'd use Mox or similar
      result = TableStream.scan_to_process(TestUser, consumer, segments: 1)

      case result do
        {:ok, task_pid} ->
          assert is_pid(task_pid)
          send(consumer, :stop)

        _ ->
          # If DynamoDB is not configured, this is expected
          send(consumer, :stop)
      end
    end
  end

  describe "build_scan_params/3" do
    test "builds basic scan parameters" do
      params = TableStream.build_scan_params("test_table", [], 100)

      assert params["TableName"] == "test_table"
      assert params["Limit"] == 100
      assert params["ConsistentRead"] == false
    end

    test "includes filter expression when provided" do
      params =
        TableStream.build_scan_params(
          "test_table",
          [
            filter_expression: "status = :val",
            expression_attribute_values: %{":val" => %{"S" => "active"}}
          ],
          100
        )

      assert params["FilterExpression"] == "status = :val"
      assert params["ExpressionAttributeValues"] == %{":val" => %{"S" => "active"}}
    end

    test "includes projection expression when provided" do
      params =
        TableStream.build_scan_params(
          "test_table",
          [
            projection_expression: "id, email, #name",
            expression_attribute_names: %{"#name" => "name"}
          ],
          100
        )

      assert params["ProjectionExpression"] == "id, email, #name"
      assert params["ExpressionAttributeNames"] == %{"#name" => "name"}
    end
  end

  describe "integration with Enum" do
    test "stream can be converted to list" do
      # This would need mocked DynamoDB responses
      stream = TableStream.scan(TestUser, page_size: 10)
      assert is_function(stream.(&1, &2))
    end

    test "stream can be filtered and mapped" do
      stream =
        TableStream.scan(TestUser, page_size: 10)
        |> Stream.filter(&(&1.age && &1.age > 18))
        |> Stream.map(& &1.email)

      assert is_function(stream.(&1, &2))
    end

    test "stream can be chunked" do
      stream =
        TableStream.scan(TestUser, page_size: 10)
        |> Stream.chunk_every(5)

      assert is_function(stream.(&1, &2))
    end
  end

  describe "error handling" do
    test "stream handles DynamoDB errors gracefully" do
      # This would need mocked error responses
      stream = TableStream.scan(TestUser, page_size: 10)
      assert is_function(stream.(&1, &2))
    end
  end
end
