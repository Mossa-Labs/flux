defmodule Flux.Test.RecordingSourceAdapter do
  @moduledoc """
  Test double that records every adapter call it receives. Each callback sends
  `{:source_adapter_called, callback, config}` to the calling process (the
  `Flux.Source` facade calls adapters synchronously), so a test can assert that
  the adapter was, or was never, handed a config.

  Register it under a test-unique type name (`Flux.Source.Registry.register/2`)
  so async tests don't overwrite a shared type. It is passive: `ingestion_spec/2`
  returns `nil`.
  """
  @behaviour Flux.Source.Adapter

  @impl true
  def queue_name(config) do
    record(:queue_name, config)
    "test.recording"
  end

  @impl true
  def ingestion_spec(config, _opts) do
    record(:ingestion_spec, config)
    nil
  end

  @impl true
  def validate_config(config) do
    record(:validate_config, config)
    :ok
  end

  @impl true
  def test_connection(config) do
    record(:test_connection, config)
    :ok
  end

  defp record(callback, config), do: send(self(), {:source_adapter_called, callback, config})
end
