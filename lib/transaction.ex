defmodule Dynamo.Transaction do
  @moduledoc """
  Support for DynamoDB transactions.

  This module provides functions for performing atomic transactions in DynamoDB.
  Transactions allow you to group multiple operations (put, update, delete, check)
  and execute them as a single atomic unit, where either all operations succeed
  or none of them do.

  ## Examples

      # Perform a transaction with multiple operations
      Dynamo.Transaction.transact([
        {:put, %User{id: "user1", name: "John Doe", active: true}},
        {:update, %Order{id: "order123", user_id: "user1"}, %{status: "processing"}},
        {:delete, %Cart{id: "cart456", user_id: "user1"}},
        {:check, %Inventory{id: "item789"}, "quantity >= :min", %{":min" => %{"N" => "5"}}}
      ])
  """

  @doc """
  Executes a transaction consisting of multiple DynamoDB operations.

  This function takes a list of transaction items and executes them as a single
  atomic transaction. Each transaction item is a tuple specifying the operation type
  and its parameters.

  ## Transaction Item Types

    * `{:put, item, condition_expression, expression_attrs}` - Put an item with optional condition
    * `{:put, item}` - Put an item without conditions
    * `{:update, key_item, updates, condition_expression, expression_attrs}` - Update an item with optional condition
    * `{:update, key_item, updates}` - Update an item without conditions
    * `{:delete, key_item, condition_expression, expression_attrs}` - Delete an item with optional condition
    * `{:delete, key_item}` - Delete an item without conditions
    * `{:check, key_item, condition_expression, expression_attrs}` - Check an item meets a condition

  ## Parameters
    * `transactions` - List of transaction items to execute
    * `opts` - Additional options:
      * `:client` - Custom AWS client to use (default: `Dynamo.AWS.client()`)
      * `:return_consumed_capacity` - Option for returning consumed capacity

  ## Returns
    * `{:ok, result}` - Transaction successful, with result containing information about the transaction
    * `{:error, reason}` - Transaction failed

  ## Examples

      # Transfer money between accounts
      Dynamo.Transaction.transact([
        # Check that source account exists and has sufficient funds
        {:check, %Account{id: source_id},
          "amount >= :amount",
          %{":amount" => %{"N" => "100.00"}}},

        # Decrease source account balance
        {:update, %Account{id: source_id},
          %{amount: {:decrement, 100.00}}},

        # Increase destination account balance
        {:update, %Account{id: dest_id},
          %{amount: {:increment, 100.00}}}
      ])

      # Create a user and their initial profile atomically
      Dynamo.Transaction.transact([
        {:put, %User{id: "user123", email: "user@example.com", name: "New User"},
          "attribute_not_exists(id)", nil}, # Ensure user doesn't already exist

        {:put, %Profile{user_id: "user123", status: "new", created_at: DateTime.utc_now()}}
      ])
  """
  @spec transact(list(), keyword()) :: {:ok, any()} | {:error, Dynamo.Error.t()}
  def transact(transactions, opts \\ []) do
    client = opts[:client] || Dynamo.AWS.client()

    # Build the TransactItems list from the transaction operations
    transact_items = Enum.map(transactions, &build_transaction_item/1)

    # Prepare the request
    request = %{
      "TransactItems" => transact_items
    }

    # Add optional return consumed capacity
    request = if opts[:return_consumed_capacity] do
      Map.put(request, "ReturnConsumedCapacity", format_return_consumed_capacity(opts[:return_consumed_capacity]))
    else
      request
    end

    # Execute the transaction
    case Dynamo.DynamoDB.transact_write_items(client, request) do
      {:ok, response, _} ->
        {:ok, response}

      error ->
        Dynamo.ErrorHandler.handle_result(error)
    end
  end

  defp format_return_consumed_capacity(:none), do: "NONE"
  defp format_return_consumed_capacity(:total), do: "TOTAL"
  defp format_return_consumed_capacity(:indexes), do: "INDEXES"
  defp format_return_consumed_capacity(value) when is_binary(value), do: value
  defp format_return_consumed_capacity(_), do: "NONE"

  # Build a transaction item based on the operation type
  defp build_transaction_item({:put, item, condition_expression, expression_attrs}) do
    # Prepare the item for writing
    encoded_item = item.__struct__.before_write(item)

    put_request = %{
      "TableName" => item.__struct__.table_name(),
      "Item" => encoded_item
    }

    # Add condition expression if provided
    put_request = if condition_expression do
      put_request
      |> Map.put("ConditionExpression", condition_expression)
    else
      put_request
    end

    # Add expression attributes if provided
    put_request = if expression_attrs do
      put_request
      |> add_expression_attributes(expression_attrs)
    else
      put_request
    end

    %{"Put" => put_request}
  end

  defp build_transaction_item({:put, item}) do
    build_transaction_item({:put, item, nil, nil})
  end

  defp build_transaction_item({:update, key_item, updates, condition_expression, expression_attrs}) do
    # Generate the key for the item
    pk = Dynamo.Schema.generate_partition_key(key_item)
    sk = Dynamo.Schema.generate_sort_key(key_item)
    config = key_item.__struct__.settings()

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    # Build the key
    key = %{
      partition_key_name => %{"S" => pk}
    }

    # Add sort key if present
    key = if sk != nil, do: Map.put(key, sort_key_name, %{"S" => sk}), else: key

    # Build update expression and attributes
    {update_expression, expr_attr_names, expr_attr_values} = build_update_expression(updates)

    # Prepare the update request
    update_request = %{
      "TableName" => key_item.__struct__.table_name(),
      "Key" => key,
      "UpdateExpression" => update_expression
    }

    # Add condition expression if provided
    update_request = if condition_expression do
      update_request
      |> Map.put("ConditionExpression", condition_expression)
    else
      update_request
    end

    # Add expression attribute names if any
    update_request = if map_size(expr_attr_names) > 0 do
      update_request
      |> Map.put("ExpressionAttributeNames", expr_attr_names)
    else
      update_request
    end

    # Add expression attribute values if any
    update_request = if map_size(expr_attr_values) > 0 do
      update_request
      |> Map.put("ExpressionAttributeValues", expr_attr_values)
    else
      update_request
    end

    # Merge additional expression attributes if provided
    update_request = if expression_attrs do
      update_request
      |> add_expression_attributes(expression_attrs)
    else
      update_request
    end

    %{"Update" => update_request}
  end

  defp build_transaction_item({:update, key_item, updates}) do
    build_transaction_item({:update, key_item, updates, nil, nil})
  end

  defp build_transaction_item({:delete, key_item, condition_expression, expression_attrs}) do
    # Generate the key for the item
    pk = Dynamo.Schema.generate_partition_key(key_item)
    sk = Dynamo.Schema.generate_sort_key(key_item)
    config = key_item.__struct__.settings()

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    # Build the key
    key = %{
      partition_key_name => %{"S" => pk}
    }

    # Add sort key if present
    key = if sk != nil, do: Map.put(key, sort_key_name, %{"S" => sk}), else: key

    # Prepare the delete request
    delete_request = %{
      "TableName" => key_item.__struct__.table_name(),
      "Key" => key
    }

    # Add condition expression if provided
    delete_request = if condition_expression do
      delete_request
      |> Map.put("ConditionExpression", condition_expression)
    else
      delete_request
    end

    # Add expression attributes if provided
    delete_request = if expression_attrs do
      delete_request
      |> add_expression_attributes(expression_attrs)
    else
      delete_request
    end

    %{"Delete" => delete_request}
  end

  defp build_transaction_item({:delete, key_item}) do
    build_transaction_item({:delete, key_item, nil, nil})
  end

  defp build_transaction_item({:check, key_item, condition_expression, expression_attrs}) do
    # Generate the key for the item
    pk = Dynamo.Schema.generate_partition_key(key_item)
    sk = Dynamo.Schema.generate_sort_key(key_item)
    config = key_item.__struct__.settings()

    partition_key_name = config[:partition_key_name]
    sort_key_name = config[:sort_key_name]

    # Build the key
    key = %{
      partition_key_name => %{"S" => pk}
    }

    # Add sort key if present
    key = if sk != nil, do: Map.put(key, sort_key_name, %{"S" => sk}), else: key

    # Prepare the condition check
    check_request = %{
      "TableName" => key_item.__struct__.table_name(),
      "Key" => key,
      "ConditionExpression" => condition_expression
    }

    # Add expression attributes if provided
    check_request = if expression_attrs do
      check_request
      |> add_expression_attributes(expression_attrs)
    else
      check_request
    end

    %{"ConditionCheck" => check_request}
  end

  # Add both expression attribute names and values to a request
  defp add_expression_attributes(request, attrs) do
    request = if Map.has_key?(attrs, :expression_attribute_names) do
      existing = Map.get(request, "ExpressionAttributeNames", %{})
      updated = Map.merge(existing, attrs.expression_attribute_names)
      Map.put(request, "ExpressionAttributeNames", updated)
    else
      request
    end

    if Map.has_key?(attrs, :expression_attribute_values) do
      existing = Map.get(request, "ExpressionAttributeValues", %{})
      updated = Map.merge(existing, attrs.expression_attribute_values)
      Map.put(request, "ExpressionAttributeValues", updated)
    else
      request
    end
  end

  # Build the update expression, similar to Dynamo.Table.build_update_expression but with support for special operators
  defp build_update_expression(updates) when is_map(updates) do
    # Initialize accumulators for different update actions
    {set_expressions, names, values} = Enum.reduce(updates, {[], %{}, %{}}, fn {key, value}, {set_exprs, names_acc, values_acc} ->
      # Generate placeholders for this key
      attr_name = "#attr_#{key}"
      attr_value = ":val_#{key}"

      # Handle special update operations
      {expr, val} = case value do
        {:increment, amount} ->
          {"#{attr_name} + #{attr_value}", encode_number(amount)}

        {:decrement, amount} ->
          {"#{attr_name} - #{attr_value}", encode_number(amount)}

        {:append, list} ->
          {"list_append(#{attr_name}, #{attr_value})", Dynamo.Encoder.encode(list)}

        {:prepend, list} ->
          {"list_append(#{attr_value}, #{attr_name})", Dynamo.Encoder.encode(list)}

        {:if_not_exists, default_value} ->
          {"if_not_exists(#{attr_name}, #{attr_value})", Dynamo.Encoder.encode(default_value)}

        # Normal value assignment
        _ ->
          {"#{attr_name} = #{attr_value}", Dynamo.Encoder.encode(value)}
      end

      # Add to expression and accumulators
      {
        [expr | set_exprs],
        Map.put(names_acc, attr_name, to_string(key)),
        Map.put(values_acc, attr_value, val)
      }
    end)

    # Build the final expression
    update_expression =
      case set_expressions do
        [] -> ""
        _ -> "SET " <> Enum.join(set_expressions, ", ")
      end

    {update_expression, names, values}
  end

  # Helper function to encode numbers for DynamoDB
  defp encode_number(num) when is_integer(num), do: %{"N" => Integer.to_string(num)}
  defp encode_number(num) when is_float(num), do: %{"N" => Float.to_string(num)}
end
