defmodule Dynamo.ConfigTest do
  use ExUnit.Case

  setup do
    # Clear any process-specific config before each test
    Dynamo.Config.clear_process_config()

    # Save existing application config and clear it completely
    previous_config = Application.get_all_env(:dynamo)

    # Clear all dynamo application config
    # We need to iterate over keys since there's no delete_all_env function
    Enum.each(previous_config, fn {k, _v} ->
      Application.delete_env(:dynamo, k)
    end)

    on_exit(fn ->
      # Clean up after test
      Enum.each(Application.get_all_env(:dynamo), fn {k, _v} ->
        Application.delete_env(:dynamo, k)
      end)

      # Restore the previous application config
      if previous_config != [] do
        Enum.each(previous_config, fn {k, v} ->
          Application.put_env(:dynamo, k, v)
        end)
      end

      Dynamo.Config.clear_process_config()
    end)

    :ok
  end

  test "default configuration values" do
    config = Dynamo.Config.config()
    assert config[:partition_key_name] == "pk"
    assert config[:sort_key_name] == "sk"
    assert config[:key_separator] == "#"
    assert config[:suffix_partition_key] == true
    assert config[:prefix_sort_key] == false
    assert config[:table_has_sort_key] == true
  end

  test "application configuration overrides defaults" do
    Application.put_env(:dynamo, :key_separator, "-")
    Application.put_env(:dynamo, :partition_key_name, "PrimaryKey")

    config = Dynamo.Config.config()
    assert config[:key_separator] == "-"
    assert config[:partition_key_name] == "PrimaryKey"
    # Other values remain as defaults
    assert config[:sort_key_name] == "sk"
  end

  test "process configuration overrides application config" do
    # Set up application config
    Application.put_env(:dynamo, :key_separator, "-")

    # Set up process config
    Dynamo.Config.put_process_config(key_separator: "+", sort_key_name: "SortKey")

    # Process config should override application config
    config = Dynamo.Config.config()
    assert config[:key_separator] == "+"
    assert config[:sort_key_name] == "SortKey"
    # Values not in process config use application config or defaults
    assert config[:partition_key_name] == "pk"
  end

  test "schema-specific configuration overrides all other configs" do
    # Set up application config
    Application.put_env(:dynamo, :key_separator, "-")

    # Set up process config
    Dynamo.Config.put_process_config(key_separator: "+", prefix_sort_key: true)

    # Schema-specific config
    schema_config = [key_separator: "*", partition_key_name: "id"]

    # Schema-specific config should override both process and application config
    config = Dynamo.Config.config(schema_config)
    assert config[:key_separator] == "*"
    assert config[:partition_key_name] == "id"
    assert config[:prefix_sort_key] == true  # From process config
    assert config[:sort_key_name] == "sk"    # From defaults
  end

  test "get/3 retrieves specific configuration value" do
    Application.put_env(:dynamo, :key_separator, "-")

    assert Dynamo.Config.get(:key_separator) == "-"
    assert Dynamo.Config.get(:prefix_sort_key) == false
    assert Dynamo.Config.get(:nonexistent_key) == nil
    assert Dynamo.Config.get(:nonexistent_key, [], "default") == "default"
  end

  test "get/3 respects schema-specific overrides" do
    schema_config = [key_separator: "*"]

    assert Dynamo.Config.get(:key_separator, schema_config) == "*"
    assert Dynamo.Config.get(:prefix_sort_key, schema_config) == false
  end
end
