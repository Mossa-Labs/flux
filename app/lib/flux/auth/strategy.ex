defmodule Flux.Auth.Strategy do
  @moduledoc """
  Contract for authentication strategies.

  A strategy takes credential-shaped params and returns either a `%User{}`
  (or richer tuple such as `{user, tokens_to_disconnect}` for magic-link)
  or an error. Community ships `Flux.Auth.Strategies.Password` and
  `Flux.Auth.Strategies.MagicLink`; the commercial edition adds SSO/SAML/OIDC
  strategies at boot.
  """

  alias Flux.Accounts.User

  @type params :: map()
  @type authenticated :: User.t() | {User.t(), list()}

  @callback name() :: atom()

  @callback authenticate(params()) :: {:ok, authenticated()} | {:error, term()}
end
