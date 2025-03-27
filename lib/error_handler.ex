defmodule Dynamo.ErrorHandler do
  @moduledoc """
  Standardized error handling for AWS DynamoDB operations.

  This module provides consistent error handling functions for various
  DynamoDB operation results. It converts AWS error responses into
  standardized `Dynamo.Error` structs.
  """

  @doc """
  Handles AWS DynamoDB operation results, standardizing error responses.

  This function transforms AWS error responses into standardized `Dynamo.Error` structs,
  providing more detailed error information and consistent error handling.

  ## Parameters
    * `result` - The result from an AWS operation

  ## Returns
    * `{:ok, result}` - Unchanged success response
    * `{:error, error}` - Standardized error struct

  ## Examples

      iex> Dynamo.ErrorHandler.handle_result({:ok, %{"Item" => item}, _})
      {:ok, %{"Item" => item}}

      iex> Dynamo.ErrorHandler.handle_result({:error, %{"__type" => "ResourceNotFoundException", "Message" => "Table not found"}})
      {:error, %Dynamo.Error{type: :resource_not_found, message: "DynamoDB error: Table not found", cause: %{type: "ResourceNotFoundException"}}}
  """
  @spec handle_result(tuple()) :: {:ok, any()} | {:error, Dynamo.Error.t()}
  def handle_result({:ok, result, _context}), do: {:ok, result}
  def handle_result({:ok, result}), do: {:ok, result}

  def handle_result({:error, %{"__type" => type, "Message" => message}}) do
    error_type = categorize_aws_error(type)
    {:error, Dynamo.Error.new(error_type, "DynamoDB error: #{message}", %{type: type})}
  end

  def handle_result({:error, error}) do
    {:error, Dynamo.Error.new(:aws_error, "AWS error occurred", error)}
  end

  def handle_result(error) do
    {:error, Dynamo.Error.new(:unknown_error, "Unknown error during DynamoDB operation", error)}
  end

  @doc """
  Categorizes AWS error types into more specific error atoms.

  ## Parameters
    * `error_type` - String with the AWS error type

  ## Returns
    * Atom representing the error category
  """
  @spec categorize_aws_error(String.t()) :: atom()
  def categorize_aws_error("ResourceNotFoundException"), do: :resource_not_found
  def categorize_aws_error("ResourceInUseException"), do: :resource_in_use
  def categorize_aws_error("LimitExceededException"), do: :limit_exceeded
  def categorize_aws_error("ProvisionedThroughputExceededException"), do: :provisioned_throughput_exceeded
  def categorize_aws_error("ConditionalCheckFailedException"), do: :conditional_check_failed
  def categorize_aws_error("ValidationException"), do: :validation_error
  def categorize_aws_error("AccessDeniedException"), do: :access_denied
  def categorize_aws_error("UnrecognizedClientException"), do: :authentication_error
  def categorize_aws_error("ItemCollectionSizeLimitExceededException"), do: :item_collection_size_exceeded
  def categorize_aws_error("TransactionConflictException"), do: :transaction_conflict
  def categorize_aws_error(_), do: :aws_error

  @doc """
  Extracts specific error data from AWS error responses.

  This function attempts to extract the error type, message, and any additional
  information provided in AWS error responses.

  ## Parameters
    * `error` - The raw error from an AWS operation

  ## Returns
    * Tuple containing error type, message, and additional data
  """
  @spec extract_error_data(any()) :: {atom(), String.t(), map() | nil}
  def extract_error_data(%{"__type" => type, "Message" => message} = error) do
    # Remove known keys to isolate additional error data
    additional_data = error
    |> Map.drop(["__type", "Message"])
    |> case do
      map when map_size(map) == 0 -> %{type: type}
      map -> Map.put(map, :type, type)
    end

    {categorize_aws_error(type), message, additional_data}
  end

  def extract_error_data(error) when is_binary(error) do
    {:unknown_error, error, nil}
  end

  def extract_error_data(error) do
    {:unknown_error, "Unknown error occurred", error}
  end
end
