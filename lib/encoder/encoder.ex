defmodule Dynamo.Encoder do
  @moduledoc """
  Takes an Elixir value and converts it into a Dynamo-style map.

  ```elixir
  MapSet.new [1,2,3] |> #{__MODULE__}.encode
  #=> %{"NS" => ["1", "2", "3"]}

  MapSet.new ["A","B","C"] |> #{__MODULE__}.encode
  #=> %{"SS" => ["A", "B", "C"]}

  "bubba" |> Dynamo.Encoder.encode
  #=> %{"S" => "bubba"}
  ```

  This is handled via the Dynamo.Encodable protocol.
  """

  alias Dynamo.Encodable

  # These functions exist to ensure that encoding is idempotent.
  def encode(value), do: encode(value, [])
  def encode(%{"B" => _} = val, _), do: val
  def encode(%{"BOOL" => _} = val, _), do: val
  def encode(%{"BS" => _} = val, _), do: val
  def encode(%{"L" => _} = val, _), do: val
  def encode(%{"M" => _} = val, _), do: val
  def encode(%{"NS" => _} = val, _), do: val
  def encode(%{"NULL" => _} = val, _), do: val
  def encode(%{"N" => _} = val, _), do: val
  def encode(%{"S" => _} = val, _), do: val
  def encode(%{"SS" => _} = val, _), do: val

  def encode(value, options), do: Encodable.encode(value, options)

  @doc """
  Encodes a value that is already in Dynamo format.

  This is a specialized function that you should rarely need to use. If you find yourself
  needing this function, please open an issue so we can better understand your use case.

  ## Parameters
    * `value` - The value to encode
    * `options` - Optional encoding options

  ## Returns
    * The encoded value
  """
  def encode!(value, options \\ []) do
    Encodable.encode(value, options)
  end

  @doc """
  Encodes a value and extracts the inner content from the resulting map.

  This function is particularly useful when encoding structs for DynamoDB operations,
  as it removes the outer wrapper and returns just the map of attributes.

  ## Parameters
    * `value` - The value to encode
    * `options` - Optional encoding options

  ## Returns
    * The encoded value with the outer wrapper removed

  ## Examples
      iex> Dynamo.Encoder.encode_root(%User{id: "123", name: "John"})
      %{"id" => %{"S" => "123"}, "name" => %{"S" => "John"}}
  """
  def encode_root(value, options \\ []) do
    case Encodable.encode(value, options) do
      %{"M" => value} -> value
      %{"L" => value} -> value
    end
  end

  @doc """
  Converts an Elixir type atom to the corresponding DynamoDB type string.

  This function maps Elixir type atoms to the string representation used by DynamoDB.

  ## Parameters
    * `atom` - The atom representing an Elixir type

  ## Returns
    * String representing the DynamoDB type

  ## Examples
      iex> Dynamo.Encoder.atom_to_dynamo_type(:string)
      "S"

      iex> Dynamo.Encoder.atom_to_dynamo_type(:number)
      "N"
  """
  def atom_to_dynamo_type(:blob), do: "B"
  def atom_to_dynamo_type(:boolean), do: "BOOL"
  def atom_to_dynamo_type(:blob_set), do: "BS"
  def atom_to_dynamo_type(:list), do: "L"
  def atom_to_dynamo_type(:map), do: "M"
  def atom_to_dynamo_type(:number_set), do: "NS"
  def atom_to_dynamo_type(:null), do: "NULL"
  def atom_to_dynamo_type(:number), do: "N"
  def atom_to_dynamo_type(:string), do: "S"
  def atom_to_dynamo_type(:string_set), do: "SS"

  def atom_to_dynamo_type(value) do
    raise ArgumentError, "Unknown dynamo type for value: #{inspect(value)}"
  end
end
