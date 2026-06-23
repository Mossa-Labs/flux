defmodule Flux.Observability.SchemaFingerprintTest do
  use ExUnit.Case, async: true

  alias Flux.Observability.SchemaFingerprint

  describe "compute/1" do
    test "is stable across key ordering" do
      a = SchemaFingerprint.compute(%{"id" => 1, "name" => "x", "ok" => true})
      b = SchemaFingerprint.compute(%{"ok" => true, "name" => "x", "id" => 1})
      assert a == b
    end

    test "ignores value contents, only value types matter" do
      a = SchemaFingerprint.compute(%{"id" => 1, "name" => "alice"})
      b = SchemaFingerprint.compute(%{"id" => 999, "name" => "bob"})
      assert a == b
    end

    test "collapses integers and floats to the same numeric type" do
      a = SchemaFingerprint.compute(%{"amount" => 10})
      b = SchemaFingerprint.compute(%{"amount" => 10.5})
      assert a == b
    end

    test "differs when a field is added" do
      a = SchemaFingerprint.compute(%{"id" => 1})
      b = SchemaFingerprint.compute(%{"id" => 1, "extra" => "new"})
      refute a == b
    end

    test "differs when a field is removed" do
      a = SchemaFingerprint.compute(%{"id" => 1, "name" => "x"})
      b = SchemaFingerprint.compute(%{"id" => 1})
      refute a == b
    end

    test "differs when a value type changes" do
      a = SchemaFingerprint.compute(%{"id" => 1})
      b = SchemaFingerprint.compute(%{"id" => "1"})
      refute a == b
    end

    test "treats atom and string keys identically" do
      assert SchemaFingerprint.compute(%{id: 1}) == SchemaFingerprint.compute(%{"id" => 1})
    end

    test "non-map payloads collapse to the empty fingerprint" do
      assert SchemaFingerprint.compute(nil) == SchemaFingerprint.compute("not a map")
    end
  end

  describe "field_count/1" do
    test "counts top-level fields" do
      assert SchemaFingerprint.field_count(%{"a" => 1, "b" => 2}) == 2
      assert SchemaFingerprint.field_count(%{}) == 0
      assert SchemaFingerprint.field_count(nil) == 0
    end
  end
end
