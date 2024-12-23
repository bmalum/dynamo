# Dynamo

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dynamo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dynamo, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/dynamo>.

## TODO:
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
- [ ] ?? add __type__ to struct with the item name as default value
- [ ] batch_write item
- [ ] scan / parallel scan
- [ ] update readme
- [ ] release!