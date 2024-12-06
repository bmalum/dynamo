defmodule Dynamo.User do
  use Dynamo.Schema

  item do
    field(:uuid4, default: "Nomnomnom")
    field(:tenant, default: "yolo")
    field(:first_name)
    field(:email, sort_key: true, default: "001")
    partition_key [:uuid4]

    table_name "test_table"
  end
end


defmodule Lagerphant.Space do
  use Dynamo.Schema
  alias Lagerphant.Space

  item do
    field :location, sort_key: true
    field :segment, sort_key: true
    field :tenant, partition_key: true
    table_name "lagerphant_dev"
  end

  def save_space(%Space{} = space) do
    Dynamo.Table.insert(space)
  end

  def list_spaces(tenant, options \\ []) do
   # options = Keyword.merge(options, [table_name: "lagerphant_dev"])
    Dynamo.Table.list_items(%Space{tenant: tenant}, options)
  end
end
