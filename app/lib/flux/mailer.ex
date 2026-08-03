defmodule Flux.Mailer do
  @moduledoc """
  Email delivery.

  Configured entirely from the environment (see `config/runtime.exs`), so one
  build serves an operator running Flux on their own hardware with their own
  SMTP relay and a hosted deployment where we supply one. Nothing here branches
  on which.

  ## The unconfigured case is loud on purpose

  Without `FLUX_SMTP_HOST` the adapter stays `Swoosh.Adapters.Local`, which
  stores mail in memory and delivers nothing. In development that is right — the
  `/dev/mailbox` preview shows it. In production it is a trap: that route is not
  mounted, so mail vanishes with no error, and sign-in links are among the things
  that vanish.

  So a production node without a mailer says so at boot rather than discovering
  it via a support ticket. It warns rather than refuses to start, because
  password sign-in works without mail and an install that never sends any is a
  legitimate configuration.
  """
  use Swoosh.Mailer, otp_app: :flux

  require Logger

  @default_from_name "Flux"

  @doc """
  The configured sender as `{name, address}`.

  `nil` when no address is set, which callers treat as "no mail can be sent" —
  better than inventing a plausible-looking address, because most relays reject
  a sender they are not authorised for and a silent rejection is what this whole
  module exists to avoid.
  """
  @spec from() :: {String.t(), String.t()} | nil
  def from do
    config = Application.get_env(:flux, :mail_from, [])

    case presence(config[:address]) do
      nil ->
        nil

      address ->
        # White-label branding overrides the display name when a deployment has
        # set one. The address deliberately does not change: relays reject a
        # sender they are not authorised for, so it stays what the operator
        # configured, and only the name a recipient sees is branded.
        name =
          Flux.Branding.mail_from_name() || presence(config[:name]) || @default_from_name

        {name, address}
    end
  end

  @doc """
  Whether outbound mail can actually leave this node.

  Both halves are needed: an adapter that delivers, and a sender it is allowed
  to use.
  """
  @spec configured?() :: boolean()
  def configured?, do: adapter_delivers?() and not is_nil(from())

  @doc """
  Logs at boot when a production node cannot send mail.

  Called from `Flux.Application.start/2`. Says which piece is missing, because
  "email is broken" and "the from address is unset" send an operator to
  different places.
  """
  @spec warn_if_unconfigured() :: :ok
  def warn_if_unconfigured do
    cond do
      not Application.get_env(:flux, :warn_unconfigured_mailer, false) ->
        :ok

      configured?() ->
        :ok

      not adapter_delivers?() ->
        Logger.warning(
          "[Mailer] No mail transport configured — set FLUX_SMTP_HOST (and " <>
            "FLUX_SMTP_USERNAME/FLUX_SMTP_PASSWORD if your relay needs them). " <>
            "Until then Flux accepts mail and delivers none of it, including " <>
            "sign-in links and account confirmations."
        )

      true ->
        Logger.warning(
          "[Mailer] A mail transport is configured but no sender is — set " <>
            "FLUX_MAIL_FROM_ADDRESS. Most relays reject a sender they are not " <>
            "authorised for, so mail would be dropped by the relay rather than sent."
        )
    end
  end

  # Swoosh.Adapters.Local is the dev mailbox: it accepts mail and stores it in
  # memory. Anything else is a real transport as far as this check is concerned.
  defp adapter_delivers? do
    Application.get_env(:flux, __MODULE__, [])[:adapter] not in [
      nil,
      Swoosh.Adapters.Local,
      Swoosh.Adapters.Test
    ]
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_), do: nil
end
