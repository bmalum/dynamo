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
    * `:access_key_id` - AWS access key ID (overrides all other credential sources)
    * `:secret_access_key` - AWS secret access key (overrides all other credential sources)
    * `:session_token` - AWS session token for temporary credentials (overrides all other credential sources)

  ## Credential Resolution Order
  
  Credentials are resolved in the following order:
  
  1. **Explicit options** - If `access_key_id` and `secret_access_key` are provided in options
  2. **Environment Variables** - `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
  3. **ECS Full URI** - If `AWS_CONTAINER_CREDENTIALS_FULL_URI` environment variable is set
  4. **ECS Relative URI** - If `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` environment variable is set (Fargate/ECS)
  5. **EC2 Instance Metadata** - Queries IMDSv2 at 169.254.169.254 (for EC2 instances with IAM roles)

  ## Environment Variables
    * `AWS_REGION` - AWS region to use if not specified in options
    * `AWS_DYNAMODB_ENDPOINT` - Custom endpoint URL if not specified in options
    * `AWS_ACCESS_KEY_ID` - AWS access key ID
    * `AWS_SECRET_ACCESS_KEY` - AWS secret access key
    * `AWS_SESSION_TOKEN` - AWS session token for temporary credentials
    * `AWS_CONTAINER_CREDENTIALS_FULL_URI` - Full URI for ECS task credentials
    * `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` - Relative URI for ECS task credentials

  ## Examples

      # Basic client (automatically detects credentials from environment)
      client = Dynamo.AWS.client()

      # Works automatically in Fargate/ECS with task IAM role
      client = Dynamo.AWS.client()

      # Works automatically on EC2 instances with IAM role
      client = Dynamo.AWS.client()

      # Client with custom endpoint (e.g., for local DynamoDB)
      client = Dynamo.AWS.client(endpoint: "http://localhost:8000")

      # Client with custom region
      client = Dynamo.AWS.client(region: "eu-west-1")

      # Client with explicit credentials (overrides all automatic detection)
      client = Dynamo.AWS.client(
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        session_token: "AQoEXAMPLEH4aoAH0gNCAPyJxz4BlCFFxWNE1OPTgk5TthT+FvwqnKwRcOIfrRh3c/LTo6UDdyJwOOvEVPvLXCrrrUtdnniCEXAMPLE/IvU1dYUg2RVAJBanLiHb4IgRmpRV3zrkuWJOgQs8IZZaIv2BXIa2R4OlgkBN9bkUDNCJiBeb/AXlzBBko7b15fjrBs2+cTQtpZ3CYWFXG8C5zqx37wnOE49mRl/+OtkIKGO7fAE"
      )

  ## Returns
    AWS client configured for DynamoDB operations
  """
  def client(opts \\ []) do
    credentials = get_credentials(opts)
    region = opts[:region] || System.get_env("AWS_REGION") || "us-east-1"
    endpoint = opts[:endpoint] || System.get_env("AWS_DYNAMODB_ENDPOINT")
    timeout = opts[:timeout] || 30000

    base_url = endpoint || "https://dynamodb.#{region}.amazonaws.com"

    %{
      access_key_id: credentials.access_key_id,
      secret_access_key: credentials.secret_access_key,
      session_token: credentials.session_token,
      region: region,
      endpoint: base_url,
      timeout: timeout,
      service: "dynamodb"
    }
  end

  defp get_credentials(opts) do
    cond do
      opts[:access_key_id] && opts[:secret_access_key] ->
        %{
          access_key_id: opts[:access_key_id],
          secret_access_key: opts[:secret_access_key],
          session_token: opts[:session_token]
        }

      true ->
        # Check env vars first (fast, no network calls)
        case fetch_env_credentials() do
          {:ok, creds} -> creds
          {:error, _} ->
            # Then try metadata endpoints (may hang in dev if not on AWS)
            case fetch_metadata_credentials() do
              {:ok, creds} -> creds
              {:error, _} ->
                raise ArgumentError, """
                AWS credentials not found. Please provide them via:
                1. Options: access_key_id and secret_access_key
                2. Environment variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
                3. ECS metadata endpoint (automatic in Fargate/ECS)
                4. EC2 instance metadata (automatic on EC2)
                """
            end
        end
    end
  end

  defp fetch_metadata_credentials do
    cond do
      full_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_FULL_URI") ->
        fetch_ecs_full_uri_credentials(full_uri)

      relative_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") ->
        fetch_ecs_relative_uri_credentials(relative_uri)

      true ->
        fetch_ec2_imds_credentials()
    end
  end

  defp fetch_ecs_full_uri_credentials(uri) do
    case Req.get(uri, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} -> parse_credentials(body)
      _ -> {:error, :metadata_fetch_failed}
    end
  end

  defp fetch_ecs_relative_uri_credentials(relative_uri) do
    url = "http://169.254.170.2#{relative_uri}"
    
    case Req.get(url, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} -> parse_credentials(body)
      _ -> {:error, :metadata_fetch_failed}
    end
  end

  defp fetch_ec2_imds_credentials do
    with {:ok, token} <- fetch_imds_token(),
         {:ok, role} <- fetch_imds_role(token),
         {:ok, body} <- fetch_imds_credentials(token, role) do
      parse_credentials(body)
    else
      _ -> {:error, :metadata_fetch_failed}
    end
  end

  defp fetch_imds_token do
    url = "http://169.254.169.254/latest/api/token"
    headers = [{"X-aws-ec2-metadata-token-ttl-seconds", "21600"}]
    
    case Req.put(url, headers: headers, receive_timeout: 1000) do
      {:ok, %{status: 200, body: token}} -> {:ok, token}
      _ -> {:error, :token_fetch_failed}
    end
  end

  defp fetch_imds_role(token) do
    url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    headers = [{"X-aws-ec2-metadata-token", token}]
    
    case Req.get(url, headers: headers, receive_timeout: 1000) do
      {:ok, %{status: 200, body: role}} -> {:ok, String.trim(role)}
      _ -> {:error, :role_fetch_failed}
    end
  end

  defp fetch_imds_credentials(token, role) do
    url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/#{role}"
    headers = [{"X-aws-ec2-metadata-token", token}]
    
    case Req.get(url, headers: headers, receive_timeout: 1000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      _ -> {:error, :credentials_fetch_failed}
    end
  end

  defp fetch_env_credentials do
    case {System.get_env("AWS_ACCESS_KEY_ID"), System.get_env("AWS_SECRET_ACCESS_KEY")} do
      {nil, _} -> {:error, :no_env_credentials}
      {_, nil} -> {:error, :no_env_credentials}
      {access_key, secret_key} ->
        {:ok, %{
          access_key_id: access_key,
          secret_access_key: secret_key,
          session_token: System.get_env("AWS_SESSION_TOKEN")
        }}
    end
  end

  defp parse_credentials(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_credentials(parsed)
      _ -> {:error, :invalid_credentials_format}
    end
  end

  defp parse_credentials(%{"AccessKeyId" => access_key, "SecretAccessKey" => secret_key, "Token" => token}) do
    {:ok, %{
      access_key_id: access_key,
      secret_access_key: secret_key,
      session_token: token
    }}
  end

  defp parse_credentials(_), do: {:error, :invalid_credentials_format}

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
