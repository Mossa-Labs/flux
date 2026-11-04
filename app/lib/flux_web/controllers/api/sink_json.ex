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
      # True when a stored secret can't be decrypted with the current vault key
      # and has to be re-entered. The secret itself shows as "[REDACTED]".
      credentials_undecryptable: Sinks.undecryptable_secrets?(s),
      updated_at: s.updated_at
    }
  end
end
