# User/Post Example with Belongs To Collections

This example demonstrates how the enhanced `list_items` function automatically handles `belongs_to` relationships.

## Schema Definition

```elixir
defmodule User do
  use Dynamo.Schema

  item do
    table_name("app_data")

    field(:email, partition_key: true)
    field(:role, sort_key: true, default: "user")
    field(:display_name)
    field(:username)
    field(:bio)
    field(:profile_image)
    field(:cover_image)
    field(:location)
    field(:social_media_links)
    field(:active, default: true)
    field(:verified, default: false)
    field(:password_hash)
    field(:created_at)
    field(:updated_at)
  end
end

defmodule Post do
  use Dynamo.Schema

  item do
    table_name("app_data")

    field(:title, sort_key: true)
    field(:body)
    field(:email)  # foreign key - auto-inferred from User's partition key

    # This makes Post use User's partition key format
    # and prefix sort keys with "post"
    belongs_to(:user, User, sk_strategy: :prefix)
  end
end
```

## Key Generation

When you create instances, the keys are generated as follows:

```elixir
user = %User{
  email: "john@example.com",
  role: "admin",
  display_name: "John Doe"
}

post = %Post{
  email: "john@example.com",  # foreign key
  title: "My First Post",
  body: "Hello world!"
}

# After key generation:
# User: pk="user#john@example.com", sk="admin"
# Post: pk="user#john@example.com", sk="post#My First Post"
```

## Enhanced Query Behavior

### Before Enhancement (would fail)

```elixir
# This would try to use Post's own partition key and fail
Dynamo.Table.list_items(%Post{email: "john@example.com"})
# Would generate: pk="post#john@example.com" (wrong!)
```

### After Enhancement (works correctly)

```elixir
# This now automatically detects belongs_to relationship
Dynamo.Table.list_items(%Post{email: "john@example.com"})

# Internally does:
# 1. Detects Post has belongs_to relationship with User
# 2. Uses User's partition key format: pk="user#john@example.com"
# 3. Since sk_strategy is :prefix, uses begins_with: sk="post"
# 4. Finds all posts for this user
```

## Query Variations

### 1. Get all posts for a user

```elixir
# Gets all posts by john@example.com
{:ok, posts} = Dynamo.Table.list_items(%Post{email: "john@example.com"})
```

### 2. Get specific post

```elixir
# Gets specific post by title
{:ok, posts} = Dynamo.Table.list_items(
  %Post{email: "john@example.com", title: "My First Post"}
)
```

### 3. Get posts with title prefix

```elixir
# Gets posts with titles starting with "My"
{:ok, posts} = Dynamo.Table.list_items(
  %Post{email: "john@example.com", title: "My"},
  sk_operator: :begins_with
)
```

### 4. Get posts in title range

```elixir
# Gets posts with titles between "A" and "M"
{:ok, posts} = Dynamo.Table.list_items(
  %Post{email: "john@example.com", title: "A"},
  sk_operator: :between,
  sk_end: "M"
)
```

## How It Works Internally

The enhanced `list_items` function:

1. **Detects belongs_to**: Checks if the struct has `belongs_to_relations()`
2. **Uses parent partition key**: Generates partition key using parent's format
3. **Handles sort key strategy**:
   - `:prefix` strategy: Uses `begins_with` with entity name when no specific sort key
   - `:use_defined` strategy: Uses normal sort key handling
4. **Builds correct query**: Creates DynamoDB query with proper keys

## Data Layout in DynamoDB

With this setup, your data is efficiently organized:

```
Partition Key: "user#john@example.com"
├── Sort Key: "admin"                    → User record
├── Sort Key: "post#My First Post"       → Post record
├── Sort Key: "post#Another Post"        → Post record
└── Sort Key: "post#Third Post"          → Post record

Partition Key: "user#jane@example.com"
├── Sort Key: "user"                     → User record
├── Sort Key: "post#Jane's Post"         → Post record
└── Sort Key: "post#Jane's Update"       → Post record
```

## Benefits

1. **Efficient queries**: All user data in same partition
2. **Automatic handling**: No manual key management needed
3. **Flexible querying**: Support for all DynamoDB query operators
4. **Single table design**: Multiple entity types in one table
5. **Type safety**: Compile-time validation of relationships

## Migration from Separate Tables

If you're migrating from separate User and Post tables:

1. **Update schemas**: Add `belongs_to` to Post schema
2. **Ensure foreign key field**: Post must have `email` field
3. **Migrate data**: Update existing Post records to use new key format
4. **Update queries**: Remove table-specific queries, use `list_items`

The enhanced `list_items` makes single-table design much easier to work with!