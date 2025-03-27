defmodule Dynamo.AWS do
  @moduledoc """
  Provides AWS client configuration for DynamoDB operations.

  This module handles the creation and configuration of AWS clients used for
  interacting with DynamoDB. It supports customization through options and
  environment variables.
  """

  @doc """
  Creates an AWS client for DynamoDB operations.

  ## Options
    * `:endpoint` - Custom endpoint URL for DynamoDB (useful for local development)
    * `:region` - AWS region to use (defaults to credentials region, AWS_REGION env var, or "us-east-1")
    * `:timeout` - Request timeout in milliseconds (default: 30000)

  ## Environment Variables
    * `AWS_REGION` - AWS region to use if not specified in options or credentials
    * `AWS_DYNAMODB_ENDPOINT` - Custom endpoint URL if not specified in options

  ## Examples

      # Basic client with default settings
      client = Dynamo.AWS.client()

      # Client with custom endpoint (e.g., for local DynamoDB)
      client = Dynamo.AWS.client(endpoint: "http://localhost:8000")

      # Client with custom region
      client = Dynamo.AWS.client(region: "eu-west-1")

  ## Returns
    AWS client configured for DynamoDB operations
  """
  def client(opts \\ []) do
    creds = :aws_credentials.get_credentials()

    endpoint = opts[:endpoint] || System.get_env("AWS_DYNAMODB_ENDPOINT")
    region = opts[:region] || creds[:region] || System.get_env("AWS_REGION") || "us-east-1"
    timeout = opts[:timeout] || 30000

    client = AWS.Client.create(
      creds.access_key_id,
      creds.secret_access_key,
      creds[:token],
      region
    )
    |> Map.put(:http_opts, [recv_timeout: timeout])

    if endpoint do
      %{client | endpoint: endpoint}
    else
      client
    end
  end
end
