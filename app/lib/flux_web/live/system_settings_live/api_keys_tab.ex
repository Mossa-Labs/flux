defmodule FluxWeb.SystemSettingsLive.ApiKeysTab do
  @moduledoc """
  The API keys tab of System Settings.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias FluxWeb.Components.UpgradePrompt

  attr :api_keys, :list, required: true
  attr :api_key_form, :any, required: true
  attr :revealed_key, :string, default: nil
  attr :scopes_enabled, :boolean, default: false

  def api_keys_tab(assigns) do
    ~H"""
    <.settings_card id="api-keys-card" title="API keys" icon="hero-key">
      <:description>
        Programmatic access to the REST API via the <code class="font-mono text-xs">X-API-Key</code>
        header. A key acts with the role you assign it.
      </:description>

      <%!--
      Kept until dismissed or the page is left, so switching tabs does not lose a
      secret that can never be shown again.
      --%>
      <div
        :if={@revealed_key}
        id="revealed-api-key"
        role="status"
        class="space-y-3 rounded-box border border-warning/30 bg-warning/10 p-4"
      >
        <div class="flex items-start justify-between gap-2">
          <p class="text-sm font-semibold text-warning">
            Copy this key now — it will not be shown again.
          </p>
          <button
            type="button"
            phx-click="dismiss_api_key"
            class="btn btn-ghost btn-xs btn-circle text-warning"
            aria-label="Dismiss"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        <div class="flex flex-col gap-2 sm:flex-row">
          <input
            type="text"
            readonly
            value={@revealed_key}
            aria-label="New API key"
            class="input input-sm w-full font-mono"
          />
          <button
            type="button"
            id="copy-api-key"
            phx-hook=".CopyApiKey"
            data-key={@revealed_key}
            class="btn btn-sm btn-warning"
          >
            <.icon name="hero-clipboard-document" class="size-4" /> Copy
          </button>
        </div>
      </div>

      <div class="rounded-box border border-base-content/5 bg-base-300 p-4">
        <.form for={@api_key_form} id="api-key-form" phx-submit="create_api_key" class="space-y-3">
          <div class="grid gap-x-3 sm:grid-cols-2 lg:grid-cols-4">
            <div class="sm:col-span-2">
              <.input
                field={@api_key_form[:name]}
                type="text"
                label="Name"
                placeholder="Production CI"
              />
            </div>
            <.input
              field={@api_key_form[:role]}
              type="select"
              label="Role"
              options={[{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]}
            />
            <.input field={@api_key_form[:expires_at]} type="date" label="Expires (optional)" />
          </div>

          <.scope_picker :if={@scopes_enabled} field={@api_key_form[:scopes]} />

          <.button class="btn btn-primary btn-sm">Create key</.button>
        </.form>
      </div>
      <UpgradePrompt.upgrade_prompt :if={!@scopes_enabled} feature={:api_key_scopes} size={:compact} />

      <div class="-mx-2 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/60">
              <th>Name</th>
              <th>Key</th>
              <th>Role</th>
              <th>Scopes</th>
              <th>Last used</th>
              <th>Status</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={key <- @api_keys} id={"api-key-#{key.id}"} class="border-base-content/5">
              <td class="font-medium">{key.name}</td>
              <td class="font-mono text-xs">{key.key_prefix}…</td>
              <td class="capitalize">{key.role}</td>
              <td class="text-xs">
                <span
                  :for={scope <- Flux.Accounts.ApiKey.effective_scopes(key)}
                  class="badge badge-ghost badge-xs mr-1 whitespace-nowrap font-mono"
                >
                  {scope}
                </span>
              </td>
              <td class="text-sm text-base-content/60">{format_last_used(key.last_used_at)}</td>
              <td>
                <span class={["badge badge-sm", api_key_status_class(key)]}>
                  {api_key_status(key)}
                </span>
              </td>
              <td class="text-right">
                <button
                  :if={Flux.Accounts.ApiKey.active?(key)}
                  type="button"
                  phx-click="revoke_api_key"
                  phx-value-id={key.id}
                  data-confirm={"Revoke #{key.name}? This cannot be undone."}
                  class="btn btn-ghost btn-xs text-error"
                >
                  Revoke
                </button>
              </td>
            </tr>
            <tr :if={@api_keys == []}>
              <td colspan="7" class="py-6 text-center text-base-content/60">
                No API keys yet.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.settings_card>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyApiKey">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard?.writeText(this.el.dataset.key)
            const original = this.el.innerHTML
            this.el.textContent = "Copied!"
            setTimeout(() => { this.el.innerHTML = original }, 1500)
          })
        }
      }
    </script>
    """
  end

  defp api_key_status(key) do
    cond do
      Flux.Accounts.ApiKey.revoked?(key) -> "revoked"
      Flux.Accounts.ApiKey.expired?(key, DateTime.utc_now()) -> "expired"
      true -> "active"
    end
  end

  defp api_key_status_class(key) do
    case api_key_status(key) do
      "active" -> "badge-success badge-soft"
      _ -> "badge-ghost"
    end
  end

  defp format_last_used(nil), do: "Never"
  defp format_last_used(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  attr :field, Phoenix.HTML.FormField, required: true

  # One row per resource with a checkbox per action, rather than a multi-select:
  # a native <select multiple> squeezed to input height showed a line and a half
  # of six options and needed cmd-click to change.
  defp scope_picker(assigns) do
    assigns = assign(assigns, :selected, List.wrap(assigns.field.value))

    ~H"""
    <fieldset id="api-key-scopes" class="space-y-2">
      <legend class="mb-1 text-sm font-medium">Scopes</legend>
      <p class="text-xs text-base-content/60">
        A key's access is the intersection of its role and its scopes. Leave every
        box unchecked to use the role's defaults.
      </p>
      <div class="divide-y divide-base-content/5 rounded-field border border-base-content/10 bg-base-200">
        <div
          :for={{resource, actions} <- scope_rows()}
          class="flex flex-wrap items-center gap-x-6 gap-y-1 px-3 py-1.5"
        >
          <span class="w-28 text-sm font-medium">{resource_label(resource)}</span>
          <label
            :for={{action, scope} <- actions}
            class="inline-flex min-h-8 cursor-pointer items-center gap-2 text-sm"
            title={scope}
          >
            <input
              type="checkbox"
              name={@field.name <> "[]"}
              value={scope}
              checked={scope in @selected}
              class="checkbox checkbox-sm checkbox-primary"
            />
            {String.capitalize(action)}
          </label>
        </div>
      </div>
    </fieldset>
    """
  end

  # Scopes are "<action>:<resource>". Grouped by resource in declaration order,
  # each with its actions, e.g. {"pipelines", [{"read", "read:pipelines"}, ...]}.
  defp scope_rows do
    scopes = Flux.Accounts.ApiKey.scopes()

    resources =
      scopes
      |> Enum.map(&(&1 |> String.split(":", parts: 2) |> List.last()))
      |> Enum.uniq()

    for resource <- resources do
      {resource,
       for(
         scope <- scopes,
         [action, ^resource] <- [String.split(scope, ":", parts: 2)],
         do: {action, scope}
       )}
    end
  end

  defp resource_label(resource),
    do: resource |> String.replace("_", " ") |> String.capitalize()
end
