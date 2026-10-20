defmodule Flux.Sink.Adapters.Parquet.SchemaTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Parquet.Schema

  describe "infer/1" do
    test "maps values to logical types" do
      row = %{
        "s" => "x",
        "i" => 1,
        "f" => 1.5,
        "b" => true,
        "n" => nil,
        "m" => %{"a" => 1},
        "l" => [1, 2],
        "d" => ~D[2026-01-01],
        "t" => ~N[2026-01-01 00:00:00]
      }

      assert Schema.infer(row) == %{
               "s" => :string,
               "i" => :integer,
               "f" => :float,
               "b" => :boolean,
               "n" => :null,
               "m" => :json,
               "l" => :json,
               "d" => :date,
               "t" => :timestamp
             }
    end
  end

  describe "fit/2" do
    test "accepts a matching row and coerces nested values to JSON" do
      schema = %{"id" => :integer, "meta" => :json}

      assert {:ok, ^schema, %{"id" => 1, "meta" => ~s({"a":1})}} =
               Schema.fit(schema, %{"id" => 1, "meta" => %{"a" => 1}})
    end

    test "missing keys are fine" do
      assert {:ok, _schema, %{"id" => 1}} =
               Schema.fit(%{"id" => :integer, "x" => :string}, %{"id" => 1})
    end

    test "widens integer columns to float" do
      assert {:ok, %{"v" => :float}, %{"v" => 2.5}} =
               Schema.fit(%{"v" => :integer}, %{"v" => 2.5})
    end

    test "accepts integers in a float column as floats" do
      assert {:ok, %{"v" => :float}, %{"v" => 2.0}} = Schema.fit(%{"v" => :float}, %{"v" => 2})
    end

    test "a null column adopts the first non-nil type" do
      assert {:ok, %{"v" => :string}, %{"v" => "x"}} = Schema.fit(%{"v" => :null}, %{"v" => "x"})
    end

    test "a new column is a mismatch" do
      assert {:mismatch, [msg]} = Schema.fit(%{"id" => :integer}, %{"id" => 1, "extra" => 2})
      assert msg =~ "new column"
    end

    test "an incompatible value is a mismatch" do
      assert {:mismatch, [msg]} = Schema.fit(%{"id" => :integer}, %{"id" => "one"})
      assert msg =~ ~s(column "id" expected integer, got string)
    end

    test "an :any column accepts every value as a string" do
      assert {:ok, _, %{"v" => "1"}} = Schema.fit(%{"v" => :any}, %{"v" => 1})
      assert {:ok, _, %{"v" => "x"}} = Schema.fit(%{"v" => :any}, %{"v" => "x"})
      assert {:ok, _, %{"v" => "[1]"}} = Schema.fit(%{"v" => :any}, %{"v" => [1]})
    end
  end

  describe "widen/2" do
    test "adds new columns and turns conflicts into :any" do
      schema = %{"id" => :integer, "name" => :string, "score" => :integer}
      row = %{"id" => "abc", "score" => 1.5, "new" => true}

      assert Schema.widen(schema, row) == %{
               "id" => :any,
               "name" => :string,
               "score" => :float,
               "new" => :boolean
             }
    end

    test "the widened schema always fits the row" do
      schema = %{"a" => :integer, "b" => :json}
      row = %{"a" => "x", "b" => 1, "c" => nil}
      assert {:ok, _, _} = Schema.fit(Schema.widen(schema, row), row)
    end
  end

  describe "parse_explicit/1" do
    test "parses known type names" do
      assert {:ok, %{"id" => :integer, "name" => :any, "at" => :timestamp}} =
               Schema.parse_explicit(%{
                 "id" => "integer",
                 "name" => "string",
                 "at" => "timestamp"
               })
    end

    test "rejects unknown types" do
      assert {:error, msg} = Schema.parse_explicit(%{"id" => "bigint"})
      assert msg =~ "unknown type"
    end

    test "rejects non-maps and empty maps" do
      assert {:error, _} = Schema.parse_explicit([])
      assert {:error, _} = Schema.parse_explicit(%{})
    end
  end

  describe "fit_explicit/2" do
    setup do
      {:ok, schema} =
        Schema.parse_explicit(%{
          "id" => "integer",
          "price" => "float",
          "ok" => "boolean",
          "name" => "string",
          "day" => "date",
          "at" => "timestamp",
          "raw" => "json"
        })

      %{schema: schema}
    end

    test "parses values into declared types and drops unknown keys", %{schema: schema} do
      row = %{
        "id" => "42",
        "price" => 3,
        "ok" => "true",
        "name" => 7,
        "day" => "2026-10-19",
        "at" => "2026-10-19T12:00:00+02:00",
        "raw" => %{"k" => "v"},
        "ignored" => "x"
      }

      assert {:ok, coerced} = Schema.fit_explicit(schema, row)
      assert coerced["id"] == 42
      assert coerced["price"] == 3.0
      assert coerced["ok"] == true
      assert coerced["name"] == "7"
      assert coerced["day"] == ~D[2026-10-19]
      assert coerced["at"] == ~N[2026-10-19 10:00:00.000000]
      assert coerced["raw"] == ~s({"k":"v"})
      refute Map.has_key?(coerced, "ignored")
    end

    test "missing keys become nil", %{schema: schema} do
      assert {:ok, coerced} = Schema.fit_explicit(schema, %{})
      assert Enum.all?(coerced, fn {_, v} -> is_nil(v) end)
    end

    test "uncoercible values are rejected", %{schema: schema} do
      assert {:error, [msg]} = Schema.fit_explicit(schema, %{"id" => "4.2"})
      assert msg =~ ~s(column "id")
    end
  end

  test "dtypes/1 is ordered by column name" do
    assert Schema.dtypes(%{"b" => :integer, "a" => :timestamp, "c" => :json}) == [
             {"a", {:naive_datetime, :microsecond}},
             {"b", {:s, 64}},
             {"c", :string}
           ]
  end
end
