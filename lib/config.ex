defmodule Dynamo.Config do
  @moduledoc """
  Configuration management for Dynamo.

  Provides functions to retrieve and manage configuration settings for the Dynamo library.
  Configuration can be specified at different levels:

  1. Application environment (global defaults)
  2. Runtime overrides (per-process configuration)
  3. Schema-specific configuration (per-schema settings)

  ## Application Configuration

  Configure Dynamo globally in your config.exs:

  ```elixir
  config :dynamo,
    partition_key_name: "pk",
    sort_key_name: "sk",
    key_separator: "#",
    suffix_partition_key: true,
    prefix_sort_key: false
  ```
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
