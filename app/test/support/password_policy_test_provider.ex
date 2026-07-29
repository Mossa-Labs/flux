defmodule Flux.PasswordPolicyTestProvider do
  @moduledoc """
  Test-only password policy provider for exercising the enforcement seam here.
  The real Enterprise provider is supplied at runtime by the commercial edition.

  Behaviour is driven by `config :flux, :test_password_policy`, a keyword list:

    * `:min_length` - when set, adds `validate_length(min: ...)` to the changeset.
    * `:expired` - when `true`, `expired?/1` returns true.

  Swap it in with `Flux.Accounts.PasswordPolicy.Registry.set_active/1` and restore
  the Community provider afterwards (so the test must be `async: false`).
  """

  @behaviour Flux.Accounts.PasswordPolicy.Provider

  import Ecto.Changeset

  @impl true
  def validate(changeset, _organization_id) do
    case config()[:min_length] do
      min when is_integer(min) -> validate_length(changeset, :password, min: min)
      _ -> changeset
    end
  end

  @impl true
  def expired?(_scope), do: config()[:expired] == true

  defp config, do: Application.get_env(:flux, :test_password_policy, [])
end
