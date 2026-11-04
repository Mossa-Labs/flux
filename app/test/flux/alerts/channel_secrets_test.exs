defmodule Flux.Alerts.ChannelSecretsTest do
  use ExUnit.Case, async: true

  alias Flux.Alerts.ChannelSecrets
  alias Flux.Vault

  @slack_url "https://hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXX"
  @webhook_url "https://example.com/hooks/flux?token=s3cr3t-token"
  @key "R0123456789ABCDEF0123456789ABCDE"

  defp channels do
    [
      %{"type" => "email", "config" => %{"to" => "ops@example.com"}},
      %{"type" => "slack", "config" => %{"url" => @slack_url}},
      %{"type" => "webhook", "config" => %{"url" => @webhook_url}},
      %{
        "type" => "pagerduty",
        "config" => %{"routing_key" => @key, "severity" => "critical", "region" => "eu"}
      }
    ]
  end

  defp config(channels, type),
    do: Enum.find_value(channels, &(&1["type"] == type && &1["config"]))

  describe "secret_keys/1" do
    test "names the secret per channel type" do
      assert ChannelSecrets.secret_keys("slack") == ["url"]
      assert ChannelSecrets.secret_keys("webhook") == ["url"]
      assert ChannelSecrets.secret_keys(:pagerduty) == ["routing_key"]
      assert ChannelSecrets.secret_keys("email") == []
      assert ChannelSecrets.secret_keys("unknown") == []
    end
  end

  describe "encrypt/1 and decrypt/1" do
    test "encrypt only the secrets and round-trip" do
      encrypted = ChannelSecrets.encrypt(channels())
      dumped = inspect(encrypted)

      refute dumped =~ @slack_url
      refute dumped =~ "s3cr3t-token"
      refute dumped =~ @key

      assert %{"encrypted" => true} = config(encrypted, "slack")["url"]
      assert %{"encrypted" => true} = config(encrypted, "pagerduty")["routing_key"]
      assert config(encrypted, "email") == %{"to" => "ops@example.com"}
      assert config(encrypted, "pagerduty")["severity"] == "critical"

      assert ChannelSecrets.decrypt(encrypted) == channels()
    end

    test "encrypt is idempotent" do
      once = ChannelSecrets.encrypt(channels())
      assert ChannelSecrets.encrypt(once) == once
    end

    test "decrypt passes legacy plaintext through" do
      assert ChannelSecrets.decrypt(channels()) == channels()
    end

    test "a wrapper moved into a non-secret field is not decrypted" do
      wrapper = Vault.encrypt_value(@key)

      planted = [
        %{"type" => "email", "config" => %{"to" => wrapper}},
        %{"type" => "pagerduty", "config" => %{"routing_key" => "x", "severity" => wrapper}}
      ]

      decrypted = ChannelSecrets.decrypt(planted)
      assert config(decrypted, "email")["to"] == wrapper
      assert config(decrypted, "pagerduty")["severity"] == wrapper
      refute inspect(decrypted) =~ @key
    end

    test "tolerates malformed channels and non-lists" do
      odd = [%{"type" => "slack"}, %{"config" => %{"url" => @slack_url}}, "junk"]
      assert ChannelSecrets.encrypt(odd) == odd
      assert ChannelSecrets.decrypt(nil) == nil
    end
  end

  describe "redact/1" do
    test "masks every secret and keeps the rest" do
      redacted = ChannelSecrets.redact(channels())

      refute inspect(redacted) =~ @slack_url
      refute inspect(redacted) =~ "s3cr3t-token"
      refute inspect(redacted) =~ @key
      assert config(redacted, "slack")["url"] == "[REDACTED]"
      assert config(redacted, "pagerduty")["routing_key"] == "[REDACTED]"
      assert config(redacted, "pagerduty")["severity"] == "critical"
      assert config(redacted, "email")["to"] == "ops@example.com"
    end

    test "masks encrypted wrappers anywhere, including non-secret fields" do
      planted = [
        %{"type" => "email", "config" => %{"to" => Vault.encrypt_value(@key)}}
      ]

      assert [%{"config" => %{"to" => "[REDACTED]"}}] = ChannelSecrets.redact(planted)
    end

    test "leaves an absent secret absent" do
      assert [%{"config" => config}] =
               ChannelSecrets.redact([%{"type" => "slack", "config" => %{}}])

      refute Map.has_key?(config, "url")
    end
  end

  describe "stored?/2" do
    test "reads presence from redacted channels" do
      redacted = ChannelSecrets.redact(channels())

      assert ChannelSecrets.stored?(redacted, "slack")
      assert ChannelSecrets.stored?(redacted, :webhook)
      assert ChannelSecrets.stored?(redacted, "pagerduty")
    end

    test "is false for a missing channel, a blank secret or no secret type" do
      refute ChannelSecrets.stored?([], "slack")
      refute ChannelSecrets.stored?([%{"type" => "slack", "config" => %{"url" => ""}}], "slack")
      refute ChannelSecrets.stored?(channels(), "email")
      refute ChannelSecrets.stored?(nil, "slack")
    end
  end

  describe "merge_stored/2" do
    test "a new secret wins" do
      submitted = [%{"type" => "slack", "config" => %{"url" => "https://hooks.slack.com/new"}}]
      assert ChannelSecrets.merge_stored(submitted, channels()) == submitted
    end

    test "a missing, blank or redacted secret keeps the stored one" do
      for config <- [%{}, %{"url" => ""}, %{"url" => "  "}, %{"url" => "[REDACTED]"}] do
        assert [%{"config" => %{"url" => @slack_url}}] =
                 ChannelSecrets.merge_stored(
                   [%{"type" => "slack", "config" => config}],
                   channels()
                 )
      end
    end

    test "keeping a secret keeps stored non-secret config, with submitted values on top" do
      submitted = [%{"type" => "pagerduty", "config" => %{"severity" => "warning"}}]

      assert [%{"config" => config}] = ChannelSecrets.merge_stored(submitted, channels())
      assert config == %{"routing_key" => @key, "severity" => "warning", "region" => "eu"}
    end

    test "with nothing stored, a blank or redacted secret is dropped, never saved" do
      for config <- [%{"url" => ""}, %{"url" => "[REDACTED]"}] do
        assert [%{"type" => "slack", "config" => %{}}] =
                 ChannelSecrets.merge_stored([%{"type" => "slack", "config" => config}], [])
      end
    end

    test "omitting a channel type removes it" do
      submitted = [%{"type" => "email", "config" => %{"to" => "a@b.c"}}]
      assert ChannelSecrets.merge_stored(submitted, channels()) == submitted
    end
  end

  describe "scrub/2" do
    test "removes secrets from nested terms" do
      reason = {:error, %{"msg" => "scheme is required for url: #{@slack_url}", list: [@key]}}
      scrubbed = ChannelSecrets.scrub(reason, channels())

      refute inspect(scrubbed) =~ @slack_url
      refute inspect(scrubbed) =~ "XXXXXXXXXXXXXXXX"
      refute inspect(scrubbed) =~ @key
      assert inspect(scrubbed) =~ "[REDACTED]"
    end

    test "removes a URL's path and query even when the host is rendered differently" do
      message = "failed for HTTPS://HOOKS.SLACK.COM/services/T000/B000/XXXXXXXXXXXXXXXX"
      refute ChannelSecrets.scrub(message, channels()) =~ "XXXXXXXXXXXXXXXX"
    end

    test "is a no-op without secrets" do
      assert ChannelSecrets.scrub("boom", []) == "boom"
      assert ChannelSecrets.scrub("boom", nil) == "boom"
    end
  end
end
