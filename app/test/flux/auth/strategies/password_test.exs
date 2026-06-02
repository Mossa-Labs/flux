defmodule Flux.Auth.Strategies.PasswordTest do
  use Flux.DataCase, async: true

  alias Flux.Auth.Strategies.Password

  import Flux.AccountsFixtures

  test "returns {:ok, user} on valid credentials" do
    user = user_fixture() |> set_password()

    assert {:ok, returned} =
             Password.authenticate(%{"email" => user.email, "password" => valid_user_password()})

    assert returned.id == user.id
  end

  test "returns {:error, :invalid_credentials} on wrong password" do
    user = user_fixture() |> set_password()

    assert {:error, :invalid_credentials} =
             Password.authenticate(%{"email" => user.email, "password" => "wrong-password"})
  end

  test "returns {:error, :invalid_params} when params are malformed" do
    assert {:error, :invalid_params} = Password.authenticate(%{})
    assert {:error, :invalid_params} = Password.authenticate(%{"email" => "foo@example.com"})
  end

  test "name/0 returns :password" do
    assert Password.name() == :password
  end
end
