defmodule Flux.Pipelines.StepSecretsTest do
  use ExUnit.Case, async: true

  alias Flux.Pipelines.StepSecrets

  defp steps(source_config) do
    %{
      "version" => "1.0",
      "steps" => [%{"type" => "native", "operation" => "map"}],
      "nodes" => [
        %{"id" => "source", "type" => "source", "sourceConfig" => source_config},
        %{"id" => "output", "type" => "sink", "queue" => "events.processed"}
      ]
    }
  end

  @config %{
    "type" => "grpc",
    "endpoint" => "telemetry.example.com:443",
    "bearerToken" => "t0k",
    "clientCert" => "-----BEGIN CERTIFICATE-----",
    "clientKey" => "-----BEGIN PRIVATE KEY-----",
    "password" => ""
  }

  test "redact/1 masks set credentials and leaves everything else" do
    redacted = StepSecrets.redact(steps(@config))
    [%{"sourceConfig" => config}, sink] = redacted["nodes"]

    assert config["bearerToken"] == "[REDACTED]"
    assert config["clientKey"] == "[REDACTED]"
    # Unset credentials stay unset; non-secret fields are untouched.
    assert config["password"] == ""
    assert config["endpoint"] == "telemetry.example.com:443"
    assert config["clientCert"] == "-----BEGIN CERTIFICATE-----"
    assert sink == %{"id" => "output", "type" => "sink", "queue" => "events.processed"}
    assert redacted["steps"] == steps(@config)["steps"]
  end

  test "strip/1 drops credentials" do
    [%{"sourceConfig" => config}, _sink] = StepSecrets.strip(steps(@config))["nodes"]

    for key <- ["bearerToken", "clientKey", "password"], do: refute(Map.has_key?(config, key))
    assert config["endpoint"] == "telemetry.example.com:443"
  end

  test "covers every source type's credential fields" do
    config = Map.new(StepSecrets.secret_keys(), &{&1, "secret"})
    [%{"sourceConfig" => redacted}, _] = StepSecrets.redact(steps(config))["nodes"]

    assert Enum.all?(redacted, fn {_key, value} -> value == "[REDACTED]" end)
  end

  test "paths/1 names every set credential in every source node" do
    steps = %{
      "nodes" => [
        %{"id" => "a", "type" => "source", "sourceConfig" => @config},
        %{"id" => "out", "type" => "sink"},
        %{"id" => "b", "type" => "source", "sourceConfig" => %{"jwt" => "j", "metadata" => nil}}
      ]
    }

    paths = StepSecrets.paths(steps)

    assert Enum.map(paths, &get_in(steps, &1)) |> Enum.sort() ==
             ["-----BEGIN PRIVATE KEY-----", "j", "t0k"]

    # Blank and nil credentials have no path, so they are not encrypted.
    assert length(paths) == 3
  end

  test "paths/1 is empty for steps without nodes" do
    assert StepSecrets.paths(%{"version" => "1.0", "steps" => []}) == []
    assert StepSecrets.paths(%{}) == []
  end

  test "redact/1 scrubs an encrypted wrapper left in a non-secret field" do
    wrapper = Flux.Vault.encrypt_value("stolen")

    [%{"sourceConfig" => config}, _] =
      StepSecrets.redact(steps(%{"endpoint" => wrapper}))["nodes"]

    assert config["endpoint"] == "[REDACTED]"
  end

  test "passes through steps without nodes" do
    assert StepSecrets.redact(nil) == nil

    assert StepSecrets.strip(%{"version" => "1.0", "steps" => []}) == %{
             "version" => "1.0",
             "steps" => []
           }
  end
end
