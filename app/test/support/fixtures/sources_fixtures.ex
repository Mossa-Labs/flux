defmodule Flux.SourcesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Flux.Sources` context.
  """

  @doc """
  Insert a source.

  Inserts the struct directly instead of going through `Flux.Sources.create_source/1`,
  so Pro/EE source types (whose Community adapters are stubs that reject every
  config) can be stored. The `EncryptedConfig` type still runs on dump and load.
  """
  def source_fixture(organization_id, attrs \\ %{}) do
    attrs = Map.new(attrs)
    type = Map.get(attrs, :type, "sqs")

    Flux.Repo.insert!(%Flux.Sources.Source{
      name: Map.get(attrs, :name, "#{type}-#{System.unique_integer([:positive])}"),
      type: type,
      enabled: Map.get(attrs, :enabled, true),
      organization_id: organization_id,
      config: Map.get(attrs, :config, sqs_config())
    })
  end

  @doc """
  Insert an SQS source whose `secret_access_key` was encrypted under a
  different vault key, so it can't be decrypted on load.
  """
  def undecryptable_source_fixture(organization_id, attrs \\ %{}) do
    organization_id
    |> source_fixture(attrs)
    |> make_secret_undecryptable(["secret_access_key"])
  end

  @doc """
  Rewrites the stored secret at `path` in `source`'s config so it is encrypted
  under a different vault key, then reloads the source.

  Writes the raw `config` column directly, skipping the `EncryptedConfig` type,
  so no global vault key has to change and the test can stay async.
  """
  def make_secret_undecryptable(%Flux.Sources.Source{} = source, path) do
    import Ecto.Query, only: [from: 2]

    paths = Flux.Sources.Secrets.paths(source.config)

    raw_config =
      source.config
      |> Flux.Vault.encrypt_map(paths)
      |> put_in(path, Flux.SinksFixtures.foreign_encrypted_wrapper(get_in(source.config, path)))

    {1, _} =
      Flux.Repo.update_all(from(s in "sources", where: s.id == ^source.id),
        set: [config: raw_config]
      )

    Flux.Repo.get!(Flux.Sources.Source, source.id)
  end

  defp sqs_config do
    %{
      "queue_url" => "https://sqs.us-east-1.amazonaws.com/123456789012/events",
      "region" => "us-east-1",
      "auth_mode" => "static",
      "access_key_id" => "AKIAEXAMPLE",
      "secret_access_key" => "old-secret-key"
    }
  end
end
