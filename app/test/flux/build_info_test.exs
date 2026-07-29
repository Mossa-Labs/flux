defmodule Flux.BuildInfoTest do
  use ExUnit.Case, async: true

  alias Flux.BuildInfo

  # These assert on the *shape* of the identity rather than specific values: the
  # values are injected at build time, so a test run and a released image
  # legitimately differ. What must hold either way is that every field is present
  # and that an uninjected build is honestly reported as such.

  describe "identity fields" do
    test "reports an edition, a version and a revision" do
      assert is_binary(BuildInfo.edition())
      assert BuildInfo.edition() != ""
      assert is_binary(BuildInfo.version())
      assert is_binary(BuildInfo.core_sha())
    end

    test "reports the toolchain it was compiled against" do
      assert %{otp: otp, elixir: elixir} = BuildInfo.toolchain()
      assert otp == System.otp_release()
      assert elixir == System.version()
    end
  end

  describe "released?/0" do
    test "a build with no injected revision is not a release" do
      # The test suite is built without FLUX_CORE_SHA, so this is the laptop case.
      assert BuildInfo.core_sha() == "dev"
      refute BuildInfo.released?()
    end

    test "a blank injected value counts as absent, not as a release" do
      # Docker's `ENV FOO=${BAR}` with an undeclared build arg sets FOO to "",
      # and "" is truthy in Elixir — so `get(...) || "dev"` used to keep the ""
      # and every arg-less image claimed released?() == true with a blank
      # revision (MOS-596). config.exs normalises blank to nil; assert the
      # invariant here because this suite's environment cannot reproduce the
      # empty-string case directly.
      refute BuildInfo.core_sha() == ""
      refute BuildInfo.built_at() == ""
    end
  end

  describe "version/0" do
    test "reports the project version, which is also the OTP release version" do
      # The version must not be sourced separately from mix.exs: it names the
      # release directory and RELEASE_VSN too, so a second source would let
      # /health and /app/releases/<vsn> disagree (MOS-596). mix.exs resolves
      # FLUX_VERSION; everything downstream reads it through here.
      assert BuildInfo.version() == Mix.Project.config()[:version]
    end
  end

  describe "short/0 and long/0" do
    test "short/0 names the product, edition, version and revision" do
      short = BuildInfo.short()

      assert short =~ "Flux"
      assert short =~ BuildInfo.edition()
      assert short =~ BuildInfo.version()
      assert short =~ BuildInfo.short_sha(BuildInfo.core_sha())
    end

    test "long/0 adds the toolchain" do
      long = BuildInfo.long()

      assert long =~ BuildInfo.short()
      assert long =~ "OTP #{System.otp_release()}"
      assert long =~ "Elixir #{System.version()}"
    end

    test "long/0 omits the build time when it was not injected" do
      # Absent rather than rendered as "built " with nothing after it.
      refute BuildInfo.built_at()
      refute BuildInfo.long() =~ "built "
    end
  end

  describe "short_sha/1" do
    test "abbreviates a full revision to 7 characters" do
      assert BuildInfo.short_sha("45611fa62790f3a906d578ab5319bc209c62c060") == "45611fa"
    end

    test "leaves the dev sentinel and nil alone" do
      assert BuildInfo.short_sha("dev") == "dev"
      assert BuildInfo.short_sha(nil) == nil
    end
  end

  describe "to_map/0" do
    test "exposes every field for diagnostics" do
      map = BuildInfo.to_map()

      assert Map.keys(map) |> Enum.sort() ==
               ~w(built_at core_sha edition edition_sha elixir otp released version)a
    end

    test "a single-repo build reports no edition revision" do
      assert BuildInfo.to_map().edition_sha == nil
    end
  end
end
