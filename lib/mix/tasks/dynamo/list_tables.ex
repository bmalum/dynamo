defmodule Mix.Tasks.Dynamo.ListTables do
  use Mix.Task

  @shortdoc "Lists all tables in the configured DynamoDB instance"
  @moduledoc """
  Lists all tables in the configured DynamoDB instance.

  ## Usage

      mix dynamo.list_tables [options]

  ## Options

      --endpoint       - Custom DynamoDB endpoint URL (e.g., for local development)
      --region         - AWS region (default: from AWS config)
      --limit          - Maximum number of tables to list (default: all)
      --name-contains  - Only list tables with names containing this string

  ## Examples

      # List all tables
      mix dynamo.list_tables

      # List tables with local DynamoDB
      mix dynamo.list_tables --endpoint http://localhost:8000

      # List tables in a specific region
      mix dynamo.list_tables --region eu-west-1

      # List tables with name filtering
      mix dynamo.list_tables --name-contains user
  """

  @doc false
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:aws)
    Application.ensure_all_started(:aws_credentials)

    # Parse arguments
    {options, _, _} = OptionParser.parse(args,
      strict: [
        endpoint: :string,
        region: :string,
        limit: :integer,
        name_contains: :string
      ]
    )

    # Setup AWS client
    client_opts = [
      endpoint: options[:endpoint],
      region: options[:region]
    ] |> Enum.filter(fn {_, v} -> v != nil end)
    client = Dynamo.AWS.client(client_opts)

    # List tables
    list_tables(client, options[:limit], options[:name_contains])
  end

  defp list_tables(client, limit, name_filter, exclusive_start_table_name \\ nil, acc \\ []) do
    # Prepare list tables request
    request = %{}

    request = if limit do
      Map.put(request, "Limit", limit)
    else
      request
    end

    request = if exclusive_start_table_name do
      Map.put(request, "ExclusiveStartTableName", exclusive_start_table_name)
    else
      request
    end

    case AWS.DynamoDB.list_tables(client, request) do
      {:ok, response, _context} ->
        tables = response["TableNames"] || []
        last_evaluated_table = response["LastEvaluatedTableName"]

        # Filter tables if requested
        filtered_tables = if name_filter do
          Enum.filter(tables, &String.contains?(&1, name_filter))
        else
          tables
        end

        # Combine with accumulated tables
        combined_tables = acc ++ filtered_tables

        # If there are more tables to fetch and we haven't hit the limit yet
        if last_evaluated_table && (is_nil(limit) || length(combined_tables) < limit) do
          list_tables(client, limit, name_filter, last_evaluated_table, combined_tables)
        else
          # We're done - output the tables
          display_tables(combined_tables, limit)
        end

      {:error, %{"__type" => type, "Message" => message}} ->
        Mix.shell().error("Failed to list tables: #{message} (#{type})")

      {:error, error} ->
        Mix.shell().error("Failed to list tables: #{inspect(error)}")
    end
  end

  defp display_tables(tables, limit) do
    if Enum.empty?(tables) do
      Mix.shell().info("No tables found")
    else
      Mix.shell().info("\nFound #{length(tables)} tables:\n")

      tables
      |> Enum.sort()
      |> Enum.take(limit || length(tables))
      |> Enum.each(fn table ->
        Mix.shell().info("  - #{table}")
      end)

      Mix.shell().info("")
    end
  end
end
