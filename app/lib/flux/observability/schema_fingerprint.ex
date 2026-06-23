defmodule Flux.Observability.SchemaFingerprint do
  @moduledoc """
  Computes a lightweight, stable fingerprint of a payload's top-level shape.

  Part of the observability feature (MOS-472). The schema-drift detector lives in
  the Pro edition, but the *fingerprint* is computed here, in the public repo, at
  the point where the webhook payload is in hand (`FluxWeb.API.WebhookController`).
  The fingerprint travels on the generic `[:flux, :webhook, :received]` telemetry
  event so the Pro detector never needs the raw payload — only its shape.

  This module is intentionally dumb: it derives the sorted set of
  `{key, value_type}` pairs and hashes it with `:erlang.phash2/1`. It makes **no**
  judgement about drift — it does not compare fingerprints, score severity, or
  emit alerts. All of that is proprietary and lives in `flux_pro`. Keep it that
  way: if this grows comparison or scoring logic, that logic belongs in the Pro
  edition, not here.

  Only top-level keys are considered; nested maps contribute their `:map` type but
  not their inner shape. This keeps the fingerprint cheap and stable while still
  catching the common drift cases (added/removed fields, top-level type changes).
  """

  @typedoc "A stable hash of a payload's top-level `{key, value_type}` set."
  @type fingerprint :: non_neg_integer()

  @doc """
  Returns a stable fingerprint of `payload`'s top-level key/type shape.

  The result is invariant to key ordering and value contents — only the set of
  keys and the JSON-ish type of each value matter. Two payloads with the same
  keys and per-key value types produce the same fingerprint.

      iex> a = Flux.Observability.SchemaFingerprint.compute(%{"id" => 1, "ok" => true})
      iex> b = Flux.Observability.SchemaFingerprint.compute(%{"ok" => false, "id" => 99})
      iex> a == b
      true
  """
  @spec compute(map()) :: fingerprint()
  def compute(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {key, value} -> {to_string(key), type_of(value)} end)
    |> Enum.sort()
    |> :erlang.phash2()
  end

  def compute(_payload), do: :erlang.phash2([])

  @doc "Number of top-level fields in `payload` (0 for non-maps)."
  @spec field_count(map()) :: non_neg_integer()
  def field_count(payload) when is_map(payload), do: map_size(payload)
  def field_count(_payload), do: 0

  # Coarse, JSON-shaped type tags. Integers and floats collapse to :number so a
  # value flipping between 1 and 1.0 is not reported as drift.
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_number(value), do: :number
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value), do: :map
  defp type_of(nil), do: :null
  defp type_of(_value), do: :other
end
