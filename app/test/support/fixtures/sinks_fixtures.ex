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

  @doc """
  Generate a MySQL sink.
  """
  def mysql_sink_fixture(organization_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "test-mysql-#{System.unique_integer([:positive])}",
        type: "mysql",
        config: %{
          "database_url" => "mysql://root:secret@localhost:3306/flux_test",
          "table" => "events",
          "columns" => %{"event_type" => "type", "payload.user_id" => "user_id"}
        },
        enabled: true,
        organization_id: organization_id
      })

    {:ok, sink} = Flux.Sinks.create_sink(attrs)
    sink
  end

  @doc """
  Generate an Email sink (SMTP provider).
  """
  def email_sink_fixture(organization_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "test-email-#{System.unique_integer([:positive])}",
        type: "email",
        config: %{
          "provider" => "smtp",
          "host" => "smtp.example.com",
          "port" => 587,
          "security" => "starttls",
          "username" => "mailer",
          "password" => "smtp-s3cr3t",
          "from" => "alerts@example.com",
          "to" => ["ops@example.com"],
          "subject" => "Order {order.id} failed"
        },
        enabled: true,
        organization_id: organization_id
      })

    {:ok, sink} = Flux.Sinks.create_sink(attrs)
    sink
  end
end
