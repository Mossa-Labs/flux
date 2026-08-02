defmodule Flux.Branding.Provider do
  @moduledoc """
  Contract for branding providers.

  Community ships `Flux.Branding.Providers.Community`, which always reports stock
  Flux and refuses writes. The commercial edition supplies a provider backed by
  per-organization storage.

  Two things are deliberately the *provider's* job rather than the caller's:

    * **Resolution.** `theme/1` returns a finished `Flux.Branding.Theme` — the
      caller renders it and derives nothing. Colour validation and the readable
      foreground are settled here, so a layout cannot disagree with a stylesheet.
    * **The deployment organization.** Pre-authentication pages have no scope, so
      `deployment_org_id/0` answers "whose branding does a signed-out visitor
      see". That is a licensing/storage question, not a rendering one.
  """

  alias Flux.Branding.Theme

  @typedoc "Which stored image is being addressed."
  @type asset_kind :: :logo | :favicon

  @typedoc """
  Field-level errors for a rejected write.

  A plain keyword list rather than an `Ecto.Changeset`: the schema lives behind
  this contract, so the caller has no struct to build a changeset from.
  """
  @type errors :: [{atom(), String.t()}]

  @doc "Resolved branding for an organization, or stock when it has none."
  @callback theme(org_id :: term() | nil) :: Theme.t()

  @doc "Persists branding for an organization."
  @callback put(org_id :: term(), attrs :: map()) :: {:ok, Theme.t()} | {:error, errors()}

  @doc """
  The organization whose branding pre-auth pages use, or `nil` when there is
  none to speak of (a deployment with no organizations yet).
  """
  @callback deployment_org_id() :: term() | nil

  @doc """
  The stored bytes for an asset: `{:ok, binary, content_type, digest}`, or
  `:none`.

  `content_type` is what the provider *validated* the bytes to be, never what an
  uploader claimed — the caller serves it verbatim in a `content-type` header.
  """
  @callback asset(org_id :: term(), asset_kind()) ::
              {:ok, binary(), String.t(), String.t()} | :none

  @doc "Validates and stores an uploaded image."
  @callback put_asset(org_id :: term(), asset_kind(), bytes :: binary()) ::
              {:ok, Theme.t()} | {:error, errors()}

  @optional_callbacks put: 2, asset: 2, put_asset: 3
end
