defmodule FluxWeb.SystemSettingsLive.ApiKeysTab do
  @moduledoc """
  API key management for System Settings.
  """
  use FluxWeb, :html

  alias FluxWeb.Components.UpgradePrompt

  def api_keys_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base font-bold">
            <.icon name="hero-key" class="w-5 h-5" /> API Keys
          </h2>
        </div>
        <p class="text-sm text-base-content/60">
          Programmatic access to the REST API via the <code>X-API-Key</code> header.
          A key acts with the role you assign it.
        </p>

        <div
          :if={@revealed_key}
          id="revealed-api-key"
          class="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-4"
        >
          <div class="flex items-start justify-between gap-2">
            <p class="text-sm font-semibold text-amber-900">
              Copy this key now — it will not be shown again.
            </p>
            <button
              type="button"
              phx-click="dismiss_api_key"
              class="btn btn-ghost btn-xs btn-circle"
              aria-label="Dismiss"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <div class="mt-2 flex items-center gap-2">
            <input
              type="text"
              readonly
              value={@revealed_key}
              class="input input-sm input-bordered font-mono w-full"
            />
            <button
              type="button"
              id="copy-api-key"
              phx-hook=".CopyApiKey"
              data-key={@revealed_key}
              class="btn btn-sm"
            >
              Copy
            </button>
          </div>
        </div>

        <.form
          for={@api_key_form}
          id="api-key-form"
          phx-submit="create_api_key"
          class="mt-4 flex flex-col sm:flex-row gap-2 sm:items-end"
        >
          <.input field={@api_key_form[:name]} type="text" label="Name" placeholder="Production CI" />
          <.input
            field={@api_key_form[:role]}
            type="select"
            label="Role"
            options={[{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]}
          />
          <.input
            :if={@scopes_enabled}
            field={@api_key_form[:scopes]}
            type="select"
            multiple
            label="Scopes"
            options={scope_options()}
          />
          <.input field={@api_key_form[:expires_at]} type="date" label="Expires (optional)" />
          <.button class="btn btn-primary">Create key</.button>
        </.form>
        <p :if={@scopes_enabled} class="text-xs text-base-content/50 mt-1">
          A key's access is the intersection of its role and its scopes.
        </p>
        <div :if={!@scopes_enabled} class="mt-2">
          <UpgradePrompt.upgrade_prompt feature={:api_key_scopes} size={:compact} />
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Name</th>
                <th>Key</th>
                <th>Role</th>
                <th>Scopes</th>
                <th>Last used</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={key <- @api_keys} id={"api-key-#{key.id}"}>
                <td class="font-medium">{key.name}</td>
                <td class="font-mono text-xs">{key.key_prefix}…</td>
                <td class="capitalize">{key.role}</td>
                <td class="text-xs">
                  <span
                    :for={scope <- Flux.Accounts.ApiKey.effective_scopes(key)}
                    class="badge badge-ghost badge-xs mr-1 whitespace-nowrap"
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
                <td colspan="7" class="text-center text-base-content/50 py-6">
                  No API keys yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyApiKey">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard?.writeText(this.el.dataset.key)
            const original = this.el.textContent
            this.el.textContent = "Copied!"
            setTimeout(() => { this.el.textContent = original }, 1500)
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
      "active" -> "badge-success"
      _ -> "badge-ghost"
    end
  end

  defp format_last_used(nil), do: "Never"
  defp format_last_used(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp scope_options, do: Enum.map(Flux.Accounts.ApiKey.scopes(), &{&1, &1})
end
