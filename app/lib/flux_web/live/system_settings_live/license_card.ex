defmodule FluxWeb.SystemSettingsLive.LicenseCard do
  @moduledoc """
  The License card on System Settings: tier, expiry, cluster nodes and activation.
  """
  use FluxWeb, :html

  attr :license, :map, required: true
  attr :activation_supported, :boolean, default: false
  attr :license_form, :any, default: nil
  attr :node_states, :list, default: []
  attr :node_capacity, :any, default: nil

  def license_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base font-bold">
            <.icon name="hero-key" class="w-5 h-5" /> License
          </h2>
          <span class={[
            "badge badge-lg font-semibold capitalize",
            tier_badge_class(@license.tier)
          ]}>
            {@license.tier}
          </span>
        </div>

        <dl class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <dt class="text-sm text-base-content/60">Organization</dt>
            <dd class="font-medium">{license_value(Map.get(@license, :org))}</dd>
          </div>
          <div>
            <dt class="text-sm text-base-content/60">Expires</dt>
            <dd class="font-medium">{format_expiry(Map.get(@license, :valid_until))}</dd>
          </div>
          <div>
            <dt class="text-sm text-base-content/60">Licensed nodes</dt>
            <dd class="font-medium">{license_value(Map.get(@license, :node_count))}</dd>
          </div>
        </dl>

        <.license_status_banner license={@license} />

        <p :if={@license.tier == :community} class="text-sm text-base-content/60 mt-2">
          Running the Community tier.
          <.link href={Flux.Marketing.pricing_url()} class="link link-primary">Upgrade</.link>
          to unlock Pro and Enterprise features.
        </p>

        <.cluster_license_state
          node_states={@node_states}
          node_count={Map.get(@license, :node_count)}
          node_capacity={@node_capacity}
        />

        <.activate_license_form :if={@activation_supported} form={@license_form} />
      </div>
    </section>
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
      :if={show_cluster_state?(@node_states, @node_count, @node_capacity)}
      id="cluster-license-state"
      class="mt-4"
    >
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-base-content/80">
          Nodes
          <span :if={@node_capacity} class="ml-1 font-normal text-base-content/60">
            {@node_capacity.live} of {@node_capacity.licensed}
          </span>
        </h3>
        <span :if={divergent?(@node_states)} class="badge badge-warning badge-sm gap-1">
          <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> Not yet consistent
        </span>
      </div>

      <p :if={divergent?(@node_states)} class="mt-1 text-xs text-base-content/60">
        These nodes are not all running the same license yet. Feature gating follows
        the license immediately, but services are wired up at boot — finish the
        rolling restart so every node matches.
      </p>

      <%!--
      Distinct from the divergence warning above: that one means the nodes we can
      see disagree, this one means we cannot see all the nodes we are licensed for.
      A node that has not restarted since activation has not joined the cluster, so
      it is absent rather than inconsistent.
      --%>
      <p :if={shortfall = node_shortfall(@node_states, @node_count)} class="mt-1 text-xs text-warning">
        Licensed for {elem(shortfall, 0)} nodes; {elem(shortfall, 1)} currently reachable.
        A node that has not restarted since the license was applied does not join the
        cluster and will not appear here.
      </p>

      <%!--
      The mirror of the shortfall above: that one means we cannot see every node
      we are licensed for, this one means we can see more than we are licensed
      for. Warning-toned rather than an error banner on purpose — nothing is
      broken, and Flux keeps running; this is a commercial state, not an outage.
      --%>
      <p :if={over_capacity?(@node_capacity)} class="mt-1 text-xs text-warning">
        Running {@node_capacity.live} nodes on a license for {@node_capacity.licensed}.
        Flux keeps running, but this is an unsupported configuration — reduce to {@node_capacity.licensed} nodes or <.link
          href={Flux.Marketing.pricing_url()}
          class="link"
        >extend your license</.link>.
      </p>

      <ul class="mt-2 divide-y divide-base-200 rounded-md border border-base-200">
        <li :for={n <- @node_states} class="flex items-center justify-between px-3 py-2 text-sm">
          <span class="font-mono text-xs text-base-content/70">{n.node}</span>
          <span class={[
            "badge badge-sm capitalize",
            node_tier_class(Map.get(n, :tier))
          ]}>
            {Map.get(n, :tier)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp divergent?(node_states) do
    node_states
    |> Enum.map(&{Map.get(&1, :tier), Map.get(&1, :license_id)})
    |> Enum.uniq()
    |> length() > 1
  end

  # An unreachable node is called out rather than shown as unlicensed: during a
  # rolling restart "we could not ask" and "it has no license" are different
  # problems, and conflating them sends the operator the wrong way.
  defp node_tier_class(:unreachable), do: "badge-ghost text-base-content/50"
  defp node_tier_class(:community), do: "badge-ghost"
  defp node_tier_class(_), do: "badge-success"

  attr :license, :map, required: true

  defp license_status_banner(assigns) do
    assigns = assign(assigns, :status, Map.get(assigns.license, :status, :active))

    ~H"""
    <div
      :if={@status == :near_expiry}
      class="mt-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900"
    >
      <.icon name="hero-clock" class="w-4 h-4 inline" />
      Your license expires on {format_expiry(Map.get(@license, :valid_until))}. Renew soon to avoid
      interruption.
    </div>
    <div
      :if={@status == :grace}
      class="mt-3 rounded-md border border-orange-300 bg-orange-50 px-3 py-2 text-sm text-orange-900"
    >
      <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline" />
      Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Pro stays active
      during the grace period — apply a renewed license to continue.
    </div>
    <div
      :if={@status == :expired}
      class="mt-3 rounded-md border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-900"
    >
      <.icon name="hero-x-circle" class="w-4 h-4 inline" />
      Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Apply a renewed
      license to keep Pro features.
    </div>
    """
  end

  attr :form, :any, required: true

  defp activate_license_form(assigns) do
    ~H"""
    <div class="mt-4 border-t border-base-200 pt-4">
      <h3 class="text-sm font-semibold">Activate Pro</h3>
      <p class="text-xs text-base-content/60 mt-1">
        Paste your signed license token to activate Pro on this node.
      </p>
      <.form
        for={@form}
        id="activate-license-form"
        phx-submit="activate_license"
        class="mt-2 space-y-2"
      >
        <.input
          field={@form[:token]}
          type="textarea"
          rows="3"
          placeholder="flux license token…"
          class="w-full textarea font-mono text-xs break-all"
        />
        <.button class="btn btn-primary btn-sm">Activate license</.button>
      </.form>
    </div>
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
