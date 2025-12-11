# Using Dynamo with Phoenix Contexts

This guide shows how to integrate Dynamo schemas with Phoenix contexts for building scalable web applications backed by DynamoDB.

## Table of Contents

- [Why Phoenix Contexts with DynamoDB?](#why-phoenix-contexts-with-dynamodb)
- [Basic Setup](#basic-setup)
- [Context Patterns](#context-patterns)
- [Real-World Examples](#real-world-examples)
- [Testing Strategies](#testing-strategies)
- [Best Practices](#best-practices)

## Why Phoenix Contexts with DynamoDB?

Phoenix contexts provide a clean boundary between your web layer and data layer. Combined with DynamoDB's scalability, you get:

- **Clear separation of concerns**: Web logic separate from data access
- **Testable business logic**: Mock contexts easily in tests
- **Scalable data layer**: DynamoDB handles millions of requests
- **Flexible schemas**: NoSQL flexibility with Elixir structure

## Basic Setup

### 1. Define Your Schema

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Dynamo.Schema

  item do
    table_name "users"
    
    field :id, partition_key: true
    field :email, sort_key: true
    field :name
    field :password_hash
    field :role, default: "user"
    field :inserted_at
    field :updated_at
    
    # GSI for email lookups
    global_secondary_index "EmailIndex", partition_key: :email
  end
end
```

### 2. Create Your Context

```elixir
# lib/my_app/accounts.ex
defmodule MyApp.Accounts do
  @moduledoc """
  The Accounts context.
  """
  
  alias MyApp.Accounts.User
  
  @doc """
  Returns the list of users.
  """
  def list_users do
    case Dynamo.Table.Stream.scan(User) do
      stream -> {:ok, Enum.to_list(stream)}
    end
  end
  
  @doc """
  Gets a single user by ID and email.
  """
  def get_user(id, email) do
    User.get_item(%User{id: id, email: email})
  end
  
  @doc """
  Gets a user by email using GSI.
  """
  def get_user_by_email(email) do
    case User.list_items(%User{email: email}, index_name: "EmailIndex") do
      {:ok, [user | _]} -> {:ok, user}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end
  
  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    
    user = %User{
      id: generate_id(),
      email: attrs[:email],
      name: attrs[:name],
      password_hash: hash_password(attrs[:password]),
      role: attrs[:role] || "user",
      inserted_at: now,
      updated_at: now
    }
    
    case User.put_item(user) do
      {:ok, saved_user} -> {:ok, saved_user}
      error -> error
    end
  end
  
  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    updated_user = %{user |
      name: attrs[:name] || user.name,
      role: attrs[:role] || user.role,
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    User.put_item(updated_user)
  end
  
  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    User.delete_item(user)
  end
  
  @doc """
  Changes a user password.
  """
  def change_password(%User{} = user, current_password, new_password) do
    if verify_password(current_password, user.password_hash) do
      updated_user = %{user |
        password_hash: hash_password(new_password),
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      User.put_item(updated_user)
    else
      {:error, :invalid_password}
    end
  end
  
  # Private functions
  
  defp generate_id do
    "user_" <> (:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false))
  end
  
  defp hash_password(password) do
    # Use Bcrypt or Argon2 in production
    :crypto.hash(:sha256, password) |> Base.encode64()
  end
  
  defp verify_password(password, hash) do
    hash_password(password) == hash
  end
end
```

## Context Patterns

### Pattern 1: Multi-Tenant Context

```elixir
# lib/my_app/organizations.ex
defmodule MyApp.Organizations do
  alias MyApp.Organizations.{Organization, Member}
  
  @doc """
  Lists all members of an organization.
  """
  def list_members(org_id) do
    Member.list_items(%Member{org_id: org_id})
  end
  
  @doc """
  Adds a member to an organization.
  """
  def add_member(org_id, user_id, role \\ "member") do
    member = %Member{
      org_id: org_id,
      user_id: user_id,
      role: role,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Member.put_item(member)
  end
  
  @doc """
  Removes a member from an organization.
  """
  def remove_member(org_id, user_id) do
    Member.delete_item(%Member{org_id: org_id, user_id: user_id})
  end
  
  @doc """
  Checks if a user is a member of an organization.
  """
  def member?(org_id, user_id) do
    case Member.get_item(%Member{org_id: org_id, user_id: user_id}) do
      {:ok, _member} -> true
      {:error, _} -> false
    end
  end
end

# Schema
defmodule MyApp.Organizations.Member do
  use Dynamo.Schema
  
  item do
    table_name "org_members"
    
    field :org_id, partition_key: true
    field :user_id, sort_key: true
    field :role
    field :joined_at
  end
end
```

### Pattern 2: Hierarchical Data Context

```elixir
# lib/my_app/content.ex
defmodule MyApp.Content do
  alias MyApp.Content.{Post, Comment}
  
  @doc """
  Lists all posts by a user.
  """
  def list_user_posts(user_id) do
    Post.list_items(%Post{user_id: user_id})
  end
  
  @doc """
  Gets a post with its comments.
  """
  def get_post_with_comments(user_id, post_id) do
    with {:ok, post} <- Post.get_item(%Post{user_id: user_id, post_id: post_id}),
         {:ok, comments} <- list_post_comments(user_id, post_id) do
      {:ok, Map.put(post, :comments, comments)}
    end
  end
  
  @doc """
  Lists comments for a post.
  """
  def list_post_comments(user_id, post_id) do
    # Using begins_with to get all comments for a post
    Comment.list_items(
      %Comment{user_id: user_id, sk: "COMMENT##{post_id}"},
      sk_operator: :begins_with
    )
  end
  
  @doc """
  Creates a comment on a post.
  """
  def create_comment(user_id, post_id, attrs) do
    comment = %Comment{
      user_id: user_id,
      post_id: post_id,
      comment_id: generate_id(),
      content: attrs[:content],
      author_id: attrs[:author_id],
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Comment.put_item(comment)
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end

# Schemas using single-table design
defmodule MyApp.Content.Post do
  use Dynamo.Schema
  
  item do
    table_name "content"
    
    field :user_id, partition_key: true
    field :post_id, sort_key: true
    field :title
    field :content
    field :created_at
  end
end

defmodule MyApp.Content.Comment do
  use Dynamo.Schema
  
  item do
    table_name "content"
    
    field :user_id, partition_key: true
    field :post_id
    field :comment_id
    field :content
    field :author_id
    field :created_at
    
    # SK format: COMMENT#post_id#comment_id
    sort_key [:post_id, :comment_id]
  end
end
```

### Pattern 3: Transactional Context

```elixir
# lib/my_app/billing.ex
defmodule MyApp.Billing do
  alias MyApp.Billing.{Account, Transaction}
  
  @doc """
  Transfers credits between accounts atomically.
  """
  def transfer_credits(from_account_id, to_account_id, amount) do
    Dynamo.Transaction.transact([
      # Check source has sufficient balance
      {:check, 
       %Account{id: from_account_id},
       "balance >= :amount",
       %{":amount" => %{"N" => to_string(amount)}}},
      
      # Deduct from source
      {:update, 
       %Account{id: from_account_id},
       %{balance: {:decrement, amount}}},
      
      # Add to destination
      {:update,
       %Account{id: to_account_id},
       %{balance: {:increment, amount}}},
      
      # Record transaction
      {:put,
       %Transaction{
         id: generate_transaction_id(),
         from_account: from_account_id,
         to_account: to_account_id,
         amount: amount,
         timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    ])
  end
  
  @doc """
  Gets account balance.
  """
  def get_balance(account_id) do
    case Account.get_item(%Account{id: account_id}) do
      {:ok, account} -> {:ok, account.balance}
      error -> error
    end
  end
  
  defp generate_transaction_id do
    "txn_" <> (:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false))
  end
end
```

## Real-World Examples

### Example 1: User Authentication Context

```elixir
# lib/my_app/accounts.ex
defmodule MyApp.Accounts do
  alias MyApp.Accounts.{User, Session}
  
  @doc """
  Authenticates a user by email and password.
  """
  def authenticate(email, password) do
    with {:ok, user} <- get_user_by_email(email),
         true <- verify_password(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :not_found} -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      error -> error
    end
  end
  
  @doc """
  Creates a session for a user.
  """
  def create_session(user_id) do
    session = %Session{
      id: generate_session_id(),
      user_id: user_id,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      expires_at: DateTime.utc_now() |> DateTime.add(86400) |> DateTime.to_iso8601()
    }
    
    Session.put_item(session)
  end
  
  @doc """
  Validates a session token.
  """
  def validate_session(session_id) do
    with {:ok, session} <- Session.get_item(%Session{id: session_id}),
         true <- session_valid?(session) do
      {:ok, session}
    else
      false -> {:error, :session_expired}
      error -> error
    end
  end
  
  @doc """
  Invalidates a session.
  """
  def logout(session_id) do
    Session.delete_item(%Session{id: session_id})
  end
  
  defp session_valid?(session) do
    {:ok, expires_at, _} = DateTime.from_iso8601(session.expires_at)
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
```

### Example 2: E-commerce Order Context

```elixir
# lib/my_app/orders.ex
defmodule MyApp.Orders do
  alias MyApp.Orders.{Order, OrderItem}
  
  @doc """
  Creates an order with items.
  """
  def create_order(user_id, items, attrs \\ %{}) do
    order_id = generate_order_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    
    order = %Order{
      id: order_id,
      user_id: user_id,
      status: "pending",
      total: calculate_total(items),
      shipping_address: attrs[:shipping_address],
      created_at: now,
      updated_at: now
    }
    
    order_items = Enum.map(items, fn item ->
      %OrderItem{
        order_id: order_id,
        product_id: item.product_id,
        quantity: item.quantity,
        price: item.price
      }
    end)
    
    # Batch write order and items
    with {:ok, _} <- Order.put_item(order),
         {:ok, _} <- Dynamo.Table.batch_write_item(order_items) do
      {:ok, order}
    end
  end
  
  @doc """
  Lists orders for a user.
  """
  def list_user_orders(user_id) do
    Order.list_items(
      %Order{user_id: user_id},
      scan_index_forward: false  # Newest first
    )
  end
  
  @doc """
  Updates order status.
  """
  def update_order_status(order_id, status) do
    with {:ok, order} <- Order.get_item(%Order{id: order_id}) do
      updated_order = %{order |
        status: status,
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      Order.put_item(updated_order)
    end
  end
  
  defp calculate_total(items) do
    Enum.reduce(items, 0, fn item, acc ->
      acc + (item.price * item.quantity)
    end)
  end
  
  defp generate_order_id do
    "order_" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
  end
end

# Schemas
defmodule MyApp.Orders.Order do
  use Dynamo.Schema
  
  item do
    table_name "orders"
    
    field :id, partition_key: true
    field :user_id, sort_key: true
    field :status
    field :total
    field :shipping_address
    field :created_at
    field :updated_at
    
    # GSI for user orders
    global_secondary_index "UserOrdersIndex",
      partition_key: :user_id,
      sort_key: :created_at
  end
end

defmodule MyApp.Orders.OrderItem do
  use Dynamo.Schema
  
  item do
    table_name "order_items"
    
    field :order_id, partition_key: true
    field :product_id, sort_key: true
    field :quantity
    field :price
  end
end
```

## Testing Strategies

### Unit Testing Contexts

```elixir
# test/my_app/accounts_test.exs
defmodule MyApp.AccountsTest do
  use ExUnit.Case, async: false
  
  alias MyApp.Accounts
  alias MyApp.Accounts.User
  
  setup do
    # Clean up test data
    on_exit(fn ->
      # Delete test users
    end)
    
    :ok
  end
  
  describe "create_user/1" do
    test "creates a user with valid attributes" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "secure_password"
      }
      
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.password_hash != nil
    end
    
    test "returns error with invalid attributes" do
      attrs = %{email: nil}
      
      assert {:error, _} = Accounts.create_user(attrs)
    end
  end
  
  describe "get_user_by_email/1" do
    test "returns user when email exists" do
      {:ok, user} = Accounts.create_user(%{
        email: "existing@example.com",
        name: "Existing User",
        password: "password"
      })
      
      assert {:ok, found_user} = Accounts.get_user_by_email("existing@example.com")
      assert found_user.id == user.id
    end
    
    test "returns error when email doesn't exist" do
      assert {:error, :not_found} = Accounts.get_user_by_email("nonexistent@example.com")
    end
  end
end
```

### Integration Testing with Phoenix

```elixir
# test/my_app_web/controllers/user_controller_test.exs
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase
  
  alias MyApp.Accounts
  
  describe "index" do
    test "lists all users", %{conn: conn} do
      {:ok, _user1} = Accounts.create_user(%{email: "user1@example.com", name: "User 1", password: "pass"})
      {:ok, _user2} = Accounts.create_user(%{email: "user2@example.com", name: "User 2", password: "pass"})
      
      conn = get(conn, ~p"/users")
      assert html_response(conn, 200) =~ "User 1"
      assert html_response(conn, 200) =~ "User 2"
    end
  end
  
  describe "create" do
    test "creates user with valid data", %{conn: conn} do
      conn = post(conn, ~p"/users", user: %{
        email: "new@example.com",
        name: "New User",
        password: "secure_password"
      })
      
      assert redirected_to(conn) == ~p"/users"
      assert {:ok, _user} = Accounts.get_user_by_email("new@example.com")
    end
  end
end
```

## Best Practices

### 1. Keep Contexts Focused

```elixir
# ✅ Good: Focused context
defmodule MyApp.Accounts do
  # Only user-related functions
end

defmodule MyApp.Billing do
  # Only billing-related functions
end

# ❌ Bad: God context
defmodule MyApp.Core do
  # Users, billing, orders, everything...
end
```

### 2. Use Changesets for Validation

```elixir
defmodule MyApp.Accounts do
  def create_user(attrs) do
    with {:ok, validated} <- validate_user(attrs),
         {:ok, user} <- insert_user(validated) do
      {:ok, user}
    end
  end
  
  defp validate_user(attrs) do
    required = [:email, :name, :password]
    
    case Enum.all?(required, &Map.has_key?(attrs, &1)) do
      true -> {:ok, attrs}
      false -> {:error, :missing_required_fields}
    end
  end
end
```

### 3. Handle Errors Consistently

```elixir
defmodule MyApp.Accounts do
  def get_user(id, email) do
    case User.get_item(%User{id: id, email: email}) do
      {:ok, user} -> {:ok, user}
      {:error, %Dynamo.Error{type: :resource_not_found}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end
end
```

### 4. Use Streaming for Large Datasets

```elixir
defmodule MyApp.Reports do
  def export_all_users do
    Dynamo.Table.Stream.scan(User, page_size: 500)
    |> Stream.map(&format_user_for_export/1)
    |> CSV.encode()
    |> Stream.into(File.stream!("users_export.csv"))
    |> Stream.run()
  end
end
```

### 5. Leverage GSIs for Access Patterns

```elixir
# Schema with GSI
defmodule MyApp.Accounts.User do
  use Dynamo.Schema
  
  item do
    table_name "users"
    
    field :id, partition_key: true
    field :email, sort_key: true
    field :status
    field :created_at
    
    # GSI for querying by status
    global_secondary_index "StatusIndex",
      partition_key: :status,
      sort_key: :created_at
  end
end

# Context using GSI
defmodule MyApp.Accounts do
  def list_active_users do
    User.list_items(
      %User{status: "active"},
      index_name: "StatusIndex",
      scan_index_forward: false
    )
  end
end
```

### 6. Document Your Access Patterns

```elixir
defmodule MyApp.Accounts do
  @moduledoc """
  The Accounts context.
  
  ## Access Patterns
  
  1. Get user by ID and email (primary key)
  2. Get user by email only (EmailIndex GSI)
  3. List users by status (StatusIndex GSI)
  4. List all users (scan - use sparingly)
  """
end
```

### 7. Use Transactions for Consistency

```elixir
defmodule MyApp.Accounts do
  def transfer_ownership(from_user_id, to_user_id, resource_id) do
    Dynamo.Transaction.transact([
      {:check, %Resource{id: resource_id}, "owner_id = :from", %{":from" => %{"S" => from_user_id}}},
      {:update, %Resource{id: resource_id}, %{owner_id: to_user_id}},
      {:put, %AuditLog{
        id: generate_id(),
        action: "transfer_ownership",
        resource_id: resource_id,
        from_user: from_user_id,
        to_user: to_user_id,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }}
    ])
  end
end
```

## Phoenix Controller Integration

### Example Controller

```elixir
# lib/my_app_web/controllers/user_controller.ex
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  
  alias MyApp.Accounts
  
  def index(conn, _params) do
    case Accounts.list_users() do
      {:ok, users} -> render(conn, :index, users: users)
      {:error, _} -> 
        conn
        |> put_flash(:error, "Failed to load users")
        |> redirect(to: ~p"/")
    end
  end
  
  def show(conn, %{"id" => id, "email" => email}) do
    case Accounts.get_user(id, email) do
      {:ok, user} -> render(conn, :show, user: user)
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/users")
    end
  end
  
  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created successfully")
        |> redirect(to: ~p"/users/#{user.id}")
      
      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create user: #{inspect(reason)}")
        |> render(:new, changeset: user_params)
    end
  end
  
  def update(conn, %{"id" => id, "email" => email, "user" => user_params}) do
    with {:ok, user} <- Accounts.get_user(id, email),
         {:ok, updated_user} <- Accounts.update_user(user, user_params) do
      conn
      |> put_flash(:info, "User updated successfully")
      |> redirect(to: ~p"/users/#{updated_user.id}")
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/users")
      
      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to update user: #{inspect(reason)}")
        |> redirect(to: ~p"/users/#{id}")
    end
  end
  
  def delete(conn, %{"id" => id, "email" => email}) do
    with {:ok, user} <- Accounts.get_user(id, email),
         {:ok, _} <- Accounts.delete_user(user) do
      conn
      |> put_flash(:info, "User deleted successfully")
      |> redirect(to: ~p"/users")
    else
      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to delete user")
        |> redirect(to: ~p"/users")
    end
  end
end
```

## Conclusion

Phoenix contexts with Dynamo provide a powerful combination for building scalable web applications:

- **Clean architecture**: Contexts separate business logic from web layer
- **Scalable data layer**: DynamoDB handles high throughput
- **Flexible schemas**: NoSQL flexibility with Elixir structure
- **Testable code**: Easy to test contexts independently

For more information:
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Dynamo README](../README.md)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
