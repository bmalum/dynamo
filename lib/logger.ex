defmodule Dynamo.Logger do
  @moduledoc """
  Provides logging functionality for DynamoDB operations.

  This module allows enabling/disabling logging of DynamoDB queries for debugging purposes.
  """

  @doc """
  Logs a DynamoDB query if logging is enabled.

  ## Parameters
    * `operation` - The DynamoDB operation (e.g., "PutItem", "GetItem", "Query")
    * `payload` - The request payload
    * `response` - The response from DynamoDB (optional)
  """
  @spec log_query(String.t(), map(), any()) :: :ok
  def log_query(operation, payload, response \\ nil) do
    if enabled?() do
      log_message = %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        operation: operation,
        table: Map.get(payload, "TableName", "unknown"),
        payload: payload,
        response: response
      }

      IO.puts("[DynamoDB] #{Jason.encode!(log_message, pretty: true)}")
    end

    :ok
  end

  @doc """
  Enables DynamoDB query logging.
  """
  @spec enable() :: :ok
  def enable() do
    Application.put_env(:dynamo, :logging_enabled, true)
  end

  @doc """
  Disables DynamoDB query logging.
  """
  @spec disable() :: :ok
  def disable() do
    Application.put_env(:dynamo, :logging_enabled, false)
  end

  @doc """
  Checks if DynamoDB query logging is enabled.

  ## Returns
    * `true` if logging is enabled
    * `false` if logging is disabled
  """
  @spec enabled?() :: boolean()
  def enabled?() do
    Application.get_env(:dynamo, :logging_enabled, false)
  end
end
