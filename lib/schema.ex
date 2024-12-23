defmodule Dynamo.Schema do
  @moduledoc """
  Provides a DSL for defining DynamoDB schema structures and key generation.

  This module allows you to define schemas for DynamoDB tables with structured field definitions,
  partition keys, and sort keys. It automatically handles the generation of composite keys
  based on the defined schema.

  ## Example

      defmodule MyApp.User do
        use Dynamo.Schema

        item do
          table_name "users"

          field :id, partition_key: true
          field :email
          field :name
          field :created_at, sort_key: true
        end
      end

  ## Schema Definition

  The schema supports the following features:
  - Field definitions with optional defaults
  - Partition key and sort key specifications
  - Automatic key generation
  - Table name definition
  """

  alias Dynamo.Schema

  defmacro __using__(opts \\ []) do
    default_opts = [
      prefix_sort_key: false,
      suffix_partition_key: true,
      key_seperator: "#",
      partition_key_name: "pk",
      sort_key_name: "sk",
      table_has_sort_key: true
    ]

    opts = Keyword.merge(default_opts, opts)

    quote do
      import Dynamo.Schema
      @prefix_sort_key unquote(opts[:prefix_sort_key])
      def settings, do: unquote(opts)
    end
  end

  defmacro item(do: block) do
    quote do
      @derive [Dynamo.Encodable]
      # @table_name unquote(table_name)

      Module.register_attribute(__MODULE__, :fields, accumulate: true)
      Module.register_attribute(__MODULE__, :sort_key, accumulate: true)
      Module.register_attribute(__MODULE__, :partition_key, accumulate: true)

      unquote(block)

      def table_name, do: @table_name
      def partition_key, do: @partition_key |> List.flatten()
      def sort_key, do: @sort_key |> List.flatten()
      def fields, do: @fields

      defstruct Schema.prepare_struct(@fields)

      def before_write(arg) do
        arg
        |> Schema.generate_and_add_partition_key()
        |> Schema.generate_and_add_sort_key()
        |> Dynamo.Encoder.encode_root()
      end

      defoverridable before_write: 1
    end
  end

  @doc """
  Generates a partition key string based on the struct's defined partition key fields.

  The partition key is generated by combining field names and values with "#" as separator,
  followed by the lowercase name of the struct.

  ## Parameters
    - arg: The struct instance to generate the partition key for

  ## Returns
    String representing the partition key
  """
  def generate_partition_key(arg) do
    # TODO conifg name - remove prefix if name is key?!
    name =
      arg.__struct__ |> Atom.to_string() |> String.split(".") |> List.last() |> String.downcase()

    sperator = arg.__struct__.settings()[:key_seperator]

    val =
      arg.__struct__.partition_key
      |> Enum.map(fn elm ->
        [
          Atom.to_string(elm),
          if(Map.get(arg, elm, "empty") == nil, do: "empty", else: Map.get(arg, elm, "empty"))
        ]
      end)
      |> List.flatten()
      # TODO make this configurable
      |> Enum.join(sperator)

    if arg.__struct__.settings()[:suffix_partition_key] do
      "#{val}#{sperator}#{name}"
    else
      val
    end
  end

  @doc """
  Generates a sort key string based on the struct's defined sort key fields.

  The sort key is generated by combining field names and values with "#" as separator.

  ## Parameters
    - arg: The struct instance to generate the sort key for

  ## Returns
    String representing the sort key
  """
  def generate_sort_key(arg) do
    # TODO conifg name - remove prefix if name is key?!
    seperator = arg.__struct__.settings()[:key_seperator]

    val = arg.__struct__.sort_key
    |> Enum.map(fn elm ->
      [
        Atom.to_string(elm),
        if(Map.get(arg, elm, "empty") == nil, do: "empty", else: Map.get(arg, elm, "empty"))
      ]
    end)
    |> List.flatten()
    # TODO make this configurable
    |> Enum.join(seperator)

    if arg.__struct__.settings()[:prefix_sort_key] == true do
      val
    else
      [_| rest] = val |> String.split(seperator)
      Enum.join(rest, seperator)
    end
  end

  @doc """
  Adds a generated sort key to the struct under the `:sk` key.

  ## Parameters
    - arg: The struct instance to add the sort key to

  ## Returns
    Updated struct with sort key
  """
  def generate_and_add_sort_key(arg) do
    v = generate_sort_key(arg)
    # TODO conifg name - remove prefix if name is key?!
    Map.put(arg, :sk, v)
  end

  @doc """
  Adds a generated partition key to the struct under the `:pk` key.

  ## Parameters
    - arg: The struct instance to add the partition key to

  ## Returns
    Updated struct with partition key
  """
  def generate_and_add_partition_key(arg) do
    v = generate_partition_key(arg)
    # TODO conifg name - remove prefix if name is key?!
    Map.put(arg, :pk, v)
  end

  def prepare_struct(tuple_list) do
    _x = for elm <- tuple_list, do: prepare_struct_elm(elm)
  end

  def prepare_struct_elm({field_name, _db_key, default}) do
    {field_name, default}
  end

  def prepare_struct_elm({field_name, default}) do
    {field_name, default}
  end

  def prepare_struct_elm({field_name}) do
    field_name
  end

  @doc """
  Defines a field in the schema.

  ## Options
    - `:partition_key` - boolean, marks the field as part of the partition key
    - `:sort_key` - boolean, marks the field as part of the sort key
    - `:default` - sets a default value for the field

  ## Example
      field :email
      field :status, default: "active"
      field :id, partition_key: true
  """
  defmacro field(name) do
    Schema.__field__(name, [], %{})
  end

  defmacro field(name, opts) do
    Schema.__field__(name, opts, %{})
  end

  def __field__(name, [{:partition_key, true} | rest], state) do
    state = state |> Map.put(:partition_key, name)
    Schema.__field__(name, rest, state)
  end

  def __field__(name, [{:sort_key, true} | rest], state) do
    state = state |> Map.put(:sort_key, name)
    Schema.__field__(name, rest, state)
  end

  def __field__(name, [{:default, default} | rest], state) do
    state = state |> Map.put(:field, {name, default})
    Schema.__field__(name, rest, state)
  end

  def __field__(name, [], state) do
    state = if !Map.has_key?(state, :field), do: Map.put(state, :field, {name, nil}), else: state

    quote do
      @fields unquote(state.field)
      if unquote(state[:sort_key]) != nil do
        @sort_key unquote(state[:sort_key])
      end

      if unquote(state[:partition_key]) != nil do
        @partition_key unquote(state[:partition_key])
      end
    end
  end

  @doc """
  Sets the table name for the schema.

  ## Parameters
    - name: String or atom representing the table name

  ## Example
      table_name "users"
  """
  defmacro table_name(name) do
    quote do
      @table_name unquote(name)
    end
  end

  @doc """
  Defines the sort key fields for the schema.

  ## Parameters
    - list: List of field names that compose the sort key

  ## Example
      sort_key [:created_at, :id]
  """
  defmacro sort_key(list) do
    quote do
      if length(@sort_key) > 0, do: raise("Sort Key already defined in fields")

      # Check if all partition key fields exist in @fields
      missing_fields =
        for field <- unquote(list),
            not Enum.any?(@fields, fn {name, _} -> name == field end),
            do: field

      unless Enum.empty?(missing_fields) do
        raise "Missing fields in schema: #{Enum.join(missing_fields, ", ")}"
      end

      @sort_key unquote(list)
    end
  end

  @doc """
  Defines the partition key fields for the schema.

  ## Parameters
    - list: List of field names that compose the partition key

  ## Example
      partition_key [:id, :type]
  """
  defmacro partition_key(list) do
    quote do
      if length(@partition_key) > 0, do: raise("Primary Key already defined in fields")

      # Check if all partition key fields exist in @fields
      missing_fields =
        for field <- unquote(list),
            not Enum.any?(@fields, fn {name, _} -> name == field end),
            do: field

      unless Enum.empty?(missing_fields) do
        raise "Missing fields in schema: #{Enum.join(missing_fields, ", ")}"
      end

      @partition_key unquote(list)
    end
  end
end
