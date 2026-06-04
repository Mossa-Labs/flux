defmodule Flux.Accounts.ApiKeyUsage do
  @moduledoc """
  Records API-key usage (`last_used_at`) off the request path.

  `ApiAuth` casts `touch/1` after a successful authentication so the DB write
  never adds latency to the API call. Best-effort: a dropped message just means
  a slightly stale `last_used_at`.
  """

  use GenServer

  alias Flux.Accounts

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Asynchronously stamp `last_used_at` for the given API key id."
  def touch(api_key_id) do
    GenServer.cast(__MODULE__, {:touch, api_key_id})
  end

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_cast({:touch, api_key_id}, state) do
    # Best-effort: never let a usage write crash the tracker (or block a request).
    try do
      Accounts.touch_api_key(api_key_id)
    rescue
      _ -> :ok
    end

    {:noreply, state}
  end
end
