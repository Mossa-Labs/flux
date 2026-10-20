defmodule FluxWeb.SystemSettingsLive.LicenseCard do
  @moduledoc """
  The License card on System Settings: tier and expiry on top, then the
  cluster's nodes and license activation side by side.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  attr :license, :map, required: true
  attr :activation_supported, :boolean, default: false
  attr :license_form, :any, default: nil
  attr :node_states, :list, default: []
  attr :node_capacity, :any, default: nil

  def license_card(assigns) do
    show_nodes =
      show_cluster_state?(
        assigns.node_states,
        Map.get(assigns.license, :node_count),
        assigns.node_capacity
      )

    assigns =
      assigns
      |> assign(:show_nodes, show_nodes)
      |> assign(:two_columns, show_nodes and assigns.activation_supported)

    ~H"""
    <.settings_card id="license-card" title="License" icon="hero-key">
      <:actions>
        <span class={["badge font-semibold capitalize", tier_badge_class(@license.tier)]}>
          {@license.tier}
        </span>
      </:actions>

      <%!-- Community has no license to describe: every field would read "—". --%>
      <dl :if={@license.tier != :community} class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div>
          <dt class="text-xs text-base-content/60">Organization</dt>
          <dd class="font-medium">{license_value(Map.get(@license, :org))}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Expires</dt>
          <dd class="font-medium tabular-nums">{format_expiry(Map.get(@license, :valid_until))}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Licensed nodes</dt>
          <dd class="font-medium tabular-nums">{license_value(Map.get(@license, :node_count))}</dd>
        </div>
      </dl>

      <p :if={@license.tier == :community} class="text-sm text-base-content/70">
        Running the Community tier.
        <.link href={Flux.Marketing.pricing_url()} class="link link-primary">Upgrade</.link>
        to unlock Pro and Enterprise features.
      </p>

      <.license_status_banner license={@license} />

      <%!--
      MOS-600: nodes and activation sit side by side when there is something to
      say about both. With only one of them, it takes the full width rather than
      leaving half the card empty.
      --%>
      <div
        :if={@show_nodes or @activation_supported}
        class={["grid grid-cols-1 gap-4", @two_columns && "lg:grid-cols-2"]}
      >
        <.cluster_license_state
          :if={@show_nodes}
          node_states={@node_states}
          node_count={Map.get(@license, :node_count)}
          node_capacity={@node_capacity}
        />
        <.activation_panel
          :if={@activation_supported}
          form={@license_form}
          mode={activation_mode(@license)}
          narrow={!@two_columns}
        />
      </div>
    </.settings_card>
    """
  end

  # Shown when there is more than one node to compare, OR when the license covers
  # more nodes than are currently reachable.
  #
  # That second case is the one that used to be invisible. Cluster formation is a
  # licensed capability, so a freshly-licensed multi-node deployment reports
  # exactly one node until each has restarted — and a table that hid itself at one
  # row turned "your other nodes have not picked this up yet" into silence.
  #
  # A single-node install with a single-node license still shows nothing: the badge
  # above already says everything, and a one-row table would be noise.
  defp show_cluster_state?(node_states, node_count, node_capacity) do
    length(node_states) > 1 or
      (is_integer(node_count) and node_count > length(node_states)) or
      over_capacity?(node_capacity)
  end

  # Whether the deployment is over its licensed node count is the PROVIDER's
  # verdict, not a comparison made here. Editions that do not cap nodes report
  # nil, and so does an uncapped license, so both render as "nothing to say".
  #
  # Deliberately not `capacity.live > capacity.licensed`: what counts as a node
  # is a licensing question, and a second comparison in the UI is a second
  # definition — one that would eventually disagree with the one that writes the
  # log line. Render the verdict; do not re-derive it.
  defp over_capacity?(%{over?: true}), do: true
  defp over_capacity?(_), do: false

  # `node_count` is nil for an unlimited license — the is_integer/1 guard keeps
  # that out of the comparison rather than treating it as zero.
  defp node_shortfall(node_states, node_count) do
    if is_integer(node_count) and node_count > length(node_states) do
      {node_count, length(node_states)}
    end
  end

  attr :node_states, :list, default: []
  attr :node_count, :any, default: nil
  attr :node_capacity, :any, default: nil

  defp cluster_license_state(assigns) do
    ~H"""
    <div
      id="cluster-license-state"
      class="min-w-0 space-y-3 rounded-box border border-base-content/5 bg-base-300 p-4"
    >
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="flex items-center gap-2 text-sm font-semibold">
          <.icon name="hero-server-stack" class="size-4" /> Nodes
        </h3>
        <span
          :if={@node_capacity}
          class={[
            "badge badge-sm tabular-nums",
            if(over_capacity?(@node_capacity), do: "badge-warning badge-soft", else: "badge-ghost")
          ]}
        >
          {@node_capacity.live} of {@node_capacity.licensed}
        </span>
        <span :if={divergent?(@node_states)} class="badge badge-warning badge-soft badge-sm gap-1">
          <.icon name="hero-exclamation-triangle" class="size-3" /> Not yet consistent
        </span>
      </div>

      <ul class="divide-y divide-base-content/5 overflow-hidden rounded-field border border-base-content/5 bg-base-200">
        <li :for={n <- @node_states} class="flex items-center gap-3 px-3 py-2 text-sm">
          <span
            class={["size-2 shrink-0 rounded-full", node_dot_class(Map.get(n, :tier))]}
            aria-hidden="true"
          >
          </span>
          <span class="min-w-0 flex-1 truncate font-mono text-xs" title={to_string(n.node)}>
            {n.node}
          </span>
          <span class={["badge badge-sm capitalize", node_tier_class(Map.get(n, :tier))]}>
            {Map.get(n, :tier)}
          </span>
        </li>
      </ul>

      <p :if={divergent?(@node_states)} class="text-xs text-base-content/70">
        These nodes are not all running the same license yet. Feature gating follows
        the license immediately, but services are wired up at boot — finish the
        rolling restart so every node matches.
      </p>

      <%!--
      Distinct from the divergence warning above: that one means the nodes we can
      see disagree, this one means we cannot see all the nodes we are licensed for.
      A node that has not restarted since activation has not joined the cluster, so
      it is absent rather than inconsistent — expected mid-rollout, hence neutral
      rather than warning-toned.
      --%>
      <p
        :if={shortfall = node_shortfall(@node_states, @node_count)}
        class="flex items-start gap-2 text-xs text-base-content/70"
      >
        <.icon name="hero-information-circle" class="size-4 shrink-0" />
        <span>
          Licensed for {elem(shortfall, 0)} nodes; {elem(shortfall, 1)} currently reachable.
          A node that has not restarted since the license was applied does not join the
          cluster and will not appear here.
        </span>
      </p>

      <%!--
      The mirror of the shortfall above: that one means we cannot see every node
      we are licensed for, this one means we can see more than we are licensed
      for. Warning-toned rather than an error banner on purpose — nothing is
      broken, and Flux keeps running; this is a commercial state, not an outage.
      --%>
      <p :if={over_capacity?(@node_capacity)} class="flex items-start gap-2 text-xs text-warning">
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        <span>
          Running {@node_capacity.live} nodes on a license for {@node_capacity.licensed}.
          Flux keeps running, but this is an unsupported configuration — reduce to {@node_capacity.licensed} nodes or <.link
            href={Flux.Marketing.pricing_url()}
            class="link"
          >extend your license</.link>.
        </span>
      </p>
    </div>
    """
  end

  defp divergent?(node_states) do
    node_states
    |> Enum.map(&{Map.get(&1, :tier), Map.get(&1, :license_id)})
    |> Enum.uniq()
    |> length() > 1
  end

  @doc """
  Whether the license or the cluster is in a state an operator should look at:
  an expiry banner is showing, the visible nodes disagree, or the provider says
  the deployment is over its licensed node count.
  """
  def needs_attention?(license, node_states, node_capacity) do
    Map.get(license, :status) in [:near_expiry, :grace, :expired] or
      divergent?(node_states) or over_capacity?(node_capacity)
  end

  # An unreachable node is called out rather than shown as unlicensed: during a
  # rolling restart "we could not ask" and "it has no license" are different
  # problems, and conflating them sends the operator the wrong way.
  defp node_tier_class(:unreachable), do: "badge-ghost text-base-content/50"
  defp node_tier_class(:community), do: "badge-ghost"
  defp node_tier_class(_), do: "badge-success badge-soft"

  defp node_dot_class(tier) when tier in [:unreachable, :community], do: "bg-base-content/30"
  defp node_dot_class(_), do: "bg-success"

  attr :license, :map, required: true

  defp license_status_banner(assigns) do
    assigns = assign(assigns, :status, Map.get(assigns.license, :status, :active))

    ~H"""
    <div :if={@status == :near_expiry} role="status" class="alert alert-warning alert-soft text-sm">
      <.icon name="hero-clock" class="size-5" />
      <span>
        <strong class="font-semibold">Renew soon.</strong>
        Your license expires on {format_expiry(Map.get(@license, :valid_until))}. Renew to avoid
        interruption.
      </span>
    </div>
    <div :if={@status == :grace} role="status" class="alert alert-warning alert-soft text-sm">
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span>
        <strong class="font-semibold">Grace period.</strong>
        Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Pro stays active
        during the grace period — apply a renewed license to continue.
      </span>
    </div>
    <div :if={@status == :expired} role="alert" class="alert alert-error alert-soft text-sm">
      <.icon name="hero-x-circle" class="size-5" />
      <span>
        <strong class="font-semibold">License expired.</strong>
        Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Apply a renewed
        license to keep Pro features.
      </span>
    </div>
    """
  end

  # What the activation panel is for depends on what is already applied: with no
  # license it is the way in, after expiry it is the way back, and with a live
  # license it is an occasional replacement that should not dominate the card.
  defp activation_mode(%{tier: :community}), do: :activate

  defp activation_mode(license) do
    if Map.get(license, :status) in [:grace, :expired], do: :renew, else: :replace
  end

  attr :form, :any, required: true
  attr :mode, :atom, values: [:activate, :renew, :replace], required: true
  attr :narrow, :boolean, default: false, doc: "cap the width when alone on the row"

  defp activation_panel(%{mode: :replace} = assigns) do
    ~H"""
    <div class="min-w-0 rounded-box border border-base-content/5 bg-base-300 p-4">
      <div class={["space-y-3", @narrow && "max-w-xl"]}>
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <h3 class="flex items-center gap-2 text-sm font-semibold">
              <.icon name="hero-arrow-path" class="size-4" /> Replace license
            </h3>
            <p class="mt-1 text-xs text-base-content/60">
              Have a new token? Apply it to replace the current license.
            </p>
          </div>
          <%!--
          JS commands rather than <details>: a server patch can reset a
          <details> element's open state, while JS-applied state survives it.
          --%>
          <button
            type="button"
            id="replace-license-toggle"
            class="btn btn-sm btn-outline"
            aria-expanded="false"
            aria-controls="replace-license-panel"
            phx-click={
              JS.toggle(to: "#replace-license-panel")
              |> JS.toggle_attribute({"aria-expanded", "true", "false"})
            }
          >
            Replace
          </button>
        </div>
        <div id="replace-license-panel" class="hidden">
          <.license_token_form form={@form} submit_label="Apply license" />
        </div>
      </div>
    </div>
    """
  end

  defp activation_panel(assigns) do
    ~H"""
    <div class="min-w-0 rounded-box border border-base-content/5 bg-base-300 p-4">
      <div class={["space-y-3", @narrow && "max-w-xl"]}>
        <div>
          <h3 class="flex items-center gap-2 text-sm font-semibold">
            <.icon name="hero-sparkles" class="size-4" />
            {if @mode == :renew, do: "Apply renewed license", else: "Activate Pro"}
          </h3>
          <p class="mt-1 text-xs text-base-content/60">
            {if @mode == :renew,
              do: "Paste the renewed token you received to restore Pro features.",
              else: "Paste your signed license token to activate Pro on this deployment."}
          </p>
        </div>
        <.license_token_form form={@form} submit_label="Activate license" />
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :submit_label, :string, required: true

  defp license_token_form(assigns) do
    ~H"""
    <.form for={@form} id="activate-license-form" phx-submit="activate_license" class="space-y-2">
      <.input
        field={@form[:token]}
        type="textarea"
        rows="3"
        label="License token"
        placeholder="flux license token…"
        class="textarea w-full break-all font-mono text-xs"
      />
      <.button class="btn btn-primary btn-sm">{@submit_label}</.button>
    </.form>
    """
  end

  defp tier_badge_class(:enterprise), do: "badge-primary"
  defp tier_badge_class(:pro), do: "badge-secondary"
  defp tier_badge_class(_), do: "badge-ghost"

  defp license_value(nil), do: "—"
  defp license_value(value), do: to_string(value)

  defp format_expiry(nil), do: "Never"

  defp format_expiry(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%Y-%m-%d")

  defp format_expiry(other), do: to_string(other)
end
