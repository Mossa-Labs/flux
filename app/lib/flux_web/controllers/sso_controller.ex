defmodule FluxWeb.SSOController do
  @moduledoc """
  Single sign-on endpoints. Protocol work happens behind `Flux.Auth.SSO`; this
  controller owns the browser side of the round trip.

  ## Why there is a hand-off step

  The identity provider returns the browser with a cross-site `POST` to the
  assertion consumer service (`acs/2`). The session cookie is `SameSite=Lax`, so
  the browser leaves it off that request: at that moment we cannot tell whose
  browser this is. Logging a user in there would let anyone holding a valid
  response for *their own* account plant it in someone else's browser (login
  CSRF).

  So `acs/2` only validates the response. It then redirects with a short-lived
  signed ticket to `complete/2`, a same-site top-level `GET` that *does* carry
  the session. There the ticket's request ID must match the one `start/2` stored
  in this browser's session, which proves the sign-in was started here, and its
  nonce must still be unclaimed on the server, which makes it single use even
  against a replayed copy of the old session cookie. Only then is a session
  created.

  RelayState carries nothing but that request ID. It is public and at most 80
  bytes, so it never holds anything trusted.
  """
  use FluxWeb, :controller

  alias Flux.Accounts
  alias Flux.Accounts.{Scope, User}
  alias Flux.Auth.SSO
  alias FluxWeb.UserAuth

  @ticket_salt "sso ticket"
  # The ticket only has to survive one redirect.
  @ticket_max_age_seconds 120
  # How long a user may spend at the identity provider before the attempt lapses.
  @pending_ttl_seconds 600
  @config_id_format ~r/\A[A-Za-z0-9_-]{1,64}\z/

  @failed "Single sign-on didn't complete. Try again, or contact your administrator."

  @doc "Starts a sign-in: work email → that domain's identity provider."
  def start(conn, %{"sso" => %{"email" => email}}) when is_binary(email) do
    request_id = new_request_id()

    with {:ok, config_id} <- SSO.discover(email),
         {:ok, url} <-
           SSO.authn_request(config_id, %{
             request_id: request_id,
             relay_state: request_id,
             acs_url: acs_url(config_id)
           }) do
      conn
      |> put_session(:sso_pending, %{
        "request_id" => request_id,
        "config_id" => config_id,
        "at" => now()
      })
      |> redirect(external: url)
    else
      :none ->
        conn
        |> put_flash(
          :error,
          "Single sign-on isn't set up for that email address. Sign in with your password or email link instead."
        )
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")

      {:error, reason} ->
        audit_failure(conn, nil, reason)

        conn
        |> put_flash(:error, @failed)
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def start(conn, _params) do
    conn
    |> put_flash(:error, "Enter your work email to sign in with SSO.")
    |> redirect(to: ~p"/users/log-in")
  end

  @doc """
  Assertion consumer service. Runs without a session (see the module note), so
  it validates and hands off; it never signs anyone in.
  """
  def acs(conn, %{"config_id" => config_id, "SAMLResponse" => response, "RelayState" => rid})
      when is_binary(response) and is_binary(rid) and byte_size(rid) <= 80 do
    with true <- Regex.match?(@config_id_format, config_id),
         {:ok, %User{} = user} <-
           SSO.consume(config_id, %{
             response: response,
             request_id: rid,
             acs_url: acs_url(config_id)
           }) do
      ticket =
        Phoenix.Token.sign(FluxWeb.Endpoint, @ticket_salt, %{
          "u" => user.id,
          "r" => rid,
          "n" => Accounts.create_sso_ticket(user)
        })

      redirect(conn, to: ~p"/sso/complete?#{[ticket: ticket]}")
    else
      false ->
        audit_failure(conn, nil, :unknown_config)
        redirect(conn, to: ~p"/sso/complete?#{[error: 1]}")

      # Audited by the provider, which knows the configuration's organization.
      {:error, _reason} ->
        redirect(conn, to: ~p"/sso/complete?#{[error: 1]}")
    end
  end

  # Missing or oversized fields, or an unsolicited (IdP-initiated) post with no
  # RelayState: never something we asked for.
  def acs(conn, params) do
    audit_failure(conn, params["config_id"], :malformed_response)
    redirect(conn, to: ~p"/sso/complete?#{[error: 1]}")
  end

  @doc "Finishes a sign-in in the browser that started it."
  def complete(conn, %{"ticket" => ticket}) when is_binary(ticket) do
    pending = get_session(conn, :sso_pending)
    # Cleared whatever the outcome. That alone isn't single use: the session is
    # a signed cookie, so a copy of the old one still carries the pending
    # attempt. The ticket's nonce, consumed on the server, is what makes it so.
    conn = delete_session(conn, :sso_pending)

    with %{"request_id" => rid, "at" => at} <- pending,
         true <- fresh?(at),
         {:ok, %{"u" => user_id, "r" => ^rid, "n" => nonce}} <-
           Phoenix.Token.verify(FluxWeb.Endpoint, @ticket_salt, ticket,
             max_age: @ticket_max_age_seconds
           ),
         :ok <- Accounts.consume_sso_ticket(user_id, nonce, @ticket_max_age_seconds),
         %User{} = user <- Accounts.get_user(user_id),
         true <- Scope.user_can_log_in?(user) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, %{}, method: :sso)
    else
      _ ->
        audit_failure(conn, pending && pending["config_id"], :session_mismatch)
        fail(conn)
    end
  end

  def complete(conn, _params) do
    conn
    |> delete_session(:sso_pending)
    |> fail()
  end

  @doc "Service-provider metadata, for pasting or pointing an IdP at."
  def metadata(conn, %{"config_id" => config_id}) do
    with true <- Regex.match?(@config_id_format, config_id),
         {:ok, xml} <- SSO.sp_metadata(config_id, %{acs_url: acs_url(config_id)}) do
      conn
      |> put_resp_content_type("application/samlmetadata+xml")
      |> send_resp(200, xml)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp fail(conn) do
    conn
    |> put_flash(:error, @failed)
    |> redirect(to: ~p"/users/log-in")
  end

  defp acs_url(config_id), do: url(~p"/sso/#{config_id}/acs")

  # An XML ID must not start with a digit; the underscore keeps it valid.
  defp new_request_id, do: "_" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

  defp now, do: System.system_time(:second)

  defp fresh?(at) when is_integer(at), do: now() - at <= @pending_ttl_seconds
  defp fresh?(_), do: false

  # The reason is for operators; the browser only ever sees @failed.
  defp audit_failure(conn, config_id, reason) do
    Flux.Audit.log(%{
      action: :sso_login_failed,
      actor_type: :system,
      resource_type: :sso_config,
      resource_id: config_id,
      metadata:
        Map.put(
          FluxWeb.AuditMeta.from_conn(conn),
          "reason",
          reason |> inspect() |> String.slice(0, 200)
        )
    })
  end
end
