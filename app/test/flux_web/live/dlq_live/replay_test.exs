defmodule FluxWeb.DLQLive.ReplayTest.FakeDLQAdapter do
  @moduledoc """
  Minimal DLQ-capable `Flux.Queue.Adapter` double so the DLQ LiveView renders its
  full (entitled + supported) surface in tests without a live broker.
  """
  @behaviour Flux.Queue.Adapter

  @message %{
    delivery_tag: "tag-1",
    original_queue: "events.a",
    source: "webhook",
    reason: "rejected",
    timestamp: ~U[2026-06-01 00:00:00Z],
    payload: %{"event" => "user.created"}
  }

  def message, do: @message

  @impl true
  def list_dlq_messages(_count, _offset), do: {:ok, [@message]}

  @impl true
  def get_dlq_depth, do: {:ok, 1}

  @impl true
  def retry_message(_delivery_tag), do: :ok

  @impl true
  def discard_message(_delivery_tag), do: :ok

  @impl true
  def replay_dlq(_filters, _limit), do: {:ok, %{replayed: 1, skipped: 0, exhausted?: true}}

  @impl true
  def publish(_queue, _message, _opts), do: :ok

  @impl true
  def ack(_message), do: :ok

  @impl true
  def reject(_message, _requeue), do: :ok
end

defmodule FluxWeb.DLQLive.ReplayTest do
  # async: false — both the :dlq license gate and the active-adapter swap mutate
  # global state.
  use FluxWeb.ConnCase, async: false
  use Oban.Testing, repo: Flux.Repo

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.LicenseHelpers

  alias Flux.Queue.Registry
  alias Flux.Workers.ReplayWorker
  alias FluxWeb.DLQLive.ReplayTest.FakeDLQAdapter

  defp make_owner(%{user: user}) do
    org =
      Flux.Structure.Organization
      |> where([o], o.user_id == ^user.id)
      |> order_by([o], asc: o.inserted_at)
      |> limit(1)
      |> Flux.Repo.one!()

    owner_scope = %Flux.Accounts.Scope{
      user: user,
      organization_id: org.id,
      organization_role: "owner"
    }

    {:ok, _team} = Flux.Structure.create_team(owner_scope, %{name: "Default Team"})
    :ok
  end

  describe "owner with a DLQ-capable adapter (:dlq entitled)" do
    setup [:register_and_log_in_user, :make_owner]

    setup do
      state = put_license_tier(:pro)
      Registry.register("fake_dlq", FakeDLQAdapter)
      Registry.set_active("fake_dlq")

      on_exit(fn ->
        reset_license(state)
        Registry.set_active("memory")
      end)

      :ok
    end

    test "renders the filter bar, message rows and replay controls", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/dlq")

      assert html =~ ~s(id="dlq-filters")
      assert html =~ "events.a"
      assert html =~ "webhook"
      assert html =~ "Replay all (filtered)"
      refute html =~ "does not support dead-letter management"
    end

    test "selecting a row reveals the 'Replay selected' action", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/dlq")

      refute render(lv) =~ "Replay selected"

      html =
        lv
        |> element(~s(input[type="checkbox"][phx-value-tag="tag-1"]))
        |> render_click()

      assert html =~ "Replay selected"
    end

    test "'Replay all (filtered)' enqueues a ReplayWorker job and shows progress", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/dlq")

      html =
        lv
        |> element("button", "Replay all (filtered)")
        |> render_click()

      assert html =~ "Bulk replay started."
      assert_enqueued(worker: ReplayWorker)
    end
  end
end
