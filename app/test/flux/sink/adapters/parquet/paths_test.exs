defmodule Flux.Sink.Adapters.Parquet.PathsTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Parquet.Paths

  @now ~U[2026-04-07 09:05:03.123456Z]

  describe "validate_directory/1" do
    test "accepts relative directories" do
      assert :ok = Paths.validate_directory("events")
      assert :ok = Paths.validate_directory("team/events")
    end

    test "rejects missing, absolute and escaping directories" do
      assert {:error, "directory is required"} = Paths.validate_directory(nil)
      assert {:error, "directory is required"} = Paths.validate_directory("")
      assert {:error, msg} = Paths.validate_directory("/etc")
      assert msg =~ "relative"
      assert {:error, msg} = Paths.validate_directory("../outside")
      assert msg =~ ".."
      assert {:error, _} = Paths.validate_directory("a/../../outside")
    end
  end

  describe "resolve/2" do
    test "keeps paths inside the root" do
      assert {:ok, "/base/a/b.parquet"} = Paths.resolve("/base", "a/b.parquet")
    end

    test "rejects escapes and the root itself" do
      assert {:error, :path_escape} = Paths.resolve("/base", "../x")
      assert {:error, :path_escape} = Paths.resolve("/base", "a/../../x")
      assert {:error, :path_escape} = Paths.resolve("/base", "")
      assert {:error, :path_escape} = Paths.resolve("/base", "a\0b")
    end

    test "does not treat a sibling with a shared prefix as inside" do
      assert {:error, :path_escape} = Paths.resolve("/base", "../base-evil/x")
    end
  end

  describe "validate_template/2" do
    test "rejects absolute and .. templates" do
      assert {:error, _} = Paths.validate_template("/abs/{uid}.parquet", :path)
      assert {:error, _} = Paths.validate_template("../{uid}.parquet", :path)
      assert {:error, _} = Paths.validate_template("x/../y={yyyy}", :partition)
    end

    test "rejects unknown placeholders in path templates only" do
      assert {:error, msg} = Paths.validate_template("{customer}/{uid}.parquet", :path)
      assert msg =~ "customer"
      assert :ok = Paths.validate_template("customer={customer}/", :partition)
    end
  end

  describe "render_partition/4" do
    test "renders time placeholders in UTC" do
      assert Paths.render_partition("year={yyyy}/month={MM}/day={dd}/hour={HH}", %{}, @now, "p1") ==
               "year=2026/month=04/day=07/hour=09/"

      assert Paths.render_partition("{date}", %{}, @now, "p1") == "2026-04-07/"
    end

    test "renders record fields, including nested paths" do
      data = %{"region" => "eu-west", "user" => %{"tier" => "gold"}, "n" => 3}

      assert Paths.render_partition("region={region}/tier={user.tier}/n={n}", data, @now, 1) ==
               "region=eu-west/tier=gold/n=3/"
    end

    test "missing fields render as unknown" do
      assert Paths.render_partition("r={region}", %{}, @now, 1) == "r=unknown/"

      assert Paths.render_partition("r={region}", %{"region" => %{"a" => 1}}, @now, 1) ==
               "r=unknown/"
    end

    test "sanitizes field values into a single safe segment" do
      data = %{"evil" => "../../etc/passwd", "ctl" => "a\nb", "slash" => "a\\b"}

      partition = Paths.render_partition("x={evil}/c={ctl}/s={slash}", data, @now, 1)

      assert partition == "x=____etc_passwd/c=a_b/s=a_b/"
      assert {:ok, _} = Paths.resolve("/base", partition <> "f.parquet")
    end

    test "empty template renders no prefix" do
      assert Paths.render_partition("", %{}, @now, 1) == ""
    end
  end

  test "render_file/2 fills every file placeholder" do
    path =
      Paths.render_file("{pipeline_id}/{date}/{partition}part-{timestamp}-{seq}-{uid}.parquet", %{
        pipeline_id: 12,
        partition: "year=2026/",
        now: @now,
        seq: 7,
        uid: "abcd1234"
      })

    assert path == "12/2026-04-07/year=2026/part-20260407T090503.123456Z-000007-abcd1234.parquet"
  end
end
