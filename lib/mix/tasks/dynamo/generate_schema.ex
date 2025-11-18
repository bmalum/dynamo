defmodule Mix.Tasks.Dynamo.GenerateSchema do
  use Mix.Task

  @shortdoc "Generates a Dynamo schema from an existing DynamoDB table"
  @moduledoc """
  Generates a Dynamo schema module based on an existing DynamoDB table.

  This task analyzes a DynamoDB table structure and generates a corresponding
  Dynamo schema module for it.

  ## Usage

      mix dynamo.generate_schema TABLE_NAME [options]

  ## Options

      --module          - Module name for the schema (default: derived from table name)
      --output          - Output file path (default: lib/<derived_name>.ex)
      --endpoint        - Custom DynamoDB endpoint URL (e.g., for local development)
      --region          - AWS region (default: from AWS config)
      --scan-items      - Number of items to scan to infer field structure (default: 5)
      --overwrite       - Overwrite existing file if it exists
      --partition-key   - Override detected partition key name
      --sort-key        - Override detected sort key name

  ## Examples

      # Generate a schema for "users" table
      mix dynamo.generate_schema users

      # Generate a schema with a specific module name
      mix dynamo.generate_schema users --module MyApp.User

      # Generate a schema with a specific output file
      mix dynamo.generate_schema users --output lib/schemas/user.ex

      # Generate a schema using local DynamoDB
      mix dynamo.generate_schema users --endpoint http://localhost:8000
  """

  @doc false
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:jason)

    # Parse arguments
    {options, args, _} = OptionParser.parse(args,
      strict: [
        module: :string,
        output: :string,
        endpoint: :string,
        region: :string,
        scan_items: :integer,
        overwrite: :boolean,
        partition_key: :string,
        sort_key: :string
      ]
    )

    # Validate required arguments
    case args do
      [table_name | _] ->
        generate_schema(table_name, options)
      [] ->
        Mix.raise("Expected TABLE_NAME argument. Usage: mix dynamo.generate_schema TABLE_NAME [options]")
    end
  end

  defp generate_schema(table_name, options) do
    # Setup AWS client
    client_opts = [
      endpoint: options[:endpoint],
      region: options[:region]
    ] |> Enum.filter(fn {_, v} -> v != nil end)
    client = Dynamo.AWS.client(client_opts)

    # Determine module name (default to CamelCase from table name)
    module_name = options[:module] || derive_module_name(table_name)

    # Determine output file path
    output_path = options[:output] || derive_output_path(module_name)

    # Check if output file already exists
    if File.exists?(output_path) && !options[:overwrite] do
      Mix.shell().error("File already exists: #{output_path}. Use --overwrite to replace it.")
      exit({:shutdown, 1})
    end

    # Analyze the table
    Mix.shell().info("Analyzing table #{table_name}...")
    case analyze_table(client, table_name, options) do
      {:ok, table_info} ->
        # Generate schema code
        schema_code = generate_schema_code(module_name, table_name, table_info)

        # Write schema to file
        File.mkdir_p!(Path.dirname(output_path))
        File.write!(output_path, schema_code)
        Mix.shell().info("Generated schema file: #{output_path}")

      {:error, reason} ->
        Mix.shell().error("Failed to analyze table: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp derive_module_name(table_name) do
    table_name
    |> String.split(["-", "_"])
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp derive_output_path(module_name) do
    parts = module_name
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)

    filename = List.last(parts) <> ".ex"
    directory = if length(parts) > 1 do
      Path.join(["lib" | Enum.drop(parts, -1)])
    else
      "lib"
    end

    File.mkdir_p!(directory)
    Path.join(directory, filename)
  end

  defp analyze_table(client, table_name, options) do
    # Get table description
    case Dynamo.DynamoDB.describe_table(client, %{"TableName" => table_name}) do
      {:ok, table_info, _} ->
        # Extract key schema
        partition_key = options[:partition_key] || extract_partition_key(table_info)
        sort_key = options[:sort_key] || extract_sort_key(table_info)

        # Scan sample items to detect fields if requested
        scan_count = options[:scan_items] || 5

        if scan_count > 0 do
          case scan_sample_items(client, table_name, scan_count) do
            {:ok, items} ->
              fields = extract_fields_from_items(items, partition_key, sort_key)
              {:ok, %{
                partition_key: partition_key,
                sort_key: sort_key,
                fields: fields
              }}

            {:error, reason} ->
              {:error, "Failed to scan items: #{inspect(reason)}"}
          end
        else
          {:ok, %{
            partition_key: partition_key,
            sort_key: sort_key,
            fields: []
          }}
        end

      {:error, %{"__type" => "ResourceNotFoundException", "Message" => _}} ->
        {:error, "Table '#{table_name}' does not exist"}

      {:error, %{"__type" => type, "Message" => message}} ->
        {:error, "#{message} (#{type})"}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end

  defp extract_partition_key(table_info) do
    get_in(table_info, ["Table", "KeySchema"])
    |> Enum.find(fn key -> key["KeyType"] == "HASH" end)
    |> case do
      %{"AttributeName" => name} -> name
      _ -> "pk"
    end
  end

  defp extract_sort_key(table_info) do
    get_in(table_info, ["Table", "KeySchema"])
    |> Enum.find(fn key -> key["KeyType"] == "RANGE" end)
    |> case do
      %{"AttributeName" => name} -> name
      _ -> nil
    end
  end

  defp scan_sample_items(client, table_name, limit) do
    case Dynamo.DynamoDB.scan(client, %{"TableName" => table_name, "Limit" => limit}) do
      {:ok, %{"Items" => items}, _} -> {:ok, items}
      {:error, error} -> {:error, error}
    end
  end

  defp extract_fields_from_items(items, partition_key, sort_key) do
    # Combine all attribute names from all items
    field_names = items
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.reject(fn name -> name == partition_key || name == sort_key end)

    # Convert DynamoDB keys to atoms, keeping type info
    Enum.map(field_names, fn name ->
      # Sample the first non-nil value to guess the type
      sample = Enum.find_value(items, fn item ->
        Map.get(item, name)
      end)

      {String.to_atom(name), infer_field_type(sample)}
    end)
  end

  defp infer_field_type(nil), do: :any
  defp infer_field_type(%{"S" => _}), do: :string
  defp infer_field_type(%{"N" => _}), do: :number
  defp infer_field_type(%{"BOOL" => _}), do: :boolean
  defp infer_field_type(%{"L" => _}), do: :list
  defp infer_field_type(%{"M" => _}), do: :map
  defp infer_field_type(%{"NULL" => _}), do: nil
  defp infer_field_type(%{"SS" => _}), do: {:array, :string}
  defp infer_field_type(%{"NS" => _}), do: {:array, :number}
  defp infer_field_type(%{"BS" => _}), do: {:array, :binary}
  defp infer_field_type(_), do: :any

  defp generate_schema_code(module_name, table_name, table_info) do
    # Generate field definitions
    fields = table_info.fields
    |> Enum.map(fn {name, _type} ->
      "    field :#{name}"
    end)
    |> Enum.join("\n")

    # Generate partition key field
    partition_key_atom = String.to_atom(table_info.partition_key)
    partition_key_field = "    field :#{partition_key_atom}, partition_key: true"

    # Generate sort key field if present
    sort_key_field = if table_info.sort_key do
      sort_key_atom = String.to_atom(table_info.sort_key)
      "    field :#{sort_key_atom}, sort_key: true"
    else
      nil
    end

    # Combine all fields
    all_fields = [partition_key_field, sort_key_field]
    |> Enum.concat([fields])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")

    # Generate the full schema module
    """
    defmodule #{module_name} do
      use Dynamo.Schema

      item do
        table_name "#{table_name}"

        #{all_fields}
      end
    end
    """
  end
end
