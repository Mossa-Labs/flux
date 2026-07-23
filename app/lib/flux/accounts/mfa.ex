defmodule Flux.Accounts.Mfa do
  @moduledoc """
  TOTP multi-factor authentication for user accounts (MOS-591).

  Per-user TOTP enrollment/verification is Community. The TOTP secret and the 10
  single-use backup codes are encrypted at rest via `Flux.Vault`, bound to the owning
  `user_id` as AAD so a stolen ciphertext cannot be replayed against another row.

  The decrypted secret and backup codes are returned to the caller **only** during
  enrollment (to render the QR / show the codes once) and are used internally for
  verification — they are never rendered back to the UI or API afterwards (MOS-484
  invariant: decrypt only where you redact).
  """
  import Ecto.Query, warn: false

  alias Flux.Accounts.{User, UserMfa}
  alias Flux.{Repo, Vault}

  @issuer "Flux"
  @backup_code_count 10

  @doc "Returns the user's MFA record, or `nil` if never enrolled."
  def get_user_mfa(%User{id: user_id}), do: Repo.get_by(UserMfa, user_id: user_id)

  @doc "Whether the user has completed MFA enrollment (a confirmed second factor)."
  def mfa_enabled?(%User{} = user) do
    case get_user_mfa(user) do
      %UserMfa{enabled_at: %DateTime{}} -> true
      _ -> false
    end
  end

  @doc """
  Begins enrollment: generates a fresh TOTP secret and its `otpauth://` URI.

  Nothing is persisted here — the secret is held by the caller (server-side LiveView
  state) and only committed once the user confirms a code via `confirm_enrollment/3`.
  """
  def start_enrollment(%User{email: email}) do
    secret = NimbleTOTP.secret()

    %{
      secret: secret,
      otpauth_uri: NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
    }
  end

  @doc """
  Confirms enrollment by verifying `code` against the pending `secret`.

  On success, generates 10 single-use backup codes, encrypts the secret and codes
  (bound to the user), stamps `enabled_at`, and returns the **plaintext** backup codes
  to show the user once. Returns `{:error, :invalid_code}` if the code doesn't match.
  """
  def confirm_enrollment(%User{} = user, secret, code)
      when is_binary(secret) and is_binary(code) do
    if valid_totp?(secret, code) do
      backup_codes = generate_backup_codes()

      attrs = %{
        secret: Vault.encrypt_value(Base.encode64(secret), aad(user)),
        backup_codes: Vault.encrypt_value(backup_codes, aad(user)),
        enabled_at: DateTime.utc_now(:second)
      }

      with {:ok, _record} <- upsert_mfa(user, attrs) do
        {:ok, backup_codes}
      end
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Verifies a 6-digit TOTP `code` for an enrolled user. Returns a boolean.
  """
  def verify_totp(%User{} = user, code) when is_binary(code) do
    case get_user_mfa(user) do
      %UserMfa{enabled_at: %DateTime{}} = record ->
        secret = record |> decrypt_secret(user)
        valid_totp?(secret, code)

      _ ->
        false
    end
  end

  @doc """
  Verifies and **consumes** a single-use backup `code`.

  On a match the code is removed and the remaining codes re-encrypted, so it can never
  be used again. Returns `:ok` or `:error`.
  """
  def verify_backup_code(%User{} = user, code) when is_binary(code) do
    case get_user_mfa(user) do
      %UserMfa{enabled_at: %DateTime{}} = record ->
        codes = decrypt_backup_codes(record, user)

        if code in codes do
          remaining = List.delete(codes, code)
          {:ok, _} = upsert_mfa(user, %{backup_codes: Vault.encrypt_value(remaining, aad(user))})
          :ok
        else
          :error
        end

      _ ->
        :error
    end
  end

  @doc "How many unused backup codes the user has left (0 if not enrolled)."
  def backup_codes_remaining(%User{} = user) do
    case get_user_mfa(user) do
      %UserMfa{enabled_at: %DateTime{}} = record -> length(decrypt_backup_codes(record, user))
      _ -> 0
    end
  end

  @doc """
  Regenerates the 10 backup codes for an enrolled user, invalidating the old set.
  Returns `{:ok, plaintext_codes}` or `{:error, :not_enrolled}`.
  """
  def regenerate_backup_codes(%User{} = user) do
    case get_user_mfa(user) do
      %UserMfa{enabled_at: %DateTime{}} ->
        codes = generate_backup_codes()
        {:ok, _} = upsert_mfa(user, %{backup_codes: Vault.encrypt_value(codes, aad(user))})
        {:ok, codes}

      _ ->
        {:error, :not_enrolled}
    end
  end

  @doc "Disables MFA for the user, deleting the stored secret and backup codes."
  def disable(%User{} = user) do
    case get_user_mfa(user) do
      %UserMfa{} = record -> Repo.delete(record)
      nil -> {:ok, nil}
    end
  end

  ## Internal

  defp valid_totp?(secret, code) do
    # Constant-work verify; NimbleTOTP.valid?/2 tolerates the adjacent time step.
    String.match?(code, ~r/^\d{6}$/) and NimbleTOTP.valid?(secret, code)
  end

  defp upsert_mfa(%User{} = user, attrs) do
    (get_user_mfa(user) || Ecto.build_assoc(user, :mfa))
    |> UserMfa.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp decrypt_secret(%UserMfa{secret: secret}, user) do
    secret |> Vault.decrypt_value(aad(user)) |> Base.decode64!()
  end

  defp decrypt_backup_codes(%UserMfa{backup_codes: codes}, user) do
    Vault.decrypt_value(codes, aad(user))
  end

  defp generate_backup_codes do
    for _ <- 1..@backup_code_count do
      :crypto.strong_rand_bytes(5) |> Base.encode32(padding: false) |> String.downcase()
    end
  end

  # Additional-authenticated-data binding the ciphertext to this exact user row.
  defp aad(%User{id: id}), do: "user_mfa:#{id}"
end
