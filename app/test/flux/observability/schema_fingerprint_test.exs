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

    test "distinguishes boolean from number value types" do
      a = SchemaFingerprint.compute(%{"flag" => true})
      b = SchemaFingerprint.compute(%{"flag" => 1})
      refute a == b
    end

    test "distinguishes list, map, null and other value types" do
      tags = [
        %{"v" => [1, 2]},
        %{"v" => %{"nested" => 1}},
        %{"v" => nil},
        %{"v" => "s"},
        # an atom value falls through to the :other type tag
        %{"v" => :sym}
      ]

      fingerprints = Enum.map(tags, &SchemaFingerprint.compute/1)
      assert length(Enum.uniq(fingerprints)) == length(tags)
    end

    test "nested maps contribute only their :map type, not inner shape" do
      a = SchemaFingerprint.compute(%{"v" => %{"x" => 1}})
      b = SchemaFingerprint.compute(%{"v" => %{"y" => "different"}})
      assert a == b
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
