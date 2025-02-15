# DynamoDB Ecto-like DSL

This project provides an Ecto-like DSL for working with DynamoDB in Elixir. It allows you to define schemas, encode and decode structs, and perform various operations on DynamoDB items with ease.

## Installation

It is *not yet* available in Hex, the package can be installed by adding dynamo github repo to your list of dependencies in mix.exs:

```elixir 
def deps do
  [
    {:dynamo, github: "bmalum/dynamo"}
  ]
end
```

Documentation can be generated with ExDoc.

## Why Use a Strong Contract with DynamoDB?

DynamoDB is a schema-free database, which provides flexibility but can lead to inconsistencies and errors if not managed properly. By using Dynamo, you can enforce a strong contract between your code and the database, ensuring that data is stored and retrieved in a consistent and predictable manner. This helps prevent common issues such as missing fields, incorrect data types, and invalid keys.

## Usage

### Defining a Schema

```elixir
defmodule Dynamo.User do
  use Dynamo.Schema, key_seperator: "_"

  item do
    field(:uuid4)
    field(:tenant, default: "open_source_user")
    field(:first_name)
    field(:email, sort_key: true, default: "hello@example.com")
    partition_key [:uuid4]

    table_name "test_table"
  end

end
```

### Encoding and Decoding

```elixir
iex>  %Dynamo.User{} |> Dynamo.Encoder.encode_root
%{
  "email" => %{"S" => "001"},
  "first_name" => %{"NULL" => true},
  "tenant" => %{"S" => "yolo"},
  "uuid4" => %{"S" => "Nomnomnom"}
}

iex> Dynamo.Decoder.decode(x)
%{
  "email" => "001",
  "first_name" => nil,
  "tenant" => "yolo",
  "uuid4" => "Nomnomnom"
}

iex> Dynamo.Decoder.decode(x, as: Dynamo.User)
%Dynamo.User{email: "001", first_name: nil, tenant: "yolo", uuid4: "Nomnomnom"}
```

### Performing Operations

```elixir
# Put an item
Dynamo.User.put_item(user)

# Get item
user = Dynamo.User.get_item(
  %Dynamo.User{
    uuid4: "no-uuid",
    email: "hello@example.com"
    }
  )

# List items
users = Dynamo.User.list_items(
    %Dynamo.User{
    uuid4: "no-uuid",
    email: "hello"
    },
    [sort_key: "hello", sk_operator: :begins_with, scan_index_forward: false]
)
 
```

### Overridable `before_write` Function

You can override the `before_write` function to add custom logic before writing items to DynamoDB. For example, you might want to add a timestamp or perform some validation:

```elixir
defmodule Dynamo.Sensor do
  use Dynamo.Schema

  schema "users" do
    partition_key :id
    sort_key :timestamp

    field :id
    field :name
    field :value
    field :timestamp
  end

  @override
    def before_write(arg) do
      arg
        |> Map.put(item, :value, 0)
        |> Dynamo.Schema.generate_and_add_partition_key()
        |> Dynamo.Schema.generate_and_add_sort_key()
    end
  end
```

## Features

- DSL for defining DynamoDB items similar to Ecto schemas
- Partition key and sort key generation
- Encoding structs into DynamoDB schema
- Decoding DynamoDB marshalled items into structs
- General DynamoDB query builder
- Basic operations: `put_item`, `list_items`, `query`
- Configurable composite key separator
- Configurable suffix for partition keys
- Configurable prefix for sort keys (if using single key)
- Overridable `before_write` function for custom logic before writing items


TODO:
- [x] DSL for DDB Items like Ecto
- [x] Partition Key Generation
- [x] Sort Key Generation
- [x] Encode Structs into DDB Schema
- [x] Decode DDB marshalled items into Struct
- [x] general DDB query builder
- [x] put_item
- [x] list_items
- [x] query
- [x] Condig seperator for composit keys
- [x] Config for suffix on partition_key
- [x] Config for prefix on sort_key (if single key)
- [ ] Config key names (default, :pk, :sk)
- [ ] batch_write item
- [ ] parallel scan
