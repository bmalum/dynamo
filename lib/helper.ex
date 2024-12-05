defmodule Dynamo.Helper do
  def decode_item(item, opts \\ [])

  def decode_item(items, opts) when is_list(items) do
    for item <- items, do: decode_item(item, opts)
  end
  def decode_item(%{"Items" => items}, opts) do
    for item <- items, do: decode_item(item, opts)
  end

  def decode_item(%{"Item" => item}, opts) do
    decode_item(item, opts)
  end

  def decode_item(item, opts) do
    Dynamo.Decoder.decode(item, opts)
  end
end
