defmodule Flux.AWS.ServerCredentials do
  @moduledoc """
  Operator switch for connectors that act with the Flux server's own AWS identity.

  An AWS connector configured with `iam_role` auth, or with `assume_role` and no
  base keys of its own, signs requests with whatever identity the Flux server
  runs as: the instance or task role, or the ambient AWS environment. In a
  deployment shared by several organizations that identity is a confused
  deputy, because any member could aim a connector at a resource that belongs
  to someone else and the server's role would sign for it.

  Operators control this with `FLUX_AWS_SERVER_CREDENTIALS`:

    * `allowed` (default): connectors may use the server's identity.
    * `disabled`: connectors must bring their own credentials, either static
      keys or `assume_role` with base keys.

  `allowed?/0` and `uses_server_identity?/1` are the single source of truth for
  both the UI and every adapter that signs AWS requests, so the forms and the
  runtime enforcement cannot disagree.
  """

  @type setting :: :allowed | :disabled

  @disabled_message "Server AWS credentials are disabled by your administrator. " <>
                      "Use static access keys, or assume a role with your own base keys."

  @doc "The configured setting. Anything other than `:disabled` reads as `:allowed`."
  @spec setting() :: setting()
  def setting do
    case Application.get_env(:flux, :aws_server_credentials, :allowed) do
      :disabled -> :disabled
      _ -> :allowed
    end
  end

  @doc "Whether connectors may act with the Flux server's own AWS identity."
  @spec allowed?() :: boolean()
  def allowed?, do: setting() == :allowed

  @doc "The message shown wherever a connector is refused the server's identity."
  @spec disabled_message() :: String.t()
  def disabled_message, do: @disabled_message

  @doc """
  The auth mode a connector config actually signs with.

  An explicit `auth_mode` wins. Without one, a config that carries both keys is
  `static`, and anything else is `iam_role`, which is how the AWS adapters have
  always treated a missing mode.
  """
  @spec effective_auth_mode(map()) :: String.t()
  def effective_auth_mode(config) when is_map(config) do
    case Map.get(config, "auth_mode") do
      mode when is_binary(mode) and mode != "" -> mode
      _ -> if base_keys?(config), do: "static", else: "iam_role"
    end
  end

  @doc """
  Whether a connector config would sign with the server's own AWS identity.

  Expects the shared credential shape: `"auth_mode"`, `"access_key_id"` and
  `"secret_access_key"`. Connectors that store these under other names map them
  first.

    * `iam_role` always uses the server's identity.
    * `assume_role` uses it for the STS call unless base keys are supplied.
    * `static` never does. Missing keys are an error, not a fallback.
  """
  @spec uses_server_identity?(map()) :: boolean()
  def uses_server_identity?(config) when is_map(config) do
    case effective_auth_mode(config) do
      "iam_role" -> true
      "assume_role" -> not base_keys?(config)
      _ -> false
    end
  end

  @doc """
  `:ok`, or `{:error, message}` when the setting is disabled and the config would
  sign with the server's identity.
  """
  @spec check(map()) :: :ok | {:error, String.t()}
  def check(config) when is_map(config) do
    if allowed?() or not uses_server_identity?(config),
      do: :ok,
      else: {:error, @disabled_message}
  end

  @doc "Whether both base keys are present and non-blank."
  @spec base_keys?(map()) :: boolean()
  def base_keys?(config) when is_map(config) do
    present?(Map.get(config, "access_key_id")) and present?(Map.get(config, "secret_access_key"))
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
