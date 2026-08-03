defmodule Flux.Accounts.UserNotifier do
  @moduledoc "Email notification functions for user account events."
  import Swoosh.Email

  alias Flux.Mailer
  alias Flux.Accounts.User

  require Logger

  # Delivers the email using the application mailer.
  #
  # The sender comes from configuration rather than a constant: most relays
  # reject a sender they are not authorised for, so it has to match whatever
  # relay the operator configured. It was previously hardcoded to a literal
  # `contact@example.com`.
  defp deliver(recipient, subject, body) do
    case Mailer.from() do
      nil ->
        # Distinguished from a delivery failure on purpose. Returning :ok here
        # would make an unconfigured install look like it had sent the mail,
        # which is the failure mode this is fixing.
        Logger.warning(
          "[Mailer] Not sending #{inspect(subject)} — no sender configured " <>
            "(set FLUX_MAIL_FROM_ADDRESS)."
        )

        {:error, :mailer_not_configured}

      sender ->
        email =
          new()
          |> to(recipient)
          |> from(sender)
          |> subject(subject)
          |> text_body(body)

        with {:ok, _metadata} <- Mailer.deliver(email) do
          {:ok, email}
        end
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
