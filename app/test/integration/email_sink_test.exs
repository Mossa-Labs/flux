defmodule Flux.Integration.EmailSinkTest do
  @moduledoc """
  Integration tests for the Email sink's SMTP provider against a real SMTP
  server (Mailpit), checking what actually arrives in the inbox.

  Excluded from the default suite (`@moduletag :integration`). To run:

      docker compose -f docker-compose.mailpit.yml up -d
      mix test --include integration test/integration/email_sink_test.exs

  Mailpit requires STARTTLS with a self-signed certificate and accepts any
  credentials. Override the hosts with `MAILPIT_SMTP_HOST` / `MAILPIT_API_URL`.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :capture_log

  alias Flux.Sink.Adapters.Email

  @smtp_host System.get_env("MAILPIT_SMTP_HOST", "127.0.0.1")
  @api System.get_env("MAILPIT_API_URL", "http://127.0.0.1:8025")

  @config %{
    "provider" => "smtp",
    "host" => @smtp_host,
    "port" => 1025,
    "security" => "starttls",
    # Mailpit's certificate is self-signed.
    "tls_verify" => false,
    "username" => "mailer",
    "password" => "secret",
    "from" => "alerts@example.com",
    "from_name" => "Flux Alerts",
    "to" => ["ops@example.com"],
    "cc" => ["lead@example.com"],
    "subject" => "Order {order.id} failed",
    "html_body" => "<p>Order <b>{order.id}</b>: {error}</p>",
    "text_body" => "Order {order.id}: {error}"
  }

  @record %{"order" => %{"id" => "A-1"}, "error" => "<script>x</script>"}

  setup_all do
    previous = Application.get_env(:flux, :email_sink_swoosh_adapter)
    Application.delete_env(:flux, :email_sink_swoosh_adapter)
    on_exit(fn -> Application.put_env(:flux, :email_sink_swoosh_adapter, previous) end)

    case Req.get(@api <> "/api/v1/info", retry: false) do
      {:ok, %{status: 200}} -> :ok
      _ -> raise "Mailpit is not reachable at #{@api} — see the moduledoc to start it"
    end
  end

  setup do
    Req.delete!(@api <> "/api/v1/messages")
    :ok
  end

  defp opts, do: [sink_id: System.unique_integer([:positive])]

  test "test_connection negotiates STARTTLS and authenticates" do
    assert :ok = Email.test_connection(@config)
  end

  test "delivers a multipart email with the right headers over authenticated STARTTLS" do
    assert :ok = Email.deliver(@record, @config, opts())

    [summary] = Req.get!(@api <> "/api/v1/messages").body["messages"]
    assert summary["Subject"] == "Order A-1 failed"
    assert summary["From"] == %{"Address" => "alerts@example.com", "Name" => "Flux Alerts"}
    assert [%{"Address" => "ops@example.com"}] = summary["To"]
    assert [%{"Address" => "lead@example.com"}] = summary["Cc"]

    message = Req.get!(@api <> "/api/v1/message/#{summary["ID"]}").body
    assert message["HTML"] =~ "<p>Order <b>A-1</b>: &lt;script&gt;x&lt;/script&gt;</p>"
    assert message["Text"] =~ "Order A-1: <script>x</script>"

    headers = Req.get!(@api <> "/api/v1/message/#{summary["ID"]}/headers").body
    assert headers["Auto-Submitted"] == ["auto-generated"]
  end

  test "certificate verification is on by default, so a self-signed server is refused" do
    config = Map.delete(@config, "tls_verify")

    assert {:error, _} = Email.test_connection(config)
    assert {:error, {:email_error, _}} = Email.deliver(@record, config, opts())
    assert Req.get!(@api <> "/api/v1/messages").body["messages"] == []
  end

  test "an unreachable server is a delivery error, not a crash" do
    config = Map.put(@config, "port", 1)

    assert {:error, _} = Email.test_connection(config)
    assert {:error, {:email_error, _}} = Email.deliver(@record, config, opts())
  end
end
