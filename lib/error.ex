defmodule Dynamo.Error do
  @moduledoc """
  Custom error types for Dynamo operations.

  This module defines a standardized error structure for Dynamo operations,
  providing more context and information about errors that occur during
  DynamoDB interactions.
  """

  defexception [:type, :message, :cause]

  @type t :: %__MODULE__{
    type: atom(),
    message: String.t(),
    cause: any()
  }

  @doc """
  Creates a new Dynamo error.

  ## Parameters
    * `type` - Atom representing the error type
    * `message` - Human-readable error message
    * `cause` - Original error or additional context (optional)

  ## Returns
    * A new `Dynamo.Error` struct

  ## Examples

      # Create a validation error
      Dynamo.Error.new(:validation_error, "Partition key cannot be empty")

      # Create an AWS error with the original error as cause
      Dynamo.Error.new(:aws_error, "Failed to put item", original_error)
  """
  @spec new(atom(), String.t(), any()) :: t()
  def new(type, message, cause \\ nil) do
    %__MODULE__{type: type, message: message, cause: cause}
  end

  @doc """
  Returns the error message.

  This function is used by the Exception protocol to display the error message.

  ## Parameters
    * `error` - The Dynamo.Error struct

  ## Returns
    * String containing the error message
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: message, type: type, cause: nil}) do
    "#{type}: #{message}"
  end

  def message(%__MODULE__{message: message, type: type, cause: cause}) do
    "#{type}: #{message} (#{inspect(cause)})"
  end

  @doc """
  Formats AWS DynamoDB errors into Dynamo.Error structs.

  ## Parameters
    * `error` - The error returned by AWS DynamoDB operations

  ## Returns
    * A `Dynamo.Error` struct with appropriate type and message
  """
  @spec from_aws_error(any()) :: t()
  def from_aws_error({:error, %{"__type" => type, "Message" => message}}) do
    new(:aws_error, "DynamoDB error: #{message}", %{type: type})
  end

  def from_aws_error({:error, error}) do
    new(:aws_error, "AWS error occurred", error)
  end

  def from_aws_error(error) do
    new(:unknown_error, "Unknown error during DynamoDB operation", error)
  end
end
