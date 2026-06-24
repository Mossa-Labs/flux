defmodule Flux.Pipelines.PipelineTest do
  use ExUnit.Case, async: true

  alias Flux.Pipelines.Pipeline

  @valid %{
    name: "orders",
    source_queue: "orders.in",
    organization_id: 1
  }

  describe "changeset/2 — required fields & inclusion" do
    test "is valid with name, source_queue and organization_id" do
      assert %Ecto.Changeset{valid?: true} = Pipeline.changeset(%Pipeline{}, @valid)
    end

    test "requires name, source_queue and organization_id" do
      changeset = Pipeline.changeset(%Pipeline{}, %{})

      assert %{
               name: ["can't be blank"],
               source_queue: ["can't be blank"],
               organization_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "accepts a valid status" do
      for status <- ~w(active paused stopped) do
        changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :status, status))
        assert changeset.valid?, "expected status #{status} to be valid"
      end
    end

    test "rejects an invalid status" do
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :status, "bogus"))
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 — steps validation" do
    test "accepts an empty map" do
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, %{}))
      assert changeset.valid?
    end

    test "accepts {version, steps:list}" do
      steps = %{"version" => "1.0", "steps" => []}
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, steps))
      assert changeset.valid?
    end

    test "accepts {version, steps, nodes}" do
      steps = %{"version" => "1.0", "steps" => [], "nodes" => []}
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, steps))
      assert changeset.valid?
    end

    test "accepts {version, steps, nodes, edges}" do
      steps = %{"version" => "1.0", "steps" => [], "nodes" => [], "edges" => []}
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, steps))
      assert changeset.valid?
    end

    test "accepts an arbitrary map (the catch-all format clause is permissive)" do
      # The `validate_steps_format(%{})` clause matches any map, so a map without
      # version/steps keys is currently accepted by the changeset.
      steps = %{"foo" => "bar"}
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, steps))
      assert changeset.valid?
    end

    test "rejects steps that cannot be cast to a map" do
      changeset = Pipeline.changeset(%Pipeline{}, Map.put(@valid, :steps, "nope"))
      assert %{steps: ["is invalid"]} = errors_on(changeset)
    end
  end

  # Local copy of the standard DataCase helper — this schema test needs no DB.
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
