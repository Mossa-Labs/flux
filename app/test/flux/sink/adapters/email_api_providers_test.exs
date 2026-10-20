defmodule Flux.Sink.Adapters.EmailApiProvidersTest do
  @moduledoc """
  Drives the email sink's API providers through their real Swoosh adapters and
  an HTTP client, against `Flux.EmailProviderStub` on a local port.

  Not async: it swaps two global settings — the Swoosh API client (disabled in
  test) and the email sink's test transport — for the duration of the module.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Flux.Sink.Adapters.Email

  @record %{"order" => %{"id" => "A-1"}}

  setup_all do
    previous_client = Application.get_env(:swoosh, :api_client)
    previous_adapter = Application.get_env(:flux, :email_sink_swoosh_adapter)

    Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)
    Application.delete_env(:flux, :email_sink_swoosh_adapter)

    on_exit(fn ->
      Application.put_env(:swoosh, :api_client, previous_client)
      Application.put_env(:flux, :email_sink_swoosh_adapter, previous_adapter)
    end)

    :ok
  end

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {Flux.EmailProviderStub, test_pid: self()},
         ip: :loopback,
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end

  defp config(provider, extra) do
    Map.merge(
      %{
        "provider" => provider,
        "from" => "alerts@example.com",
        "to" => ["ops@example.com"],
        "subject" => "Order {order.id} failed",
        "html_body" => "<p>Order {order.id}</p>",
        "text_body" => "Order {order.id}"
      },
      extra
    )
  end

  defp opts, do: [sink_id: System.unique_integer([:positive])]

  test "SendGrid sends a multipart message with a bearer key", %{base: base} do
    config = config("sendgrid", %{"api_key" => "SG.key", "base_url" => base <> "/v3"})

    assert :ok = Email.validate_config(config)
    assert :ok = Email.deliver(@record, config, opts())

    assert_receive {:provider_request, %{path: "/v3/mail/send", headers: headers, body: body}}
    assert {"authorization", "Bearer SG.key"} in headers

    payload = Jason.decode!(body)
    assert payload["subject"] == "Order A-1 failed"
    assert [%{"type" => "text/plain"}, %{"type" => "text/html"}] = payload["content"]
  end

  test "Postmark sends with its server token", %{base: base} do
    config = config("postmark", %{"api_key" => "pm-token", "base_url" => base})

    assert :ok = Email.deliver(@record, config, opts())

    assert_receive {:provider_request, %{path: "/email", headers: headers, body: body}}
    assert {"x-postmark-server-token", "pm-token"} in headers

    payload = Jason.decode!(body)
    assert payload["Subject"] == "Order A-1 failed"
    assert payload["HtmlBody"] == "<p>Order A-1</p>"
    assert payload["TextBody"] == "Order A-1"
  end

  test "Mailgun posts to the sending domain", %{base: base} do
    config =
      config("mailgun", %{
        "api_key" => "mg-key",
        "domain" => "mg.example.com",
        "base_url" => base <> "/v3"
      })

    assert :ok = Email.deliver(@record, config, opts())

    assert_receive {:provider_request, %{path: "/v3/mg.example.com/messages", body: body}}

    form = URI.decode_query(body)
    assert form["subject"] == "Order A-1 failed"
    assert form["html"] == "<p>Order A-1</p>"
    assert form["h:Auto-Submitted"] == "auto-generated"
  end

  test "Amazon SES sends a signed raw message", %{base: base} do
    config =
      config("amazon_ses", %{
        "region" => "us-east-1",
        "access_key" => "AKIAEXAMPLE",
        "secret_access_key" => "ses-secret",
        "base_url" => base <> "/"
      })

    assert :ok = Email.deliver(@record, config, opts())

    assert_receive {:provider_request, %{path: "/", headers: headers, body: body}}

    assert {_, "AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/" <> _} =
             List.keyfind(headers, "authorization", 0)

    assert body =~ "Action=SendRawEmail"
    refute body =~ "ses-secret"
  end

  test "a provider error is returned, not raised", %{base: base} do
    config = config("sendgrid", %{"api_key" => "k", "base_url" => base <> "/nowhere"})

    assert {:error, {:email_error, _}} = Email.deliver(@record, config, opts())
  end
end
