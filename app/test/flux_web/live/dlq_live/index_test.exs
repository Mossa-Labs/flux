defmodule FluxWeb.DLQLive.IndexTest do
  # async: false — the :dlq gate swaps the global license provider.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.LicenseHelpers

  # Resolve the logged-in user to "owner" of their own org so the owner-only
  # gate passes (mirrors SystemSettingsLiveTest's setup).
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

  describe "owner on the community tier (DLQ not licensed)" do
    setup [:register_and_log_in_user, :make_owner]

    test "shows the heading and an upgrade prompt instead of message data", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/dlq")

      assert html =~ "Dead Letter Queue"
      assert html =~ "Dead-letter queue"
      assert html =~ "View pricing"
      refute html =~ "Messages in dead-letter queue"
    end
  end

  describe "owner on a licensed tier (:dlq entitled) without a Pro broker" do
    setup [:register_and_log_in_user, :make_owner]

    setup do
      state = put_license_tier(:pro)
      on_exit(fn -> reset_license(state) end)
      :ok
    end

    test "mounts without crashing and surfaces the unsupported-backend notice", %{conn: conn} do
      # The active adapter in test is Memory, which omits the DLQ callbacks, so
      # the facade returns {:error, {:pro_required, :dlq}} and the page degrades
      # gracefully rather than rendering the upgrade prompt or crashing.
      {:ok, _lv, html} = live(conn, ~p"/system/dlq")

      assert html =~ "Dead Letter Queue"
      assert html =~ "does not support dead-letter management"
      refute html =~ "View pricing"
    end
  end

  describe "unauthenticated access" do
    test "redirects to the login page", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/system/dlq")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
