defmodule Flux.Repo do
  @moduledoc "Ecto repository for database access."
  use Ecto.Repo,
    otp_app: :flux,
    adapter: Ecto.Adapters.Postgres
end
