defmodule Dynamo.SchemaTest do
  use ExUnit.Case, async: false

  # TODO
  # MultiKey Key generation test (partition & sort key)

  defmodule TestItem do
    use Dynamo.Schema, prefix_sort_key: true

    item do
      table_name "test_table"

      field :id
      field :name, default: "test"
      field :age, default: 0
      field :email

      partition_key [:id]
      sort_key [:name]
    end
  end

  defmodule AnotherTestItem do
    use Dynamo.Schema

    item do
      table_name "test_table"

      field :id, partition_key: true
      field :name, sort_key: true, default: "test"
      field :age, default: 0
      field :email

    end
  end

  describe "schema definition" do
    test "defines correct table name" do
      assert TestItem.table_name() == "test_table"
    end

    test "defines correct partition key" do
      assert TestItem.partition_key() == [:id]
    end

    test "defines correct sort key" do
      assert TestItem.sort_key() == [:name]
    end

    test "defines correct fields" do
      expected_fields = [
        {:name, "test"},
        {:age, 0},
        {:email, nil},
        {:id, nil}
      ]

      assert Keyword.equal?(TestItem.fields(), expected_fields)
    end
  end

  describe "struct creation" do
    test "creates struct with default values" do
      item = %TestItem{}
      assert item.name == "test"
      assert item.age == 0
      assert item.id == nil
      assert item.email == nil
    end

    test "creates struct with custom values" do
      item = %TestItem{id: "123", name: "John", age: 25, email: "john@example.com"}
      assert item.id == "123"
      assert item.name == "John"
      assert item.age == 25
      assert item.email == "john@example.com"
    end
  end

  describe "key generation" do
    test "generates partition key" do
      item = %TestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_partition_key(item)
      assert result.pk == "id#123#testitem"
    end

    test "generates sort key" do
      item = %TestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_sort_key(item)
      assert result.sk == "name#John"
    end

    test "generates keys with empty values" do
      item = %TestItem{}
      result = item
               |> Dynamo.Schema.generate_and_add_partition_key()
               |> Dynamo.Schema.generate_and_add_sort_key()

      assert result.pk == "id#empty#testitem"
      assert result.sk == "name#test"
    end
  end

  describe "validation" do
    test "raises error when redefining partition key" do
      assert_raise RuntimeError, "Primary Key already defined in fields", fn ->
        defmodule InvalidPartitionKey do
          use Dynamo.Schema

          item do
            field :id, partition_key: true
            partition_key [:id]
          end
        end
      end
    end

    test "raises error when redefining sort key" do
      assert_raise RuntimeError, "Sort Key already defined in fields", fn ->
        defmodule InvalidSortKey do
          use Dynamo.Schema

          item do
            field :name, sort_key: true
            sort_key [:name]
          end
        end
      end
    end

    test "raises error when partition key field is missing" do
      assert_raise RuntimeError, "Missing fields in schema: missing_field", fn ->
        defmodule MissingPartitionKey do
          use Dynamo.Schema

          item do
            field :id
            partition_key [:missing_field]
          end
        end
      end
    end
  end

  describe "schema definition (AnotherItem)" do
    test "defines correct table name" do
      assert TestItem.table_name() == "test_table"
    end

    test "defines correct partition key" do
      assert TestItem.partition_key() == [:id]
    end

    test "defines correct sort key" do
      assert TestItem.sort_key() == [:name]
    end

    test "defines correct fields" do
      expected_fields = [
        {:name, "test"},
        {:age, 0},
        {:email, nil},
        {:id, nil}
      ]

      assert Keyword.equal?(TestItem.fields(), expected_fields)
    end
  end

  describe "struct creation (Another Item)" do
    test "creates struct with default values" do
      item = %AnotherTestItem{}
      assert item.name == "test"
      assert item.age == 0
      assert item.id == nil
      assert item.email == nil
    end

    test "creates struct with custom values" do
      item = %AnotherTestItem{id: "123", name: "John", age: 25, email: "john@example.com"}
      assert item.id == "123"
      assert item.name == "John"
      assert item.age == 25
      assert item.email == "john@example.com"
    end
  end

  describe "key generation  (Another Item)" do
    test "generates partition key" do
      item = %AnotherTestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_partition_key(item)
      assert result.pk == "id#123#anothertestitem"
    end

    test "generates sort key" do
      item = %AnotherTestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_sort_key(item)
      assert result.sk == "John"
    end

    test "generates keys with empty values" do
      item = %AnotherTestItem{}
      result = item
               |> Dynamo.Schema.generate_and_add_partition_key()
               |> Dynamo.Schema.generate_and_add_sort_key()

      assert result.pk == "id#empty#anothertestitem"
      assert result.sk == "test"
    end
  end
end
