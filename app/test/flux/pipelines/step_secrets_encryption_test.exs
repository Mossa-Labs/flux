defmodule Flux.Pipelines.StepSecretsEncryptionTest do
  @moduledoc """
  End-to-end coverage for encrypting the builder's source credentials in
  `pipelines.steps` and `pipeline_versions.steps` at rest (MOS-654).
  """
  use Flux.DataCase

  alias Flux.Pipelines
  alias Flux.Pipelines.StepSecrets
  alias Flux.Repo
  alias Flux.Vault.Backfill

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  @sftp %{
    "type" => "sftp",
    "host" => "sftp.example.com",
    "username" => "flux",
    "password" => "hunter2",
    "privateKey" => "-----BEGIN OPENSSH PRIVATE KEY-----",
    "passphrase" => ""
  }

  @sqs %{
    "type" => "sqs",
    "queueUrl" => "https://sqs.us-east-1.amazonaws.com/1/q",
    "accessKeyId" => "AKIA123",
    "secretAccessKey" => "aws-secret"
  }

  defp steps do
    %{
      "version" => "1.0",
      "steps" => [%{"type" => "native", "operation" => "map"}],
      "nodes" => [
        %{"id" => "src-a", "type" => "source", "sourceConfig" => @sftp},
        %{"id" => "map", "type" => "transform", "config" => %{"password" => "not-a-source"}},
        %{"id" => "src-b", "type" => "source", "sourceConfig" => @sqs}
      ],
      "edges" => []
    }
  end

  defp raw_steps(table, id) do
    %{rows: [[steps]]} = Repo.query!("SELECT steps FROM #{table} WHERE id = $1", [id])
    steps
  end

  defp raw_version_steps(pipeline_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT steps FROM pipeline_versions WHERE pipeline_id = $1 ORDER BY version",
        [pipeline_id]
      )

    Enum.map(rows, &hd/1)
  end

  defp source_config(steps, index),
    do: steps |> Map.fetch!("nodes") |> Enum.at(index) |> Map.fetch!("sourceConfig")

  test "only source-node credentials are ciphertext on disk", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: steps()})
    raw = raw_steps("pipelines", pipeline.id)

    a = source_config(raw, 0)
    assert %{"encrypted" => true} = a["password"]
    assert %{"encrypted" => true} = a["privateKey"]
    # Blank credentials stay blank; non-secret fields stay plaintext.
    assert a["passphrase"] == ""
    assert a["host"] == "sftp.example.com"
    assert a["username"] == "flux"

    b = source_config(raw, 2)
    assert %{"encrypted" => true} = b["secretAccessKey"]
    assert b["accessKeyId"] == "AKIA123"

    # A non-source node is not part of the taxonomy, even with a "password" key.
    assert Enum.at(raw["nodes"], 1)["config"]["password"] == "not-a-source"
    assert raw["steps"] == steps()["steps"]
  end

  test "loaded pipelines see plaintext", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: steps()})

    assert Pipelines.get_pipeline(pipeline.id, org_id).steps == steps()
    assert Pipelines.get_pipeline!(pipeline.id).steps == steps()
  end

  test "version snapshots are encrypted too, and rollback restores plaintext", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: steps()})

    {:ok, pipeline} =
      Pipelines.update_pipeline(pipeline, %{steps: put_in(steps(), ["steps"], [])})

    for raw <- raw_version_steps(pipeline.id), raw["nodes"] do
      assert %{"encrypted" => true} = source_config(raw, 0)["password"]
    end

    [first | _] = Pipelines.list_pipeline_versions(pipeline.id)
    {:ok, rolled_back} = Pipelines.rollback_pipeline(pipeline, first.version)

    assert source_config(rolled_back.steps, 0)["password"] == "hunter2"

    assert %{"encrypted" => true} =
             source_config(raw_steps("pipelines", pipeline.id), 0)["password"]
  end

  test "redaction and export still hide credentials", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: steps()})
    loaded = Pipelines.get_pipeline(pipeline.id, org_id)

    redacted = StepSecrets.redact(loaded.steps)
    assert source_config(redacted, 0)["password"] == "[REDACTED]"
    assert source_config(redacted, 2)["secretAccessKey"] == "[REDACTED]"

    stripped = StepSecrets.strip(loaded.steps)
    refute Map.has_key?(source_config(stripped, 0), "password")
  end

  test "legacy steps without nodes round-trip untouched", %{org_id: org_id} do
    legacy = %{"version" => "1.0", "steps" => [%{"type" => "native", "operation" => "map"}]}
    pipeline = pipeline_fixture(org_id, %{steps: legacy})

    assert raw_steps("pipelines", pipeline.id) == legacy
    assert Pipelines.get_pipeline(pipeline.id, org_id).steps == legacy
  end

  test "backfill encrypts legacy plaintext rows in both tables and reverses", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: steps()})

    # Force pre-encryption (plaintext) rows, as written before MOS-654.
    Repo.query!("UPDATE pipelines SET steps = $1 WHERE id = $2", [steps(), pipeline.id])

    Repo.query!("UPDATE pipeline_versions SET steps = $1 WHERE pipeline_id = $2", [
      steps(),
      pipeline.id
    ])

    for table <- ~w(pipelines pipeline_versions) do
      assert Backfill.run(Repo, table, "steps", StepSecrets, :encrypt) >= 1
    end

    assert %{"encrypted" => true} =
             source_config(raw_steps("pipelines", pipeline.id), 0)["password"]

    for raw <- raw_version_steps(pipeline.id),
        do: assert(%{"encrypted" => true} = source_config(raw, 2)["secretAccessKey"])

    for table <- ~w(pipelines pipeline_versions) do
      assert Backfill.run(Repo, table, "steps", StepSecrets, :decrypt) >= 1
    end

    assert raw_steps("pipelines", pipeline.id) == steps()
    assert Enum.all?(raw_version_steps(pipeline.id), &(&1 == steps()))
  end
end
