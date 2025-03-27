defmodule Mix.Tasks.Dynamo.DeleteTable do
  use Mix.Task

  @shortdoc "Deletes a DynamoDB table"
  @moduledoc """
  Deletes a DynamoDB table.

  This task requires confirmation before deletion to prevent accidental data loss.

  ## Usage

      mix dynamo.delete_table TABLE_NAME [options]

  ## Options

      --endpoint       - Custom DynamoDB endpoint URL (e.g., for local development)
      --region         - AWS region (default: from AWS config)
      --force          - Skip confirmation prompt

  ## Examples

      # Delete a table (will prompt for confirmation)
      mix dynamo.delete_table users

      # Force delete without confirmation
      mix dynamo.delete_table users --force

      # Delete a table from local DynamoDB
      mix dynamo.delete_table users --endpoint http://localhost:8000
  """

  @doc false
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:aws)
    Application.ensure_all_started(:aws_credentials)

    # Parse arguments
    {options, args, _} = OptionParser.parse(args,
      strict: [
        endpoint: :string,
        region: :string,
        force: :boolean
      ]
    )

    # Validate required arguments
    case args do
      [table_name | _] ->
        delete_table(table_name, options)
      [] ->
        Mix.raise("Expected TABLE_NAME argument. Usage: mix dynamo.delete_table TABLE_NAME [options]")
    end
  end

  defp delete_table(table_name, options) do
    # Setup AWS client
    client_opts = [
      endpoint: options[:endpoint],
      region: options[:region]
    ] |> Enum.filter(fn {_, v} -> v != nil end)
    client = Dynamo.AWS.client(client_opts)

    # Check if the table exists
    case AWS.DynamoDB.describe_table(client, %{"TableName" => table_name}) do
      {:ok, table_info, _} ->
        # Table exists, proceed with deletion after confirmation
        item_count = get_item_count(table_info)
        confirm_and_delete(client, table_name, item_count, options[:force])

      {:error, %{"__type" => "ResourceNotFoundException", "Message" => _}} ->
        Mix.shell().error("Table '#{table_name}' does not exist")

      {:error, %{"__type" => type, "Message" => message}} ->
        Mix.shell().error("Error checking table: #{message} (#{type})")

      {:error, error} ->
        Mix.shell().error("Failed to check table: #{inspect(error)}")
    end
  end

  defp get_item_count(table_info) do
    case table_info do
      %{"Table" => %{"ItemCount" => count}} -> count
      _ -> "unknown"
    end
  end

  defp confirm_and_delete(client, table_name, item_count, force) do
    # Show warning and confirmation prompt if not forced
    if force do
      execute_delete(client, table_name)
    else
      Mix.shell().info("\n" <> IO.ANSI.red() <> "WARNING: " <> IO.ANSI.reset() <>
        "You are about to delete the DynamoDB table '#{table_name}'")
      Mix.shell().info("This table contains approximately #{item_count} items.")
      Mix.shell().info("This operation cannot be undone.")

      if Mix.shell().yes?("Do you want to proceed?") do
        execute_delete(client, table_name)
      else
        Mix.shell().info("Table deletion cancelled")
      end
    end
  end

  defp execute_delete(client, table_name) do
    # Delete the table
    Mix.shell().info("Deleting table #{table_name}...")

    case AWS.DynamoDB.delete_table(client, %{"TableName" => table_name}) do
      {:ok, response, _context} ->
        status = get_in(response, ["TableDescription", "TableStatus"])
        Mix.shell().info("Table #{table_name} deletion initiated (Status: #{status})")
        wait_for_table_deleted(client, table_name)

      {:error, %{"__type" => type, "Message" => message}} ->
        Mix.shell().error("Failed to delete table: #{message} (#{type})")

      {:error, error} ->
        Mix.shell().error("Failed to delete table: #{inspect(error)}")
    end
  end

  defp wait_for_table_deleted(client, table_name, attempts \\ 1) do
    if attempts > 30 do
      Mix.shell().info("Giving up on waiting for table deletion. Please check manually.")
      :ok
    else
      case AWS.DynamoDB.describe_table(client, %{"TableName" => table_name}) do
        {:error, %{"__type" => "ResourceNotFoundException", "Message" => _}} ->
          # Table no longer exists - deletion complete
          Mix.shell().info("Table #{table_name} has been deleted successfully")
          :ok

        {:ok, %{"Table" => %{"TableStatus" => status}}, _} ->
          # Table still exists
          Mix.shell().info("Table status: #{status} (waiting...)")
          :timer.sleep(1000)
          wait_for_table_deleted(client, table_name, attempts + 1)

        {:error, error} ->
          Mix.shell().error("Error checking table status: #{inspect(error)}")
          :error
      end
    end
  end
end
