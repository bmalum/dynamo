defmodule Dynamo.User do
  use Dynamo.Schema, key_seperator: "_"

  item do
    field(:uuid4, default: "Nomnomnom")
    field(:tenant, default: "yolo")
    field(:first_name)
    field(:email, sort_key: true, default: "001")
    partition_key [:uuid4]

    table_name "test_table"
  end

end
