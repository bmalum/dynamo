defmodule Dynamo.Helper do
  @moduledoc """
  Helper functions for working with DynamoDB items.

  This module provides utility functions for common operations when working with
  DynamoDB responses, such as decoding items from various response formats.
  """

  @doc """
  Decodes DynamoDB items from various response formats.

  This function handles different DynamoDB response structures and decodes the items
  contained within them. It can process:
  - Single items
  - Lists of items
  - Response maps with an "Item" key
  - Response maps with an "Items" key

  ## Parameters
    * `item` - The DynamoDB item or response to decode
    * `opts` - Options to pass to the decoder (default: [])
      * `:as` - The struct module to decode into

  ## Returns
    * The decoded item(s) in the specified format

  ## Examples

      # Decode a single item
      Dynamo.Helper.decode_item(dynamo_item, as: MyApp.User)
      #=> %MyApp.User{...}

      # Decode a list of items
      Dynamo.Helper.decode_item([item1, item2], as: MyApp.User)
      #=> [%MyApp.User{...}, %MyApp.User{...}]

      # Decode a GetItem response
      Dynamo.Helper.decode_item(%{"Item" => item}, as: MyApp.User)
      #=> %MyApp.User{...}

      # Decode a Query/Scan response
      Dynamo.Helper.decode_item(%{"Items" => [item1, item2]}, as: MyApp.User)
      #=> [%MyApp.User{...}, %MyApp.User{...}]
  """
  @spec decode_item(map() | list() | any(), keyword()) :: any()
  def decode_item(item, opts \\ [])

  @spec decode_item(list(), keyword()) :: list()
  def decode_item(items, opts) when is_list(items) do
    for item <- items, do: decode_item(item, opts)
  end

  @spec decode_item(%{String.t() => list()}, keyword()) :: list()
  def decode_item(%{"Items" => items}, opts) do
    for item <- items, do: decode_item(item, opts)
  end

  @spec decode_item(%{String.t() => map()}, keyword()) :: any()
  def decode_item(%{"Item" => item}, opts) do
    decode_item(item, opts)
  end

  @spec decode_item(map(), keyword()) :: any()
  def decode_item(item, opts) do
    Dynamo.Decoder.decode(item, opts)
  end
end
