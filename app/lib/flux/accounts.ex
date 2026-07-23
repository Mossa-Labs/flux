defmodule Flux.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Flux.Repo

  alias Flux.Accounts.{ApiKey, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a user by id, returning `nil` if not found."
  def get_user(id), do: Repo.get(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 60 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -60)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Flux.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Flux.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  ## Options

  Accepts the same `opts` as `User.password_changeset/3` — notably `:org_id`, so
  the org's password policy is enforced when the `:password_policy` feature is
  entitled.
  """
  def update_user_password(user, attrs, opts \\ []) do
    user
    |> User.password_changeset(attrs, opts)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token, recording the request device/IP (MOS-589).

  `meta` is a string-keyed map as produced by `FluxWeb.AuditMeta.from_conn/1`
  (`"ip_address"`, `"user_agent"`); both are optional.
  """
  def generate_user_session_token(user, meta \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, meta)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, user_token}` is returned (the `user_token`
  carries `inserted_at`/`last_active_at` for timeout enforcement), otherwise
  `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Lists a user's active session tokens, most-recently-active first (MOS-589).
  """
  def list_user_sessions(%User{} = user) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session",
      order_by: [desc: coalesce(t.last_active_at, t.inserted_at)]
    )
    |> Repo.all()
  end

  @doc """
  Records session activity by bumping `last_active_at`, throttled so at most one
  write happens per `@activity_throttle_seconds` window (keeps this off the
  write-hot path). Returns `:ok`.
  """
  @activity_throttle_seconds 300
  def touch_session_activity(%UserToken{id: id}) do
    now = DateTime.utc_now(:second)
    cutoff = DateTime.add(now, -@activity_throttle_seconds, :second)

    Repo.update_all(
      from(t in UserToken,
        where: t.id == ^id and (is_nil(t.last_active_at) or t.last_active_at < ^cutoff)
      ),
      set: [last_active_at: now]
    )

    :ok
  end

  @doc """
  Deletes one of the user's session tokens by id, scoped to the owning user (no
  IDOR). Returns `{:ok, token}` with the deleted token (raw value, for socket
  disconnect), or `:error` if it does not exist / belongs to another user.
  """
  def delete_user_session(%User{} = user, id) do
    from(t in UserToken,
      where: t.id == ^id and t.user_id == ^user.id and t.context == "session",
      select: t
    )
    |> Repo.delete_all()
    |> case do
      {1, [token]} -> {:ok, token}
      _ -> :error
    end
  end

  @doc """
  Deletes all of the user's session tokens EXCEPT the current one. Returns the
  list of deleted tokens (for socket disconnect).
  """
  def delete_other_user_sessions(%User{} = user, current_token) do
    {_count, tokens} =
      from(t in UserToken,
        where: t.user_id == ^user.id and t.context == "session" and t.token != ^current_token,
        select: t
      )
      |> Repo.delete_all()

    tokens
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## API keys

  @api_key_prefix "flux_pk_"
  @api_key_random_len 32
  @base62 ~c"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  @doc """
  Creates an API key for `organization_id`.

  Returns `{:ok, plaintext, %ApiKey{}}` where `plaintext` (e.g.
  `flux_pk_<32 chars>`) is shown exactly once — only its SHA-256 hash is
  stored. `attrs` accepts `:name` (required), `:role`, `:expires_at`, and
  `:scopes` (defaults to the role's full set when omitted).
  """
  def create_api_key(organization_id, attrs) do
    raw = generate_api_key()

    programmatic = %{
      organization_id: organization_id,
      key_prefix: String.slice(raw, 0, byte_size(@api_key_prefix) + 8),
      key_hash: hash_api_key(raw)
    }

    %ApiKey{}
    |> ApiKey.create_changeset(gate_scopes(attrs), programmatic)
    |> Repo.insert()
    |> case do
      {:ok, api_key} ->
        Flux.Audit.log(%{
          organization_id: api_key.organization_id,
          action: :api_key_created,
          resource_type: :api_key,
          resource_id: api_key.id,
          changes: %{"name" => api_key.name, "role" => api_key.role}
        })

        {:ok, raw, api_key}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Fine-grained (below-role) scopes are a Pro feature. Without the entitlement,
  # drop any requested scopes so the changeset falls back to the role's full set
  # — the key still works, just at role granularity.
  defp gate_scopes(attrs) do
    if Flux.License.has_feature?(:api_key_scopes),
      do: attrs,
      else: Map.drop(attrs, [:scopes, "scopes"])
  end

  @doc "Lists an organization's API keys, newest first."
  def list_api_keys(organization_id) do
    ApiKey
    |> where([k], k.organization_id == ^organization_id)
    |> order_by([k], desc: k.inserted_at)
    |> Repo.all()
  end

  @doc "Revokes a key (soft-delete via `revoked_at`); idempotent."
  def revoke_api_key(%ApiKey{} = api_key) do
    api_key
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    |> case do
      {:ok, revoked} = result ->
        Flux.Audit.log(%{
          organization_id: revoked.organization_id,
          action: :api_key_revoked,
          resource_type: :api_key,
          resource_id: revoked.id,
          changes: %{"name" => revoked.name}
        })

        result

      other ->
        other
    end
  end

  def revoke_api_key(id) do
    case Repo.get(ApiKey, id) do
      nil -> {:error, :not_found}
      api_key -> revoke_api_key(api_key)
    end
  end

  @doc """
  Authenticates a raw API key. Returns `{:ok, %ApiKey{}}` for an active key
  (not revoked, not expired) or `{:error, :unauthorized}`.
  """
  def authenticate_api_key(raw) when is_binary(raw) do
    case Repo.get_by(ApiKey, key_hash: hash_api_key(raw)) do
      %ApiKey{} = key -> if ApiKey.active?(key), do: {:ok, key}, else: {:error, :unauthorized}
      nil -> {:error, :unauthorized}
    end
  end

  def authenticate_api_key(_), do: {:error, :unauthorized}

  @doc "Records that a key was used (called off the request path)."
  def touch_api_key(id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    from(k in ApiKey, where: k.id == ^id) |> Repo.update_all(set: [last_used_at: now])
    :ok
  end

  @doc "Hashes a raw API key (SHA-256, lowercase hex)."
  def hash_api_key(raw) when is_binary(raw) do
    :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
  end

  defp generate_api_key do
    random =
      @api_key_random_len
      |> :crypto.strong_rand_bytes()
      |> :binary.bin_to_list()
      |> Enum.map_join("", fn byte -> <<Enum.at(@base62, rem(byte, 62))>> end)

    @api_key_prefix <> random
  end

  ## MFA / TOTP (MOS-591) — see Flux.Accounts.Mfa

  defdelegate mfa_enabled?(user), to: Flux.Accounts.Mfa
  defdelegate get_user_mfa(user), to: Flux.Accounts.Mfa
  defdelegate start_mfa_enrollment(user), to: Flux.Accounts.Mfa, as: :start_enrollment

  defdelegate confirm_mfa_enrollment(user, secret, code),
    to: Flux.Accounts.Mfa,
    as: :confirm_enrollment

  defdelegate verify_totp(user, code), to: Flux.Accounts.Mfa
  defdelegate verify_backup_code(user, code), to: Flux.Accounts.Mfa
  defdelegate backup_codes_remaining(user), to: Flux.Accounts.Mfa
  defdelegate regenerate_backup_codes(user), to: Flux.Accounts.Mfa
  defdelegate disable_mfa(user), to: Flux.Accounts.Mfa, as: :disable

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = from(t in UserToken, where: t.user_id == ^user.id) |> Repo.all()

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
