defmodule Dynamo.LoggerTest do
  use ExUnit.Case, async: true
  doctest Dynamo.Logger

  test "logging can be enabled and disabled" do
    # Initially disabled
    assert Dynamo.Logger.enabled?() == false

    # Enable logging
    Dynamo.Logger.enable()
    assert Dynamo.Logger.enabled?() == true

    # Disable logging
    Dynamo.Logger.disable()
    assert Dynamo.Logger.enabled?() == false
  end

  test "log_query does not raise when logging is disabled" do
    # Ensure logging is disabled
    Dynamo.Logger.disable()

    # This should not raise an error
    assert Dynamo.Logger.log_query("TestOperation", %{"TableName" => "test"}) == :ok
  end
end
