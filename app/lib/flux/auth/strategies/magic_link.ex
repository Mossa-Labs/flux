defmodule Flux.Auth.Strategies.MagicLink do
  @moduledoc """
  One-time magic-link authentication. Community default; shares the email +
  user-token infrastructure in `Flux.Accounts`.
  """

  @behaviour Flux.Auth.Strategy

  alias Flux.Accounts

  @impl Flux.Auth.Strategy
  def name, do: :magic_link

  @impl Flux.Auth.Strategy
  def authenticate(%{"token" => token}) when is_binary(token) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} -> {:ok, {user, tokens_to_disconnect}}
      other -> {:error, other}
    end
  end

  def authenticate(_), do: {:error, :invalid_params}
end
