defmodule Flux.Alerts.ChannelSecrets do
  @moduledoc """
  Which alert-channel config values are secrets, and how they are protected.

  An alert rule's `channels` is a list of
  `%{"type" => type, "config" => map()}`. Some config values are credentials:

    * `slack` / `webhook`: `url`. A Slack Incoming Webhook URL embeds a token,
      and a generic webhook URL often carries one in its path or query.
    * `pagerduty`: `routing_key`, the Events API v2 integration key.

  This module is the single source of truth for those locations. The same
  taxonomy drives encryption at rest (`encrypt/1`, `decrypt/1`), redaction on the
  way out (`redact/1`), the write-only form merge (`merge_stored/2`) and error
  scrubbing (`scrub/2`).

  Secrets are encrypted and decrypted **only** at the locations listed here,
  and those are exactly the locations `redact/1` masks. A ciphertext planted in
  a non-secret field is never decrypted, so the app can't be used as a
  decryption oracle (see `Flux.Vault.decrypt_map/2`).
  """

  alias Flux.Vault

  require Logger

  @redacted "[REDACTED]"

  @secret_keys %{
    "slack" => ["url"],
    "webhook" => ["url"],
    "pagerduty" => ["routing_key"]
  }

  @doc "The value redacted secrets are replaced with."
  @spec redacted() :: String.t()
  def redacted, do: @redacted

  @doc "The secret config keys for a channel type. Empty for types with no secret."
  @spec secret_keys(String.t() | atom()) :: [String.t()]
  def secret_keys(type), do: Map.get(@secret_keys, to_string(type), [])

  @doc """
  Encrypts each channel's secret values with `Flux.Vault`. Idempotent: values
  that are already encrypted are left as they are.
  """
  @spec encrypt([map()]) :: [map()]
  def encrypt(channels) when is_list(channels),
    do:
      Enum.map(
        channels,
        &map_config(&1, fn config, paths -> Vault.encrypt_map(config, paths) end)
      )

  def encrypt(other), do: other

  @doc """
  Decrypts each channel's secret values. Only the locations named by
  `secret_keys/1` are decrypted; legacy plaintext passes through unchanged.

  A secret that can't be decrypted (the Vault key changed, or the ciphertext
  was tampered with) is dropped with a warning instead of raising. The channel
  then reads as "not set": it fails delivery cleanly, and the owner can
  re-enter the value, rather than one bad row breaking every rule.
  """
  @spec decrypt([map()]) :: [map()]
  def decrypt(channels) when is_list(channels),
    do: Enum.map(channels, &map_config(&1, fn config, paths -> decrypt_config(config, paths) end))

  def decrypt(other), do: other

  defp decrypt_config(config, paths) do
    Vault.decrypt_map(config, paths)
  rescue
    Flux.Vault.DecryptError ->
      Logger.warning(
        "[Alerts] could not decrypt an alert channel secret (#{Enum.map_join(paths, ", ", &hd/1)}); " <>
          "it must be re-entered"
      )

      Map.drop(config, Enum.map(paths, &hd/1))
  end

  @doc """
  Masks every secret value with `"[REDACTED]"`, then masks any encrypted
  wrapper left anywhere in the channels, as defense in depth.

  Use this on anything leaving the provider other than the dispatcher.
  """
  @spec redact([map()]) :: [map()]
  def redact(channels) when is_list(channels) do
    channels
    |> Enum.map(&map_config(&1, fn config, paths -> mask(config, paths) end))
    |> scrub_wrappers()
  end

  def redact(other), do: other

  @doc """
  Whether the channel of `type` holds a stored secret. Works on redacted
  channels, so a form can tell "stored" from "not set" without the value.
  """
  @spec stored?([map()] | nil, String.t() | atom()) :: boolean()
  def stored?(channels, type) when is_list(channels) do
    type = to_string(type)

    case Enum.find(channels, &(channel_type(&1) == type)) do
      nil -> false
      channel -> Enum.any?(secret_keys(type), &present?(get_in(config(channel), [&1])))
    end
  end

  def stored?(_channels, _type), do: false

  @doc """
  Fills in the secrets a write-only form left blank.

  `submitted` is the channel list from a create/update; `stored` is the rule's
  current, decrypted channel list. The rules:

    * A submitted channel with a new secret value is used as submitted.
    * A submitted channel whose secret is missing, blank or `"[REDACTED]"` keeps
      the stored secret: the stored config is the base and the submitted
      non-secret values (e.g. PagerDuty `severity`) are applied on top. If no
      secret is stored, the blank secret is dropped so validation rejects the
      channel rather than saving a placeholder.
    * A channel type that is not submitted is removed.
  """
  @spec merge_stored([map()], [map()] | nil) :: [map()]
  def merge_stored(submitted, stored) when is_list(submitted) do
    stored = if is_list(stored), do: stored, else: []
    Enum.map(submitted, &merge_channel(&1, stored))
  end

  def merge_stored(submitted, _stored), do: submitted

  @doc """
  Replaces every plaintext secret held by `channels` with `"[REDACTED]"` inside
  `term`. Use this before an error reason or exception message is logged or
  stored. Walks binaries, lists, tuples and plain maps; structs are left as
  they are.
  """
  @spec scrub(term(), [map()] | nil) :: term()
  def scrub(term, channels) do
    case secret_values(channels) do
      [] -> term
      secrets -> do_scrub(term, secrets)
    end
  end

  # -- internals -------------------------------------------------------------

  defp map_config(%{"config" => config} = channel, fun) when is_map(config) do
    case secret_keys(channel_type(channel)) do
      [] -> channel
      keys -> %{channel | "config" => fun.(config, Enum.map(keys, &[&1]))}
    end
  end

  defp map_config(channel, _fun), do: channel

  defp mask(config, paths) do
    Enum.reduce(paths, config, fn [key], acc ->
      if is_nil(Map.get(acc, key)), do: acc, else: Map.put(acc, key, @redacted)
    end)
  end

  defp scrub_wrappers(%{"encrypted" => true}), do: @redacted

  defp scrub_wrappers(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, scrub_wrappers(v)} end)

  defp scrub_wrappers(list) when is_list(list), do: Enum.map(list, &scrub_wrappers/1)
  defp scrub_wrappers(value), do: value

  defp merge_channel(%{"config" => config} = channel, stored) when is_map(config) do
    type = channel_type(channel)
    blank = Enum.reject(secret_keys(type), &new_secret?(Map.get(config, &1)))

    case {blank, stored_config(stored, type)} do
      {[], _stored} ->
        channel

      {_blank, nil} ->
        %{channel | "config" => Map.drop(config, blank)}

      {_blank, stored_config} ->
        %{channel | "config" => Map.merge(stored_config, Map.drop(config, blank))}
    end
  end

  defp merge_channel(channel, _stored), do: channel

  defp stored_config(stored, type) do
    with %{} = channel <- Enum.find(stored, &(channel_type(&1) == type)),
         config when is_map(config) <- config(channel),
         true <- Enum.all?(secret_keys(type), &new_secret?(Map.get(config, &1))) do
      config
    else
      _ -> nil
    end
  end

  defp new_secret?(value) when is_binary(value),
    do: String.trim(value) not in ["", @redacted]

  defp new_secret?(%{"encrypted" => true}), do: true
  defp new_secret?(_), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(%{"encrypted" => true}), do: true
  defp present?(_), do: false

  defp secret_values(channels) when is_list(channels) do
    channels
    |> Enum.flat_map(fn channel ->
      config = config(channel)

      channel
      |> channel_type()
      |> secret_keys()
      |> Enum.flat_map(&secret_patterns(&1, Map.get(config, &1)))
    end)
    |> Enum.uniq()
    # Longest first, so a full URL is replaced before its path is.
    |> Enum.sort_by(&(-byte_size(&1)))
  end

  defp secret_values(_channels), do: []

  # A URL may be echoed back re-rendered (e.g. normalised by a URI parser), so
  # its path-and-query, where Slack and webhook tokens live, is scrubbed too.
  defp secret_patterns("url", url) when is_binary(url) and url != "" do
    path_query =
      case URI.parse(url) do
        %URI{host: host, path: path} = uri when is_binary(host) and is_binary(path) ->
          path <> if(uri.query, do: "?" <> uri.query, else: "")

        _ ->
          nil
      end

    if is_binary(path_query) and byte_size(path_query) >= 8,
      do: [url, path_query],
      else: [url]
  end

  defp secret_patterns(_key, value) when is_binary(value) and value != "", do: [value]
  defp secret_patterns(_key, _value), do: []

  defp do_scrub(bin, secrets) when is_binary(bin),
    do: Enum.reduce(secrets, bin, &String.replace(&2, &1, @redacted))

  defp do_scrub(list, secrets) when is_list(list), do: Enum.map(list, &do_scrub(&1, secrets))

  defp do_scrub(tuple, secrets) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> do_scrub(secrets) |> List.to_tuple()

  defp do_scrub(map, secrets) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, do_scrub(v, secrets)} end)

  defp do_scrub(other, _secrets), do: other

  defp channel_type(%{"type" => type}), do: to_string(type)
  defp channel_type(%{type: type}), do: to_string(type)
  defp channel_type(_), do: nil

  defp config(%{"config" => config}) when is_map(config), do: config
  defp config(%{config: config}) when is_map(config), do: config
  defp config(_), do: %{}
end
