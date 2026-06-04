defmodule FluxWeb.AuthorizationTest do
  @moduledoc """
  Web-layer authorization for pipelines and sinks. The LiveView UI must enforce
  the same rules as the REST API:

    * role gating (MOS-524) — a viewer-role user can read but not mutate;
    * tenant isolation (MOS-528) — a crafted event id for another org's record
      is treated as not-found, even for a permitted role.
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

  # Tenant isolation (MOS-528): even with a permitted role, a crafted event id
  # for another organization's record must be treated as not-found.
  describe "cross-organization isolation" do
    setup :register_and_log_in_user

    defp other_org do
      Repo.insert!(%Organization{
        name: "Other",
        slug: "org-#{System.unique_integer([:positive])}"
      })
    end

    test "cannot delete another org's pipeline via a crafted id", %{conn: conn} do
      foreign = pipeline_fixture(other_org().id, %{name: "Theirs"})

      {:ok, lv, _html} = live(conn, ~p"/pipelines")
      render_click(lv, "delete", %{"id" => to_string(foreign.id)})

      assert Repo.reload(foreign)
    end

    test "cannot start another org's pipeline via a crafted id", %{conn: conn} do
      foreign = pipeline_fixture(other_org().id, %{name: "Theirs", status: "stopped"})

      {:ok, lv, _html} = live(conn, ~p"/pipelines")
      render_click(lv, "start", %{"id" => to_string(foreign.id)})

      assert Repo.reload(foreign).status == "stopped"
    end

    test "cannot delete another org's sink via a crafted id", %{conn: conn} do
      foreign = sink_fixture(other_org().id, %{name: "Theirs"})

      {:ok, lv, _html} = live(conn, ~p"/sinks")
      render_click(lv, "delete", %{"id" => to_string(foreign.id)})

      assert Repo.reload(foreign)
    end

    test "cannot toggle another org's sink via a crafted id", %{conn: conn} do
      foreign = sink_fixture(other_org().id, %{name: "Theirs", enabled: true})

      {:ok, lv, _html} = live(conn, ~p"/sinks")
      render_click(lv, "toggle", %{"id" => to_string(foreign.id)})

      assert Repo.reload(foreign).enabled == true
    end
  end
end
