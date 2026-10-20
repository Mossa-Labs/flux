defmodule Flux.Sink.Adapters.EmailTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  import Swoosh.TestAssertions

  alias Flux.Sink.Adapters.Email

  @base %{
    "provider" => "smtp",
    "host" => "smtp.example.com",
    "from" => "alerts@example.com",
    "to" => ["ops@example.com"],
    "subject" => "Order {order.id} failed"
  }

  @record %{"order" => %{"id" => "A-1"}, "error" => %{"message" => "<b>card declined</b>"}}

  use Flux.SinkConformance,
    adapter: Email,
    type: "email",
    valid_config: @base,
    invalid_configs: [
      %{},
      Map.delete(@base, "to"),
      Map.put(@base, "from", "alerts@@example.com"),
      Map.put(@base, "provider", "pigeon")
    ],
    # Captured by Swoosh.Adapters.Test in this environment.
    deliver_config: @base,
    test_connection_config: %{"provider" => "sendgrid", "api_key" => "k"}

  defp config(overrides), do: Map.merge(@base, overrides)

  # Each test gets its own rate-limit bucket so async tests don't share one.
  defp opts, do: [sink_id: System.unique_integer([:positive])]

  describe "validate_config/1" do
    test "accepts a minimal SMTP config" do
      assert :ok = Email.validate_config(@base)
    end

    test "requires a known provider" do
      assert {:error, errors} = Email.validate_config(Map.delete(@base, "provider"))
      assert "provider is required" in errors

      assert {:error, [msg | _]} = Email.validate_config(config(%{"provider" => "pigeon"}))
      assert msg =~ "provider must be one of"
    end

    test "requires from, to and subject" do
      assert {:error, errors} =
               Email.validate_config(%{"provider" => "smtp", "host" => "smtp.example.com"})

      assert "from address is required" in errors
      assert "to must include at least one recipient" in errors
      assert "subject is required" in errors
    end

    test "from is optional for the system provider" do
      assert :ok = Email.validate_config(config(%{"provider" => "system"}) |> Map.delete("from"))
    end

    test "rejects a malformed from and reply_to, naming the value" do
      assert {:error, errors} =
               Email.validate_config(config(%{"from" => "alerts@localhost", "reply_to" => "x"}))

      assert Enum.any?(errors, &(&1 =~ ~s(from: "alerts@localhost")))
      assert Enum.any?(errors, &(&1 =~ ~s(reply_to: "x")))
    end

    test "names every bad recipient" do
      assert {:error, [msg]} =
               Email.validate_config(config(%{"to" => ["ok@example.com", "bob@@x.com"]}))

      assert msg =~ "to:"
      assert msg =~ ~s("bob@@x.com")
      refute msg =~ "ok@example.com"
    end

    test "accepts recipients as a comma-separated string" do
      assert :ok = Email.validate_config(config(%{"to" => "a@example.com, b@example.com"}))
    end

    test "caps the total number of recipients" do
      many = for i <- 1..30, do: "user#{i}@example.com"

      assert {:error, [msg]} = Email.validate_config(config(%{"to" => many, "cc" => many}))
      assert msg =~ "at most 50 recipients"
    end

    test "rejects a from_name with a line break or that is too long" do
      assert {:error, [_]} = Email.validate_config(config(%{"from_name" => "Ops\r\nBcc: x"}))

      assert {:error, [_]} =
               Email.validate_config(config(%{"from_name" => String.duplicate("a", 79)}))
    end

    test "SMTP: host is required and must not be a URL" do
      assert {:error, ["host is required"]} = Email.validate_config(Map.delete(@base, "host"))

      assert {:error, [msg]} =
               Email.validate_config(config(%{"host" => "smtp://mail.example.com"}))

      assert msg =~ "no scheme"
    end

    test "SMTP: port, security and auth" do
      assert {:error, [_]} = Email.validate_config(config(%{"port" => 70_000}))
      assert {:error, [_]} = Email.validate_config(config(%{"security" => "maybe"}))

      assert {:error, ["password is required when a username is set"]} =
               Email.validate_config(config(%{"username" => "mailer"}))

      assert :ok =
               Email.validate_config(
                 config(%{
                   "port" => 465,
                   "security" => "ssl",
                   "username" => "u",
                   "password" => "p"
                 })
               )
    end

    test "API providers require their credentials" do
      assert {:error, ["api_key is required"]} =
               Email.validate_config(config(%{"provider" => "sendgrid"}))

      assert {:error, errors} = Email.validate_config(config(%{"provider" => "mailgun"}))
      assert "api_key is required" in errors
      assert "domain is required" in errors

      assert {:error, errors} = Email.validate_config(config(%{"provider" => "amazon_ses"}))
      assert "secret_access_key is required" in errors

      assert {:error, [_]} =
               Email.validate_config(
                 config(%{
                   "provider" => "mailgun",
                   "api_key" => "k",
                   "domain" => "mg.x.com",
                   "region" => "mars"
                 })
               )
    end

    test "rate_limit bounds" do
      assert :ok = Email.validate_config(config(%{"rate_limit" => %{"max_per_minute" => 10}}))

      assert {:error, [msg]} =
               Email.validate_config(config(%{"rate_limit" => %{"max_per_minute" => 0}}))

      assert msg =~ "rate_limit.max_per_minute"
    end
  end

  describe "build_email/2" do
    test "fills the subject from the record and sets the envelope" do
      email =
        Email.build_email(
          @record,
          config(%{
            "from_name" => "Alerts",
            "cc" => ["lead@example.com"],
            "bcc" => ["audit@example.com"],
            "reply_to" => "help@example.com"
          })
        )

      assert email.subject == "Order A-1 failed"
      assert email.from == {"Alerts", "alerts@example.com"}
      assert email.to == [{"", "ops@example.com"}]
      assert email.cc == [{"", "lead@example.com"}]
      assert email.bcc == [{"", "audit@example.com"}]
      assert email.reply_to == {"", "help@example.com"}
      assert email.headers["Auto-Submitted"] == "auto-generated"
    end

    test "HTML + text bodies make a multipart email, escaping only the HTML part" do
      email =
        Email.build_email(
          @record,
          config(%{
            "html_body" => "<p>{error.message}</p>",
            "text_body" => "Failed: {error.message}"
          })
        )

      assert email.html_body == "<p>&lt;b&gt;card declined&lt;/b&gt;</p>"
      assert email.text_body == "Failed: <b>card declined</b>"
    end

    test "an HTML-only template gets a plain-text part derived from it" do
      email =
        Email.build_email(
          @record,
          config(%{"html_body" => "<h1>Order {order.id}</h1><p>{error.message}</p>"})
        )

      assert email.text_body == "Order A-1\n<b>card declined</b>"
    end

    test "with no body template the record is sent as JSON" do
      email = Email.build_email(@record, @base)

      assert email.html_body == nil
      assert Jason.decode!(email.text_body) == @record
    end

    test "a subject cannot inject headers through record data" do
      email =
        Email.build_email(%{"order" => %{"id" => "1\r\nBcc: evil@example.com"}}, @base)

      refute email.subject =~ "\n"
      refute email.subject =~ "\r"
    end
  end

  describe "swoosh_config/1" do
    test "SMTP with STARTTLS verifies the server certificate" do
      {:ok, cfg} = Email.swoosh_config(config(%{"username" => "u", "password" => "p"}))

      assert cfg[:adapter] == Swoosh.Adapters.SMTP
      assert cfg[:relay] == "smtp.example.com"
      assert cfg[:port] == 587
      assert cfg[:tls] == :always
      assert cfg[:ssl] == false
      assert cfg[:auth] == :always
      assert cfg[:username] == "u"
      assert cfg[:no_mx_lookups] == true
      assert cfg[:tls_options][:verify] == :verify_peer
      assert cfg[:tls_options][:server_name_indication] == ~c"smtp.example.com"
    end

    test "SMTP over implicit SSL defaults to port 465" do
      {:ok, cfg} = Email.swoosh_config(config(%{"security" => "ssl"}))

      assert cfg[:port] == 465
      assert cfg[:ssl] == true
      assert cfg[:sockopts][:verify] == :verify_peer
    end

    test "SMTP without a username sends no credentials" do
      {:ok, cfg} = Email.swoosh_config(@base)

      assert cfg[:auth] == :never
      refute Keyword.has_key?(cfg, :username)
      refute Keyword.has_key?(cfg, :password)
    end

    test "SMTP can skip certificate verification when explicitly asked" do
      {:ok, cfg} = Email.swoosh_config(config(%{"tls_verify" => false}))
      assert cfg[:tls_options] == [verify: :verify_none]
    end

    test "SMTP against an IP address sends no SNI" do
      {:ok, cfg} = Email.swoosh_config(config(%{"host" => "10.0.0.5"}))
      refute Keyword.has_key?(cfg[:tls_options], :server_name_indication)
    end

    test "API providers get only their own credentials" do
      assert {:ok, [adapter: Swoosh.Adapters.Sendgrid, api_key: "sg"]} =
               Email.swoosh_config(%{"provider" => "sendgrid", "api_key" => "sg"})

      assert {:ok, [adapter: Swoosh.Adapters.Postmark, api_key: "pm"]} =
               Email.swoosh_config(%{"provider" => "postmark", "api_key" => "pm"})

      {:ok, mailgun} =
        Email.swoosh_config(%{
          "provider" => "mailgun",
          "api_key" => "mg",
          "domain" => "mg.x.com",
          "region" => "eu"
        })

      assert mailgun[:base_url] == "https://api.eu.mailgun.net/v3"
      assert mailgun[:domain] == "mg.x.com"

      {:ok, ses} =
        Email.swoosh_config(%{
          "provider" => "amazon_ses",
          "region" => "eu-west-1",
          "access_key" => "AKIA",
          "secret_access_key" => "shh"
        })

      assert ses[:secret] == "shh"
      assert ses[:region] == "eu-west-1"
    end

    test "an API provider's base_url can be overridden" do
      {:ok, cfg} =
        Email.swoosh_config(%{
          "provider" => "sendgrid",
          "api_key" => "k",
          "base_url" => "http://localhost:4010"
        })

      assert cfg[:base_url] == "http://localhost:4010"
    end
  end

  describe "deliver/3" do
    test "sends the email" do
      assert :ok = Email.deliver(@record, @base, opts())

      assert_email_sent(fn email ->
        assert email.subject == "Order A-1 failed"
        assert email.to == [{"", "ops@example.com"}]
      end)
    end

    test "the system provider sends as the operator's configured sender" do
      config = @base |> Map.delete("from") |> Map.put("provider", "system")

      assert :ok = Email.deliver(@record, config, opts())

      assert_email_sent(fn email ->
        assert email.from == {"Flux", "flux@test.local"}
      end)
    end

    test "over the rate limit with no wait, the record is dropped" do
      config = config(%{"rate_limit" => %{"max_per_minute" => 1, "max_wait_ms" => 0}})
      opts = opts()

      assert :ok = Email.deliver(@record, config, opts)
      assert {:error, :rate_limited} = Email.deliver(@record, config, opts)

      assert_email_sent()
      refute_email_sent()
    end

    test "over the rate limit, a record waits for the next window" do
      config =
        config(%{
          "rate_limit" => %{"max_per_minute" => 1, "max_wait_ms" => 5_000, "window_ms" => 100}
        })

      opts = opts()

      assert :ok = Email.deliver(@record, config, opts)
      assert :ok = Email.deliver(@record, config, opts)
    end

    test "only one window's worth of records wait; the rest are dropped at once" do
      # max_per_minute 1 allows one waiting record. Occupy that slot as a
      # waiting task would, then confirm the next over-limit record is dropped
      # immediately rather than parking for max_wait_ms.
      config =
        config(%{
          "rate_limit" => %{"max_per_minute" => 1, "max_wait_ms" => 30_000, "window_ms" => 60_000}
        })

      opts = opts()
      key = {:email_sink, opts[:sink_id]}

      assert :ok = Email.deliver(@record, config, opts)
      assert Flux.RateLimiter.acquire(key, 1)

      {micros, result} = :timer.tc(fn -> Email.deliver(@record, config, opts) end)

      assert result == {:error, :rate_limited}
      assert micros < 1_000_000

      Flux.RateLimiter.release(key)
    end

    test "a waiting record frees its slot when it finishes" do
      config =
        config(%{
          "rate_limit" => %{"max_per_minute" => 1, "max_wait_ms" => 5_000, "window_ms" => 100}
        })

      opts = opts()
      key = {:email_sink, opts[:sink_id]}

      assert :ok = Email.deliver(@record, config, opts)
      assert :ok = Email.deliver(@record, config, opts)

      # The waiter released its slot, so the gauge is free again.
      assert Flux.RateLimiter.acquire(key, 1)
      Flux.RateLimiter.release(key)
    end

    test "sinks have independent rate-limit budgets" do
      config = config(%{"rate_limit" => %{"max_per_minute" => 1, "max_wait_ms" => 0}})

      assert :ok = Email.deliver(@record, config, opts())
      assert :ok = Email.deliver(@record, config, opts())
    end
  end

  describe "test_connection/1" do
    test "API providers have no probe and report ok" do
      assert :ok = Email.test_connection(%{"provider" => "sendgrid", "api_key" => "k"})
    end

    test "the system provider reports the mailer is not configured in test" do
      assert {:error, :mailer_not_configured} = Email.test_connection(%{"provider" => "system"})
    end

    test "SMTP reports an unreachable server as an error" do
      assert {:error, _} =
               Email.test_connection(
                 config(%{"host" => "127.0.0.1", "port" => 1, "security" => "none"})
               )
    end
  end
end
