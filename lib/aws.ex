defmodule Dynamo.AWS do
  def client() do
    creds = :aws_credentials.get_credentials()
    AWS.Client.create(
      creds.access_key_id,
      creds.secret_access_key,
      creds.token,
      creds[:region] || "us-east-1"
    )
  end
end
