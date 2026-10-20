defmodule Flux.Sink.Adapters.Parquet.PathsTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Parquet.{Paths, Settings}

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

    test "bounds field values and directory names in bytes, not characters" do
      # 200 three-byte characters: 200 characters, 600 bytes.
      wide = String.duplicate("界", 200)
      partition = Paths.render_partition("{v}", %{"v" => wide}, @now, 1)

      assert partition == String.duplicate("界", 42) <> "/"
      assert String.valid?(partition)

      long =
        Paths.render_partition("{a}-{b}-{c}", %{"a" => wide, "b" => wide, "c" => wide}, @now, 1)

      assert long |> String.trim_trailing("/") |> byte_size() <= 255
    end

    test "empty template renders no prefix" do
      assert Paths.render_partition("", %{}, @now, 1) == ""
    end
  end

  test "render_file/2 caps directory names but never the file name" do
    dir = String.duplicate("d", 300)
    name = String.duplicate("f", 300) <> ".parquet"
    vars = %{pipeline_id: 1, partition: "", now: @now, seq: 1, uid: "u"}

    assert Paths.render_file("#{dir}/#{name}", vars) == String.duplicate("d", 255) <> "/" <> name
  end

  describe "validate_file_name/2" do
    test "accepts the default and typical templates" do
      assert :ok = Paths.validate_file_name(Settings.default_path_template(), "")
      assert :ok = Paths.validate_file_name("{pipeline_id}-{timestamp}-{seq}-{uid}.parquet", "")
    end

    test "rejects a file name that can render past 255 bytes" do
      prefix = String.duplicate("p", 200)

      assert {:error, msg} = Paths.validate_file_name("#{prefix}-{uid}-{timestamp}.parquet", "")
      assert msg =~ "limit is 255"
    end

    test "counts text on both sides of an empty partition as one name" do
      half = String.duplicate("p", 120)
      template = "#{half}{partition}#{half}-{uid}.parquet"

      assert {:error, _} = Paths.validate_file_name(template, "")
      # A partition ends the name before it, so only the second half counts.
      assert :ok = Paths.validate_file_name(template, "r={region}/")
    end
  end

  test "scratch names are hidden and match their glob" do
    assert Paths.scratch_name(".tmp") =~ ~r/^\.flux-[a-z2-7]{26}\.tmp$/
    assert Paths.scratch_glob(".tmp") == ".flux-*.tmp"
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
