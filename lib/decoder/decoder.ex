defmodule Dynamo.Decoder do
  @moduledoc """
  Decodes a Dynamo response into a struct.

  If Dynamo.Decodable is implemented for the struct, it will be called
  after the completion of the coercion.

  This is important for handling nested maps if you wanted the nested maps
  to have atom keys.
  """

  alias Dynamo.Decodable

  @doc """
  Decodes a DynamoDB item into a struct of the specified type.

  This function first decodes the DynamoDB-formatted item into a regular Elixir map,
  then converts it to the specified struct type, and finally applies any custom
  decoding logic defined by the struct's implementation of the Decodable protocol.

  ## Parameters
    * `item` - The DynamoDB item to decode
    * `struct_module` - The struct module to decode into

  ## Returns
    * An instance of the specified struct with values from the DynamoDB item

  ## Examples
      iex> Dynamo.Decoder.decode(dynamo_item, as: User)
      %User{id: "123", name: "John", email: "john@example.com"}
  """
  def decode(item, as: struct_module) do
    item
    |> decode
    |> binary_map_to_struct(struct_module)
    |> Decodable.decode()
  end

  @doc """
  Convert Dynamo format to Elixir

  Functions which convert the Dynamo-style values into normal Elixir values.
  Use these if you just want the Dynamo result to look more like Elixir without
  coercing it into a particular struct.
  """
  def decode(%{"BOOL" => true}), do: true
  def decode(%{"BOOL" => false}), do: false
  def decode(%{"BOOL" => "true"}), do: true
  def decode(%{"BOOL" => "false"}), do: false
  def decode(%{"NULL" => true}), do: nil
  def decode(%{"NULL" => "true"}), do: nil
  def decode(%{"B" => value}), do: Base.decode64!(value)
  def decode(%{"S" => value}), do: value
  def decode(%{"M" => value}), do: value |> decode

  def decode(%{"BS" => values}), do: MapSet.new(values)
  def decode(%{"SS" => values}), do: MapSet.new(values)

  def decode(%{"NS" => values}) do
    values
    |> Stream.map(&binary_to_number/1)
    |> Enum.into(MapSet.new())
  end

  def decode(%{"L" => values}) do
    Enum.map(values, &decode/1)
  end

  def decode(%{"N" => value}) when is_binary(value), do: binary_to_number(value)
  def decode(%{"N" => value}) when value |> is_integer or value |> is_float, do: value

  def decode(%{} = item) do
    item
    |> Enum.reduce(%{}, fn {k, v}, map ->
      Map.put(map, k, decode(v))
    end)
  end

  @doc "Attempts to convert a number to a float, and then an integer"
  def binary_to_number(binary) when is_binary(binary) do
    String.to_float(binary)
  rescue
    ArgumentError -> String.to_integer(binary)
  end

  def binary_to_number(binary), do: binary

  @doc "Converts a map with binary keys to the specified struct"
  def binary_map_to_struct(bmap, module) do
    module.__struct__()
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {k, v}, map ->
      Map.put(map, k, Map.get(bmap, Atom.to_string(k), v))
    end)
    |> Map.put(:__struct__, module)
  end
end
