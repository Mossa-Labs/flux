defmodule Flux.SinksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Flux.Sinks` context.
  """

  @doc """
  Generate a sink.
  """
  def sink_fixture(organization_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "test-sink-#{System.unique_integer([:positive])}",
        type: "http",
        config: %{"url" => "https://example.com/webhook", "method" => "POST"},
        enabled: true,
        organization_id: organization_id
      })

    {:ok, sink} = Flux.Sinks.create_sink(attrs)
    sink
  end
end
