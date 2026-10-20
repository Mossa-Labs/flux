defmodule Flux.EmailProviderStub do
  @moduledoc """
  A Plug standing in for the HTTP APIs of the email sink's API providers
  (SendGrid, Mailgun, Postmark, Amazon SES), so their Swoosh adapters can be
  exercised end to end over real HTTP without credentials.

  Serve it with Bandit on an ephemeral port and point the sink's `base_url` at
  it. Each request is forwarded to the `:test_pid` given in the plug options as
  `{:provider_request, %{method:, path:, headers:, body:}}`, and answered with
  the success response that provider's adapter expects.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :test_pid)

  @impl Plug
  def call(conn, test_pid) do
    {:ok, body, conn} = read_body(conn)

    send(
      test_pid,
      {:provider_request,
       %{method: conn.method, path: conn.request_path, headers: conn.req_headers, body: body}}
    )

    respond(conn, conn.request_path)
  end

  # SendGrid
  defp respond(conn, "/v3/mail/send") do
    conn
    |> put_resp_header("x-message-id", "sendgrid-1")
    |> send_resp(202, "")
  end

  # Postmark
  defp respond(conn, "/email") do
    json(conn, %{"ErrorCode" => 0, "Message" => "OK", "MessageID" => "postmark-1"})
  end

  # Amazon SES (the adapter posts to the host root)
  defp respond(conn, "/") do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, """
    <SendRawEmailResponse>
      <SendRawEmailResult><MessageId>ses-1</MessageId></SendRawEmailResult>
      <ResponseMetadata><RequestId>req-1</RequestId></ResponseMetadata>
    </SendRawEmailResponse>
    """)
  end

  # Mailgun: /v3/<domain>/messages
  defp respond(conn, "/v3/" <> _domain_messages) do
    json(conn, %{"id" => "<mailgun-1@example.com>", "message" => "Queued. Thank you."})
  end

  defp respond(conn, _path), do: send_resp(conn, 404, "not found")

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end
end
