defmodule Flux.RegistrationsTest do
  # async: false — mutates global queue config and the shared active-queue
  # registry entry; restores "memory" afterwards.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  alias Flux.Queue.Registry

  setup do
    prior_queue = Application.get_env(:flux, Flux.Queue)

    on_exit(fn ->
      if prior_queue,
        do: Application.put_env(:flux, Flux.Queue, prior_queue),
        else: Application.delete_env(:flux, Flux.Queue)

      # Leave the shared registry back on the default Community queue.
      Registry.set_active("memory")
    end)

    :ok
  end

  describe "seed_active_queue/0" do
    test "falls back to memory when an unlicensed Pro queue type is configured" do
      Application.put_env(:flux, Flux.Queue, type: "rabbitmq")

      assert :ok = Flux.Registrations.seed_active_queue()
      assert {:ok, Flux.Queue.Adapters.Memory} = Registry.active()
    end

    test "honors a licensed Pro queue type" do
      Application.put_env(:flux, Flux.Queue, type: "rabbitmq")

      with_license_tier(:pro, fn ->
        assert :ok = Flux.Registrations.seed_active_queue()
        # In a Community build "rabbitmq" maps to the Stub adapter; the point is
        # it did NOT fall back to memory now that the tier is entitled.
        assert {:ok, module} = Registry.active()
        refute module == Flux.Queue.Adapters.Memory
      end)
    end

    test "always honors the memory queue regardless of tier" do
      Application.put_env(:flux, Flux.Queue, type: "memory")

      assert :ok = Flux.Registrations.seed_active_queue()
      assert {:ok, Flux.Queue.Adapters.Memory} = Registry.active()
    end
  end
end
