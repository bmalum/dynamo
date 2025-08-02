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
    Dynamo.AWS.request(client, "PutItem", payload)
  end

  @doc """
  Gets an item from a DynamoDB table.
  """
  def get_item(client, payload) do
    Dynamo.AWS.request(client, "GetItem", payload)
  end

  @doc """
  Queries items from a DynamoDB table.
  """
  def query(client, payload) do
    Dynamo.AWS.request(client, "Query", payload)
  end

  @doc """
  Scans items from a DynamoDB table.
  """
  def scan(client, payload) do
    Dynamo.AWS.request(client, "Scan", payload)
  end

  @doc """
  Deletes an item from a DynamoDB table.
  """
  def delete_item(client, payload) do
    Dynamo.AWS.request(client, "DeleteItem", payload)
  end

  @doc """
  Updates an item in a DynamoDB table.
  """
  def update_item(client, payload) do
    Dynamo.AWS.request(client, "UpdateItem", payload)
  end

  @doc """
  Performs a batch write operation (put or delete multiple items).
  """
  def batch_write_item(client, payload) do
    Dynamo.AWS.request(client, "BatchWriteItem", payload)
  end

  @doc """
  Performs a batch get operation (retrieve multiple items).
  """
  def batch_get_item(client, payload) do
    Dynamo.AWS.request(client, "BatchGetItem", payload)
  end

  @doc """
  Executes a transaction with multiple write operations.
  """
  def transact_write_items(client, payload) do
    Dynamo.AWS.request(client, "TransactWriteItems", payload)
  end

  @doc """
  Creates a new DynamoDB table.
  """
  def create_table(client, payload) do
    Dynamo.AWS.request(client, "CreateTable", payload)
  end

  @doc """
  Deletes a DynamoDB table.
  """
  def delete_table(client, payload) do
    Dynamo.AWS.request(client, "DeleteTable", payload)
  end

  @doc """
  Describes a DynamoDB table.
  """
  def describe_table(client, payload) do
    Dynamo.AWS.request(client, "DescribeTable", payload)
  end

  @doc """
  Lists all DynamoDB tables.
  """
  def list_tables(client, payload \\ %{}) do
    Dynamo.AWS.request(client, "ListTables", payload)
  end
end
