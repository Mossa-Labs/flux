defmodule Flux.Test.PermissiveSinkAdapter do
  @moduledoc """
  Test double that accepts any sink config. Register it over a Pro sink type's
  stub (`Flux.Sink.Registry.register/2`) to exercise a licensed save path, e.g.
  the sink form's edit-and-save behaviour, without the real adapter.
  """
  @behaviour Flux.Sink.Adapter

  @impl true
  def deliver(_data, _config, _opts), do: :ok

  @impl true
  def validate_config(_config), do: :ok
end
