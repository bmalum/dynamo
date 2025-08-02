defmodule Dynamo.AWS do
  @moduledoc """
  Provides AWS client configuration for DynamoDB operations using Req.

  This module handles the creation and configuration of AWS clients used for
  interacting with DynamoDB. It supports customization through options and
  environment variables, including session tokens for temporary credentials.
  """

  @doc """
  Creates an AWS client for DynamoDB operations.

  ## Options
    * `:endpoint` - Custom endpoint URL for DynamoDB (useful for local development)
    * `:region` - AWS region to use (defaults to AWS_REGION env var or "us-east-1")
    * `:timeout` - Request timeout in milliseconds (default: 30000)
    * `:access_key_id` - AWS access key ID (overrides environment)
    * `:secret_access_key` - AWS secret access key (overrides environment)
    * `:session_token` - AWS session token for temporary credentials (overrides environment)

  ## Environment Variables
    * `AWS_REGION` - AWS region to use if not specified in options
    * `AWS_DYNAMODB_ENDPOINT` - Custom endpoint URL if not specified in options
    * `AWS_ACCESS_KEY_ID` - AWS access key ID
    * `AWS_SECRET_ACCESS_KEY` - AWS secret access key
    * `AWS_SESSION_TOKEN` - AWS session token for temporary credentials

  ## Examples

      # Basic client with default settings (uses environment variables)
      client = Dynamo.AWS.client()

      # Client with custom endpoint (e.g., for local DynamoDB)
      client = Dynamo.AWS.client(endpoint: "http://localhost:8000")

      # Client with custom region
      client = Dynamo.AWS.client(region: "eu-west-1")

      # Client with explicit credentials including session token
      client = Dynamo.AWS.client(
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        session_token: "AQoEXAMPLEH4aoAH0gNCAPyJxz4BlCFFxWNE1OPTgk5TthT+FvwqnKwRcOIfrRh3c/LTo6UDdyJwOOvEVPvLXCrrrUtdnniCEXAMPLE/IvU1dYUg2RVAJBanLiHb4IgRmpRV3zrkuWJOgQs8IZZaIv2BXIa2R4OlgkBN9bkUDNCJiBeb/AXlzBBko7b15fjrBs2+cTQtpZ3CYWFXG8C5zqx37wnOE49mRl/+OtkIKGO7fAE"
      )

  ## Returns
    AWS client configured for DynamoDB operations
  """
  def client(opts \\ []) do
    access_key_id = opts[:access_key_id] || System.get_env("AWS_ACCESS_KEY_ID")
    secret_access_key = opts[:secret_access_key] || System.get_env("AWS_SECRET_ACCESS_KEY")
    session_token = opts[:session_token] || System.get_env("AWS_SESSION_TOKEN")
    region = opts[:region] || System.get_env("AWS_REGION") || "us-east-1"
    endpoint = opts[:endpoint] || System.get_env("AWS_DYNAMODB_ENDPOINT")
    timeout = opts[:timeout] || 30000

    if is_nil(access_key_id) or is_nil(secret_access_key) do
      raise ArgumentError, """
      AWS credentials not found. Please provide them via:
      1. Options: access_key_id and secret_access_key
      2. Environment variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
      """
    end

    base_url = endpoint || "https://dynamodb.#{region}.amazonaws.com"

    %{
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      session_token: session_token,
      region: region,
      endpoint: base_url,
      timeout: timeout,
      service: "dynamodb"
    }
  end

  @doc """
  Makes a DynamoDB API request using the AWS Signature Version 4.

  ## Parameters
    * `client` - AWS client configuration
    * `action` - DynamoDB action (e.g., "PutItem", "GetItem")
    * `payload` - Request payload as a map

  ## Returns
    `{:ok, response}` on success or `{:error, reason}` on failure
  """
  def request(client, action, payload) do
    headers = [
      {"Content-Type", "application/x-amz-json-1.0"},
      {"X-Amz-Target", "DynamoDB_20120810.#{action}"}
    ]

    body = Jason.encode!(payload)

    signed_headers = sign_request(client, "POST", "/", headers, body)

    Req.post(client.endpoint,
      headers: signed_headers,
      body: body,
      receive_timeout: client.timeout
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded, %{}}
      {:error, _} -> {:error, "Invalid JSON response"}
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    case Jason.decode(body) do
      {:ok, error} -> {:error, error}
      {:error, _} -> {:error, "HTTP #{status}: #{body}"}
    end
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp sign_request(client, method, path, headers, body) do
    now = DateTime.utc_now()
    date_stamp = Calendar.strftime(now, "%Y%m%d")
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

    # Add required headers
    headers = [
      {"Host", URI.parse(client.endpoint).host},
      {"X-Amz-Date", amz_date}
      | headers
    ]

    # Add session token if present
    headers = if client.session_token do
      [{"X-Amz-Security-Token", client.session_token} | headers]
    else
      headers
    end

    # Create canonical request
    canonical_headers =
      headers
      |> Enum.sort_by(fn {key, _} -> String.downcase(key) end)
      |> Enum.map(fn {key, value} -> "#{String.downcase(key)}:#{String.trim(value)}" end)
      |> Enum.join("\n")

    signed_headers_list =
      headers
      |> Enum.map(fn {key, _} -> String.downcase(key) end)
      |> Enum.sort()
      |> Enum.join(";")

    payload_hash = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    canonical_request = [
      method,
      path,
      "", # query string
      canonical_headers,
      "",
      signed_headers_list,
      payload_hash
    ] |> Enum.join("\n")

    # Create string to sign
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = "#{date_stamp}/#{client.region}/#{client.service}/aws4_request"
    canonical_request_hash = :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)

    string_to_sign = [
      algorithm,
      amz_date,
      credential_scope,
      canonical_request_hash
    ] |> Enum.join("\n")

    # Calculate signature
    signing_key = get_signature_key(client.secret_access_key, date_stamp, client.region, client.service)
    signature = :crypto.mac(:hmac, :sha256, signing_key, string_to_sign) |> Base.encode16(case: :lower)

    # Create authorization header
    authorization = "#{algorithm} Credential=#{client.access_key_id}/#{credential_scope}, SignedHeaders=#{signed_headers_list}, Signature=#{signature}"

    [{"Authorization", authorization} | headers]
  end

  defp get_signature_key(secret_access_key, date_stamp, region, service) do
    k_date = :crypto.mac(:hmac, :sha256, "AWS4" <> secret_access_key, date_stamp)
    k_region = :crypto.mac(:hmac, :sha256, k_date, region)
    k_service = :crypto.mac(:hmac, :sha256, k_region, service)
    :crypto.mac(:hmac, :sha256, k_service, "aws4_request")
  end
end
