defmodule Flux.Auth.Strategies.MagicLinkTest do
  use Flux.DataCase, async: true

  import Flux.AccountsFixtures

  alias Flux.Accounts
  alias Flux.Auth.Strategies.MagicLink

  describe "name/0" do
    test "identifies the strategy" do
      assert MagicLink.name() == :magic_link
    end
  end

  describe "authenticate/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

      %{user: user, token: token}
    end

    test "authenticates with a valid magic-link token", %{user: user, token: token} do
      assert {:ok, {authed, tokens_to_disconnect}} = MagicLink.authenticate(%{"token" => token})
      assert authed.id == user.id
      assert is_list(tokens_to_disconnect)
    end

    test "fails when the token has already been consumed", %{token: token} do
      # First use consumes (deletes) the one-time token.
      assert {:ok, _} = MagicLink.authenticate(%{"token" => token})
      # Second use can no longer find it.
      assert {:error, {:error, :not_found}} = MagicLink.authenticate(%{"token" => token})
    end

    test "rejects params without a token" do
      assert {:error, :invalid_params} = MagicLink.authenticate(%{})
      assert {:error, :invalid_params} = MagicLink.authenticate(%{"token" => 123})
    end

    test "rejects non-map params" do
      assert {:error, :invalid_params} = MagicLink.authenticate("nope")
    end
  end
end
