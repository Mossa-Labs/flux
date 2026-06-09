defmodule Flux.Pipeline.ManagerTest do
  # async: true keeps the sandbox in per-owner (manual) mode, so the Manager
  # process — which owns no connection — fails its auto-start query. That's
  # exactly the boot condition we're guarding against.
  use Flux.DataCase, async: true

  test "auto-start tolerates an unavailable database without crashing the Manager" do
    manager = Process.whereis(Flux.Pipeline.Manager)
    assert is_pid(manager)
    ref = Process.monitor(manager)

    # Re-run boot auto-start. This test process owns the sandbox connection, not
    # the Manager, so its `list_active_pipelines/0` query raises. The Manager
    # must survive (and retry) rather than crash — a crash-loop here would breach
    # the supervisor's restart intensity and take down Flux.Repo / the Endpoint.
    send(manager, :auto_start)

    refute_receive {:DOWN, ^ref, :process, ^manager, _reason}, 300
    assert Process.alive?(manager)
  end
end
