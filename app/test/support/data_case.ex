defmodule Flux.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Flux.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Flux.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Flux.DataCase
    end
  end

  setup tags do
    Flux.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Flux.Repo, shared: not tags[:async])

    on_exit(fn ->
      drain_api_key_usage()
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)
  end

  # ApiAuth casts an async `last_used_at` write to the app-wide ApiKeyUsage
  # GenServer on every authenticated request. In shared sandbox mode that write
  # runs on this test's connection, so if it is still in flight when the owner
  # stops, Postgrex logs a disconnect and the next test can inherit the race.
  # A sync call drains the mailbox while the connection is still alive.
  defp drain_api_key_usage do
    if Process.whereis(Flux.Accounts.ApiKeyUsage) do
      :sys.get_state(Flux.Accounts.ApiKeyUsage)
    end
  catch
    # The tracker restarting or stopping mid-call just means nothing to drain.
    :exit, _ -> :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
