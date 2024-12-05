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

    payload = %{"TableName" => table, "Item" => item} |> IO.inspect()

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

    query = %{
      "TableName" => table,
      "Key" => %{
        "pk" => %{"S" => pk}
      }
    }

    query = if sk != nil, do: put_in(query, ["Key", "sk"], %{"S" => sk}), else: query

    case AWS.DynamoDB.get_item(Dynamo.AWS.client(), query) do
      {:ok, %{"Item" => item}, _} -> {:ok, item}
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
      scan_index_forward: true
    ]

    options = Keyword.merge(defaults, options)
    table = options[:table_name]
    sk = options[:sort_key]
    pk_query_fragment = "pk = :pk"

    query = %{
      "TableName" => table,
      "KeyConditionExpression" => pk_query_fragment,
      "ScanIndexForward" => options[:scan_index_forward],
      "ExpressionAttributeValues" => %{
        ":pk" => %{"S" => pk}
      }
    }

    {sk, sk_operator} =
      case {sk, options[:sk_operator]} do
        {nil, nil} -> {nil, nil}
        {nil, _val2} -> raise "InvalidVariablesError"
        {val1, nil} -> {val1, :full_match}
        {val1, val2} -> {val1, val2}
      end

    if sk != nil do
      query = put_in(query, ["ExpressionAttributeValues", ":sk"], %{"S" => sk})

      case sk_operator do
        :full_match ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND sk = :sk"
          )
        :begins_with ->
          put_in(
            query,
            ["KeyConditionExpression"],
            "#{pk_query_fragment} AND begins_with(sk, :sk)"
          )
      end
    else
      query
    end
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
    acc
  end

  defp query(query, limit, acc, last_key)
       when length(acc) < limit or limit == :infinity do
    query = if last_key, do: Map.put(query, "ExclusiveStartKey", last_key), else: query

    case AWS.DynamoDB.query(Dynamo.AWS.client(), query) do
      {:ok, %{"Items" => items, "LastEvaluatedKey" => last_evaluated_key}, _} ->
        query(query, limit, acc ++ items, last_evaluated_key)

      {:ok, %{"Items" => items}, _} ->
        case limit do
          :infinity -> acc ++ items
          limit -> Enum.take(acc ++ items, limit)
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

    build_query(pk, table_name: table)
    |> query(:infinity, [], nil)
  end

  @doc """
  Lists items for a given struct's partition key with additional options.

  ## Parameters
    * `struct` - Struct containing the partition key information
    * `options` - Additional query options

  ## Returns
    * List of items or error tuple
  """
  def list_items(struct, options) when is_struct(struct) do
    pk = Dynamo.Schema.generate_partition_key(struct)
    table = struct.__struct__.table_name
    opts = [table_name: table]
    Keyword.merge(opts, options)
    build_query(pk, options)
    |> query(:infinity, [], nil)
  end
end
