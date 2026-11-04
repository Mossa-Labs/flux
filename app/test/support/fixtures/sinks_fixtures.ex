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

  @doc """
  Encrypts `value` into a vault wrapper under a key that is **not** the
  configured vault key, the way a row looks after a key rotation that missed
  it. `Flux.Vault` can't decrypt it.
  """
  def foreign_encrypted_wrapper(value) do
    base = "a-different-vault-key-#{System.unique_integer([:positive])}"
    aes = Plug.Crypto.KeyGenerator.generate(base, "flux.vault.aes256.v1", length: 32)
    sign = Plug.Crypto.KeyGenerator.generate(base, "flux.vault.sign.v1", length: 32)
    token = Plug.Crypto.MessageEncryptor.encrypt(Jason.encode!(value), aes, sign)
    %{"encrypted" => true, "ciphertext" => token}
  end

  @doc """
  Generate an HTTP sink whose bearer token was encrypted under a different
  vault key, so it can't be decrypted on load.
  """
  def undecryptable_sink_fixture(organization_id, attrs \\ %{}) do
    organization_id
    |> sink_fixture(
      Enum.into(attrs, %{
        config: %{
          "url" => "https://example.com/webhook",
          "method" => "POST",
          "auth" => %{"type" => "bearer", "token" => "old-token"}
        }
      })
    )
    |> make_secret_undecryptable(["auth", "token"])
  end

  @doc """
  Rewrites the stored secret at `path` in `sink`'s config so it is encrypted
  under a different vault key, then reloads the sink.

  Writes the raw `config` column directly, skipping the `EncryptedConfig` type,
  so no global vault key has to change and the test can stay async.
  """
  def make_secret_undecryptable(%Flux.Sinks.Sink{} = sink, path) do
    import Ecto.Query, only: [from: 2]

    paths = Flux.Sinks.Secrets.paths(sink.config)

    raw_config =
      sink.config
      |> Flux.Vault.encrypt_map(paths)
      |> put_in(path, foreign_encrypted_wrapper(get_in(sink.config, path)))

    {1, _} =
      Flux.Repo.update_all(from(s in "sinks", where: s.id == ^sink.id),
        set: [config: raw_config]
      )

    Flux.Repo.get!(Flux.Sinks.Sink, sink.id)
  end
end
