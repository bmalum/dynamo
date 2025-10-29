defmodule Dynamo.Schema do
  @moduledoc """
  Provides a DSL for defining DynamoDB schema structures and automatic key generation.

  This module enables you to define structured schemas for DynamoDB tables with typed field
  definitions, partition keys, and sort keys. It automatically handles the generation of
  composite keys based on your schema configuration, eliminating boilerplate code and reducing
  errors in key construction.

  ## Overview

  DynamoDB is a schema-less NoSQL database, but maintaining consistent data structures is
  essential for reliable applications. Dynamo.Schema brings structure to DynamoDB by:

  - Defining typed fields with default values
  - Automatically generating composite keys from field values
  - Providing compile-time validation of schema definitions
  - Enabling clean, maintainable code through an Ecto-inspired DSL
  - Supporting flexible key generation strategies via configuration

  ## Basic Usage

  The simplest schema defines a table name and fields with their key properties:

      defmodule MyApp.User do
        use Dynamo.Schema

        item do
          table_name "users"

          field :id, partition_key: true
          field :email, sort_key: true
          field :name
          field :role, default: "user"
        end
      end

  ## Composite Keys

  For more complex data models, you can create composite keys from multiple fields:

      defmodule MyApp.Order do
        use Dynamo.Schema

        item do
          table_name "orders"

          field :tenant_id
          field :user_id
          field :order_id
          field :created_at
          field :status, default: "pending"

          # Composite partition key from tenant and user
          partition_key [:tenant_id, :user_id]

          # Composite sort key from timestamp and order ID
          sort_key [:created_at, :order_id]
        end
      end

      # This generates keys like:
      # pk: "tenant_id#acme#user_id#123#order"
      # sk: "created_at#2024-01-15T10:30:00Z#order_id#ORD-789"

  ## Field Options

  - `partition_key: true` - Marks this field as part of the partition key
  - `sort_key: true` - Marks this field as part of the sort key
  - `default: value` - Sets a default value applied when creating structs

  ## Configuration Options

  When using `Dynamo.Schema`, you can provide configuration options that override global defaults:

      defmodule MyApp.User do
        use Dynamo.Schema,
          key_separator: "_",           # Use underscore instead of hash
          prefix_sort_key: true,         # Include field names in sort key
          suffix_partition_key: false    # Don't add entity type to partition key

        item do
          # schema definition...
        end
      end

  Available configuration options:

  - `key_separator` - String used to separate parts of composite keys (default: `"#"`)
  - `prefix_sort_key` - Whether to include field names as prefixes in sort key (default: `false`)
  - `suffix_partition_key` - Whether to add entity type suffix to partition key (default: `true`)
  - `partition_key_name` - Name of the partition key attribute in DynamoDB (default: `"pk"`)
  - `sort_key_name` - Name of the sort key attribute in DynamoDB (default: `"sk"`)
  - `table_has_sort_key` - Whether the table uses a sort key (default: `true`)

  These options can also be configured globally in your application configuration or
  at runtime using `Dynamo.Config` functions. Configuration precedence is:
  schema options > process config > application config > defaults.

  ## Advanced: Custom Key Generation

  You can override the `before_write/1` callback to customize how items are prepared
  before writing to DynamoDB:

      defmodule MyApp.TimeSeries do
        use Dynamo.Schema

        item do
          table_name "metrics"
          field :device_id, partition_key: true
          field :timestamp, sort_key: true
          field :value
        end

        # Add timestamp if not provided
        def before_write(item) do
          item = if is_nil(item.timestamp) do
            %{item | timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}
          else
            item
          end

          # Call default key generation
          item
          |> Dynamo.Schema.generate_and_add_partition_key()
          |> Dynamo.Schema.generate_and_add_sort_key()
          |> Dynamo.Encoder.encode_root()
        end
      end

  ## See Also

  - `Dynamo.Config` - For managing configuration at different levels
  - `Dynamo.Table` - For performing CRUD operations on schema-defined items
  - `Dynamo.Encoder` - For manual encoding of structs to DynamoDB format
  """

  alias Dynamo.Schema

  @doc """
  Sets up a module to use the Dynamo.Schema functionality.

  This macro imports the necessary functions and sets up the configuration
  for the schema. It also defines a `settings/0` function that returns the
  merged configuration from defaults, application config, process config,
  and schema-specific options.

  ## Parameters
    * `opts` - Optional keyword list of schema-specific configuration options

  ## Example
      defmodule MyApp.User do
        use Dynamo.Schema, key_separator: "_", prefix_sort_key: true

        # schema definition...
      end
  """
  defmacro __using__(opts \\ []) do
    quote do
      import Dynamo.Schema
      @schema_config unquote(opts)

      def settings do
        Dynamo.Config.config(@schema_config)
      end
    end
  end

  @doc """
  Defines the structure of a DynamoDB item.

  This macro is the core of the schema definition. It sets up the necessary attributes
  and functions for working with DynamoDB items, including:

  - Table name
  - Field definitions
  - Partition and sort key specifications
  - Automatic key generation
  - Encoding and decoding behavior

  ## Example

      item do
        table_name "users"

        field :id, partition_key: true
        field :email
        field :name
        field :created_at, sort_key: true
      end

  ## Overriding the before_write Function

  You can override the `before_write/1` function to add custom logic before writing items to DynamoDB:

      def before_write(item) do
        item
        |> Map.put(:updated_at, DateTime.utc_now())
        |> Dynamo.Schema.generate_and_add_partition_key()
        |> Dynamo.Schema.generate_and_add_sort_key()
        |> Dynamo.Encoder.encode_root()
      end
  """
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
    config = arg.__struct__.settings()
    name = arg.__struct__ |> Atom.to_string() |> String.split(".") |> List.last() |> String.downcase()
    separator = config[:key_separator]

    val =
      arg.__struct__.partition_key()
      |> Enum.map(fn elm ->
        [
          Atom.to_string(elm),
          if(Map.get(arg, elm, "empty") == nil, do: "empty", else: Map.get(arg, elm, "empty"))
        ]
      end)
      |> List.flatten()
      |> Enum.join(separator)

    if config[:suffix_partition_key] do
      "#{val}#{separator}#{name}"
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
    config = arg.__struct__.settings()
    separator = config[:key_separator]

    val = arg.__struct__.sort_key()
    |> Enum.map(fn elm ->
      [
        Atom.to_string(elm),
        if(Map.get(arg, elm, "empty") == nil, do: "empty", else: Map.get(arg, elm, "empty"))
      ]
    end)
    |> List.flatten()
    |> Enum.join(separator)

    if config[:prefix_sort_key] do
      val
    else
      [_| rest] = val |> String.split(separator)
      Enum.join(rest, separator)
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
    config = arg.__struct__.settings()
    sort_key_name = String.to_atom(config[:sort_key_name])
    Map.put(arg, sort_key_name, v)
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
    config = arg.__struct__.settings()
    partition_key_name = String.to_atom(config[:partition_key_name])
    Map.put(arg, partition_key_name, v)
  end

  @doc """
  Prepares the struct definition from field definitions.

  Converts the field definitions collected during schema definition into
  a format suitable for use with `defstruct`.

  ## Parameters
    * `tuple_list` - List of field definitions

  ## Returns
    * List of field definitions suitable for `defstruct`
  """
  def prepare_struct(tuple_list) do
    _x = for elm <- tuple_list, do: prepare_struct_elm(elm)
  end

  @doc """
  Processes a field definition based on its format.

  ## Parameters
    * `{field_name, _db_key, default}` - Field definition with database key and default value
    * `{field_name, default}` - Field definition with default value
    * `{field_name}` - Field definition without default value

  ## Returns
    * Field definition in the appropriate format for defstruct
  """
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
