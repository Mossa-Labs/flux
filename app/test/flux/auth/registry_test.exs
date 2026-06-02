defmodule Flux.Auth.RegistryTest do
  use ExUnit.Case, async: false

  alias Flux.Auth.Registry

  test "password and magic_link strategies are registered at boot" do
    assert {:ok, Flux.Auth.Strategies.Password} = Registry.lookup(:password)
    assert {:ok, Flux.Auth.Strategies.MagicLink} = Registry.lookup(:magic_link)
  end

  test "unknown strategies return :unknown_strategy" do
    assert {:error, :unknown_strategy} = Registry.lookup(:saml)
  end

  test "list/0 includes Community strategies" do
    names = Registry.list()
    assert :password in names
    assert :magic_link in names
  end
end
