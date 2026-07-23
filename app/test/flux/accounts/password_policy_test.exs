defmodule Flux.Accounts.PasswordPolicyTest do
  # async: false — swaps the globally-registered active provider.
  use Flux.DataCase, async: false

  alias Flux.Accounts.PasswordPolicy
  alias Flux.Accounts.PasswordPolicy.Providers.Community
  alias Flux.Accounts.PasswordPolicy.Registry

  setup do
    # Restore whatever the boot-time registration set (the Community stub).
    previous = Registry.active()
    on_exit(fn -> Registry.set_active(previous) end)
    :ok
  end

  describe "Community provider (default)" do
    test "validate/2 is a no-op — leaves the base rules untouched" do
      changeset = Ecto.Changeset.change({%{}, %{password: :string}}, password: "shortish")
      assert Community.validate(changeset, 123) == changeset
    end

    test "expired?/1 never expires a password" do
      refute Community.expired?(%{organization_id: 1, user: %{}})
    end
  end

  describe "facade delegates to the active provider" do
    test "validate/2 routes through the registry" do
      Registry.set_active(Flux.PasswordPolicyTestProvider)
      Application.put_env(:flux, :test_password_policy, min_length: 20)
      on_exit(fn -> Application.delete_env(:flux, :test_password_policy) end)

      changeset = Ecto.Changeset.change({%{}, %{password: :string}}, password: "only-15-charsx")
      result = PasswordPolicy.validate(changeset, 1)
      refute result.valid?
      assert %{password: ["should be at least 20 character(s)"]} = errors_on(result)
    end

    test "expired?/1 routes through the registry" do
      Registry.set_active(Flux.PasswordPolicyTestProvider)
      Application.put_env(:flux, :test_password_policy, expired: true)
      on_exit(fn -> Application.delete_env(:flux, :test_password_policy) end)

      assert PasswordPolicy.expired?(%{organization_id: 1, user: %{}})
    end
  end

  describe "registry" do
    test "set_active/1 and active/0 round-trip" do
      Registry.set_active(Flux.PasswordPolicyTestProvider)
      assert Registry.active() == Flux.PasswordPolicyTestProvider

      Registry.set_active(Community)
      assert Registry.active() == Community
    end
  end
end
