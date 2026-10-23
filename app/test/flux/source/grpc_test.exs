defmodule Flux.Source.GRPCTest do
  use ExUnit.Case, async: true

  alias Flux.Source.GRPC

  test "uses the slugged channel" do
    assert GRPC.queue_name(%{"mode" => "server", "channel" => "orders"}) == "grpc.orders"
    assert GRPC.queue_name(%{"channel" => "EU Orders/v2"}) == "grpc.eu-orders-v2"
  end

  test "derives a client-mode channel from the method when none is set" do
    config = %{"mode" => "client", "method" => "/telemetry.v1.Telemetry/StreamReadings"}
    assert GRPC.queue_name(config) == "grpc.telemetry-v1-telemetry-streamreadings"

    assert GRPC.queue_name(Map.put(config, "channel", "")) ==
             "grpc.telemetry-v1-telemetry-streamreadings"
  end

  test "falls back to grpc.ingest without a usable channel" do
    assert GRPC.queue_name(%{}) == "grpc.ingest"
    assert GRPC.queue_name(%{"mode" => "server", "channel" => "///"}) == "grpc.ingest"
  end
end
