defmodule Flux.Auth.Strategies.Password do
  @moduledoc """
  Email + password authentication (Argon2-hashed). Community default.
  """

  @behaviour Flux.Auth.Strategy

  alias Flux.Accounts

  @impl Flux.Auth.Strategy
  def name, do: :password

  @impl Flux.Auth.Strategy
  def authenticate(%{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil -> {:error, :invalid_credentials}
      user -> {:ok, user}
    end
  end

  def authenticate(_), do: {:error, :invalid_params}
end
