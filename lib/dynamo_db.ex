defmodule Dynamo.DynamoDB do
  @moduledoc """
  DynamoDB API client using Req and AWS Signature Version 4.

  This module provides the same interface as AWS.DynamoDB but uses our custom
  Req-based client with support for session tokens.
  """

  @doc """
  Puts an item into a DynamoDB table.
  """
  def put_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "PutItem", payload) do
      Dynamo.Logger.log_query("PutItem", payload, response)
      result
    end
  end

  @doc """
  Gets an item from a DynamoDB table.
  """
  def get_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "GetItem", payload) do
      Dynamo.Logger.log_query("GetItem", payload, response)
      result
    end
  end

  @doc """
  Queries items from a DynamoDB table.
  """
  def query(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "Query", payload) do
      Dynamo.Logger.log_query("Query", payload, response)
      result
    end
  end

  @doc """
  Scans items from a DynamoDB table.
  """
  def scan(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "Scan", payload) do
      Dynamo.Logger.log_query("Scan", payload, response)
      result
    end
  end

  @doc """
  Deletes an item from a DynamoDB table.
  """
  def delete_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "DeleteItem", payload) do
      Dynamo.Logger.log_query("DeleteItem", payload, response)
      result
    end
  end

  @doc """
  Updates an item in a DynamoDB table.
  """
  def update_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "UpdateItem", payload) do
      Dynamo.Logger.log_query("UpdateItem", payload, response)
      result
    end
  end

  @doc """
  Performs a batch write operation (put or delete multiple items).
  """
  def batch_write_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "BatchWriteItem", payload) do
      Dynamo.Logger.log_query("BatchWriteItem", payload, response)
      result
    end
  end

  @doc """
  Performs a batch get operation (retrieve multiple items).
  """
  def batch_get_item(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "BatchGetItem", payload) do
      Dynamo.Logger.log_query("BatchGetItem", payload, response)
      result
    end
  end

  @doc """
  Executes a transaction with multiple write operations.
  """
  def transact_write_items(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "TransactWriteItems", payload) do
      Dynamo.Logger.log_query("TransactWriteItems", payload, response)
      result
    end
  end

  @doc """
  Creates a new DynamoDB table.
  """
  def create_table(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "CreateTable", payload) do
      Dynamo.Logger.log_query("CreateTable", payload, response)
      result
    end
  end

  @doc """
  Deletes a DynamoDB table.
  """
  def delete_table(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "DeleteTable", payload) do
      Dynamo.Logger.log_query("DeleteTable", payload, response)
      result
    end
  end

  @doc """
  Describes a DynamoDB table.
  """
  def describe_table(client, payload) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "DescribeTable", payload) do
      Dynamo.Logger.log_query("DescribeTable", payload, response)
      result
    end
  end

  @doc """
  Lists all DynamoDB tables.
  """
  def list_tables(client, payload \\ %{}) do
    with {:ok, response, _} = result <- Dynamo.AWS.request(client, "ListTables", payload) do
      Dynamo.Logger.log_query("ListTables", payload, response)
      result
    end
  end
end
