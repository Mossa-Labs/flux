defmodule Flux.MailerTest do
  # async: false — swaps global mailer configuration.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Flux.Mailer

  setup do
    prior = {
      Application.get_env(:flux, :mail_from),
      Application.get_env(:flux, Flux.Mailer),
      Application.get_env(:flux, :warn_unconfigured_mailer)
    }

    on_exit(fn ->
      {from, mailer, warn} = prior
      restore(:mail_from, from)
      restore(Flux.Mailer, mailer)
      restore(:warn_unconfigured_mailer, warn)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:flux, key)
  defp restore(key, value), do: Application.put_env(:flux, key, value)

  describe "from/0" do
    test "returns the configured sender" do
      Application.put_env(:flux, :mail_from, name: "Acme", address: "no-reply@acme.test")
      assert Mailer.from() == {"Acme", "no-reply@acme.test"}
    end

    test "falls back to a default name, but never to a default address" do
      # An invented address is worse than none: most relays reject a sender they
      # are not authorised for, so it would be dropped downstream where the
      # operator cannot see it.
      Application.put_env(:flux, :mail_from, address: "no-reply@acme.test")
      assert Mailer.from() == {"Flux", "no-reply@acme.test"}

      Application.put_env(:flux, :mail_from, name: "Acme")
      assert Mailer.from() == nil
    end

    test "treats blank configuration as unset" do
      # An env var set to "" is how this arrives from a .env file with the key
      # present but empty, which is more common than omitting the line.
      Application.put_env(:flux, :mail_from, name: "  ", address: "   ")
      assert Mailer.from() == nil
    end

    test "is nil when nothing is configured" do
      Application.delete_env(:flux, :mail_from)
      assert Mailer.from() == nil
    end
  end

  describe "configured?/0" do
    setup do
      Application.put_env(:flux, :mail_from, name: "Acme", address: "no-reply@acme.test")
    end

    test "false for the adapters that capture rather than deliver" do
      # This is the whole bug: production inherited the dev mailbox adapter, so
      # mail was accepted and silently never sent.
      for adapter <- [Swoosh.Adapters.Local, Swoosh.Adapters.Test] do
        Application.put_env(:flux, Flux.Mailer, adapter: adapter)
        refute Mailer.configured?()
      end
    end

    test "false when a transport exists but no sender does" do
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.SMTP)
      Application.delete_env(:flux, :mail_from)
      refute Mailer.configured?()
    end

    test "true with both a transport and a sender" do
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.SMTP)
      assert Mailer.configured?()
    end
  end

  describe "warn_if_unconfigured/0" do
    test "says nothing outside production" do
      # dev uses the mailbox preview and test the Test adapter, both on purpose.
      # A warning on every boot is how a real warning gets ignored.
      Application.put_env(:flux, :warn_unconfigured_mailer, false)
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.Local)

      assert capture_log(&Mailer.warn_if_unconfigured/0) == ""
    end

    test "names the missing transport" do
      Application.put_env(:flux, :warn_unconfigured_mailer, true)
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.Local)
      Application.put_env(:flux, :mail_from, address: "no-reply@acme.test")

      log = capture_log(&Mailer.warn_if_unconfigured/0)

      assert log =~ "FLUX_SMTP_HOST"
      assert log =~ "delivers none of it"
    end

    test "names the missing sender separately" do
      # "email is broken" and "the from address is unset" send an operator to
      # different places, so the two cases must not share a message.
      Application.put_env(:flux, :warn_unconfigured_mailer, true)
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.SMTP)
      Application.delete_env(:flux, :mail_from)

      log = capture_log(&Mailer.warn_if_unconfigured/0)

      assert log =~ "FLUX_MAIL_FROM_ADDRESS"
      refute log =~ "FLUX_SMTP_HOST"
    end

    test "says nothing when fully configured" do
      Application.put_env(:flux, :warn_unconfigured_mailer, true)
      Application.put_env(:flux, Flux.Mailer, adapter: Swoosh.Adapters.SMTP)
      Application.put_env(:flux, :mail_from, address: "no-reply@acme.test")

      assert capture_log(&Mailer.warn_if_unconfigured/0) == ""
    end
  end

  describe "sending without a configured sender" do
    test "reports an error rather than pretending to have sent" do
      # Returning :ok here is what made the original bug invisible.
      Application.delete_env(:flux, :mail_from)

      log =
        capture_log(fn ->
          assert {:error, :mailer_not_configured} =
                   Flux.Accounts.UserNotifier.deliver_update_email_instructions(
                     %Flux.Accounts.User{email: "someone@acme.test"},
                     "https://example.test/confirm"
                   )
        end)

      assert log =~ "FLUX_MAIL_FROM_ADDRESS"
    end
  end
end
