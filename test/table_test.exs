defmodule Dynamo.TableTest do
  use ExUnit.Case, async: false
  import Mock

  # Define test items for use across tests
  defmodule TestItem do
    use Dynamo.Schema

    item do
      table_name "test_table"

      field :id, partition_key: true
      field :name, sort_key: true, default: "test"
      field :age, default: 0
      field :email
    end
  end

  describe "delete_item/2" do
    test "successfully deletes an item" do
      item = %TestItem{id: "123", name: "John"}

      with_mocks([
        {Dynamo.DynamoDB, [], [delete_item: fn _, _ -> {:ok, %{}, %{}} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, nil} = Dynamo.Table.delete_item(item)
      end
    end

    test "returns deleted item when return_values is set to ALL_OLD" do
      item = %TestItem{id: "123", name: "John"}
      returned_item = %{
        "id" => %{"S" => "123"},
        "name" => %{"S" => "John"},
        "age" => %{"N" => "0"}
      }

      with_mocks([
        {Dynamo.DynamoDB, [], [delete_item: fn _, _ -> {:ok, %{"Attributes" => returned_item}, %{}} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, %TestItem{id: "123", name: "John", age: 0}} = Dynamo.Table.delete_item(item, return_values: "ALL_OLD")
      end
    end

    test "returns error on AWS error" do
      item = %TestItem{id: "123", name: "John"}
      error = %{"__type" => "ConditionalCheckFailedException", "Message" => "The condition check failed"}

      with_mocks([
        {Dynamo.DynamoDB, [], [delete_item: fn _, _ -> {:error, error} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:error, %Dynamo.Error{type: :aws_error}} = Dynamo.Table.delete_item(item)
      end
    end

    test "validates partition key requirement" do
      defmodule InvalidItemMock do
        def partition_key, do: []
        def settings, do: %{}
        def table_name, do: "test_table"
      end

      invalid_item = %{__struct__: InvalidItemMock}
      assert {:error, %Dynamo.Error{type: :validation_error}} = Dynamo.Table.delete_item(invalid_item)
    end

    test "supports condition expressions" do
      item = %TestItem{id: "123", name: "John"}
      condition_expression = "attribute_exists(id)"

      with_mocks([
        {Dynamo.DynamoDB, [], [delete_item: fn _client, payload ->
          assert payload["ConditionExpression"] == condition_expression
          {:ok, %{}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        Dynamo.Table.delete_item(item, condition_expression: condition_expression)
      end
    end
  end

  describe "scan/2" do
    test "scans table successfully" do
      items = [
        %{"id" => %{"S" => "123"}, "name" => %{"S" => "John"}},
        %{"id" => %{"S" => "456"}, "name" => %{"S" => "Jane"}}
      ]

      with_mocks([
        {Dynamo.DynamoDB, [], [scan: fn _, _ -> {:ok, %{"Items" => items}, %{}} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, %{items: [%TestItem{}, %TestItem{}], last_evaluated_key: nil}} = Dynamo.Table.scan(TestItem)
      end
    end

    test "handles pagination with LastEvaluatedKey" do
      items = [%{"id" => %{"S" => "123"}}]
      last_key = %{"id" => %{"S" => "123"}}

      with_mocks([
        {Dynamo.DynamoDB, [], [scan: fn _, _ -> {:ok, %{"Items" => items, "LastEvaluatedKey" => last_key}, %{}} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, %{items: [%TestItem{}], last_evaluated_key: ^last_key}} = Dynamo.Table.scan(TestItem)
      end
    end

    test "applies filter expressions" do
      with_mocks([
        {Dynamo.DynamoDB, [], [scan: fn _, payload ->
          assert payload["FilterExpression"] == "age > :min_age"
          assert payload["ExpressionAttributeValues"][":min_age"] == %{"N" => "18"}
          {:ok, %{"Items" => []}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        Dynamo.Table.scan(TestItem,
          filter_expression: "age > :min_age",
          expression_attribute_values: %{":min_age" => %{"N" => "18"}}
        )
      end
    end

    test "returns error on AWS error" do
      error = %{"__type" => "ProvisionedThroughputExceededException", "Message" => "Throughput exceeded"}

      with_mocks([
        {Dynamo.DynamoDB, [], [scan: fn _, _ -> {:error, error} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:error, %Dynamo.Error{type: :aws_error}} = Dynamo.Table.scan(TestItem)
      end
    end
  end

  describe "update_item/3" do
    test "updates an item successfully" do
      item = %TestItem{id: "123", name: "John"}
      updates = %{age: 30, email: "john@example.com"}

      with_mocks([
        {Dynamo.DynamoDB, [], [update_item: fn _, payload ->
          assert payload["UpdateExpression"] =~ "SET"
          assert Map.has_key?(payload["ExpressionAttributeNames"], "#attr_age")
          assert Map.has_key?(payload["ExpressionAttributeValues"], ":val_age")
          {:ok, %{}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, nil} = Dynamo.Table.update_item(item, updates)
      end
    end

    test "returns updated item when return_values specified" do
      item = %TestItem{id: "123", name: "John"}
      updates = %{age: 30}
      updated_item = %{
        "id" => %{"S" => "123"},
        "name" => %{"S" => "John"},
        "age" => %{"N" => "30"}
      }

      with_mocks([
        {Dynamo.DynamoDB, [], [update_item: fn _, _ -> {:ok, %{"Attributes" => updated_item}, %{}} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, %TestItem{id: "123", name: "John", age: 30}} =
          Dynamo.Table.update_item(item, updates, return_values: "ALL_NEW")
      end
    end

    test "supports custom update expressions" do
      item = %TestItem{id: "123", name: "John"}
      custom_expression = "SET #age = :age, #visits = #visits + :inc"
      attr_names = %{"#age" => "age", "#visits" => "visits"}
      attr_values = %{":age" => %{"N" => "30"}, ":inc" => %{"N" => "1"}}

      with_mocks([
        {Dynamo.DynamoDB, [], [update_item: fn _, payload ->
          assert payload["UpdateExpression"] == custom_expression
          assert payload["ExpressionAttributeNames"] == attr_names
          assert payload["ExpressionAttributeValues"] == attr_values
          {:ok, %{}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        Dynamo.Table.update_item(item, %{},
          update_expression: custom_expression,
          expression_attribute_names: attr_names,
          expression_attribute_values: attr_values
        )
      end
    end

    test "validates partition key requirement" do
      defmodule InvalidUpdateItemMock do
        def partition_key, do: []
        def settings, do: %{}
        def table_name, do: "test_table"
      end

      invalid_item = %{__struct__: InvalidUpdateItemMock}
      assert {:error, %Dynamo.Error{type: :validation_error}} =
        Dynamo.Table.update_item(invalid_item, %{})
    end
  end

  describe "batch_get_item/2" do
    test "retrieves multiple items successfully" do
      items = [
        %TestItem{id: "123", name: "John"},
        %TestItem{id: "456", name: "Jane"}
      ]

      response_items = [
        %{"id" => %{"S" => "123"}, "name" => %{"S" => "John"}},
        %{"id" => %{"S" => "456"}, "name" => %{"S" => "Jane"}}
      ]

      with_mocks([
        {Dynamo.DynamoDB, [], [batch_get_item: fn _, _ ->
          {:ok, %{"Responses" => %{"test_table" => response_items}}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        assert {:ok, %{items: [%TestItem{}, %TestItem{}], unprocessed_keys: []}} =
          Dynamo.Table.batch_get_item(items)
      end
    end

    test "handles unprocessed keys" do
      items = [
        %TestItem{id: "123", name: "John"},
        %TestItem{id: "456", name: "Jane"}
      ]

      response_items = [%{"id" => %{"S" => "123"}, "name" => %{"S" => "John"}}]
      unprocessed = [%{"pk" => %{"S" => "id#456#testitem"}, "sk" => %{"S" => "Jane"}}]

      with_mocks([
        {Dynamo.DynamoDB, [], [batch_get_item: fn _, _ ->
          {:ok, %{
            "Responses" => %{"test_table" => response_items},
            "UnprocessedKeys" => %{"test_table" => %{"Keys" => unprocessed}}
          }, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        {:ok, result} = Dynamo.Table.batch_get_item(items)
        assert length(result.items) == 1
        assert length(result.unprocessed_keys) == 1
      end
    end

    test "returns error on AWS error" do
      items = [%TestItem{id: "123", name: "John"}]
      aws_error = %{"__type" => "ProvisionedThroughputExceededException", "Message" => "Throughput exceeded"}

      with_mocks([
        {Dynamo.DynamoDB, [], [batch_get_item: fn _, _ -> {:error, aws_error} end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        {:error, error} = Dynamo.Table.batch_get_item(items)
        assert error.type == :aws_error
        assert error.message =~ "Throughput exceeded"
      end
    end

    test "applies consistent read option" do
      items = [%TestItem{id: "123", name: "John"}]

      with_mocks([
        {Dynamo.DynamoDB, [], [batch_get_item: fn _, payload ->
          table_request = payload["RequestItems"]["test_table"]
          assert table_request["ConsistentRead"] == true
          {:ok, %{"Responses" => %{"test_table" => []}}, %{}}
        end]},
        {Dynamo.AWS, [], [client: fn -> :mock_client end]}
      ]) do
        Dynamo.Table.batch_get_item(items, consistent_read: true)
      end
    end
  end
end
