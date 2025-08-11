defmodule Dynamo.SchemaTest do
  use ExUnit.Case, async: false

  # TODO
  # MultiKey Key generation test (partition & sort key)

  defmodule TestItem do
    use Dynamo.Schema, prefix_sort_key: true

    item do
      table_name("test_table")

      field(:id)
      field(:name, default: "test")
      field(:age, default: 0)
      field(:email)

      partition_key([:id])
      sort_key([:name])
    end
  end

  defmodule AnotherTestItem do
    use Dynamo.Schema

    item do
      table_name("test_table")

      field(:id, partition_key: true)
      field(:name, sort_key: true, default: "test")
      field(:age, default: 0)
      field(:email)
    end
  end

  defmodule GSITestItem do
    use Dynamo.Schema

    item do
      table_name("gsi_test_table")

      field(:uuid4, partition_key: true)
      field(:tenant)
      field(:email)
      field(:created_at, sort_key: true)
      field(:status)

      global_secondary_index("EmailIndex", partition_key: :email)
      global_secondary_index("TenantIndex", partition_key: :tenant, sort_key: :created_at)

      global_secondary_index("TenantEmailIndex",
        partition_key: :tenant,
        sort_key: :email,
        projection: :include,
        projected_attributes: [:uuid4, :created_at]
      )
    end
  end

  defmodule GSITestItemWithPrefix do
    use Dynamo.Schema, prefix_sort_key: true

    item do
      table_name("gsi_test_table_prefix")

      field(:uuid4, partition_key: true)
      field(:tenant)
      field(:email)
      field(:created_at, sort_key: true)

      global_secondary_index("TenantIndex", partition_key: :tenant, sort_key: :created_at)
    end
  end

  describe "schema definition" do
    test "defines correct table name" do
      assert TestItem.table_name() == "test_table"
    end

    test "defines correct partition key" do
      assert TestItem.partition_key() == [:id]
    end

    test "defines correct sort key" do
      assert TestItem.sort_key() == [:name]
    end

    test "defines correct fields" do
      expected_fields = [
        {:name, "test"},
        {:age, 0},
        {:email, nil},
        {:id, nil}
      ]

      assert Keyword.equal?(TestItem.fields(), expected_fields)
    end
  end

  describe "struct creation" do
    test "creates struct with default values" do
      item = %TestItem{}
      assert item.name == "test"
      assert item.age == 0
      assert item.id == nil
      assert item.email == nil
    end

    test "creates struct with custom values" do
      item = %TestItem{id: "123", name: "John", age: 25, email: "john@example.com"}
      assert item.id == "123"
      assert item.name == "John"
      assert item.age == 25
      assert item.email == "john@example.com"
    end
  end

  describe "key generation" do
    test "generates partition key" do
      item = %TestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_partition_key(item)
      assert result.pk == "testitem#123"
    end

    test "generates sort key" do
      item = %TestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_sort_key(item)
      assert result.sk == "name#John"
    end

    test "generates keys with empty values" do
      item = %TestItem{}

      result =
        item
        |> Dynamo.Schema.generate_and_add_partition_key()
        |> Dynamo.Schema.generate_and_add_sort_key()

      assert result.pk == "testitem#empty"
      assert result.sk == "name#test"
    end
  end

  describe "validation" do
    test "raises error when redefining partition key" do
      assert_raise RuntimeError, "Primary Key already defined in fields", fn ->
        defmodule InvalidPartitionKey do
          use Dynamo.Schema

          item do
            field(:id, partition_key: true)
            partition_key([:id])
          end
        end
      end
    end

    test "raises error when redefining sort key" do
      assert_raise RuntimeError, "Sort Key already defined in fields", fn ->
        defmodule InvalidSortKey do
          use Dynamo.Schema

          item do
            field(:name, sort_key: true)
            sort_key([:name])
          end
        end
      end
    end

    test "raises error when partition key field is missing" do
      assert_raise RuntimeError, "Missing fields in schema: missing_field", fn ->
        defmodule MissingPartitionKey do
          use Dynamo.Schema

          item do
            field(:id)
            partition_key([:missing_field])
          end
        end
      end
    end
  end

  describe "schema definition (AnotherItem)" do
    test "defines correct table name" do
      assert TestItem.table_name() == "test_table"
    end

    test "defines correct partition key" do
      assert TestItem.partition_key() == [:id]
    end

    test "defines correct sort key" do
      assert TestItem.sort_key() == [:name]
    end

    test "defines correct fields" do
      expected_fields = [
        {:name, "test"},
        {:age, 0},
        {:email, nil},
        {:id, nil}
      ]

      assert Keyword.equal?(TestItem.fields(), expected_fields)
    end
  end

  describe "struct creation (Another Item)" do
    test "creates struct with default values" do
      item = %AnotherTestItem{}
      assert item.name == "test"
      assert item.age == 0
      assert item.id == nil
      assert item.email == nil
    end

    test "creates struct with custom values" do
      item = %AnotherTestItem{id: "123", name: "John", age: 25, email: "john@example.com"}
      assert item.id == "123"
      assert item.name == "John"
      assert item.age == 25
      assert item.email == "john@example.com"
    end
  end

  describe "key generation  (Another Item)" do
    test "generates partition key" do
      item = %AnotherTestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_partition_key(item)
      assert result.pk == "anothertestitem#123"
    end

    test "generates sort key" do
      item = %AnotherTestItem{id: "123", name: "John"}
      result = Dynamo.Schema.generate_and_add_sort_key(item)
      assert result.sk == "John"
    end

    test "generates keys with empty values" do
      item = %AnotherTestItem{}

      result =
        item
        |> Dynamo.Schema.generate_and_add_partition_key()
        |> Dynamo.Schema.generate_and_add_sort_key()

      assert result.pk == "anothertestitem#empty"
      assert result.sk == "test"
    end
  end

  describe "GSI definition" do
    test "defines GSI configurations correctly" do
      gsis = GSITestItem.global_secondary_indexes()

      assert length(gsis) == 3

      # Check EmailIndex
      email_index = Enum.find(gsis, fn gsi -> gsi.name == "EmailIndex" end)
      assert email_index.partition_key == :email
      assert email_index.sort_key == nil
      assert email_index.projection == :all
      assert email_index.projected_attributes == []

      # Check TenantIndex
      tenant_index = Enum.find(gsis, fn gsi -> gsi.name == "TenantIndex" end)
      assert tenant_index.partition_key == :tenant
      assert tenant_index.sort_key == :created_at
      assert tenant_index.projection == :all
      assert tenant_index.projected_attributes == []

      # Check TenantEmailIndex
      tenant_email_index = Enum.find(gsis, fn gsi -> gsi.name == "TenantEmailIndex" end)
      assert tenant_email_index.partition_key == :tenant
      assert tenant_email_index.sort_key == :email
      assert tenant_email_index.projection == :include
      assert tenant_email_index.projected_attributes == [:uuid4, :created_at]
    end

    test "returns empty list when no GSIs defined" do
      assert TestItem.global_secondary_indexes() == []
    end
  end

  describe "GSI key generation" do
    test "generates GSI partition key correctly" do
      item = %GSITestItem{
        uuid4: "123",
        tenant: "acme",
        email: "test@example.com",
        created_at: "2023-01-01",
        status: "active"
      }

      # Test EmailIndex GSI partition key
      email_gsi_config = %{partition_key: :email, sort_key: nil}
      email_partition_key = Dynamo.Schema.generate_gsi_partition_key(item, email_gsi_config)
      assert email_partition_key == "test@example.com"

      # Test TenantIndex GSI partition key
      tenant_gsi_config = %{partition_key: :tenant, sort_key: :created_at}
      tenant_partition_key = Dynamo.Schema.generate_gsi_partition_key(item, tenant_gsi_config)
      assert tenant_partition_key == "acme"
    end

    test "generates GSI partition key with empty values" do
      item = %GSITestItem{}

      gsi_config = %{partition_key: :email, sort_key: nil}
      partition_key = Dynamo.Schema.generate_gsi_partition_key(item, gsi_config)
      assert partition_key == "empty"
    end

    test "generates GSI partition key with nil values" do
      item = %GSITestItem{email: nil}

      gsi_config = %{partition_key: :email, sort_key: nil}
      partition_key = Dynamo.Schema.generate_gsi_partition_key(item, gsi_config)
      assert partition_key == "empty"
    end

    test "generates GSI sort key correctly" do
      item = %GSITestItem{
        uuid4: "123",
        tenant: "acme",
        email: "test@example.com",
        created_at: "2023-01-01",
        status: "active"
      }

      # Test TenantIndex GSI sort key
      tenant_gsi_config = %{partition_key: :tenant, sort_key: :created_at}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, tenant_gsi_config)
      assert sort_key == "2023-01-01"

      # Test TenantEmailIndex GSI sort key
      tenant_email_gsi_config = %{partition_key: :tenant, sort_key: :email}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, tenant_email_gsi_config)
      assert sort_key == "test@example.com"
    end

    test "generates GSI sort key with empty values" do
      item = %GSITestItem{}

      gsi_config = %{partition_key: :tenant, sort_key: :created_at}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, gsi_config)
      assert sort_key == "empty"
    end

    test "generates GSI sort key with nil values" do
      item = %GSITestItem{created_at: nil}

      gsi_config = %{partition_key: :tenant, sort_key: :created_at}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, gsi_config)
      assert sort_key == "empty"
    end

    test "returns nil for partition-only GSI sort key" do
      item = %GSITestItem{
        uuid4: "123",
        tenant: "acme",
        email: "test@example.com",
        created_at: "2023-01-01",
        status: "active"
      }

      # Test EmailIndex GSI (partition-only)
      email_gsi_config = %{partition_key: :email, sort_key: nil}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, email_gsi_config)
      assert sort_key == nil
    end

    test "respects prefix_sort_key configuration for GSI sort keys" do
      item = %GSITestItemWithPrefix{
        uuid4: "123",
        tenant: "acme",
        created_at: "2023-01-01"
      }

      gsi_config = %{partition_key: :tenant, sort_key: :created_at}
      sort_key = Dynamo.Schema.generate_gsi_sort_key(item, gsi_config)
      assert sort_key == "2023-01-01"
    end
  end

  describe "GSI validation" do
    test "raises error when partition_key option is missing" do
      assert_raise RuntimeError, ~r/requires :partition_key option/, fn ->
        defmodule MissingPartitionKeyGSI do
          use Dynamo.Schema

          item do
            field(:id, partition_key: true)
            field(:email)

            global_secondary_index("EmailIndex", sort_key: :email)
          end
        end
      end
    end

    test "raises error when partition_key field does not exist" do
      assert_raise RuntimeError,
                   ~r/partition_key field ':nonexistent' does not exist in schema/,
                   fn ->
                     defmodule InvalidPartitionKeyGSI do
                       use Dynamo.Schema

                       item do
                         field(:id, partition_key: true)
                         field(:email)

                         global_secondary_index("EmailIndex", partition_key: :nonexistent)
                       end
                     end
                   end
    end

    test "raises error when sort_key field does not exist" do
      assert_raise RuntimeError, ~r/sort_key field ':nonexistent' does not exist in schema/, fn ->
        defmodule InvalidSortKeyGSI do
          use Dynamo.Schema

          item do
            field(:id, partition_key: true)
            field(:email)

            global_secondary_index("EmailIndex", partition_key: :email, sort_key: :nonexistent)
          end
        end
      end
    end

    test "raises error when projected_attributes contain non-existent fields" do
      assert_raise RuntimeError,
                   ~r/projected_attributes contain non-existent fields: nonexistent/,
                   fn ->
                     defmodule InvalidProjectedAttributesGSI do
                       use Dynamo.Schema

                       item do
                         field(:id, partition_key: true)
                         field(:email)
                         field(:name)

                         global_secondary_index("EmailIndex",
                           partition_key: :email,
                           projection: :include,
                           projected_attributes: [:name, :nonexistent]
                         )
                       end
                     end
                   end
    end

    test "allows valid GSI with all options" do
      defmodule ValidGSI do
        use Dynamo.Schema

        item do
          field(:id, partition_key: true)
          field(:email)
          field(:name)
          field(:created_at, sort_key: true)

          global_secondary_index("EmailIndex",
            partition_key: :email,
            sort_key: :created_at,
            projection: :include,
            projected_attributes: [:name]
          )
        end
      end

      gsis = ValidGSI.global_secondary_indexes()
      assert length(gsis) == 1

      gsi = List.first(gsis)
      assert gsi.name == "EmailIndex"
      assert gsi.partition_key == :email
      assert gsi.sort_key == :created_at
      assert gsi.projection == :include
      assert gsi.projected_attributes == [:name]
    end
  end

  describe "GSI configuration lookup" do
    test "get_gsi_config/2 returns GSI configuration when found" do
      item = %GSITestItem{}

      {:ok, gsi_config} = Dynamo.Schema.get_gsi_config(item, "EmailIndex")
      assert gsi_config.name == "EmailIndex"
      assert gsi_config.partition_key == :email
      assert gsi_config.sort_key == nil
      assert gsi_config.projection == :all
      assert gsi_config.projected_attributes == []
    end

    test "get_gsi_config/2 returns error when GSI not found" do
      item = %GSITestItem{}

      {:error, error} = Dynamo.Schema.get_gsi_config(item, "NonExistentIndex")
      assert error.type == :validation_error

      assert error.message ==
               "GSI 'NonExistentIndex' not found. Available indexes: EmailIndex, TenantEmailIndex, TenantIndex"
    end

    test "get_gsi_config/2 returns error with 'none' when no GSIs defined" do
      item = %TestItem{}

      {:error, error} = Dynamo.Schema.get_gsi_config(item, "AnyIndex")
      assert error.type == :validation_error
      assert error.message == "GSI 'AnyIndex' not found. Available indexes: none"
    end

    test "get_gsi_config/2 finds correct GSI among multiple" do
      item = %GSITestItem{}

      {:ok, tenant_gsi} = Dynamo.Schema.get_gsi_config(item, "TenantIndex")
      assert tenant_gsi.name == "TenantIndex"
      assert tenant_gsi.partition_key == :tenant
      assert tenant_gsi.sort_key == :created_at

      {:ok, tenant_email_gsi} = Dynamo.Schema.get_gsi_config(item, "TenantEmailIndex")
      assert tenant_email_gsi.name == "TenantEmailIndex"
      assert tenant_email_gsi.partition_key == :tenant
      assert tenant_email_gsi.sort_key == :email
      assert tenant_email_gsi.projection == :include
      assert tenant_email_gsi.projected_attributes == [:uuid4, :created_at]
    end
  end

  describe "GSI partition key validation" do
    test "validate_gsi_partition_key_populated/2 returns :ok when field is populated" do
      item = %GSITestItem{email: "test@example.com"}
      gsi_config = %{name: "EmailIndex", partition_key: :email}

      assert Dynamo.Schema.validate_gsi_partition_key_populated(item, gsi_config) == :ok
    end

    test "validate_gsi_partition_key_populated/2 returns error when field is nil" do
      item = %GSITestItem{email: nil}
      gsi_config = %{name: "EmailIndex", partition_key: :email}

      {:error, error} = Dynamo.Schema.validate_gsi_partition_key_populated(item, gsi_config)
      assert error.type == :validation_error
      assert error.message == "GSI 'EmailIndex' requires field 'email' to be populated"
    end

    test "validate_gsi_partition_key_populated/2 returns error when field is not set" do
      item = %GSITestItem{}
      gsi_config = %{name: "EmailIndex", partition_key: :email}

      {:error, error} = Dynamo.Schema.validate_gsi_partition_key_populated(item, gsi_config)
      assert error.type == :validation_error
      assert error.message == "GSI 'EmailIndex' requires field 'email' to be populated"
    end
  end

  describe "GSI sort key validation" do
    test "validate_gsi_sort_key_populated/3 returns error when GSI has no sort key but sort operation requested" do
      item = %GSITestItem{}
      gsi_config = %{name: "EmailIndex", partition_key: :email, sort_key: nil}

      assert {:error, error} =
               Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, true)

      assert error.type == :validation_error

      assert error.message ==
               "GSI 'EmailIndex' does not have a sort key but sort operation was requested"
    end

    test "validate_gsi_sort_key_populated/3 returns :ok when GSI has no sort key and no sort operation requested" do
      item = %GSITestItem{}
      gsi_config = %{name: "EmailIndex", partition_key: :email, sort_key: nil}

      assert Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, false) == :ok
    end

    test "validate_gsi_sort_key_populated/3 returns :ok when sort key not required" do
      item = %GSITestItem{created_at: nil}
      gsi_config = %{name: "TenantIndex", partition_key: :tenant, sort_key: :created_at}

      assert Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, false) == :ok
    end

    test "validate_gsi_sort_key_populated/3 returns :ok when sort key is populated and required" do
      item = %GSITestItem{created_at: "2023-01-01"}
      gsi_config = %{name: "TenantIndex", partition_key: :tenant, sort_key: :created_at}

      assert Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, true) == :ok
    end

    test "validate_gsi_sort_key_populated/3 returns error when sort key is required but nil" do
      item = %GSITestItem{created_at: nil}
      gsi_config = %{name: "TenantIndex", partition_key: :tenant, sort_key: :created_at}

      {:error, error} = Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, true)
      assert error.type == :validation_error

      assert error.message ==
               "GSI 'TenantIndex' sort operation requires field 'created_at' to be populated"
    end

    test "validate_gsi_sort_key_populated/3 returns error when sort key is required but not set" do
      item = %GSITestItem{}
      gsi_config = %{name: "TenantIndex", partition_key: :tenant, sort_key: :created_at}

      {:error, error} = Dynamo.Schema.validate_gsi_sort_key_populated(item, gsi_config, true)
      assert error.type == :validation_error

      assert error.message ==
               "GSI 'TenantIndex' sort operation requires field 'created_at' to be populated"
    end
  end

  describe "GSI complete validation" do
    test "validate_gsi_config/3 returns GSI config when all validations pass" do
      item = %GSITestItem{
        email: "test@example.com",
        tenant: "acme",
        created_at: "2023-01-01"
      }

      {:ok, gsi_config} = Dynamo.Schema.validate_gsi_config(item, "TenantIndex", true)
      assert gsi_config.name == "TenantIndex"
      assert gsi_config.partition_key == :tenant
      assert gsi_config.sort_key == :created_at
    end

    test "validate_gsi_config/3 returns error when GSI not found" do
      item = %GSITestItem{email: "test@example.com"}

      {:error, error} = Dynamo.Schema.validate_gsi_config(item, "NonExistentIndex")
      assert error.type == :validation_error
      assert String.contains?(error.message, "GSI 'NonExistentIndex' not found")
    end

    test "validate_gsi_config/3 returns error when partition key not populated" do
      item = %GSITestItem{email: nil}

      {:error, error} = Dynamo.Schema.validate_gsi_config(item, "EmailIndex")
      assert error.type == :validation_error
      assert error.message == "GSI 'EmailIndex' requires field 'email' to be populated"
    end

    test "validate_gsi_config/3 returns error when sort key required but not populated" do
      item = %GSITestItem{tenant: "acme", created_at: nil}

      {:error, error} = Dynamo.Schema.validate_gsi_config(item, "TenantIndex", true)
      assert error.type == :validation_error

      assert error.message ==
               "GSI 'TenantIndex' sort operation requires field 'created_at' to be populated"
    end

    test "validate_gsi_config/3 succeeds when sort key not required even if not populated" do
      item = %GSITestItem{tenant: "acme", created_at: nil}

      {:ok, gsi_config} = Dynamo.Schema.validate_gsi_config(item, "TenantIndex", false)
      assert gsi_config.name == "TenantIndex"
    end

    test "validate_gsi_config/3 defaults requires_sort_key to false" do
      item = %GSITestItem{tenant: "acme", created_at: nil}

      {:ok, gsi_config} = Dynamo.Schema.validate_gsi_config(item, "TenantIndex")
      assert gsi_config.name == "TenantIndex"
    end
  end
end
