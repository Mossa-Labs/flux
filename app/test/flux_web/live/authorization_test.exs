defmodule FluxWeb.AuthorizationTest do
  @moduledoc """
  Web-layer authorization parity (MOS-524): the LiveView UI must enforce the
  same `Flux.Permissions` rules as the REST API. A viewer-role user can read but
  must not be able to mutate pipelines or sinks.
  """
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.PipelinesFixtures
  import Flux.SinksFixtures

  alias Flux.Accounts
  alias Flux.AccountsFixtures
  alias Flux.Repo
  alias Flux.Structure.{Organization, Team, TeamMember}

  # Logs in a bare user with the given org role (team-centric: role comes from a
  # team membership in an org they do not own).
  defp log_in_role(conn, role) do
    {:ok, owner} = Accounts.register_user(AccountsFixtures.valid_user_attributes())

    org =
      Repo.insert!(%Organization{
        name: "Acme",
        slug: "org-#{System.unique_integer([:positive])}",
        user_id: owner.id
      })

    {:ok, actor} = Accounts.register_user(AccountsFixtures.valid_user_attributes())
    team = Repo.insert!(%Team{name: "Core", organization_id: org.id, user_id: owner.id})
    Repo.insert!(%TeamMember{team_id: team.id, user_id: actor.id, role: role})

    {log_in_user(conn, actor), org}
  end

  describe "viewer (read-only role)" do
    test "cannot delete a pipeline", %{conn: conn} do
      {conn, org} = log_in_role(conn, "viewer")
      pipeline = pipeline_fixture(org.id, %{name: "Keep me"})

      {:ok, lv, _html} = live(conn, ~p"/pipelines")

      html =
        lv
        |> element(~s|button[phx-click="delete"][phx-value-id="#{pipeline.id}"]|)
        |> render_click()

      assert html =~ "permission"
      assert Repo.reload(pipeline)
    end

    test "cannot start a pipeline", %{conn: conn} do
      {conn, org} = log_in_role(conn, "viewer")
      pipeline = pipeline_fixture(org.id, %{name: "Idle", status: "stopped"})

      {:ok, lv, _html} = live(conn, ~p"/pipelines")

      html =
        lv
        |> element(~s|button[phx-click="start"][phx-value-id="#{pipeline.id}"]|)
        |> render_click()

      assert html =~ "permission"
      assert Repo.reload(pipeline).status == "stopped"
    end

    test "does not see the New Pipeline control", %{conn: conn} do
      {conn, _org} = log_in_role(conn, "viewer")
      {:ok, _lv, html} = live(conn, ~p"/pipelines")
      refute html =~ "New Pipeline"
      refute html =~ "Create Pipeline"
    end

    test "cannot delete a sink", %{conn: conn} do
      {conn, org} = log_in_role(conn, "viewer")
      sink = sink_fixture(org.id, %{name: "Keep sink"})

      {:ok, lv, _html} = live(conn, ~p"/sinks")

      html =
        lv
        |> element(~s|button[phx-click="delete"][phx-value-id="#{sink.id}"]|)
        |> render_click()

      assert html =~ "permission"
      assert Repo.reload(sink)
    end

    test "does not see the New Sink control", %{conn: conn} do
      {conn, _org} = log_in_role(conn, "viewer")
      {:ok, _lv, html} = live(conn, ~p"/sinks")
      refute html =~ "New Sink"
    end
  end

  describe "owner (full access)" do
    setup :register_and_log_in_user

    test "sees the New Pipeline control", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines")
      assert html =~ "New Pipeline"
    end

    test "can delete a pipeline", %{conn: conn, scope: scope} do
      pipeline = pipeline_fixture(scope.organization_id, %{name: "Disposable"})

      {:ok, lv, _html} = live(conn, ~p"/pipelines")

      lv
      |> element(~s|button[phx-click="delete"][phx-value-id="#{pipeline.id}"]|)
      |> render_click()

      refute Repo.reload(pipeline)
    end
  end
end
