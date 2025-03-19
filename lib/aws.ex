defmodule Dynamo.AWS do
  def client() do
    creds = :aws_credentials.get_credentials()

    AWS.Client.create(
      creds.access_key_id,
      creds.secret_access_key,
      creds[:token],
      creds[:region] || System.get_env("AWS_REGION") || "us-east-1"
    )
  end
end
