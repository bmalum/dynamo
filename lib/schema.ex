defmodule Dynamo.Schema do
  @moduledoc """
  Provides a DSL for defining DynamoDB schema structures and key generation.

  This module allows you to define schemas for DynamoDB tables with structured field definitions,
  partition keys, sort keys, and Global Secondary Indexes (GSIs). It automatically handles the
  generation of composite keys based on the defined schema.

  ## Basic Example

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

  ## Global Secondary Index (GSI) Support

  You can define Global Secondary Indexes in your schema to enable efficient querying
  on non-key attributes:

      defmodule MyApp.User do
        use Dynamo.Schema

        item do
          table_name "users"

          field :id, partition_key: true
          field :tenant
          field :email
          field :name
          field :status, default: "active"
          field :created_at, sort_key: true

          # GSI with partition key only
          global_secondary_index "EmailIndex", partition_key: :email

          # GSI with partition and sort keys
          global_secondary_index "TenantIndex",
            partition_key: :tenant,
            sort_key: :created_at

          # GSI with custom projection
          global_secondary_index "TenantStatusIndex",
            partition_key: :tenant,
            sort_key: :status,
            projection: :include,
            projected_attributes: [:id, :email, :name]
        end
      end

  ## GSI Query Examples

  Once GSIs are defined, you can query them using the same `list_items/2` function:

      # Query by email (EmailIndex)
      {:ok, users} = MyApp.User.list_items(
        %MyApp.User{email: "user@example.com"},
        index_name: "EmailIndex"
      )

      # Query by tenant with date range (TenantIndex)
      {:ok, recent_users} = MyApp.User.list_items(
        %MyApp.User{tenant: "acme", created_at: "2023-01-01"},
        index_name: "TenantIndex",
        sk_operator: :gte
      )

      # Query active users in tenant (TenantStatusIndex)
      {:ok, active_users} = MyApp.User.list_items(
        %MyApp.User{tenant: "acme", status: "active"},
        index_name: "TenantStatusIndex"
      )

  ## Schema Definition

  The schema supports the following features:
  - Field definitions with optional defaults
  - Partition key and sort key specifications
  - Global Secondary Index definitions
  - Automatic key generation for tables and GSIs
  - Table name definition

  ## Configuration Options

  When using `Dynamo.Schema`, you can provide configuration options that override the defaults:

      defmodule MyApp.User do
        use Dynamo.Schema,
          key_separator: "_",
          prefix_sort_key: true

        item do
          # schema definition...
        end
      end

  Available configuration options:

  - `key_separator`: String used to separate parts of composite keys (default: "#")
  - `prefix_sort_key`: Whether to include field name as prefix in sort key (default: false)
  - `partition_key_name`: Name of the partition key in DynamoDB (default: "pk")
  - `sort_key_name`: Name of the sort key in DynamoDB (default: "sk")
  - `table_has_sort_key`: Whether the table has a sort key (default: true)

  These options can also be configured globally in your application configuration or
  at runtime using `Dynamo.Config` functions.
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
      Module.register_attribute(__MODULE__, :global_secondary_indexes, accumulate: true)

      unquote(block)

      def table_name, do: @table_name
      def partition_key, do: @partition_key |> List.flatten()
      def sort_key, do: @sort_key |> List.flatten()
      def fields, do: @fields
      def global_secondary_indexes, do: @global_secondary_indexes || []

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

    name =
      arg.__struct__ |> Atom.to_string() |> String.split(".") |> List.last() |> String.downcase()

    separator = config[:key_separator]

    # Get only the field values (without field names)
    values =
      arg.__struct__.partition_key()
      |> Enum.map(fn elm ->
        if(Map.get(arg, elm, "empty") == nil, do: "empty", else: Map.get(arg, elm, "empty"))
      end)
      |> Enum.join(separator)

    # Always put entity name first, then the values
    "#{name}#{separator}#{values}"
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

    val =
      arg.__struct__.sort_key()
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
      [_ | rest] = val |> String.split(separator)
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
  Generates a partition key string for a GSI based on the GSI configuration.

  The GSI partition key is generated by combining the GSI partition key field value
  with the entity name, following the same pattern as table partition keys.

  ## Parameters
    - struct: The struct instance to generate the GSI partition key for
    - gsi_config: Map containing GSI configuration with :partition_key field

  ## Returns
    String representing the GSI partition key

  ## Example
      # user = %User{email: "test@example.com"}
      # gsi_config = %{partition_key: :email}
      # Dynamo.Schema.generate_gsi_partition_key(user, gsi_config)
      # "test@example.com"
  """
  def generate_gsi_partition_key(struct, gsi_config) do
    # Get the GSI partition key field value
    partition_key_field = gsi_config[:partition_key]
    field_value = Map.get(struct, partition_key_field, "empty")
    field_value = if field_value == nil, do: "empty", else: field_value

    # For GSI keys, just return the raw field value without any prefixing
    to_string(field_value)
  end

  @doc """
  Generates a sort key string for a GSI based on the GSI configuration.

  The GSI sort key is generated by combining the GSI sort key field name and value
  with the configured separator, following the same pattern as table sort keys.
  Returns nil if the GSI has no sort key configured (partition-only GSI).

  ## Parameters
    - struct: The struct instance to generate the GSI sort key for
    - gsi_config: Map containing GSI configuration with optional :sort_key field

  ## Returns
    String representing the GSI sort key, or nil if GSI has no sort key

  ## Example
      # user = %User{created_at: "2023-01-01"}
      # gsi_config = %{sort_key: :created_at}
      # Dynamo.Schema.generate_gsi_sort_key(user, gsi_config)
      # "2023-01-01"

      # gsi_config = %{sort_key: nil}
      # Dynamo.Schema.generate_gsi_sort_key(user, gsi_config)
      # nil
  """
  def generate_gsi_sort_key(struct, gsi_config) do
    case gsi_config[:sort_key] do
      nil ->
        # Partition-only GSI, no sort key
        nil

      sort_key_field ->
        # Get the GSI sort key field value
        field_value = Map.get(struct, sort_key_field, "empty")
        field_value = if field_value == nil, do: "empty", else: field_value

        # For GSI keys, just return the raw field value without any prefixing
        to_string(field_value)
    end
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

  @doc """
  Finds a GSI configuration by index name.

  ## Parameters
    - struct: The struct instance containing the schema
    - index_name: String name of the GSI to find

  ## Returns
    - `{:ok, gsi_config}` if GSI is found
    - `{:error, error_struct}` if GSI is not found

  ## Example
      # user = %User{}
      # Dynamo.Schema.get_gsi_config(user, "EmailIndex")
      # {:ok, %{name: "EmailIndex", partition_key: :email, sort_key: nil, ...}}

      # Dynamo.Schema.get_gsi_config(user, "NonExistentIndex")
      # {:error, %Dynamo.Error{...}}
  """
  def get_gsi_config(struct, index_name) do
    gsi_configs = struct.__struct__.global_secondary_indexes()

    case Enum.find(gsi_configs, fn config -> config.name == index_name end) do
      nil ->
        available_indexes = gsi_configs |> Enum.map(& &1.name) |> Enum.sort()
        available_list = if Enum.empty?(available_indexes), do: "none", else: Enum.join(available_indexes, ", ")

        {:error, Dynamo.Error.new(:validation_error,
          "GSI '#{index_name}' not found. Available indexes: #{available_list}")}

      gsi_config ->
        {:ok, gsi_config}
    end
  end

  @doc """
  Validates that a GSI exists in the schema and required fields are populated.

  ## Parameters
    - struct: The struct instance to validate
    - index_name: String name of the GSI to validate
    - requires_sort_key: Boolean indicating if sort key validation is needed (default: false)

  ## Returns
    - `{:ok, gsi_config}` if validation passes
    - `{:error, error_struct}` if validation fails

  ## Example
      # user = %User{email: "test@example.com"}
      # Dynamo.Schema.validate_gsi_config(user, "EmailIndex")
      # {:ok, %{name: "EmailIndex", partition_key: :email, ...}}

      # user = %User{email: nil}
      # Dynamo.Schema.validate_gsi_config(user, "EmailIndex")
      # {:error, %Dynamo.Error{...}}
  """
  def validate_gsi_config(struct, index_name, requires_sort_key \\ false) do
    with {:ok, gsi_config} <- get_gsi_config(struct, index_name),
         :ok <- validate_gsi_partition_key_populated(struct, gsi_config),
         :ok <- validate_gsi_sort_key_populated(struct, gsi_config, requires_sort_key) do
      {:ok, gsi_config}
    end
  end

  @doc """
  Validates that the GSI partition key field is populated in the struct.

  ## Parameters
    - struct: The struct instance to validate
    - gsi_config: Map containing GSI configuration

  ## Returns
    - `:ok` if partition key field is populated
    - `{:error, error_struct}` if partition key field is missing or nil

  ## Example
      # user = %User{email: "test@example.com"}
      # gsi_config = %{name: "EmailIndex", partition_key: :email}
      # Dynamo.Schema.validate_gsi_partition_key_populated(user, gsi_config)
      # :ok

      # user = %User{email: nil}
      # Dynamo.Schema.validate_gsi_partition_key_populated(user, gsi_config)
      # {:error, %Dynamo.Error{...}}
  """
  def validate_gsi_partition_key_populated(struct, gsi_config) do
    partition_key_field = gsi_config.partition_key
    field_value = Map.get(struct, partition_key_field)

    if field_value == nil do
      {:error, Dynamo.Error.new(:validation_error,
        "GSI '#{gsi_config.name}' requires field '#{partition_key_field}' to be populated")}
    else
      :ok
    end
  end

  @doc """
  Validates that the GSI sort key field is populated when sort operations are used.

  ## Parameters
    - struct: The struct instance to validate
    - gsi_config: Map containing GSI configuration
    - requires_sort_key: Boolean indicating if sort key validation is needed

  ## Returns
    - `:ok` if sort key validation passes
    - `{:error, error_struct}` if sort key field is required but missing or nil

  ## Example
      # user = %User{created_at: "2023-01-01"}
      # gsi_config = %{name: "TenantIndex", sort_key: :created_at}
      # Dynamo.Schema.validate_gsi_sort_key_populated(user, gsi_config, true)
      # :ok

      # user = %User{created_at: nil}
      # Dynamo.Schema.validate_gsi_sort_key_populated(user, gsi_config, true)
      # {:error, %Dynamo.Error{...}}
  """
  def validate_gsi_sort_key_populated(struct, gsi_config, requires_sort_key) do
    case {gsi_config.sort_key, requires_sort_key} do
      # GSI has no sort key but sort operations are required - this should fail
      {nil, true} ->
        {:error, Dynamo.Error.new(:validation_error,
          "GSI '#{gsi_config.name}' does not have a sort key but sort operation was requested")}

      # GSI has no sort key and no sort operations required
      {nil, false} ->
        :ok

      # GSI has sort key but sort operations not required
      {_sort_key_field, false} ->
        :ok

      # GSI has sort key and sort operations are required
      {sort_key_field, true} ->
        field_value = Map.get(struct, sort_key_field)

        if field_value == nil do
          {:error, Dynamo.Error.new(:validation_error,
            "GSI '#{gsi_config.name}' sort operation requires field '#{sort_key_field}' to be populated")}
        else
          :ok
        end
    end
  end

  @doc """
  Defines a Global Secondary Index (GSI) for the schema.

  ## Parameters
    - index_name: String name of the GSI
    - opts: Keyword list of GSI configuration options

  ## Options
    - `:partition_key` - atom, field name for GSI partition key (required)
    - `:sort_key` - atom, field name for GSI sort key (optional)
    - `:projection` - atom, projection type (:all, :keys_only, :include) (optional, defaults to :all)
    - `:projected_attributes` - list of atoms, attributes to project when projection is :include (optional)

  ## Example
      global_secondary_index "EmailIndex", partition_key: :email
      global_secondary_index "TenantIndex", partition_key: :tenant, sort_key: :created_at
      global_secondary_index "TenantEmailIndex",
        partition_key: :tenant,
        sort_key: :email,
        projection: :include,
        projected_attributes: [:uuid4, :created_at]
  """
  defmacro global_secondary_index(index_name, opts) do
    quote do
      # Validate required partition_key option
      partition_key_field = unquote(opts)[:partition_key]
      unless partition_key_field do
        raise "Global Secondary Index '#{unquote(index_name)}' requires :partition_key option"
      end

      # Get optional sort_key
      sort_key_field = unquote(opts)[:sort_key]

      # Set default values for optional parameters
      projection = unquote(opts)[:projection] || :all
      projected_attributes = unquote(opts)[:projected_attributes] || []

      # Validate that partition_key field exists in schema
      partition_key_exists = Enum.any?(@fields, fn
        {name, _} -> name == partition_key_field
        {name} -> name == partition_key_field
      end)

      unless partition_key_exists do
        raise "Global Secondary Index '#{unquote(index_name)}' partition_key field ':#{partition_key_field}' does not exist in schema"
      end

      # Validate that sort_key field exists in schema (if provided)
      if sort_key_field do
        sort_key_exists = Enum.any?(@fields, fn
          {name, _} -> name == sort_key_field
          {name} -> name == sort_key_field
        end)

        unless sort_key_exists do
          raise "Global Secondary Index '#{unquote(index_name)}' sort_key field ':#{sort_key_field}' does not exist in schema"
        end
      end

      # Validate projected_attributes exist in schema (if projection is :include)
      if projection == :include and length(projected_attributes) > 0 do
        missing_projected_fields =
          for field <- projected_attributes,
              not Enum.any?(@fields, fn
                {name, _} -> name == field
                {name} -> name == field
              end),
              do: field

        unless Enum.empty?(missing_projected_fields) do
          raise "Global Secondary Index '#{unquote(index_name)}' projected_attributes contain non-existent fields: #{Enum.join(missing_projected_fields, ", ")}"
        end
      end

      # Store GSI configuration
      gsi_config = %{
        name: unquote(index_name),
        partition_key: partition_key_field,
        sort_key: sort_key_field,
        projection: projection,
        projected_attributes: projected_attributes
      }

      @global_secondary_indexes gsi_config
    end
  end
end
