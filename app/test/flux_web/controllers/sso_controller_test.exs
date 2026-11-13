defmodule FluxWeb.SSOControllerTest do
  # async: false - swaps the global SSO registry and license provider.
  use FluxWeb.ConnCase, async: false

  import Flux.AccountsFixtures
  import Flux.LicenseHelpers
  import Phoenix.LiveViewTest

  alias Flux.Auth.SSO.Registry

  @remember_me_cookie "_flux_web_user_remember_me"

  setup do
    prior_license = put_license_tier(:enterprise)
    original = Registry.active()
    original_mfa = Flux.Accounts.MfaEnforcement.Registry.active()

    on_exit(fn ->
      reset_license(prior_license)
      Registry.set_active(original)
      Flux.Accounts.MfaEnforcement.Registry.set_active(original_mfa)
      Application.delete_env(:flux, :test_sso)
    end)

    Registry.set_active(Flux.SSOTestProvider)
    Application.put_env(:flux, :test_sso, %{test_pid: self()})
    :ok
  end

  defp put_sso(key, value) do
    Application.put_env(
      :flux,
      :test_sso,
      Map.put(Application.get_env(:flux, :test_sso, %{}), key, value)
    )
  end

  # start → IdP → ACS → complete, the way a browser does it: the ACS post comes
  # cross-site without the session cookie; complete comes back with it.
  defp sign_in_via_sso(conn, user) do
    put_sso(:consume, {:ok, user})

    conn = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})
    idp_url = redirected_to(conn, 302)
    %{"RelayState" => rid} = idp_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    acs = post(build_conn(), ~p"/sso/cfg_test/acs", %{"SAMLResponse" => "x", "RelayState" => rid})
    complete_path = redirected_to(acs, 302)

    conn |> recycle() |> get(complete_path)
  end

  describe "start" do
    test "sends the browser to the IdP with a short request ID as RelayState", %{conn: conn} do
      conn = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})

      assert "https://idp.acme.test/sso?" <> _ = redirected_to(conn, 302)
      assert_received {:sso, :authn_request, {"cfg_test", params}}
      assert params.relay_state == params.request_id
      assert byte_size(params.relay_state) <= 80
      assert params.request_id =~ ~r/\A_[0-9a-f]{40}\z/
      assert params.acs_url =~ ~r{/sso/cfg_test/acs\z}
      assert %{"request_id" => rid} = get_session(conn, :sso_pending)
      assert rid == params.request_id
    end

    test "an address with no SSO goes back to the sign-in page", %{conn: conn} do
      conn = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@elsewhere.test"}})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't set up"
      assert Phoenix.Flash.get(conn.assigns.flash, :email) == "pat@elsewhere.test"
    end

    test "unentitled, nothing is discovered", %{conn: conn} do
      put_license_tier(:community)
      conn = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})

      assert redirected_to(conn) == ~p"/users/log-in"
      refute_received {:sso, :authn_request, _}
    end
  end

  describe "the full round trip" do
    test "signs the user in with an SSO session and no remember-me cookie", %{conn: conn} do
      user = user_fixture()
      conn = sign_in_via_sso(conn, user)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
      assert get_session(conn, :login_method) == "sso"
      assert get_session(conn, :sso_pending) == nil
      refute conn.resp_cookies[@remember_me_cookie][:value]
      assert_received {:sso, :consume, {"cfg_test", %{request_id: rid}}}
      assert rid =~ ~r/\A_/
    end

    test "the ticket only works in the browser that started the sign-in", %{conn: conn} do
      user = user_fixture()
      put_sso(:consume, {:ok, user})

      started = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})

      %{"RelayState" => rid} =
        redirected_to(started) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      acs =
        post(build_conn(), ~p"/sso/cfg_test/acs", %{"SAMLResponse" => "x", "RelayState" => rid})

      # An attacker replays the hand-off in a different browser.
      victim = build_conn() |> init_test_session(%{}) |> get(redirected_to(acs))

      assert redirected_to(victim) == ~p"/users/log-in"
      refute get_session(victim, :user_token)
    end

    test "a ticket for a different sign-in attempt is refused", %{conn: conn} do
      user = user_fixture()
      put_sso(:consume, {:ok, user})

      started = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})

      acs =
        post(build_conn(), ~p"/sso/cfg_test/acs", %{
          "SAMLResponse" => "x",
          "RelayState" => "_other"
        })

      conn = started |> recycle() |> get(redirected_to(acs))

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "a pending attempt is single use", %{conn: conn} do
      user = user_fixture()
      conn = sign_in_via_sso(conn, user)

      # The pending attempt was consumed; replaying the same complete URL in the
      # same browser (now logged in) must not mint anything new.
      assert get_session(conn, :sso_pending) == nil
    end
  end

  describe "acs" do
    test "a rejected response never signs anyone in", %{conn: conn} do
      put_sso(:consume, {:error, :bad_signature})

      started = post(conn, ~p"/sso/start", %{"sso" => %{"email" => "pat@acme.test"}})

      %{"RelayState" => rid} =
        redirected_to(started) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      acs =
        post(build_conn(), ~p"/sso/cfg_test/acs", %{"SAMLResponse" => "x", "RelayState" => rid})

      assert redirected_to(acs) == ~p"/sso/complete?error=1"

      conn = started |> recycle() |> get(redirected_to(acs))
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't complete"
      refute get_session(conn, :user_token)
    end

    test "an unsolicited post with no RelayState is refused without consulting the provider" do
      acs = post(build_conn(), ~p"/sso/cfg_test/acs", %{"SAMLResponse" => "x"})

      assert redirected_to(acs) == ~p"/sso/complete?error=1"
      refute_received {:sso, :consume, _}
    end

    test "an oversized RelayState is refused" do
      acs =
        post(build_conn(), ~p"/sso/cfg_test/acs", %{
          "SAMLResponse" => "x",
          "RelayState" => String.duplicate("a", 81)
        })

      assert redirected_to(acs) == ~p"/sso/complete?error=1"
      refute_received {:sso, :consume, _}
    end

    test "a malformed config ID never reaches the provider" do
      acs =
        post(build_conn(), "/sso/bad%20id/acs", %{"SAMLResponse" => "x", "RelayState" => "_r"})

      assert redirected_to(acs) == ~p"/sso/complete?error=1"
      refute_received {:sso, :consume, _}
    end
  end

  describe "metadata" do
    test "serves SP metadata for a known configuration" do
      conn = get(build_conn(), ~p"/sso/cfg_test/metadata")

      assert response(conn, 200) =~ "/sso/cfg_test/acs"
      assert response_content_type(conn, :xml) =~ "application/samlmetadata+xml"
    end

    test "404s for anything else" do
      assert build_conn() |> get(~p"/sso/nope/metadata") |> response(404)
    end
  end

  describe "enforcement at the password and magic-link entry points" do
    test "an SSO-only member cannot sign in with a valid password", %{conn: conn} do
      user = user_fixture() |> set_password()
      put_sso(:sso_only, [user.id])

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "requires single sign-on"
      refute get_session(conn, :user_token)
    end

    test "a wrong password still reads as a wrong password", %{conn: conn} do
      user = user_fixture() |> set_password()
      put_sso(:sso_only, [user.id])

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "nope nope nope"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    test "an SSO-only member cannot sign in with a magic link", %{conn: conn} do
      user = user_fixture()
      put_sso(:sso_only, [user.id])
      {token, _hashed} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "requires single sign-on"
      refute get_session(conn, :user_token)
    end

    test "members SSO doesn't bind (owners, as break-glass) keep their password", %{conn: conn} do
      user = user_fixture() |> set_password()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert get_session(conn, :login_method) == "password"
    end

    test "after a lapsed license an SSO-only member can use their password again", %{conn: conn} do
      user = user_fixture() |> set_password()
      put_sso(:sso_only, [user.id])
      put_license_tier(:community)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
    end
  end

  describe "SSO sessions and Flux's own second factor" do
    setup do
      Flux.Accounts.MfaEnforcement.Registry.set_active(Flux.MfaEnforcementTestProvider)
      :ok
    end

    test "an SSO session is not sent to enrol in MFA", %{conn: conn} do
      user = user_fixture()
      conn = conn |> sign_in_via_sso(user) |> recycle()

      assert {:ok, _lv, _html} = live(conn, ~p"/dashboard")
    end

    test "a password session under the same policy is", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/users/settings"}}} =
               conn |> log_in_user(user) |> live(~p"/dashboard")
    end
  end
end
