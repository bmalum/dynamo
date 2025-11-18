defmodule Mix.Tasks.Dynamo.CreateTable do
  use Mix.Task

  @shortdoc "Creates a DynamoDB table with specified configuration"
  @moduledoc """
  Creates a new DynamoDB table with configured primary key structure.

  ## Usage

      mix dynamo.create_table TABLE_NAME [options]

  ## Options

      --partition-key    - Name of the partition key (default: "pk")
      --sort-key         - Name of the sort key (default: "sk")
      --billing-mode     - Billing mode: "PROVISIONED" or "PAY_PER_REQUEST" (default: "PAY_PER_REQUEST")
      --read-capacity    - Read capacity units (when using PROVISIONED) (default: 5)
      --write-capacity   - Write capacity units (when using PROVISIONED) (default: 5)
      --endpoint         - Custom DynamoDB endpoint URL (e.g., for local development)
      --region           - AWS region (default: from AWS config)
      --no-sort-key      - Create table without a sort key

  ## Examples

      # Create a table with default configuration
      mix dynamo.create_table users

      # Create a table with custom keys
      mix dynamo.create_table users --partition-key user_id --sort-key email

      # Create a table with only a partition key
      mix dynamo.create_table simple_users --partition-key user_id --no-sort-key

      # Create a table with provisioned throughput
      mix dynamo.create_table high_traffic_table --billing-mode PROVISIONED --read-capacity 50 --write-capacity 25

      # Create a table using local DynamoDB
      mix dynamo.create_table local_test --endpoint http://localhost:8000
  """

  @doc false
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:jason)

    # Parse arguments
    {options, args, _} = OptionParser.parse(args,
      strict: [
        partition_key: :string,
        sort_key: :string,
        billing_mode: :string,
        read_capacity: :integer,
        write_capacity: :integer,
        endpoint: :string,
        region: :string,
        no_sort_key: :boolean
      ]
    )

    # Validate required arguments
    case args do
      [table_name | _] ->
        create_table(table_name, options)
      [] ->
        Mix.raise("Expected TABLE_NAME argument. Usage: mix dynamo.create_table TABLE_NAME [options]")
    end
  end

  defp create_table(table_name, options) do
    # Set defaults
    partition_key = options[:partition_key] || "pk"
    has_sort_key = !options[:no_sort_key]
    sort_key = if has_sort_key, do: options[:sort_key] || "sk", else: nil
    billing_mode = options[:billing_mode] || "PAY_PER_REQUEST"
    read_capacity = options[:read_capacity] || 5
    write_capacity = options[:write_capacity] || 5

    # Setup AWS client
    client_opts = [
      endpoint: options[:endpoint],
      region: options[:region]
    ] |> Enum.filter(fn {_, v} -> v != nil end)
    client = Dynamo.AWS.client(client_opts)

    # Build attribute definitions and key schema
    attribute_definitions = [
      %{"AttributeName" => partition_key, "AttributeType" => "S"}
    ]

    attribute_definitions = if has_sort_key do
      attribute_definitions ++ [%{"AttributeName" => sort_key, "AttributeType" => "S"}]
    else
      attribute_definitions
    end

    key_schema = [
      %{"AttributeName" => partition_key, "KeyType" => "HASH"}
    ]

    key_schema = if has_sort_key do
      key_schema ++ [%{"AttributeName" => sort_key, "KeyType" => "RANGE"}]
    else
      key_schema
    end

    # Build create table request
    create_request = %{
      "TableName" => table_name,
      "AttributeDefinitions" => attribute_definitions,
      "KeySchema" => key_schema,
      "BillingMode" => billing_mode
    }

    # Add provisioned throughput if using PROVISIONED billing mode
    create_request = if billing_mode == "PROVISIONED" do
      Map.put(create_request, "ProvisionedThroughput", %{
        "ReadCapacityUnits" => read_capacity,
        "WriteCapacityUnits" => write_capacity
      })
    else
      create_request
    end

    # Create the table
    Mix.shell().info("Creating table #{table_name}...")

    case Dynamo.DynamoDB.create_table(client, create_request) do
      {:ok, response, _context} ->
        status = get_in(response, ["TableDescription", "TableStatus"])
        Mix.shell().info("Table #{table_name} created successfully (Status: #{status})")
        Mix.shell().info("Waiting for table to become active...")
        wait_for_table_active(client, table_name)

      {:error, %{"__type" => type, "Message" => message}} ->
        Mix.shell().error("Failed to create table: #{message} (#{type})")

      {:error, error} ->
        Mix.shell().error("Failed to create table: #{inspect(error)}")
    end
  end

  defp wait_for_table_active(client, table_name) do
    case Dynamo.DynamoDB.describe_table(client, %{"TableName" => table_name}) do
      {:ok, %{"Table" => %{"TableStatus" => "ACTIVE"}}, _} ->
        Mix.shell().info("Table #{table_name} is now ACTIVE")

      {:ok, %{"Table" => %{"TableStatus" => status}}, _} ->
        Mix.shell().info("Table status: #{status} (waiting...)")
        :timer.sleep(1000)
        wait_for_table_active(client, table_name)

      {:error, error} ->
        Mix.shell().error("Error checking table status: #{inspect(error)}")
    end
  end
end
