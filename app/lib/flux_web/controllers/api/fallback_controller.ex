defmodule FluxWeb.API.FallbackController do
  @moduledoc """
  Translates context/controller error tuples into consistent JSON responses
  for the API. Wired into API controllers via `action_fallback`.
  """
  use FluxWeb, :controller

  def call(conn, {:error, :not_found}) do
    error(conn, :not_found, "not_found", "Resource not found")
  end

  def call(conn, {:error, :unauthorized}) do
    error(conn, :unauthorized, "unauthorized", "Authentication is required")
  end

  def call(conn, {:error, :forbidden}) do
    error(conn, :forbidden, "forbidden", "You do not have permission to perform this action")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "unprocessable_entity", details: changeset_errors(changeset)})
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: code, message: message})
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &interpolate_error/1)
  end

  # Fills only the placeholders the message actually uses. Error opts can hold
  # values with no string form (e.g. a cast error's `type: {:parameterized, ...}`
  # or `{:array, :integer}`), so stringifying every opt would crash.
  defp interpolate_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
