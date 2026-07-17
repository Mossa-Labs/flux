defmodule Flux.Audit do
  @moduledoc """
  Facade over the active `Flux.Audit.Provider` (MOS-482).

  Every mutating context (`Flux.Pipelines`, `Flux.Sinks`, `Flux.Structure`,
  `Flux.Accounts`, …) records actions through this module rather than touching a
  provider directly. Audit logging is an **Enterprise** feature: the Community
  build resolves to `Flux.Audit.Providers.Community`, a no-op stub, so these
  calls are free and safe on every edition. The commercial edition overlays a
  Postgres-backed provider via `Flux.Audit.Registry.set_active/1` at boot.

  ## Recording

      Flux.Audit.log(%{
        organization_id: org_id,
        actor: scope,                 # Scope | User | {:api_key, key} | :system
        action: :pipeline_updated,
        resource_type: :pipeline,
        resource_id: pipeline.id,
        changes: %{"name" => %{"from" => "a", "to" => "b"}},
        metadata: %{"ip_address" => "1.2.3.4"}
      })

  `log/1` never raises: a failure in the audit path must not break the business
  action that triggered it.
  """

  alias Flux.Audit.{Context, Event, Provider, Registry}

  require Logger

  @doc """
  Records one audit event from loose call-site attrs (see `Flux.Audit.Event`).

  The ambient `Flux.Audit.Context` (actor + request metadata, set at LiveView
  mount / API plug) fills in `:actor` and `:metadata`; explicit attrs win, and
  metadata from both is merged. Returns `:ok` regardless of provider outcome;
  audit failures are logged, never raised, so a mutating action is never rolled
  back by its own audit call.
  """
  @spec log(map() | keyword()) :: :ok
  def log(attrs) do
    attrs_map = Map.new(attrs)
    ctx = Context.get()
    metadata = Map.merge(ctx[:metadata] || %{}, attrs_map[:metadata] || %{})

    event =
      ctx
      |> Map.merge(attrs_map)
      |> Map.put(:metadata, metadata)
      |> Event.normalize()

    Registry.active().log(event)
    :ok
  rescue
    error ->
      Logger.warning("[Flux.Audit] failed to record event: #{Exception.message(error)}")
      :ok
  catch
    kind, reason ->
      Logger.warning("[Flux.Audit] failed to record event: #{inspect({kind, reason})}")
      :ok
  end

  @doc """
  Lists audit entries for an org, newest first.

  `opts`: `:filters` (map — see `Flux.Audit.Provider`), `:limit`, `:offset`.
  """
  @spec list_logs(Provider.organization_id(), keyword()) :: [Provider.entry()]
  def list_logs(organization_id, opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})
    Registry.active().list(organization_id, filters, Keyword.take(opts, [:limit, :offset]))
  end

  @doc "Total entries matching `filters` (for pagination)."
  @spec count(Provider.organization_id(), map()) :: non_neg_integer()
  def count(organization_id, filters \\ %{}) do
    Registry.active().count(organization_id, filters)
  end

  @doc """
  Exports matching entries encoded as `:csv` or `:json`.

  Returns `{:ok, iodata}` or `{:error, term}` (e.g. `{:error, {:pro_required,
  :audit_log}}` on Community). Filters come from `opts[:filters]`.
  """
  @spec export_logs(Provider.organization_id(), :csv | :json, keyword()) ::
          {:ok, iodata()} | {:error, term()}
  def export_logs(organization_id, format, opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})

    case Registry.active().export(organization_id, filters) do
      {:error, _} = error -> error
      stream -> {:ok, encode(stream, format)}
    end
  end

  @doc "Prunes entries older than the retention window. No-op on Community."
  @spec prune(keyword()) :: {:ok, non_neg_integer()} | :ok
  def prune(opts \\ []) do
    Registry.active().prune(opts)
  end

  @doc """
  Builds a JSON-safe `field => %{"from" => old, "to" => new}` diff from a
  changeset's changes, for the `:changes` payload on update events.

  Pass `redact: [fields]` to replace those fields' values with `"«redacted»"`
  (e.g. a sink's `:config`, which may hold secrets).
  """
  @spec diff(Ecto.Changeset.t(), keyword()) :: map()
  def diff(%Ecto.Changeset{} = changeset, opts \\ []) do
    redact = opts |> Keyword.get(:redact, []) |> Enum.map(&to_string/1)

    Enum.reduce(changeset.changes, %{}, fn {field, new}, acc ->
      key = to_string(field)
      old = Map.get(changeset.data, field)

      value =
        if key in redact do
          %{"from" => "«redacted»", "to" => "«redacted»"}
        else
          %{"from" => jsonable(old), "to" => jsonable(new)}
        end

      Map.put(acc, key, value)
    end)
  end

  # Ecto structs / associations aren't JSON-encodable; collapse anything exotic
  # to a marker so a diff never breaks the audit write.
  defp jsonable(%Ecto.Association.NotLoaded{}), do: nil
  defp jsonable(%_{}), do: "«struct»"
  defp jsonable(value) when is_map(value) or is_list(value) or is_binary(value), do: value
  defp jsonable(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp jsonable(value) when is_atom(value), do: to_string(value)
  defp jsonable(value), do: inspect(value)

  # ── encoding ────────────────────────────────────────────────────────────

  @csv_columns ~w(inserted_at actor_type actor_id action resource_type resource_id changes metadata)

  defp encode(entries, :json) do
    entries
    |> Enum.map(&json_row/1)
    |> then(&Jason.encode!(%{data: &1}))
  end

  defp encode(entries, :csv) do
    header = csv_line(@csv_columns)
    rows = Enum.map(entries, &csv_line(csv_values(&1)))
    [header | rows]
  end

  defp json_row(entry) do
    %{
      id: entry[:id],
      organization_id: entry[:organization_id],
      actor_id: entry[:actor_id],
      actor_type: entry[:actor_type],
      action: entry[:action],
      resource_type: entry[:resource_type],
      resource_id: entry[:resource_id],
      changes: entry[:changes] || %{},
      metadata: entry[:metadata] || %{},
      inserted_at: entry[:inserted_at]
    }
  end

  defp csv_values(entry) do
    [
      to_string(entry[:inserted_at]),
      entry[:actor_type],
      entry[:actor_id],
      entry[:action],
      entry[:resource_type],
      entry[:resource_id],
      Jason.encode!(entry[:changes] || %{}),
      Jason.encode!(entry[:metadata] || %{})
    ]
  end

  # Minimal RFC-4180 line encoder — avoids pulling a CSV dep into the public repo
  # for this one export path.
  defp csv_line(values) do
    values
    |> Enum.map(&csv_field/1)
    |> Enum.intersperse(",")
    |> then(&[&1, "\r\n"])
  end

  defp csv_field(nil), do: ""

  defp csv_field(value) do
    string = to_string(value)

    if String.contains?(string, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(string, "\"", "\"\"")}")
    else
      string
    end
  end
end
