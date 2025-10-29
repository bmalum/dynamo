defmodule Dynamo.Config do
  @moduledoc """
  Configuration management for Dynamo with multi-level hierarchy.

  This module provides functions to retrieve and manage configuration settings for the Dynamo
  library. Configuration can be specified at three different levels, with later levels overriding
  earlier ones:

  1. **Application environment** - Global defaults set in config files
  2. **Process configuration** - Runtime overrides for the current process
  3. **Schema-specific configuration** - Per-schema settings passed to `use Dynamo.Schema`

  ## Configuration Hierarchy

  The configuration hierarchy allows you to set sensible defaults while maintaining flexibility:

  ```
  Defaults → Application Config → Process Config → Schema Config
  (lowest)                                              (highest)
  ```

  ## Application Configuration

  Set global defaults in your `config/config.exs`:

      config :dynamo,
        partition_key_name: "pk",
        sort_key_name: "sk",
        key_separator: "#",
        suffix_partition_key: true,
        prefix_sort_key: false,
        table_has_sort_key: true

  ## Process Configuration

  Override settings for the current process at runtime:

      # Set process-specific configuration
      Dynamo.Config.put_process_config(key_separator: "-", suffix_partition_key: false)

      # Operations in this process use the new settings
      {:ok, user} = MyApp.User.put_item(user)

      # Clear process configuration
      Dynamo.Config.clear_process_config()

  This is particularly useful for:
  - Multi-tenant applications with different key formats per tenant
  - Testing scenarios requiring isolated configurations
  - Background jobs with special requirements

  ## Schema Configuration

  Pass options directly when defining a schema:

      defmodule MyApp.LegacyUser do
        use Dynamo.Schema,
          key_separator: "_",
          prefix_sort_key: true

        item do
          # schema definition...
        end
      end

  ## Available Configuration Options

  - `partition_key_name` - DynamoDB attribute name for partition key (default: `"pk"`)
  - `sort_key_name` - DynamoDB attribute name for sort key (default: `"sk"`)
  - `key_separator` - String to join composite key parts (default: `"#"`)
  - `suffix_partition_key` - Add entity type to partition key (default: `true`)
  - `prefix_sort_key` - Include field names in sort key (default: `false`)
  - `table_has_sort_key` - Whether table uses sort keys (default: `true`)

  ## Examples

      # Get full merged configuration
      config = Dynamo.Config.config()
      IO.inspect(config[:key_separator])  # => "#"

      # Get configuration with schema overrides
      config = Dynamo.Config.config(key_separator: "_")
      IO.inspect(config[:key_separator])  # => "_"

      # Get specific value with default
      separator = Dynamo.Config.get(:key_separator, [], "#")

      # Process-level configuration for multi-tenant scenario
      defmodule TenantOperations do
        def perform_for_tenant(tenant_id, operation) do
          tenant_config = get_tenant_config(tenant_id)
          Dynamo.Config.put_process_config(tenant_config)

          try do
            operation.()
          after
            Dynamo.Config.clear_process_config()
          end
        end

        defp get_tenant_config("tenant_a"), do: [key_separator: "_"]
        defp get_tenant_config("tenant_b"), do: [key_separator: "::"]
        defp get_tenant_config(_), do: []
      end

  ## See Also

  - `Dynamo.Schema` - For using configuration in schema definitions
  - `Dynamo.Table` - For operations that respect configuration
  """

  @default_config [
    prefix_sort_key: false,
    suffix_partition_key: true,
    key_separator: "#",
    partition_key_name: "pk",
    sort_key_name: "sk",
    table_has_sort_key: true
  ]

  @doc """
  Returns the full configuration with defaults applied.

  ## Parameters
    - schema_opts: Optional schema-specific configuration that overrides defaults

  ## Returns
    Configuration map with all settings
  """
  def config(schema_opts \\ []) do
    app_config = Application.get_all_env(:dynamo)
    process_config = get_process_config()

    Keyword.merge(@default_config, app_config)
    |> Keyword.merge(process_config)
    |> Keyword.merge(schema_opts)
  end

  @doc """
  Gets a specific configuration value.

  ## Parameters
    - key: The configuration key
    - schema_opts: Optional schema-specific configuration
    - default: Default value if key is not found

  ## Returns
    The configuration value
  """
  def get(key, schema_opts \\ [], default \\ nil) do
    Keyword.get(config(schema_opts), key, default)
  end

  @doc """
  Sets configuration values for the current process.

  These values will override application configuration but only for the current process.

  ## Example

  ```elixir
  Dynamo.Config.put_process_config(key_separator: "-")
  ```
  """
  def put_process_config(config) do
    Process.put({__MODULE__, :config}, config)
  end

  @doc """
  Clears process-specific configuration.
  """
  def clear_process_config do
    Process.delete({__MODULE__, :config})
  end

  @doc """
  Gets the process-specific configuration.
  """
  def get_process_config do
    Process.get({__MODULE__, :config}, [])
  end
end
