defmodule FluxWeb.UserLive.LoginSSOTest do
  # async: false - swaps the global SSO registry and license provider.
  use FluxWeb.ConnCase, async: false

  import Flux.AccountsFixtures
  import Flux.LicenseHelpers
  import Phoenix.LiveViewTest

  alias Flux.Accounts.UserToken
  alias Flux.Auth.SSO.Registry

  setup do
    prior_license =
      {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

    original = Registry.active()

    on_exit(fn ->
      reset_license(prior_license)
      Registry.set_active(original)
      Application.delete_env(:flux, :test_sso)
    end)

    :ok
  end

  defp use_sso(cfg) do
    put_license_tier(:enterprise)
    Application.put_env(:flux, :test_sso, cfg)
    Registry.set_active(Flux.SSOTestProvider)
  end

  test "no SSO panel on Community", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(lv, "#sso-login")
    assert has_element?(lv, "#login_form_password")
  end

  test "no SSO panel when entitled but nothing is configured", %{conn: conn} do
    use_sso(%{available: false})
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(lv, "#sso-login")
  end

  test "the SSO panel posts the work email to /sso/start", %{conn: conn} do
    use_sso(%{available: true})
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, ~s(#login_form_sso[action="/sso/start"]))
    assert has_element?(lv, "#login_form_sso input[name='sso[email]']")
    # Passwords and email links remain for everyone SSO doesn't bind.
    assert has_element?(lv, "#login_form_password")
    assert has_element?(lv, "#login_form_magic")
  end

  # New UI is custom Tailwind, not daisyUI component classes (CLAUDE.md). The
  # core <.input> inside the panel is the sanctioned exception.
  test "the SSO panel and its divider are styled without daisyUI components", %{conn: conn} do
    use_sso(%{available: true})
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(lv, "#sso-login.rounded-box")
    refute has_element?(lv, "#sso-login .btn")
    refute has_element?(lv, "#sso-login + .divider")
    # Restyled, not removed.
    assert has_element?(lv, "#login_form_sso button", "Continue with SSO")
    assert has_element?(lv, "#sso-login + #sso-login-divider", "or use a password or email link")
  end

  test "an SSO-only member gets no magic link, and the reply doesn't say why", %{conn: conn} do
    user = user_fixture()
    use_sso(%{available: true, sso_only: [user.id]})
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    {:ok, _lv, html} =
      lv
      |> form("#login_form_magic", user: %{email: user.email})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "If your email is in our system"
    refute Flux.Repo.get_by(UserToken, user_id: user.id, context: "login")
  end
end
