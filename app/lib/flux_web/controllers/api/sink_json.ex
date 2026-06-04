defmodule FluxWeb.API.SinkJSON do
  @moduledoc "JSON rendering for the sinks API (secrets redacted)."

  alias Flux.Sinks

  def index(%{sinks: sinks}) do
    %{data: Enum.map(sinks, &sink/1)}
  end

  defp sink(s) do
    %{
      id: s.id,
      name: s.name,
      description: s.description,
      type: s.type,
      enabled: s.enabled,
      config: Sinks.redact_config(s.config),
      updated_at: s.updated_at
    }
  end
end
