defmodule Flux.BuildInfo do
  @moduledoc """
  Identifies the running build: version, source revision, edition, and toolchain.

  Given a customer instance, "what build is this?" has to be answerable — from a
  support log, from the UI, or from the image without running it. A single version
  string is not enough, because a Flux image can be assembled from more than one
  source repository: the edition carries its own version and records the core
  revision as metadata, the way a Linux distribution reports both its own release
  and the kernel it ships.

      Flux Community 0.1.0 (core 45611fa)
      OTP 28 / Elixir 1.19.4 · built 2026-07-27T18:24:00Z

  ## Why the values are injected at build time

  Git is not available at runtime, and `.git` is excluded from the Docker build
  context, so the revision cannot be discovered by the running app — it has to be
  handed in. `config/config.exs` reads the build-time environment into
  `:build_info` and this module resolves it with `Application.compile_env/3`.

  `compile_env` matters: a bare `@attr System.get_env(...)` would *not* trigger
  recompilation when the value changed, so a stale SHA could be baked in silently
  — the worst failure mode for a version string, since it is confidently wrong
  rather than obviously missing.

  Builds without the variables set report `"dev"` and are marked accordingly, so
  an unreproducible laptop build is visible on sight rather than passing for a
  release.
  """

  @info Application.compile_env(:flux, :build_info, [])

  @version Keyword.get(@info, :version, "0.0.0")
  @core_sha Keyword.get(@info, :core_sha) || "dev"
  @built_at Keyword.get(@info, :built_at)
  @edition Keyword.get(@info, :edition, "Community")
  @edition_sha Keyword.get(@info, :edition_sha)
  @otp System.otp_release()
  @elixir System.version()

  @doc "Edition name, e.g. `\"Community\"`. Set by the edition being built."
  @spec edition() :: String.t()
  def edition, do: @edition

  @doc "Semantic version of this build."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Full revision of the core source, or `\"dev\"` for an uninjected build."
  @spec core_sha() :: String.t()
  def core_sha, do: @core_sha

  @doc """
  Revision of the edition layer, when the build is assembled from a second
  repository. `nil` for a single-repo (Community) build.
  """
  @spec edition_sha() :: String.t() | nil
  def edition_sha, do: @edition_sha

  @doc "ISO-8601 build timestamp, or `nil` if not injected."
  @spec built_at() :: String.t() | nil
  def built_at, do: @built_at

  @doc "OTP release and Elixir version this build was compiled against."
  @spec toolchain() :: %{otp: String.t(), elixir: String.t()}
  def toolchain, do: %{otp: @otp, elixir: @elixir}

  @doc """
  Whether this build carries an injected revision.

  False means it was built outside the release pipeline — useful to surface, so
  a build nobody can reproduce is not mistaken for a shipped one.
  """
  @spec released?() :: boolean()
  def released?, do: @core_sha != "dev"

  @doc """
  Short single-line identity, e.g. `"Flux Community 0.1.0 (45611fa)"`.

  When the build is assembled from a second repository, both revisions are named
  explicitly: `"Flux <Edition> 1.4.2 (core 45611fa, edition a1b2c3d)"`.

  Suitable for a boot log line or a UI footer.
  """
  @spec short() :: String.t()
  def short do
    "Flux #{@edition} #{@version} (#{revisions()})"
  end

  @doc """
  Multi-line identity including toolchain and build time, for an About panel or
  a support bundle.
  """
  @spec long() :: String.t()
  def long do
    [
      short(),
      "OTP #{@otp} / Elixir #{@elixir}",
      if(@built_at, do: "built #{@built_at}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "Every field at once, for JSON responses and diagnostics."
  @spec to_map() :: map()
  def to_map do
    %{
      edition: @edition,
      version: @version,
      core_sha: @core_sha,
      edition_sha: @edition_sha,
      built_at: @built_at,
      otp: @otp,
      elixir: @elixir,
      released: released?()
    }
  end

  @doc "Abbreviates a revision to 7 characters, leaving `\"dev\"` alone."
  @spec short_sha(String.t() | nil) :: String.t() | nil
  def short_sha(nil), do: nil
  def short_sha("dev"), do: "dev"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  # A single-repo build names one revision; a layered build names both, so a
  # support conversation is never ambiguous about which half is in question.
  defp revisions do
    case @edition_sha do
      nil -> short_sha(@core_sha)
      sha -> "core #{short_sha(@core_sha)}, edition #{short_sha(sha)}"
    end
  end
end
