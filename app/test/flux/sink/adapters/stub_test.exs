defmodule Flux.Sink.Adapters.StubTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Stub

  test "deliver/3 returns a pro_required tuple with feature atom" do
    config = %{"type" => "s3", "bucket" => "whatever"}
    assert {:error, {:pro_required, :s3_sink}} = Stub.deliver(%{"x" => 1}, config, [])
  end

  test "deliver/3 falls back to :pro_sink for unknown Pro types" do
    assert {:error, {:pro_required, :pro_sink}} =
             Stub.deliver(%{}, %{"type" => "something_new"}, [])
  end

  test "validate_config/1 surfaces an upgrade CTA string" do
    assert {:error, [msg]} = Stub.validate_config(%{"type" => "s3"})
    assert msg =~ "Flux Pro"
  end

  test "test_connection/1 also returns pro_required" do
    assert {:error, {:pro_required, :s3_sink}} = Stub.test_connection(%{"type" => "s3"})
  end
end
